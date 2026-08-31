#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"
#include "game/dvars.hpp"

#include "command.hpp"
#include "console/console.hpp"
#include "custom_music.hpp"
#include "fastfiles.hpp"
#include "filesystem.hpp"
#include "focus_audio.hpp"
#include "game_module.hpp"
#include "localized_strings.hpp"
#include "party.hpp"
#include "scheduler.hpp"
#include "scripting.hpp"
#include "server_list.hpp"
#include "download.hpp"
#include "zombies_cast.hpp"

#include "game/ui_scripting/execution.hpp"
//#include "game/scripting/execution.hpp"

#include "ui_scripting.hpp"

#include <utils/string.hpp>
#include <utils/hook.hpp>
#include <utils/io.hpp>
#include <utils/binary_resource.hpp>

#include "steam/steam.hpp"

namespace ui_scripting
{
	namespace lua_calls
	{
		int64_t is_development_build_stub([[maybe_unused]] game::hks::lua_State* luaVM)
		{
#if defined(DEBUG)
			ui_scripting::push_value(true);
#else
			ui_scripting::push_value(false);
#endif
			return 1;
		}
	}

	namespace
	{
		std::unordered_map<game::hks::cclosure*, std::function<arguments(const function_arguments& args)>> converted_functions;

		utils::hook::detour lui_cod_init_hook;
		utils::hook::detour hks_shutdown_hook;
		utils::hook::detour hks_package_require_hook;

		utils::hook::detour hks_load_hook;

		/*
		const auto lui_common = utils::nt::load_resource(LUI_COMMON);
		const auto lui_updater = utils::nt::load_resource(LUI_UPDATER);
		const auto lua_json = utils::nt::load_resource(LUA_JSON);
		*/

		struct globals_t
		{
			std::string in_require_script;
			std::unordered_map<std::string, std::string> loaded_scripts;
			bool load_raw_script{};
			std::string raw_script_name{};
		};

		globals_t globals{};
		game::hks::lua_State* active_lui_state{};
		std::uint64_t lui_generation{};

		bool is_loaded_script(const std::string& name)
		{
			return globals.loaded_scripts.contains(name);
		}

		std::string get_root_script(const std::string& name)
		{
			const auto itr = globals.loaded_scripts.find(name);
			return itr == globals.loaded_scripts.end() ? std::string() : itr->second;
		}

		void print_error(const std::string& error)
		{
			console::error("************** LUI script execution error **************\n");
			console::error("%s\n", error.data());
			console::error("********************************************************\n");
		}

		void print_loading_script(const std::string& name)
		{
			console::info("Loading LUI script '%s'\n", name.data());
		}

		std::string get_current_script()
		{
			const auto state = *game::hks::lua_state;
			game::hks::lua_Debug info{};
			game::hks::hksi_lua_getstack(state, 1, &info);
			game::hks::hksi_lua_getinfo(state, "nSl", &info);
			return info.short_src;
		}

		int load_buffer(const std::string& name, const std::string& data)
		{
			const auto state = *game::hks::lua_state;
			const auto sharing_mode = state->m_global->m_bytecodeSharingMode;
			state->m_global->m_bytecodeSharingMode = game::hks::HKS_BYTECODE_SHARING_ON;
			const auto _0 = gsl::finally([&]()
			{
				state->m_global->m_bytecodeSharingMode = sharing_mode;
			});

			game::hks::HksCompilerSettings compiler_settings{};
			return game::hks::hksi_hksL_loadbuffer(state, &compiler_settings, data.data(), data.size(), name.data());
		}

		void load_script(const std::string& name, const std::string& data)
		{
			globals.loaded_scripts[name] = name;

			const auto lua = get_globals();
			const auto load_results = lua["loadstring"](data, name);

			if (load_results[0].is<function>())
			{
				const auto results = lua["pcall"](load_results);
				if (!results[0].as<bool>())
				{
					print_error(results[1].as<std::string>());
				}
			}
			else if (load_results[1].is<std::string>())
			{
				print_error(load_results[1].as<std::string>());
			}
		}

		struct script_candidate
		{
			std::string logical_name;
			std::string root_script;
			std::string data;
			std::size_t priority;
		};

