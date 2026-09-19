#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "console/console.hpp"
#include "game_module.hpp"
#include "shader_cache.hpp"
#include <utils/hook.hpp>

namespace shader_cache
{
	namespace
	{
		std::wstring client_path;
		std::wstring client_command_line;

		std::string progress_path()
		{
			const auto* root = *reinterpret_cast<game::dvar_t**>(0x14756DEB0);
			char path[256]{};
			utils::hook::invoke<void>(0x140CDBBF0, root->current.string, "players2", "upshd.dat", path);
			return path;
		}

		bool load_progress(progress_record* output)
		{
			const auto path = progress_path();
			std::ifstream stream(path, std::ios::binary);
			progress_records records{};
			const auto valid = stream && read_progress(stream, records);
			if (valid) std::copy(records.begin(), records.end(), output);
			console::info("[IWZ][ShaderCache] progress path='%s' valid=%d action=%s\n", path.c_str(), valid,
				valid ? "reuse-completed-work" : "rebuild-missing-or-invalid-progress");
			return valid;
		}

		HANDLE open_progress_write(const char*)
		{
			const auto path = progress_path();
			std::error_code error;
			std::filesystem::create_directories(std::filesystem::path(path).parent_path(), error);
			if (error)
			{
				console::error("[IWZ][ShaderCache] cannot create progress directory: %s\n", error.message().c_str());
				return nullptr;
			}
			const auto handle = utils::hook::invoke<HANDLE>(0x140B82320, path.c_str());
			console::info("[IWZ][ShaderCache] saving progress path='%s' opened=%d\n", path.c_str(), handle != nullptr);
			return handle;
		}

		bool restart_caching()
		{
			// Same availability checks as the stock RestartCaching / OptionsAreAvailable.
			if (!utils::hook::invoke<bool>(0x1400BEC10))
			{
				console::warn("[IWZ][ShaderCache] restart refused: caching options unavailable\n");
				return false;
			}

			// Resolve the same profile path as FS_Delete, including a custom filesystem root.
			const auto path = progress_path();
			std::error_code error;
			const auto removed = std::filesystem::remove(path, error);
			if (error)
			{
				console::error("[IWZ][ShaderCache] cannot reset progress file '%s': %s; restart cancelled\n",
					path.c_str(), error.message().c_str());
				return false;
			}
			console::info("[IWZ][ShaderCache] reset progress file='%s' removed=%d; restarting client\n", path.c_str(), removed);
			game::Cbuf_AddText(0, "sys_restart\n");
			return true;
		}

		bool launch_client(const char* executable, const char* arguments)
		{
			if (!executable || _stricmp(executable, "iw7_ship.exe"))
			{
				return utils::hook::invoke<bool>(0x140DA8720, executable, arguments);
			}

			auto command_line = client_command_line;
			if (arguments && *arguments)
			{
				const auto length = MultiByteToWideChar(CP_ACP, 0, arguments, -1, nullptr, 0);
				if (!length) return false;
				std::wstring extra(length, L'\0');
				MultiByteToWideChar(CP_ACP, 0, arguments, -1, extra.data(), length);
				extra.pop_back();
				command_line += L" " + extra;
			}

			STARTUPINFOW startup{};
			startup.cb = sizeof(startup);
			PROCESS_INFORMATION process{};
			// CreateProcess requires a mutable command line. Keep the user's launch flags
			// and current game directory, and bypass the stock steam://run launch entirely.
			if (!CreateProcessW(client_path.c_str(), command_line.data(), nullptr, nullptr, FALSE,
				0, nullptr, nullptr, &startup, &process))
			{
				const auto error = GetLastError();
				console::error("[IWZ][ShaderCache] client relaunch failed WindowsError=%lu\n", error);
				SetLastError(error);
				return false;
			}
			console::info("[IWZ][ShaderCache] launched client pid=%lu; original launch flags preserved\n", process.dwProcessId);
			CloseHandle(process.hThread);
			CloseHandle(process.hProcess);
			return true;
		}
	}

	class component final : public component_interface
	{
	public:
		void post_start() override
		{
			// Capture before the game-module compatibility hooks change null-module queries.
			std::wstring path(32768, L'\0');
			const auto length = GetModuleFileNameW(game_module::get_host_module(), path.data(), static_cast<DWORD>(path.size()));
			if (!length || length >= path.size()) throw std::runtime_error("Unable to resolve client executable for restart");
			path.resize(length);
			client_path = std::move(path);
			client_command_line = GetCommandLineW();
		}

		void post_unpack() override
		{
			if (game::environment::is_dedi()) return;
			utils::hook::call(0x140D34E4F, launch_client);
			utils::hook::jump(0x1400BEB60, restart_caching);
			// The stock reader/writer bypass FS_BuildOSPath and use the retail
			// players2 directory, while FS_Delete is redirected to iw7-mod/players2.
			utils::hook::jump(0x1400BE9B0, load_progress);
			utils::hook::call(0x1400BF077, open_progress_write);
			console::info("[IWZ][ShaderCache] client restart routing, unified progress path and bounded cache reader installed\n");
		}
	};
}

REGISTER_COMPONENT(shader_cache::component)
