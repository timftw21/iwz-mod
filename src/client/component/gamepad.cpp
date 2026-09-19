#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "console/console.hpp"
#include "gamepad.hpp"
#include "command.hpp"
#include "scheduler.hpp"
#include <utils/binary_resource.hpp>
#include <utils/hook.hpp>
#include <SDL3/SDL.h>
#include <Xinput.h>
#include <delayimp.h>

#pragma comment(lib, "xinput9_1_0.lib")

namespace gamepad
{
	namespace
	{
		FARPROC WINAPI load_sdl(unsigned notification, PDelayLoadInfo info)
		{
			if (notification != dliNotePreLoadLibrary || _stricmp(info->szDll, "SDL3.dll")) return nullptr;
			static utils::binary_resource resource(SDL_DLL, "iwz-SDL3-3.4.16.dll");
			static const auto module = utils::nt::library::load(resource.get_extracted_file(true));
			return reinterpret_cast<FARPROC>(module.get_handle());
		}

		std::mutex mutex;
		utils::hook::detour update_hook;
		utils::hook::detour mouse_hook;
		std::atomic_bool input_ready{};
		SDL_Gamepad* controller{};
		bool initialized{};
		bool attempted_init{};
		bool connected{};
		int native_slot = -1;
		XINPUT_STATE state{};
		ULONGLONG next_discovery{};

		bool game_focused()
		{
			// The same window used by IN_GetCursorPos and IN_RecenterMouse.
			const auto window = *reinterpret_cast<HWND*>(0x1477A02D0);
			return window && GetForegroundWindow() == window;
		}

		bool gamepad_enabled()
		{
			// GamerProfile_GetGamepadEnabled, also used by Engine.IsGamepadEnabled.
			return utils::hook::invoke<bool>(0x140337800, 0);
		}

		void select_input(bool enabled)
		{
			if (!input_ready || !game_focused() || gamepad_enabled() == enabled) return;
			// Use the stock setter so input filtering and binding lookup agree. Device
			// changes are transient: do not rewrite the profile on every switch.
			command::execute(enabled ? "profile_toggleEnableGamepad 1" : "profile_toggleEnableGamepad 0", true);
			console::info("[IWZ][Input] selected=%s applied=%d\n", enabled ? "gamepad" : "mouse/keyboard",
				gamepad_enabled() == enabled);
		}

		bool axis_pressed(int value, int previous, int deadzone)
		{
			return abs(value) > deadzone && (abs(previous) <= deadzone || abs(value - previous) > 4096);
		}

		bool controller_activity(const XINPUT_GAMEPAD& next, const XINPUT_GAMEPAD& previous)
		{
			return (next.wButtons & ~previous.wButtons) != 0
				|| (next.bLeftTrigger > XINPUT_GAMEPAD_TRIGGER_THRESHOLD && previous.bLeftTrigger <= XINPUT_GAMEPAD_TRIGGER_THRESHOLD)
				|| (next.bRightTrigger > XINPUT_GAMEPAD_TRIGGER_THRESHOLD && previous.bRightTrigger <= XINPUT_GAMEPAD_TRIGGER_THRESHOLD)
				|| axis_pressed(next.sThumbLX, previous.sThumbLX, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE)
				|| axis_pressed(next.sThumbLY, previous.sThumbLY, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE)
				|| axis_pressed(next.sThumbRX, previous.sThumbRX, XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE)
				|| axis_pressed(next.sThumbRY, previous.sThumbRY, XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE);
		}

		int mouse_stub(int x, int y, int delta_x, int delta_y)
		{
			// Engine deltas already exclude cursor recentering and support both its
			// raw and window-message mouse paths.
			if (delta_x || delta_y) select_input(false);
			return mouse_hook.invoke<int>(x, y, delta_x, delta_y);
		}

		SHORT invert_axis(Sint16 value)
		{
			return static_cast<SHORT>(std::clamp(-static_cast<int>(value), -32768, 32767));
		}