		void load_scripts()
		{
			std::vector<script_candidate> candidates{};
			std::unordered_map<std::string, std::string> selected_roots{};
			std::size_t duplicate_count = 0;

			// Search paths are ordered from highest to lowest priority. Build one
			// effective overlay before executing anything so a packaged copy and an
			// AppData copy of the same logical script cannot both stack global hooks.
			const auto search_paths = filesystem::get_search_paths();
			for (std::size_t priority = 0; priority < search_paths.size(); ++priority)
			{
				const auto& path = search_paths[priority];
				const auto script_dir = path + "/ui_scripts/";
				if (!utils::io::directory_exists(script_dir))
				{
					continue;
				}

				for (const auto& script : utils::io::list_files(script_dir))
				{
					std::string data{};
					const auto root_script = script + "/__init__.lua";
					if (!std::filesystem::is_directory(script) || !utils::io::read_file(root_script, &data))
					{
						continue;
					}

					const auto logical_name = std::filesystem::path(script).filename().generic_string();
					const auto logical_key = utils::string::to_lower(logical_name);
					if (const auto existing = selected_roots.find(logical_key); existing != selected_roots.end())
					{
						++duplicate_count;
						console::info("[IWZ][LUI] ignored lower-priority duplicate script='%s' selected='%s' ignored='%s'\n",
							logical_name.data(), existing->second.data(), root_script.data());
						continue;
					}

					selected_roots.emplace(logical_key, root_script);
					candidates.push_back({logical_name, root_script, std::move(data), priority});
				}
			}

			std::ranges::sort(candidates, [](const script_candidate& left, const script_candidate& right)
			{
				// Preserve the established low-to-high root execution order so shared
				// AppData foundations load before install-only extensions. Within one
				// root, make the directory order deterministic.
				if (left.priority != right.priority)
				{
					return left.priority > right.priority;
				}

				return utils::string::to_lower(left.logical_name) < utils::string::to_lower(right.logical_name);
			});

			console::info("[IWZ][LUI] effective script overlay selected=%zu duplicatesIgnored=%zu priority=first-search-path-wins\n",
				candidates.size(), duplicate_count);

			for (const auto& candidate : candidates)
			{
				print_loading_script(std::filesystem::path(candidate.root_script).parent_path().generic_string());
				load_script(candidate.root_script, candidate.data);
			}
		}

		void setup_functions()
		{
			const auto lua = get_globals();

			lua["io"]["fileexists"] = utils::io::file_exists;
			lua["io"]["writefile"] = utils::io::write_file;
			lua["io"]["movefile"] = utils::io::move_file;
			lua["io"]["filesize"] = utils::io::file_size;
			lua["io"]["createdirectory"] = utils::io::create_directory;
			lua["io"]["directoryexists"] = utils::io::directory_exists;
			lua["io"]["directoryisempty"] = utils::io::directory_is_empty;
			lua["io"]["listfiles"] = utils::io::list_files;
			lua["io"]["removefile"] = utils::io::remove_file;
			lua["io"]["readfile"] = static_cast<std::string(*)(const std::string&)>(utils::io::read_file);

			using game = table;
			auto game_type = game();
			lua["game"] = game_type;

			/*
			game_type["addlocalizedstring"] = [](const game&, const std::string& string,
				const std::string& value)
			{
				localized_strings::override(string, value);
			};
			*/

			game_type["getplayerclantag"] = [](const game&, const int& clientIndex)
			{
				if (clientIndex < 18)
				{
					auto lobbyMember = &party::g_clientMemberInfo[clientIndex];
					auto lobbyMemberValid = &party::g_clientMemberInfoValid[clientIndex];

					if (!lobbyMember || !lobbyMemberValid)return "";

					auto lobbyMemberClanAbbrev = lobbyMember->clanTag.c_str();

					if (!lobbyMemberClanAbbrev || !*lobbyMemberClanAbbrev)
						return "";

					return (const char*)lobbyMemberClanAbbrev;
				}

				return "";
			};

			game_type["getcurrentgamelanguage"] = [](const game&)
			{
				return steam::SteamApps()->GetCurrentGameLanguage();
			};

			game_type["isdefaultmaterial"] = [](const game&, const std::string& material)
			{
				return static_cast<bool>(::game::DB_IsXAssetDefault(::game::ASSET_TYPE_MATERIAL,
					material.data()));
			};

			game_type["getzombiescharacter"] = [](const game&)
			{
				return zombies_cast::get_selection();
			};

			game_type["setzombiescharacter"] = [](const game&, const int selection)
			{
				zombies_cast::set_selection(selection);
			};

			game_type["isclientfocused"] = [](const game&)
			{
				return focus_audio::is_client_focused();
			};

			game_type["getmonotonicmilliseconds"] = [](const game&)
			{
				return static_cast<double>(std::chrono::duration_cast<std::chrono::milliseconds>(
					std::chrono::steady_clock::now().time_since_epoch()).count());
			};

			auto custom_music_table = table();
			lua["custommusic"] = custom_music_table;

			custom_music_table["rescan"] = custom_music::rescan;
			custom_music_table["count"] = custom_music::count;
			custom_music_table["name"] = custom_music::get_name;
			custom_music_table["extension"] = custom_music::get_extension;
			custom_music_table["folder"] = custom_music::get_folder;
			custom_music_table["selectedname"] = custom_music::get_selected_name;
			custom_music_table["selectedindex"] = custom_music::get_selected_index;
			custom_music_table["play"] = custom_music::play;
			custom_music_table["resume"] = custom_music::resume;
			custom_music_table["isplaying"] = custom_music::is_playing;
			custom_music_table["claim"] = custom_music::claim;
			custom_music_table["release"] = custom_music::release;
			custom_music_table["isclaimed"] = custom_music::is_claimed;
			custom_music_table["islobbysession"] = custom_music::is_lobby_session_active;
			custom_music_table["setscene"] = custom_music::set_frontend_scene;
			custom_music_table["openfolder"] = custom_music::open_folder;
			custom_music_table["clear"] = []
			{
				custom_music::stop(true, "stock lobby music selected");
			};

			auto scheduler = table();
			lua["scheduler"] = scheduler;

			scheduler["once"] = [](const function_argument& arg0, const variadic_args& va)
			{
				int delay = va.size() >= 1 ? va[0].as<int>() : 0;

				scheduler::once([arg0, delay]()
				{
					auto func = arg0.as<function>();
					func();
				}, scheduler::lui, std::chrono::milliseconds(delay));
			};

			auto server_list_table = table();
			lua["serverlist"] = server_list_table;

			server_list_table["getplayercount"] = server_list::get_player_count;
			server_list_table["getservercount"] = server_list::get_server_count;

			auto download_table = table();
			lua["download"] = download_table;

			download_table["abort"] = download::stop_download;

			//download_table["userdownloadresponse"] = party::user_download_response;
			//download_table["getwwwurl"] = []
			//{
			//	const auto state = party::get_server_connection_state();
			//	return state.base_url;
			//};
		}

