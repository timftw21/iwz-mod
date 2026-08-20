#include <std_include.hpp>

#pragma warning(disable: 4701) // stb_vorbis false positive emitted during LTCG.
#pragma warning(push, 0)
#define STB_VORBIS_HEADER_ONLY
#include <stb_vorbis.c>
#undef STB_VORBIS_HEADER_ONLY
#define MINIAUDIO_IMPLEMENTATION
#include <miniaudio.h>
#include <extras/decoders/libopus/miniaudio_libopus.h>
#include <stb_vorbis.c>
#pragma warning(pop)

#include "loader/component_loader.hpp"

#include "custom_music.hpp"
#include "command.hpp"
#include "console/console.hpp"
#include "scheduler.hpp"

#include "game/game.hpp"

#include <utils/hook.hpp>
#include <utils/nt.hpp>

#include <charconv>
#include <cwctype>

namespace custom_music
{
	namespace
	{
		constexpr auto custom_music_directory = "custom_music";
		constexpr auto selected_track_dvar_name = "iwz_custom_music_track";
		constexpr auto volume_dvar_name = "iwz_custom_music_volume";
		constexpr auto ownership_dvar_name = "iwz_custom_music_active";
		constexpr auto lobby_session_dvar_name = "iwz_custom_music_lobby_session_active";
		constexpr auto frontend_monitor_dvar_name = "iwz_custom_music_frontend_monitor_ready";

		struct track
		{
			std::filesystem::path path;
			std::string file_name;
			std::string display_name;
			std::string extension;
		};

		std::recursive_mutex mutex;
		std::vector<track> tracks;
		ma_engine engine{};
		ma_sound sound{};
		ma_decoder decoder{};
		bool engine_initialized{};
		bool sound_initialized{};
		bool decoder_initialized{};
		game::dvar_t* selected_track_dvar{};
		game::dvar_t* custom_volume_dvar{};
		game::dvar_t* ownership_dvar{};
		game::dvar_t* lobby_session_dvar{};
		game::dvar_t* frontend_monitor_dvar{};
		game::dvar_t* master_volume_dvar{};
		game::dvar_t* playlist_volume_dvar{};
		bool volume_sources_logged{};
		float applied_volume{-1.0f};
		bool lifecycle_snapshot_initialized{};
		bool last_monitor_ready{};
		bool last_lobby_session_active{};
		bool initialized{};
		bool shutdown_started{};
		utils::hook::detour snd_set_music_state_hook;

		void bootstrap_log(const char* message)
		{
			wchar_t executable_path[MAX_PATH]{};
			const auto length = GetModuleFileNameW(nullptr, executable_path, ARRAYSIZE(executable_path));
			if (length == 0 || length >= ARRAYSIZE(executable_path))
			{
				return;
			}

			auto folder = std::filesystem::path(executable_path).parent_path() / "iw7-mod";
			CreateDirectoryW(folder.c_str(), nullptr);
			folder /= "logs";
			CreateDirectoryW(folder.c_str(), nullptr);

			const auto path = folder / "custom_music_bootstrap.log";
			const auto handle = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
				OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
			if (handle == INVALID_HANDLE_VALUE)
			{
				return;
			}

			SYSTEMTIME time{};
			GetLocalTime(&time);
			char buffer[512]{};
			const auto size = _snprintf_s(buffer, sizeof(buffer), _TRUNCATE,
				"%04hu-%02hu-%02hu %02hu:%02hu:%02hu.%03hu [IWZ][CustomMusic][Bootstrap] %s\r\n",
				time.wYear, time.wMonth, time.wDay, time.wHour, time.wMinute, time.wSecond,
				time.wMilliseconds, message);
			if (size > 0)
			{
				DWORD written{};
				WriteFile(handle, buffer, static_cast<DWORD>(size), &written, nullptr);
			}

			CloseHandle(handle);
		}

		std::filesystem::path get_folder_path()
		{
			return std::filesystem::path(utils::nt::library().get_folder()) / "iw7-mod" / custom_music_directory;
		}

