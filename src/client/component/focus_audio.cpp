#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"

#include "console/console.hpp"
#include "scheduler.hpp"
#include "focus_audio.hpp"

#include <audiopolicy.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>

#pragma comment(lib, "ole32.lib")

namespace focus_audio
{
	bool is_client_focused()
	{
		const auto foreground_window = GetForegroundWindow();
		if (!foreground_window)
		{
			return false;
		}

		DWORD foreground_process_id{};
		GetWindowThreadProcessId(foreground_window, &foreground_process_id);
		return foreground_process_id == GetCurrentProcessId();
	}

	namespace
	{
		using Microsoft::WRL::ComPtr;

		game::dvar_t* mute_on_focus_lost;
		game::dvar_t* pause_on_focus_lost;
		std::unordered_set<std::wstring> muted_sessions;
		std::optional<bool> last_focus_state;
		std::optional<bool> last_pause_setting;

		class com_scope final
		{
		public:
			com_scope()
				: result_(CoInitializeEx(nullptr, COINIT_MULTITHREADED))
			{
			}

			~com_scope()
			{
				if (SUCCEEDED(result_))
				{
					CoUninitialize();
				}
			}

			bool available() const
			{
				return SUCCEEDED(result_) || result_ == RPC_E_CHANGED_MODE;
			}

		private:
			HRESULT result_;
		};

		void update_session_mute(const ComPtr<IAudioSessionControl>& session, const bool mute)
		{
			ComPtr<IAudioSessionControl2> session_control;
			if (FAILED(session.As(&session_control)))
			{
				return;
			}

			DWORD process_id{};
			if (FAILED(session_control->GetProcessId(&process_id)) || process_id != GetCurrentProcessId())
			{
				return;
			}

			LPWSTR session_identifier{};
			if (FAILED(session_control->GetSessionInstanceIdentifier(&session_identifier)) || !session_identifier)
			{
				return;
			}

			const std::wstring identifier{session_identifier};
			CoTaskMemFree(session_identifier);

			ComPtr<ISimpleAudioVolume> volume;
			if (FAILED(session.As(&volume)))
			{
				return;
			}

			BOOL is_muted{};
			if (FAILED(volume->GetMute(&is_muted)))
			{
				return;
			}

			if (mute)
			{
				if (!is_muted && SUCCEEDED(volume->SetMute(TRUE, nullptr)))
				{
					muted_sessions.insert(identifier);
				}
			}
			else if (muted_sessions.contains(identifier))
			{
				if (is_muted)
				{
					volume->SetMute(FALSE, nullptr);
				}

				muted_sessions.erase(identifier);
			}
		}

		void update_device_sessions(const ComPtr<IMMDevice>& device, const bool mute)
		{
			ComPtr<IAudioSessionManager2> session_manager;
			if (FAILED(device->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL, nullptr,
				reinterpret_cast<void**>(session_manager.GetAddressOf()))))
			{
				return;
			}

			ComPtr<IAudioSessionEnumerator> session_enumerator;
			if (FAILED(session_manager->GetSessionEnumerator(&session_enumerator)))
			{
				return;
			}

			int session_count{};
			if (FAILED(session_enumerator->GetCount(&session_count)))
			{
				return;
			}

			for (auto i = 0; i < session_count; ++i)
			{
				ComPtr<IAudioSessionControl> session;
				if (SUCCEEDED(session_enumerator->GetSession(i, &session)))
				{
					update_session_mute(session, mute);
				}
			}
		}

		void set_client_sessions_muted(const bool mute)
		{
			com_scope com;
			if (!com.available())
			{
				return;
			}

			ComPtr<IMMDeviceEnumerator> device_enumerator;
			if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
				IID_PPV_ARGS(&device_enumerator))))
			{
				return;
			}

			ComPtr<IMMDeviceCollection> devices;
			if (FAILED(device_enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &devices)))
			{
				return;
			}

			UINT device_count{};
			if (FAILED(devices->GetCount(&device_count)))
			{
				return;
			}

			for (UINT i = 0; i < device_count; ++i)
			{
				ComPtr<IMMDevice> device;
				if (SUCCEEDED(devices->Item(i, &device)))
				{
					update_device_sessions(device, mute);
				}
			}
		}

		void update_focus_mute()
		{
			const auto focused = is_client_focused();
			const auto pause_enabled = pause_on_focus_lost && pause_on_focus_lost->current.enabled;

			if (!last_focus_state || !last_pause_setting || *last_focus_state != focused ||
				*last_pause_setting != pause_enabled)
			{
				console::info("[IWZ][FocusPause] focused=%d enabled=%d\n", focused, pause_enabled);
				last_focus_state = focused;
				last_pause_setting = pause_enabled;
			}

			const auto should_mute = mute_on_focus_lost && mute_on_focus_lost->current.enabled &&
				!focused;

			if (should_mute || !muted_sessions.empty())
			{
				set_client_sessions_muted(should_mute);
			}
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (game::environment::is_dedi())
			{
				return;
			}

			mute_on_focus_lost = game::Dvar_RegisterBool("iwz_mute_on_focus_lost", false,
				game::DVAR_FLAG_SAVED, "Mute client audio while the client is not focused");
			pause_on_focus_lost = game::Dvar_RegisterBool("iwz_pause_on_focus_lost", true, game::DVAR_FLAG_SAVED,
				"Automatically pause solo Zombies while the client is not focused");
			scheduler::loop(update_focus_mute, scheduler::pipeline::async, 250ms);
		}
	};
}

REGISTER_COMPONENT(focus_audio::component)