		void enable_globals()
		{
			const auto lua = get_globals();
			const std::string code =
				"local g = getmetatable(_G)\n"
				"if not g then\n"
				"g = {}\n"
				"setmetatable(_G, g)\n"
				"end\n"
				"g.__newindex = nil\n";

			lua["loadstring"](code)[0]();
		}

		void start()
		{
			globals = {};
			const auto lua = get_globals();
			enable_globals(); // EnableGlobals() isn't a thing?

			setup_functions();

			lua["print"] = [](const variadic_args& va)
			{
				std::string buffer{};
				const auto to_string = get_globals()["tostring"];

				for (auto i = 0; i < va.size(); i++)
				{
					const auto& arg = va[i];
					const auto str = to_string(arg)[0].as<std::string>();
					buffer.append(str);

					if (i < va.size() - 1)
					{
						buffer.append("\t");
					}
				}

				console::info("%s\n", buffer.data());
			};

			lua["table"]["unpack"] = lua["unpack"];
			lua["luiglobals"] = lua;

			/*
			load_script("lui_common", lui_common);
			load_script("lui_updater", lui_updater);
			load_script("lua_json", lua_json);
			*/

			load_scripts();
		}

		void try_start()
		{
			try
			{
				start();
			}
			catch (const std::exception& e)
			{
				console::error("Failed to load LUI scripts: %s\n", e.what());
			}
		}

		void lui_cod_init_stub(const bool frontend, const bool error_recovery)
		{
			lui_cod_init_hook.invoke<void>(frontend, error_recovery);

			const auto state = *game::hks::lua_state;
			if (state == nullptr)
			{
				console::error("[IWZ][LUI] custom scripts not loaded: LUI_CoD_Init completed without an HKS state\n");
				return;
			}

			// LUI_CoD_Init owns the complete HKS VM lifecycle and exposes whether the
			// engine is constructing a normal UI or a minimal recovery UI. The old
			// lower-level HKS hook could not distinguish those lifecycles.
			if (active_lui_state == state)
			{
				console::warn("[IWZ][LUI] ignored duplicate initialization for generation=%llu state=%p\n",
					lui_generation, state);
				return;
			}

			active_lui_state = state;
			++lui_generation;

			// Error recovery intentionally starts a minimal stock VM. Injecting the
			// complete custom overlay into it can make recovery fail again, producing
			// an init/shutdown loop until the map transition times out.
			if (error_recovery)
			{
				globals = {};
				console::warn("[IWZ][LUI] preserving minimal error-recovery VM generation=%llu state=%p frontend=%d customScripts=skipped\n",
					lui_generation, state, frontend);
				return;
			}

			console::info("[IWZ][LUI] loading custom scripts generation=%llu state=%p frontend=%d errorRecovery=%d\n",
				lui_generation, state, frontend, error_recovery);
			try_start();
			console::info("[IWZ][LUI] custom scripts ready generation=%llu loaded=%zu\n",
				lui_generation, globals.loaded_scripts.size());
		}