		XINPUT_GAMEPAD read_controller()
		{
			XINPUT_GAMEPAD result{};
			constexpr std::pair<SDL_GamepadButton, WORD> buttons[] = {
				{SDL_GAMEPAD_BUTTON_SOUTH, XINPUT_GAMEPAD_A}, {SDL_GAMEPAD_BUTTON_EAST, XINPUT_GAMEPAD_B},
				{SDL_GAMEPAD_BUTTON_WEST, XINPUT_GAMEPAD_X}, {SDL_GAMEPAD_BUTTON_NORTH, XINPUT_GAMEPAD_Y},
				{SDL_GAMEPAD_BUTTON_BACK, XINPUT_GAMEPAD_BACK}, {SDL_GAMEPAD_BUTTON_START, XINPUT_GAMEPAD_START},
				{SDL_GAMEPAD_BUTTON_LEFT_STICK, XINPUT_GAMEPAD_LEFT_THUMB},
				{SDL_GAMEPAD_BUTTON_RIGHT_STICK, XINPUT_GAMEPAD_RIGHT_THUMB},
				{SDL_GAMEPAD_BUTTON_LEFT_SHOULDER, XINPUT_GAMEPAD_LEFT_SHOULDER},
				{SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER, XINPUT_GAMEPAD_RIGHT_SHOULDER},
				{SDL_GAMEPAD_BUTTON_DPAD_UP, XINPUT_GAMEPAD_DPAD_UP},
				{SDL_GAMEPAD_BUTTON_DPAD_DOWN, XINPUT_GAMEPAD_DPAD_DOWN},
				{SDL_GAMEPAD_BUTTON_DPAD_LEFT, XINPUT_GAMEPAD_DPAD_LEFT},
				{SDL_GAMEPAD_BUTTON_DPAD_RIGHT, XINPUT_GAMEPAD_DPAD_RIGHT}
			};
			for (const auto& [button, mask] : buttons)
			{
				if (SDL_GetGamepadButton(controller, button)) result.wButtons |= mask;
			}
			result.sThumbLX = SDL_GetGamepadAxis(controller, SDL_GAMEPAD_AXIS_LEFTX);
			result.sThumbLY = invert_axis(SDL_GetGamepadAxis(controller, SDL_GAMEPAD_AXIS_LEFTY));
			result.sThumbRX = SDL_GetGamepadAxis(controller, SDL_GAMEPAD_AXIS_RIGHTX);
			result.sThumbRY = invert_axis(SDL_GetGamepadAxis(controller, SDL_GAMEPAD_AXIS_RIGHTY));
			result.bLeftTrigger = static_cast<BYTE>(std::max(0, static_cast<int>(SDL_GetGamepadAxis(controller, SDL_GAMEPAD_AXIS_LEFT_TRIGGER))) * 255 / 32767);
			result.bRightTrigger = static_cast<BYTE>(std::max(0, static_cast<int>(SDL_GetGamepadAxis(controller, SDL_GAMEPAD_AXIS_RIGHT_TRIGGER))) * 255 / 32767);
			return result;
		}

		std::optional<bool> update()
		{
			std::lock_guard lock(mutex);
			if (!attempted_init)
			{
				attempted_init = true;
				// Only initialize input. The engine owns its window, audio, and event loop.
				SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
				SDL_SetHint(SDL_HINT_XINPUT_ENABLED, "0");
				initialized = SDL_InitSubSystem(SDL_INIT_GAMEPAD);
				if (initialized)
				{
					SDL_SetGamepadEventsEnabled(false);
					SDL_SetJoystickEventsEnabled(false);
				}
				console::info("[IWZ][Gamepad] SDL input initialized=%d error=%s\n", initialized, initialized ? "none" : SDL_GetError());
			}

			const auto previous_connected = connected;
			const auto previous_slot = native_slot;
			XINPUT_STATE next{};
			connected = native_slot >= 0 && XInputGetState(native_slot, &next) == ERROR_SUCCESS;
			if (!connected) native_slot = -1;
			if (initialized)
			{
				SDL_UpdateGamepads();
				if (controller && !SDL_GamepadConnected(controller))
				{
					console::info("[IWZ][Gamepad] SDL controller disconnected\n");
					SDL_CloseGamepad(controller);
					controller = nullptr;
				}
			}

			const auto now = GetTickCount64();
			if (now >= next_discovery)
			{
				next_discovery = now + 1000;
				if (!connected)
				{
					for (DWORD slot = 0; slot < XUSER_MAX_COUNT; ++slot)
					{
						if (XInputGetState(slot, &next) == ERROR_SUCCESS)
						{
							native_slot = static_cast<int>(slot);
							connected = true;
							break;
						}
					}
				}
				if (initialized && !controller && !connected)
				{
					int count{};
					auto* ids = SDL_GetGamepads(&count);
					for (int i = 0; i < count && !controller; ++i) controller = SDL_OpenGamepad(ids[i]);
					SDL_free(ids);
					if (controller) console::info("[IWZ][Gamepad] opened %s vendor=%04x product=%04x\n",
						SDL_GetGamepadName(controller), SDL_GetGamepadVendor(controller), SDL_GetGamepadProduct(controller));
				}
			}
			if (!connected && controller)
			{
				connected = true;
				next.Gamepad = read_controller();
			}
			if (connected != previous_connected || native_slot != previous_slot)
			{
				console::info("[IWZ][Gamepad] connected=%d backend=%s nativeSlot=%d\n", connected,
					native_slot >= 0 ? "XInput" : "SDL", native_slot);
			}
			std::optional<bool> requested_input;
			if (connected && controller_activity(next.Gamepad, state.Gamepad)) requested_input = true;
			else if (previous_connected && !connected) requested_input = false;
			if (connected != previous_connected || memcmp(&state.Gamepad, &next.Gamepad, sizeof(next.Gamepad))) ++state.dwPacketNumber;
			state.Gamepad = next.Gamepad;
			return requested_input;
		}