		std::string wide_to_utf8(const std::wstring& value)
		{
			if (value.empty())
			{
				return {};
			}

			const auto size = WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
				nullptr, 0, nullptr, nullptr);
			if (size <= 0)
			{
				return {};
			}

			std::string result(static_cast<std::size_t>(size), '\0');
			WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), size,
				nullptr, nullptr);
			return result;
		}

		std::wstring lowercase(std::wstring value)
		{
			std::transform(value.begin(), value.end(), value.begin(), [](const wchar_t character)
			{
				return static_cast<wchar_t>(std::towlower(character));
			});
			return value;
		}

		bool is_supported_extension(const std::filesystem::path& path)
		{
			const auto extension = lowercase(path.extension().wstring());
			return extension == L".mp3" || extension == L".wav" || extension == L".flac" ||
				extension == L".ogg" || extension == L".oga";
		}

		void ensure_folder_exists()
		{
			std::error_code error;
			const auto folder = get_folder_path();
			std::filesystem::create_directories(folder, error);
			if (error)
			{
				console::error("[IWZ][CustomMusic] failed to create folder='%s' error='%s'\n",
					wide_to_utf8(folder.wstring()).data(), error.message().data());
			}
		}

		int scan_locked()
		{
			ensure_folder_exists();
			tracks.clear();

			const auto folder = get_folder_path();
			std::error_code error;
			for (std::filesystem::directory_iterator iterator(folder, error), end; iterator != end && !error;
				iterator.increment(error))
			{
				const auto& entry = *iterator;
				std::error_code entry_error;
				if (!entry.is_regular_file(entry_error) || entry_error || !is_supported_extension(entry.path()))
				{
					continue;
				}

				track item{};
				item.path = entry.path();
				item.file_name = wide_to_utf8(entry.path().filename().wstring());
				item.display_name = wide_to_utf8(entry.path().stem().wstring());
				item.extension = wide_to_utf8(lowercase(entry.path().extension().wstring()).substr(1));
				tracks.emplace_back(std::move(item));
			}

			if (error)
			{
				console::error("[IWZ][CustomMusic] scan failed folder='%s' error='%s'\n",
					wide_to_utf8(folder.wstring()).data(), error.message().data());
			}

			std::sort(tracks.begin(), tracks.end(), [](const track& left, const track& right)
			{
				return lowercase(left.path.filename().wstring()) < lowercase(right.path.filename().wstring());
			});

			console::info("[IWZ][CustomMusic] scan complete folder='%s' supported=%zu formats=mp3,wav,flac,ogg\n",
				wide_to_utf8(folder.wstring()).data(), tracks.size());
			return static_cast<int>(tracks.size());
		}

		void set_selected_track_locked(const std::string& file_name)
		{
			if (selected_track_dvar)
			{
				game::Dvar_SetCommand(selected_track_dvar_name, file_name.data());
			}
		}

		std::string get_selected_file_locked()
		{
			if (!selected_track_dvar || !selected_track_dvar->current.string)
			{
				return {};
			}

			return selected_track_dvar->current.string;
		}

		bool is_claimed_locked()
		{
			return ownership_dvar && ownership_dvar->current.enabled;
		}

		bool is_lobby_session_active_locked()
		{
			return lobby_session_dvar && lobby_session_dvar->current.enabled;
		}

		void set_claimed_locked(const bool claimed, const char* reason)
		{
			if (!ownership_dvar || ownership_dvar->current.enabled == claimed)
			{
				return;
			}

			game::Dvar_SetBool(ownership_dvar, claimed);
			if (!shutdown_started)
			{
				console::info("[IWZ][CustomMusic] ownership changed active=%d reason='%s' lobbySession=%d monitorReady=%d\n",
					claimed ? 1 : 0, reason, is_lobby_session_active_locked() ? 1 : 0,
					frontend_monitor_dvar && frontend_monitor_dvar->current.enabled ? 1 : 0);
			}
		}

		std::string detect_codec(const track& item)
		{
			if (item.extension != "ogg" && item.extension != "oga")
			{
				return item.extension;
			}

			std::ifstream stream(item.path, std::ios::binary);
			if (!stream)
			{
				return "ogg-unknown";
			}

			std::array<char, 4096> header{};
			stream.read(header.data(), static_cast<std::streamsize>(header.size()));
			const std::string_view bytes(header.data(), static_cast<std::size_t>(stream.gcount()));
			if (bytes.find("OpusHead") != std::string_view::npos)
			{
				return "ogg-opus";
			}
			if (bytes.find("vorbis") != std::string_view::npos)
			{
				return "ogg-vorbis";
			}

			return "ogg-unknown";
		}

		void stop_locked(const char* reason)
		{
			const auto had_playback_state = sound_initialized || decoder_initialized;
			if (sound_initialized)
			{
				ma_sound_stop(&sound);
				ma_sound_uninit(&sound);
				sound_initialized = false;
			}

			if (decoder_initialized)
			{
				ma_decoder_uninit(&decoder);
				decoder_initialized = false;
			}

			if (had_playback_state && !shutdown_started)
			{
				console::info("[IWZ][CustomMusic] playback stopped reason='%s'\n", reason);
			}
		}

		void snd_set_music_state_stub(const char* music_state)
		{
			snd_set_music_state_hook.invoke<void>(music_state);

			if (shutdown_started || !music_state || !music_state[0])
			{
				return;
			}

			std::lock_guard lock(mutex);
			if (!sound_initialized && !decoder_initialized)
			{
				return;
			}

			stop_locked("stock music state claimed ownership");
			set_claimed_locked(false, "stock music state claimed ownership");
			console::info("[IWZ][CustomMusic] lifecycle transition stockState='%s' customStopped=1 "
				"selectionPreserved=1 frontend=%d frontendScene=%d\n", music_state,
				game::Com_FrontEnd_IsInFrontEnd() ? 1 : 0, game::Com_FrontEndScene_IsActive() ? 1 : 0);
		}

		bool initialize_engine_locked()
		{
			if (engine_initialized)
			{
				return true;
			}

			const auto result = ma_engine_init(nullptr, &engine);
			if (result != MA_SUCCESS)
			{
				console::error("[IWZ][CustomMusic] audio engine initialization failed result=%d description='%s'\n",
					result, ma_result_description(result));
				return false;
			}

			engine_initialized = true;
			console::info("[IWZ][CustomMusic] audio engine initialized backend=miniaudio-%d.%d.%d\n",
				MA_VERSION_MAJOR, MA_VERSION_MINOR, MA_VERSION_REVISION);
			return true;
		}

		void update_volume();

		bool play_locked(const track& item, const bool persist_selection)
		{
			stop_locked("track changed");
			if (!initialize_engine_locked())
			{
				set_claimed_locked(false, "audio engine initialization failed");
				return false;
			}
			update_volume();

			ma_decoding_backend_vtable* custom_backends[]{ma_decoding_backend_libopus};
			auto decoder_config = ma_decoder_config_init_default();
			decoder_config.ppCustomBackendVTables = custom_backends;
			decoder_config.customBackendCount = static_cast<ma_uint32>(std::size(custom_backends));
			const auto codec = detect_codec(item);
			const auto decoder_result = ma_decoder_init_vfs_w(nullptr, item.path.c_str(), &decoder_config, &decoder);
			if (decoder_result != MA_SUCCESS)
			{
				console::error("[IWZ][CustomMusic] decoder failed file='%s' format='%s' codec='%s' result=%d description='%s'\n",
					item.file_name.data(), item.extension.data(), codec.data(), decoder_result,
					ma_result_description(decoder_result));
				set_claimed_locked(false, "decoder initialization failed");
				return false;
			}
			decoder_initialized = true;
			console::info("[IWZ][CustomMusic] decoder initialized file='%s' codec='%s' backend='%s'\n",
				item.file_name.data(), codec.data(), codec == "ogg-opus" ? "libopus" : "miniaudio-built-in");

			const auto sound_result = ma_sound_init_from_data_source(&engine, &decoder,
				MA_SOUND_FLAG_NO_SPATIALIZATION, nullptr, &sound);
			if (sound_result != MA_SUCCESS)
			{
				console::error("[IWZ][CustomMusic] sound source initialization failed file='%s' result=%d description='%s'\n",
					item.file_name.data(), sound_result, ma_result_description(sound_result));
				ma_decoder_uninit(&decoder);
				decoder_initialized = false;
				set_claimed_locked(false, "sound source initialization failed");
				return false;
			}
			sound_initialized = true;
			ma_sound_set_looping(&sound, MA_TRUE);
			const auto start_result = ma_sound_start(&sound);
			if (start_result != MA_SUCCESS)
			{
				console::error("[IWZ][CustomMusic] playback start failed file='%s' result=%d description='%s'\n",
					item.file_name.data(), start_result, ma_result_description(start_result));
				stop_locked("playback start failure");
				set_claimed_locked(false, "playback start failure");
				return false;
			}

			set_claimed_locked(true, persist_selection ? "custom track selected" : "persisted custom track resumed");

			// cp_frontend.gsc stores the selected stock lobby song as a persistent
			// sound state. Engine.StopMusic() only stops its current voice, allowing
			// that state to restart when the frontend scene is restored. Emptying the
			// state after the custom stream starts transfers ownership to this player.
			game::SND_SetMusicState("");
			console::info("[IWZ][CustomMusic] stock music state cleared reason='custom playback claimed ownership'\n");

			if (persist_selection)
			{
				set_selected_track_locked(item.file_name);
			}

			console::info("[IWZ][CustomMusic] playback started file='%s' format='%s' codec='%s' looping=1 persisted=%d\n",
				item.file_name.data(), item.extension.data(), codec.data(), persist_selection ? 1 : 0);
			return true;
		}

		float normalized_dvar_value(const game::dvar_t* dvar)
		{
			if (!dvar)
			{
				return 1.0f;
			}

			float value = 1.0f;
			if (dvar->type == game::DVAR_TYPE_FLOAT)
			{
				value = dvar->current.value;
			}
			else if (dvar->type == game::DVAR_TYPE_INT)
			{
				value = static_cast<float>(dvar->current.integer);
			}

			if (value > 1.0f)
			{
				value /= 100.0f;
			}

			return std::clamp(value, 0.0f, 1.0f);
		}

		void update_volume()
		{
			std::lock_guard lock(mutex);
			if (!engine_initialized)
			{
				return;
			}

			if (!master_volume_dvar)
			{
				master_volume_dvar = game::Dvar_FindVar("profileMenuOption_volume");
			}
			if (!playlist_volume_dvar)
			{
				playlist_volume_dvar = game::Dvar_FindVar("profileMenuOption_licensedMusicVolume");
			}

			if (!volume_sources_logged)
			{
				console::info("[IWZ][CustomMusic] volume integration masterDvar=%s playlistDvar=%s customDvar=%s\n",
					master_volume_dvar ? "found" : "missing", playlist_volume_dvar ? "found" : "missing",
					custom_volume_dvar ? "found" : "missing");
				volume_sources_logged = true;
			}

			const auto master_volume = normalized_dvar_value(master_volume_dvar);
			const auto playlist_volume = normalized_dvar_value(playlist_volume_dvar);
			const auto custom_volume = normalized_dvar_value(custom_volume_dvar);
			const auto volume = master_volume * playlist_volume * custom_volume;
			if (std::abs(volume - applied_volume) < 0.001f)
			{
				return;
			}

			ma_engine_set_volume(&engine, volume);
			applied_volume = volume;
			console::info("[IWZ][CustomMusic] volume applied value=%.3f master=%.3f playlist=%.3f custom=%.3f\n",
				volume, master_volume, playlist_volume, custom_volume);
		}

		void frontend_watcher()
		{
			if (shutdown_started)
			{
				return;
			}

			if (!game::Com_FrontEnd_IsInFrontEnd())
			{
				std::lock_guard lock(mutex);
				stop_locked("left frontend");
				set_claimed_locked(false, "left frontend");
				if (lobby_session_dvar)
				{
					game::Dvar_SetBool(lobby_session_dvar, false);
				}
				if (frontend_monitor_dvar)
				{
					game::Dvar_SetBool(frontend_monitor_dvar, false);
				}
				lifecycle_snapshot_initialized = false;
				return;
			}

			{
				std::lock_guard lock(mutex);
				const auto monitor_ready = frontend_monitor_dvar && frontend_monitor_dvar->current.enabled;
				const auto lobby_session_active = is_lobby_session_active_locked();
				if (!lifecycle_snapshot_initialized || monitor_ready != last_monitor_ready ||
					lobby_session_active != last_lobby_session_active)
				{
					console::info("[IWZ][CustomMusic] frontend lifecycle monitorReady=%d lobbySession=%d "
						"customActive=%d playing=%d\n", monitor_ready ? 1 : 0, lobby_session_active ? 1 : 0,
						is_claimed_locked() ? 1 : 0,
						sound_initialized && ma_sound_is_playing(&sound) == MA_TRUE ? 1 : 0);
					lifecycle_snapshot_initialized = true;
					last_monitor_ready = monitor_ready;
					last_lobby_session_active = lobby_session_active;
				}

				if (monitor_ready && is_claimed_locked() && !lobby_session_active)
				{
					stop_locked("returned to Zombies main menu");
					set_claimed_locked(false, "returned to Zombies main menu");
					console::info("[IWZ][CustomMusic] lifecycle transition customStopped=1 "
						"selectionPreserved=1 reason='lobby session reached zm_main'\n");
				}
			}

			update_volume();
		}

		void shutdown()
		{
			std::lock_guard lock(mutex);
			if (shutdown_started)
			{
				return;
			}

			shutdown_started = true;
			bootstrap_log("shutdown entered");
			stop_locked("client shutdown");
			if (ownership_dvar)
			{
				game::Dvar_SetBool(ownership_dvar, false);
			}
			if (engine_initialized)
			{
				ma_engine_uninit(&engine);
				engine_initialized = false;
			}
			initialized = false;
			bootstrap_log("shutdown completed; audio resources released");
		}

		void initialize()
		{
			if (initialized)
			{
				return;
			}

			bootstrap_log("deferred initialization entered");
			bootstrap_log("registering selection dvar");
			selected_track_dvar = game::Dvar_RegisterString(selected_track_dvar_name, "", game::DVAR_FLAG_SAVED,
				"Custom Zombies lobby music file selected by the player");
			bootstrap_log("selection dvar registered");
			custom_volume_dvar = game::Dvar_RegisterFloat(volume_dvar_name, 1.0f, 0.0f, 1.0f,
				game::DVAR_FLAG_SAVED, "Volume scale applied to custom Zombies lobby music");
			bootstrap_log("volume dvar registered");
			ownership_dvar = game::Dvar_RegisterBool(ownership_dvar_name, false, game::DVAR_FLAG_NONE,
				"Whether the external custom lobby music player owns frontend music playback");
			lobby_session_dvar = game::Dvar_RegisterBool(lobby_session_dvar_name, false, game::DVAR_FLAG_NONE,
				"Whether the Zombies frontend is in a lobby session that has not returned to zm_main");
			frontend_monitor_dvar = game::Dvar_RegisterBool(frontend_monitor_dvar_name, false, game::DVAR_FLAG_NONE,
				"Whether the Zombies frontend GSC lifecycle monitor is running");
			game::Dvar_SetBool(ownership_dvar, false);
			game::Dvar_SetBool(lobby_session_dvar, false);
			game::Dvar_SetBool(frontend_monitor_dvar, false);
			bootstrap_log("frontend lifecycle dvars registered");

			ensure_folder_exists();
			scan_locked();
			console::info("[IWZ][CustomMusic] initialized folder='%s' selected='%s'\n", get_folder().data(),
				get_selected_file_locked().data());

			command::add("custommusiclist", []
			{
				const auto total = rescan();
				console::info("[IWZ][CustomMusic] console list count=%d\n", total);
				for (auto index = 0; index < total; ++index)
				{
					console::info("[IWZ][CustomMusic]   %d: %s [%s]\n", index, get_name(index).data(),
						get_extension(index).data());
				}
			});

			command::add("custommusicplay", [](const command::params& params)
			{
				if (params.size() < 2)
				{
					console::info("usage: custommusicplay <zero-based index>\n");
					return;
				}

				const std::string_view argument{params[1]};
				int index{};
				const auto [end, error] = std::from_chars(argument.data(), argument.data() + argument.size(), index);
				if (error != std::errc{} || end != argument.data() + argument.size())
				{
					console::warn("[IWZ][CustomMusic] rejected invalid console track index='%s'\n", params[1]);
					console::info("usage: custommusicplay <zero-based index>\n");
					return;
				}

				rescan();
				play(index);
			});

			command::add("custommusicstop", []
			{
				stop(true, "console command");
			});

			scheduler::loop(frontend_watcher, scheduler::main, 250ms);
			initialized = true;
			bootstrap_log("deferred initialization completed");
		}
	}

	int rescan()
	{
		std::lock_guard lock(mutex);
		return scan_locked();
	}

	int count()
	{
		std::lock_guard lock(mutex);
		return static_cast<int>(tracks.size());
	}

	std::string get_name(const int index)
	{
		std::lock_guard lock(mutex);
		if (index < 0 || static_cast<std::size_t>(index) >= tracks.size())
		{
			return {};
		}

		return tracks[static_cast<std::size_t>(index)].display_name;
	}

	std::string get_extension(const int index)
	{
		std::lock_guard lock(mutex);
		if (index < 0 || static_cast<std::size_t>(index) >= tracks.size())
		{
			return {};
		}

		return tracks[static_cast<std::size_t>(index)].extension;
	}

	std::string get_folder()
	{
		return wide_to_utf8(get_folder_path().wstring());
	}

	std::string get_selected_name()
	{
		std::lock_guard lock(mutex);
		const auto selected = get_selected_file_locked();
		for (const auto& item : tracks)
		{
			if (_stricmp(item.file_name.data(), selected.data()) == 0)
			{
				return item.display_name;
			}
		}

		return {};
	}

	int get_selected_index()
	{
		std::lock_guard lock(mutex);
		const auto selected = get_selected_file_locked();
		for (auto index = 0u; index < tracks.size(); ++index)
		{
			if (_stricmp(tracks[index].file_name.data(), selected.data()) == 0)
			{
				return static_cast<int>(index);
			}
		}

		return -1;
	}

	bool play(const int index)
	{
		std::lock_guard lock(mutex);
		if (index < 0 || static_cast<std::size_t>(index) >= tracks.size())
		{
			console::error("[IWZ][CustomMusic] play rejected index=%d count=%zu\n", index, tracks.size());
			return false;
		}

		return play_locked(tracks[static_cast<std::size_t>(index)], true);
	}

	bool resume()
	{
		std::lock_guard lock(mutex);
		const auto selected = get_selected_file_locked();
		if (selected.empty())
		{
			return false;
		}

		scan_locked();
		for (const auto& item : tracks)
		{
			if (_stricmp(item.file_name.data(), selected.data()) == 0)
			{
				console::info("[IWZ][CustomMusic] resuming persisted selection file='%s'\n", item.file_name.data());
				return play_locked(item, false);
			}
		}

		console::warn("[IWZ][CustomMusic] persisted selection missing file='%s'; clearing selection\n", selected.data());
		set_selected_track_locked("");
		return false;
	}

	bool is_playing()
	{
		std::lock_guard lock(mutex);
		return sound_initialized && ma_sound_is_playing(&sound) == MA_TRUE;
	}

	bool claim(const std::string& reason)
	{
		std::lock_guard lock(mutex);
		if (!initialized || shutdown_started || !game::Com_FrontEnd_IsInFrontEnd())
		{
			console::warn("[IWZ][CustomMusic] ownership claim rejected reason='%s' initialized=%d shutdown=%d frontend=%d\n",
				reason.data(), initialized ? 1 : 0, shutdown_started ? 1 : 0,
				game::Com_FrontEnd_IsInFrontEnd() ? 1 : 0);
			return false;
		}

		set_claimed_locked(true, reason.data());
		return true;
	}

	void release(const std::string& reason)
	{
		std::lock_guard lock(mutex);
		stop_locked(reason.data());
		set_claimed_locked(false, reason.data());
	}

	bool is_claimed()
	{
		std::lock_guard lock(mutex);
		return is_claimed_locked();
	}

	bool is_lobby_session_active()
	{
		std::lock_guard lock(mutex);
		return is_lobby_session_active_locked();
	}

	void set_frontend_scene(const std::string& section_name)
	{
		std::lock_guard lock(mutex);
		const auto entered_lobby = _stricmp(section_name.data(), "zm_lobby") == 0;
		const auto returned_to_main = _stricmp(section_name.data(), "zm_main") == 0;
		if (!entered_lobby && !returned_to_main)
		{
			console::info("[IWZ][CustomMusic] frontend section inherited lobby session source=lui name='%s' "
				"lobbySession=%d customActive=%d\n", section_name.data(),
				is_lobby_session_active_locked() ? 1 : 0, is_claimed_locked() ? 1 : 0);
			return;
		}

		const auto lobby_session_active = entered_lobby;
		const auto changed = lobby_session_dvar &&
			lobby_session_dvar->current.enabled != lobby_session_active;
		if (lobby_session_dvar)
		{
			game::Dvar_SetBool(lobby_session_dvar, lobby_session_active);
		}

		if (changed)
		{
			console::info("[IWZ][CustomMusic] lobby session boundary source=lui name='%s' lobbySession=%d "
				"customActive=%d\n", section_name.data(), lobby_session_active ? 1 : 0,
				is_claimed_locked() ? 1 : 0);
		}

		if (returned_to_main && is_claimed_locked())
		{
			stop_locked("LUI returned to Zombies main menu");
			set_claimed_locked(false, "LUI returned to Zombies main menu");
			console::info("[IWZ][CustomMusic] lifecycle transition customStopped=1 selectionPreserved=1 "
				"reason='LUI lobby session reached zm_main' destination='%s'\n", section_name.data());
		}
	}

	bool open_folder()
	{
		std::lock_guard lock(mutex);
		ensure_folder_exists();
		const auto folder = get_folder_path();
		const auto result = reinterpret_cast<std::intptr_t>(ShellExecuteW(nullptr, L"open", folder.c_str(), nullptr,
			nullptr, SW_SHOWNORMAL));
		if (result <= 32)
		{
			console::error("[IWZ][CustomMusic] open folder failed folder='%s' shellResult=%lld\n",
				wide_to_utf8(folder.wstring()).data(), static_cast<long long>(result));
			return false;
		}

		console::info("[IWZ][CustomMusic] opened folder='%s'\n", wide_to_utf8(folder.wstring()).data());
		return true;
	}

	void stop(const bool clear_selection, const char* reason)
	{
		std::lock_guard lock(mutex);
		const auto had_selection = !get_selected_file_locked().empty();
		stop_locked(reason);
		set_claimed_locked(false, reason);
		if (clear_selection && had_selection)
		{
			set_selected_track_locked("");
			console::info("[IWZ][CustomMusic] persisted selection cleared reason='%s'\n", reason);
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

			snd_set_music_state_hook.create(game::SND_SetMusicState, snd_set_music_state_stub);
			bootstrap_log("stock music lifecycle hook installed");
			bootstrap_log("post_unpack entered; deferring engine registration");
			scheduler::once(initialize, scheduler::main);
			bootstrap_log("post_unpack completed; initialization queued");
		}

		void pre_destroy() override
		{
			shutdown();
		}
	};
}

REGISTER_COMPONENT(custom_music::component)