		void hks_shutdown_stub()
		{
			// Lua scheduler callbacks own registry references in the active HKS VM.
			// Destroy them while that VM is still alive so they cannot execute in a
			// replacement VM or unref an unrelated replacement registry.
			const auto cancelled_callbacks = scheduler::clear(scheduler::pipeline::lui);
			console::info("[IWZ][LUI] shutting down custom scripts generation=%llu state=%p loaded=%zu callbacks=%zu\n",
				lui_generation, active_lui_state, globals.loaded_scripts.size(), cancelled_callbacks);

			converted_functions.clear();
			globals = {};
			active_lui_state = nullptr;
			return hks_shutdown_hook.invoke<void>();
		}

		void* hks_package_require_stub(game::hks::lua_State* state)
		{
			const auto script = get_current_script();
			const auto root = get_root_script(script);
			globals.in_require_script = root;
			return hks_package_require_hook.invoke<void*>(state);
		}

		game::XAssetHeader db_find_x_asset_header_stub(game::XAssetType type, const char* name, int allow_create_default)
		{
			game::XAssetHeader header{.luaFile = nullptr};

			if (!is_loaded_script(globals.in_require_script))
			{
				return game::DB_FindXAssetHeader(type, name, allow_create_default);
			}

			const auto folder = globals.in_require_script.substr(0, globals.in_require_script.find_last_of("/\\"));
			std::string name_ = name;
			std::string name_noprefix = std::string(name_.begin() + 3, name_.end());

			const std::string target_script = folder + "/" + name_noprefix;

			if (utils::io::file_exists(target_script))
			{
				globals.load_raw_script = true;
				globals.raw_script_name = target_script;
				header.luaFile = reinterpret_cast<game::LuaFile*>(1);
			}
			else if (name_.starts_with("ui/"))
			{
				return game::DB_FindXAssetHeader(type, name, allow_create_default);
			}

			return header;
		}

		int hks_load_stub(game::hks::lua_State* state, void* compiler_options, 
			void* reader, void* reader_data, const char* chunk_name)
		{
			if (globals.load_raw_script)
			{
				globals.load_raw_script = false;
				globals.loaded_scripts[globals.raw_script_name] = globals.in_require_script;
				return load_buffer(globals.raw_script_name, utils::io::read_file(globals.raw_script_name));
			}

			return hks_load_hook.invoke<int>(state, compiler_options, reader,
				reader_data, chunk_name);
		}

		std::string current_error;
		int main_handler(game::hks::lua_State* state)
		{
			bool error = false;

			try
			{
				const auto value = state->m_apistack.base[-1];
				if (value.t != game::hks::TCFUNCTION)
				{
					return 0;
				}

				const auto closure = value.v.cClosure;
				if (!converted_functions.contains(closure))
				{
					return 0;
				}

				const auto& function = converted_functions[closure];

				const auto args = get_return_values();
				const auto results = function(args);

				for (const auto& result : results)
				{
					push_value(result);
				}

				return static_cast<int>(results.size());
			}
			catch (const std::exception& e)
			{
				current_error = e.what();
				error = true;
			}

			if (error)
			{
				game::hks::hksi_luaL_error(state, current_error.data());
			}

			return 0;
		}
	}

	table get_globals()
	{
		const auto state = *game::hks::lua_state;
		return state->globals.v.table;
	}

	template <typename F>
	game::hks::cclosure* convert_function(F f)
	{
		const auto state = *game::hks::lua_state;
		const auto closure = game::hks::cclosure_Create(state, main_handler, 0, 0, 0);
		converted_functions[closure] = wrap_function(f);
		return closure;
	}

	bool lui_running()
	{
		return *game::hks::lua_state != nullptr;
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

			utils::hook::call(0x1405FC2F7, db_find_x_asset_header_stub);
			utils::hook::call(0x1405FC0AB, db_find_x_asset_header_stub);

			hks_load_hook.create(0x1411E0B00, hks_load_stub);

			hks_package_require_hook.create(0x1411C7F00, hks_package_require_stub);
			lui_cod_init_hook.create(0x140615090, lui_cod_init_stub);
			hks_shutdown_hook.create(0x1406124B0, hks_shutdown_stub);

			// replace LUA engine calls
			utils::hook::set(0x1414B4D98, lua_calls::is_development_build_stub); // IsDevelopmentBuild

			game::Dvar_RegisterBool("ui_showList", false, game::DVAR_FLAG_SAVED, "Show the current menus on the UI stack");
		}
	};
}

REGISTER_COMPONENT(ui_scripting::component)