		void update_stub()
		{
			const auto requested_input = update();
			// The stock profile command may query XInput. Release our lock first.
			if (requested_input.has_value()) select_input(*requested_input);
			update_hook.invoke<void>();
		}

		DWORD WINAPI get_state(DWORD index, XINPUT_STATE* output)
		{
			if (index != 0) return XInputGetState(index, output);
			if (!output) return ERROR_BAD_ARGUMENTS;
			std::lock_guard lock(mutex);
			if (!connected) return ERROR_DEVICE_NOT_CONNECTED;
			*output = state;
			return ERROR_SUCCESS;
		}

		DWORD WINAPI get_capabilities(DWORD index, DWORD flags, XINPUT_CAPABILITIES* output)
		{
			if (index != 0) return XInputGetCapabilities(index, flags, output);
			if (!output) return ERROR_BAD_ARGUMENTS;
			std::lock_guard lock(mutex);
			if (!connected) return ERROR_DEVICE_NOT_CONNECTED;
			if (native_slot >= 0) return XInputGetCapabilities(native_slot, flags, output);
			*output = {};
			output->Type = XINPUT_DEVTYPE_GAMEPAD;
			output->SubType = XINPUT_DEVSUBTYPE_GAMEPAD;
			output->Gamepad = {0xF3FF, 255, 255, 32767, 32767, 32767, 32767};
			if (SDL_GetBooleanProperty(SDL_GetGamepadProperties(controller), SDL_PROP_GAMEPAD_CAP_RUMBLE_BOOLEAN, false))
			{
				output->Vibration = {65535, 65535};
			}
			return ERROR_SUCCESS;
		}

		DWORD WINAPI set_state(DWORD index, XINPUT_VIBRATION* vibration)
		{
			if (index != 0) return XInputSetState(index, vibration);
			if (!vibration) return ERROR_BAD_ARGUMENTS;
			std::lock_guard lock(mutex);
			if (!connected) return ERROR_DEVICE_NOT_CONNECTED;
			if (native_slot >= 0) return XInputSetState(native_slot, vibration);
			// Engine refreshes rumble; expire it if the game stops submitting frames.
			return SDL_RumbleGamepad(controller, vibration->wLeftMotorSpeed, vibration->wRightMotorSpeed, 1000)
				? ERROR_SUCCESS : ERROR_NOT_SUPPORTED;
		}
	}

	bool is_controller_key(int key)
	{
		return (key >= 1 && key <= 6) || (key >= 14 && key <= 23)
			|| (key >= 28 && key <= 31) || key == game::K_BUTTON_LSTICK_ALTIMAGE || key == game::K_BUTTON_RSTICK_ALTIMAGE;
	}

	void key_event(int key, bool down)
	{
		if (down && key > 0 && !is_controller_key(key)) select_input(false);
	}

	class component final : public component_interface
	{
	public:
		void* load_import(const std::string& library, const std::string& function) override
		{
			if (_stricmp(library.c_str(), "XINPUT9_1_0.dll")) return nullptr;
			if (function == "XInputGetState") return get_state;
			if (function == "XInputGetCapabilities") return get_capabilities;
			if (function == "XInputSetState") return set_state;
			return nullptr;
		}

		void post_unpack() override
		{
			if (game::environment::is_dedi()) return;
			update_hook.create(0x140D30A30, update_stub);
			mouse_hook.create(0x14033C060, mouse_stub);
			scheduler::on_game_initialized([] { input_ready = true; }, scheduler::main);
		}

		void pre_destroy() override
		{
			std::lock_guard lock(mutex);
			connected = false;
			if (native_slot >= 0)
			{
				XINPUT_VIBRATION stop{};
				XInputSetState(native_slot, &stop);
			}
			if (controller)
			{
				SDL_RumbleGamepad(controller, 0, 0, 0);
				SDL_CloseGamepad(controller);
				controller = nullptr;
			}
			if (initialized) SDL_QuitSubSystem(SDL_INIT_GAMEPAD);
			initialized = false;
		}
	};
}

extern "C" const PfnDliHook __pfnDliNotifyHook2 = gamepad::load_sdl;
REGISTER_COMPONENT(gamepad::component)
