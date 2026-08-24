#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "command.hpp"

#include "game/game.hpp"
#include "game/dvars.hpp"
#include "game/scripting/execution.hpp"

#include "console/console.hpp"
#include "game_console.hpp"
#include "dvars.hpp"
#include "scheduler.hpp"

#include <utils/hook.hpp>
#include <utils/string.hpp>
#include <utils/memory.hpp>

namespace command
{
	namespace
	{
		utils::hook::detour client_command_mp_hook;
		utils::hook::detour client_command_sp_hook;
		utils::hook::detour parse_commandline_hook;

		std::unordered_map<std::string, std::function<void(params&)>> handlers;
		std::unordered_map<std::string, std::function<void(int, params_sv&)>> handlers_sv;

		void main_handler()
		{
			params params = {};

			const auto command = utils::string::to_lower(params[0]);
			if (handlers.find(command) != handlers.end())
			{
				handlers[command](params);
			}
		}

		void client_command_mp(const int client_num)
		{
			params_sv params = {};

			const auto command = utils::string::to_lower(params[0]);
			if (handlers_sv.find(command) != handlers_sv.end())
			{
				handlers_sv[command](client_num, params);
			}

			client_command_mp_hook.invoke<void>(client_num);
		}

		void client_command_sp(const int client_num, const char* s)
		{
			game::SV_Cmd_TokenizeString(s);
			params_sv params = {};

			const auto command = utils::string::to_lower(s);
			if (handlers_sv.find(command) != handlers_sv.end())
			{
				handlers_sv[command](client_num, params);
			}
			game::SV_Cmd_EndTokenizedString();

			client_command_sp_hook.invoke<void>(client_num, s);
		}

		// Shamelessly stolen from Quake3
		// https://github.com/id-Software/Quake-III-Arena/blob/dbe4ddb10315479fc00086f08e25d968b4b43c49/code/qcommon/common.c#L364
		void parse_command_line()
		{
			static auto parsed = false;
			if (parsed)
			{
				return;
			}

			static std::string comand_line_buffer = GetCommandLineA();
			auto* command_line = comand_line_buffer.data();

			auto& com_num_console_lines = *game::com_num_console_lines;
			auto* com_console_lines = game::com_console_lines.get();

			auto inq = false;
			com_console_lines[0] = command_line;
			com_num_console_lines = 0;

			while (*command_line)
			{
				if (*command_line == '"')
				{
					inq = !inq;
				}
				// look for a + separating character
				// if commandLine came from a file, we might have real line seperators
				if ((*command_line == '+' && !inq) || *command_line == '\n' || *command_line == '\r')
				{
					if (com_num_console_lines == 0x20) // MAX_CONSOLE_LINES
					{
						break;
					}
					com_console_lines[com_num_console_lines] = command_line + 1;
					com_num_console_lines++;
					*command_line = '\0';
				}
				command_line++;
			}
			parsed = true;
		}

		void parse_startup_variables()
		{
			auto& com_num_console_lines = *game::com_num_console_lines;
			auto* com_console_lines = game::com_console_lines.get();

			for (int i = 0; i < com_num_console_lines; i++)
			{
				game::Cmd_TokenizeString(com_console_lines[i]);

				// only +set dvar value
				if (game::Cmd_Argc() >= 3 && (game::Cmd_Argv(0) == "set"s || game::Cmd_Argv(0) == "seta"s))
				{
					const std::string& key = game::Cmd_Argv(1);
					const std::string& value = game::Cmd_Argv(2);

					const auto* dvar = game::Dvar_FindVar(key.data());
					if (dvar)
					{
						game::Dvar_SetCommand(key.data(), value.data());
					}
					else
					{
						dvars::callback::on_register(key, [key, value]()
						{
							game::Dvar_SetCommand(key.data(), value.data());
						});
					}
				}

				game::Cmd_EndTokenizeString();
			}
		}

		void parse_commandline()
		{
			parse_command_line();
			parse_startup_variables();

			parse_commandline_hook.invoke<void>();
		}

		game::dvar_t* dvar_command_stub()
		{
			const params args;

			if (args.size() <= 0)
			{
				return 0;
			}

			auto* dvar = game::Dvar_FindVar(args[0]);
			if (dvar == nullptr)
			{
				dvar = game::Dvar_FindMalleableVar(atoi(args[0]));
			}

			if (dvar)
			{
				if (args.size() == 1)
				{
					const std::string current = game::Dvar_ValueToString(dvar, dvar->current);
					const std::string reset = game::Dvar_ValueToString(dvar, dvar->reset);

					console::info("\"%s\" is: \"%s\" default: \"%s\" checksum: %d type: %i\n",
						dvars::dvar_get_name(dvar).data(), current.data(), reset.data(), dvar->checksum, dvar->type);

					const auto dvar_info = dvars::dvar_get_description(dvar);

					if (!dvar_info.empty())
						console::info("%s\n", dvar_info.data());

					console::info("   %s\n", dvars::dvar_get_domain(dvar->type, dvar->domain).data());
				}
				else
				{
					char command[0x1000]{};
					game::Dvar_GetCombinedString(command, 1);
					game::Dvar_SetCommand(args[0], command);
				}

				return dvar;
			}

			return 0;
		}

		void cmd_give(const int client_num, const std::vector<std::string>& params)
		{
			if (params.size() < 2)
			{
				game::shared::client_println(client_num, "You did not specify a weapon name");
				return;
			}

			try
			{
				const auto& arg = params[1];
				const auto player = scripting::entity({ static_cast<uint16_t>(client_num), 0 });

				if (arg == "ammo")
				{
					const auto weapon = player.call("getcurrentweapon").as<std::string>();
					player.call("givemaxammo", { weapon });
				}
				else if (arg == "allammo")
				{
					const auto weapons = player.call("getweaponslistall").as<scripting::array>();
					for (auto i = 0; i < weapons.size(); i++)
					{
						player.call("givemaxammo", { weapons[i] });
					}
				}
				else if (arg == "health")
				{
					if (params.size() > 2)
					{
						const auto amount = atoi(params[2].data());
						const auto health = player.get("health").as<int>();
						player.set("health", { health + amount });
					}
					else
					{
						const auto amount = atoi(game::Dvar_FindVar("scr_player_maxhealth")->current.string);
						player.set("health", { amount });
					}
				}
				else if (arg == "all")
				{
					const auto type = game::XAssetType::ASSET_TYPE_WEAPON;
					game::DB_EnumXAssets(type, [&player, type](const game::XAssetHeader header)
					{
						const auto asset = game::XAsset{ type, header };
						const auto asset_name = game::DB_GetXAssetName(&asset);

						player.call("giveweapon", { asset_name });
					});
				}
				else
				{
					player.call("giveweapon", { arg });
					player.call("switchtoweapon", { arg });
				}
			}
			catch (...)
			{
			}
		}

		void cmd_drop_weapon(int client_num)
		{
			try
			{
				const auto player = scripting::entity({ static_cast<uint16_t>(client_num), 0 });
				const auto weapon = player.call("getcurrentweapon");
				player.call("dropitem", { weapon });
			}
			catch (...)
			{
			}
		}

		void cmd_take(int client_num, const std::vector<std::string>& params)
		{
			if (params.size() < 2)
			{
				game::shared::client_println(client_num, "You did not specify a weapon name");
				return;
			}

			const auto& weapon = params[1];

			try
			{
				const auto player = scripting::entity({ static_cast<uint16_t>(client_num), 0 });
				if (weapon == "all"s)
				{
					player.call("takeallweapons");
				}
				else
				{
					player.call("takeweapon", { weapon });
				}
			}
			catch (...)
			{
			}
		}

		void cmd_spawn_clown(const int client_num)
		{
			try
			{
				const auto player = scripting::entity({ static_cast<uint16_t>(client_num), 0 });
				const scripting::entity level{ *game::levelEntityId };
				scripting::notify(level, "iwz_spawn_clown", { player });
				console::info("[IWZ][Collision] spawnClown request client=%d playerEnt=%d levelEnt=%u\n",
					client_num, player.get_entity_reference().entnum, *game::levelEntityId);
			}
			catch (const std::exception& e)
			{
				console::error("[IWZ][Collision] failed to dispatch spawnClown: %s\n", e.what());
				game::shared::client_println(client_num, "Unable to spawn clown");
			}
		}

		void cmd_zombie_scene(const int client_num, const char* command_name, const char* notify_name)
		{
			if (game::Com_GameMode_GetActiveGameMode() != game::GAME_MODE_CP)
			{
				console::warn("[IWZ][Scenes] command=%s rejected client=%d reason=not in Zombies\n",
					command_name, client_num);
				game::shared::client_println(client_num, "This command is only available in Zombies");
				return;
			}

			try
			{
				const auto player = scripting::entity({ static_cast<uint16_t>(client_num), 0 });
				const scripting::entity level{ *game::levelEntityId };
				scripting::notify(level, notify_name, { player });
				console::info("[IWZ][Scenes] command=%s dispatched notify=%s client=%d playerEnt=%d levelEnt=%u\n",
					command_name, notify_name, client_num, player.get_entity_reference().entnum, *game::levelEntityId);
			}
			catch (const std::exception& e)
			{
				console::error("[IWZ][Scenes] command=%s dispatch failed client=%d error=%s\n",
					command_name, client_num, e.what());
				game::shared::client_println(client_num, "Unable to change the current scene");
			}
		}

		void cmd_win_gns(const int client_num)
		{
			if (game::Com_GameMode_GetActiveGameMode() != game::GAME_MODE_CP)
			{
				console::warn("[IWZ][GhostsNSkullsArcade] winGNS rejected client=%d reason=not in Zombies\n",
					client_num);
				game::shared::client_println(client_num, "This command is only available in Zombies");
				return;
			}

			try
			{
				const auto player = scripting::entity({static_cast<uint16_t>(client_num), 0});
				const scripting::entity level{*game::levelEntityId};
				scripting::notify(level, "iwz_gns_win", {player});
				console::info("[IWZ][GhostsNSkullsArcade] winGNS dispatched client=%d playerEnt=%d levelEnt=%u\n",
					client_num, player.get_entity_reference().entnum, *game::levelEntityId);
			}
			catch (const std::exception& e)
			{
				console::error("[IWZ][GhostsNSkullsArcade] winGNS dispatch failed client=%d error=%s\n",
					client_num, e.what());
				game::shared::client_println(client_num, "Unable to finish Ghosts N Skulls");
			}
		}

		void cmd_paproom(const int client_num)
		{
			try
			{
				const auto player = scripting::entity({static_cast<uint16_t>(client_num), 0});
				const scripting::entity level{*game::levelEntityId};
				scripting::notify(level, "iwz_paproom", {player});
				console::info("[IWZ][PaPRoom] teleport request client=%d playerEnt=%d levelEnt=%u\n",
					client_num, player.get_entity_reference().entnum, *game::levelEntityId);
			}
			catch (const std::exception& e)
			{
				console::error("[IWZ][PaPRoom] failed to dispatch teleport: %s\n", e.what());
				game::shared::client_println(client_num, "Unable to teleport to Pack-a-Punch room");
			}
		}

		void cmd_test_barrier_tier(const int client_num, const char* command_name, const char* notify_name)
		{
			if (game::Com_GameMode_GetActiveGameMode() != game::GAME_MODE_CP)
			{
				console::warn("[IWZ][Challenges] command=%s rejected client=%d reason=not in Zombies\n",
					command_name, client_num);
				game::shared::client_println(client_num, "This command is only available in Zombies");
				return;
			}

			try
			{
				const auto player = scripting::entity({static_cast<uint16_t>(client_num), 0});
				const scripting::entity level{*game::levelEntityId};
				scripting::notify(level, notify_name, {player});
				console::info("[IWZ][Challenges] command=%s dispatched notify=%s client=%d playerEnt=%d levelEnt=%u\n",
					command_name, notify_name, client_num, player.get_entity_reference().entnum, *game::levelEntityId);
			}
			catch (const std::exception& e)
			{
				console::error("[IWZ][Challenges] command=%s dispatch failed client=%d error=%s\n",
					command_name, client_num, e.what());
				game::shared::client_println(client_num, "Unable to stage the barrier challenge");
			}
		}

		void cmd_test_alien_kill(const int client_num)
		{
			if (game::Com_GameMode_GetActiveGameMode() != game::GAME_MODE_CP)
			{
				console::warn("[IWZ][Spaceland] testAlienKill rejected client=%d reason=not in Zombies\n",
					client_num);
				game::shared::client_println(client_num, "This command is only available in Zombies");
				return;
			}

			const auto* mapname = game::Dvar_FindVar("ui_mapname");
			if (!mapname || !mapname->current.string || _stricmp(mapname->current.string, "cp_zmb") != 0)
			{
				console::warn("[IWZ][Spaceland] testAlienKill rejected client=%d reason=not on cp_zmb\n",
					client_num);
				game::shared::client_println(client_num, "This command is only available on Zombies in Spaceland");
				return;
			}

			try
			{
				const auto player = scripting::entity({static_cast<uint16_t>(client_num), 0});
				const scripting::entity level{*game::levelEntityId};
				scripting::notify(level, "iwz_test_alien_kill", {player});
				console::info("[IWZ][Spaceland] testAlienKill dispatched client=%d playerEnt=%d levelEnt=%u\n",
					client_num, player.get_entity_reference().entnum, *game::levelEntityId);
			}
			catch (const std::exception& e)
			{
				console::error("[IWZ][Spaceland] testAlienKill dispatch failed client=%d error=%s\n",
					client_num, e.what());
				game::shared::client_println(client_num, "Unable to simulate the Alien kill");
			}
		}

		void cmd_spawn_alien_fuses(const int client_num)
		{
			if (game::Com_GameMode_GetActiveGameMode() != game::GAME_MODE_CP)
			{
				console::warn("[IWZ][Spaceland] spawnAlienFuses rejected client=%d reason=not in Zombies\n",
					client_num);
				game::shared::client_println(client_num, "This command is only available in Zombies");
				return;
			}

			const auto* mapname = game::Dvar_FindVar("ui_mapname");
			if (!mapname || !mapname->current.string || _stricmp(mapname->current.string, "cp_zmb") != 0)
			{
				console::warn("[IWZ][Spaceland] spawnAlienFuses rejected client=%d reason=not on cp_zmb\n",
					client_num);
				game::shared::client_println(client_num, "This command is only available on Zombies in Spaceland");
				return;
			}

			try
			{
				const auto player = scripting::entity({static_cast<uint16_t>(client_num), 0});
				const scripting::entity level{*game::levelEntityId};
				scripting::notify(level, "iwz_spawn_alien_fuses", {player});
				console::info("[IWZ][Spaceland] spawnAlienFuses dispatched client=%d playerEnt=%d levelEnt=%u\n",
					client_num, player.get_entity_reference().entnum, *game::levelEntityId);
			}
			catch (const std::exception& e)
			{
				console::error("[IWZ][Spaceland] spawnAlienFuses dispatch failed client=%d error=%s\n",
					client_num, e.what());
				game::shared::client_println(client_num, "Unable to spawn the Alien fuses");
			}
		}

		void cmd_give_petn(const int client_num)
		{
			if (game::Com_GameMode_GetActiveGameMode() != game::GAME_MODE_CP)
			{
				console::warn("[IWZ][AttackFixes] givePetn rejected client=%d reason=not in Zombies\n",
					client_num);
				game::shared::client_println(client_num, "This command is only available in Zombies");
				return;
			}

			const auto* mapname = game::Dvar_FindVar("ui_mapname");
			if (!mapname || !mapname->current.string || _stricmp(mapname->current.string, "cp_town") != 0)
			{
				console::warn("[IWZ][AttackFixes] givePetn rejected client=%d reason=not on cp_town\n",
					client_num);
				game::shared::client_println(client_num, "This command is only available on Attack of the Radioactive Thing");
				return;
			}

			try
			{
				const auto player = scripting::entity({static_cast<uint16_t>(client_num), 0});
				const scripting::entity level{*game::levelEntityId};
				scripting::notify(level, "iwz_give_petn", {player});
				console::info("[IWZ][AttackFixes] givePetn dispatched client=%d playerEnt=%d levelEnt=%u\n",
					client_num, player.get_entity_reference().entnum, *game::levelEntityId);
			}
			catch (const std::exception& e)
			{
				console::error("[IWZ][AttackFixes] givePetn dispatch failed client=%d error=%s\n",
					client_num, e.what());
				game::shared::client_println(client_num, "Unable to give the requested chemical");
			}
		}
	}

	params::params()
		: nesting_(game::cmd_args->nesting)
	{
	}

	int params::size() const
	{
		return game::cmd_args->argc[this->nesting_];
	}

	const char* params::get(const int index) const
	{
		if (index >= this->size())
		{
			return "";
		}

		return game::cmd_args->argv[this->nesting_][index];
	}

	std::string params::join(const int index) const
	{
		std::string result = {};

		for (auto i = index; i < this->size(); i++)
		{
			if (i > index) result.append(" ");
			result.append(this->get(i));
		}
		return result;
	}

	std::vector<std::string> params::get_all() const
	{
		std::vector<std::string> params_;
		for (auto i = 0; i < this->size(); i++)
		{
			params_.push_back(this->get(i));
		}
		return params_;
	}

	params_sv::params_sv()
		: nesting_(game::sv_cmd_args->nesting)
	{
	}

	int params_sv::size() const
	{
		return game::sv_cmd_args->argc[this->nesting_];
	}

	const char* params_sv::get(const int index) const
	{
		if (index >= this->size())
		{
			return "";
		}

		return game::sv_cmd_args->argv[this->nesting_][index];
	}

	std::string params_sv::join(const int index) const
	{
		std::string result = {};

		for (auto i = index; i < this->size(); i++)
		{
			if (i > index) result.append(" ");
			result.append(this->get(i));
		}
		return result;
	}

	std::vector<std::string> params_sv::get_all() const
	{
		std::vector<std::string> params_;
		for (auto i = 0; i < this->size(); i++)
		{
			params_.push_back(this->get(i));
		}
		return params_;
	}

	void add_raw(const char* name, void (*callback)())
	{
		game::Cmd_AddCommandInternal(name, callback, utils::memory::get_allocator()->allocate<game::cmd_function_s>());
	}

	void add(const char* name, const std::function<void(const params&)>& callback)
	{
		const auto command = utils::string::to_lower(name);

		if (handlers.find(command) == handlers.end())
			add_raw(name, main_handler);

		handlers[command] = callback;
	}

	void add(const char* name, const std::function<void()>& callback)
	{
		add(name, [callback](const params&)
		{
			callback();
		});
	}

	void add_sv(const char* name, std::function<void(int, const params_sv&)> callback)
	{
		// doing this so the sv command would show up in the console
		add_raw(name, nullptr);

		const auto command = utils::string::to_lower(name);

		if (handlers_sv.find(command) == handlers_sv.end())
			handlers_sv[command] = std::move(callback);
	}

	void execute(std::string command, const bool sync)
	{
		command += "\n";

		if (sync)
		{
			game::Cmd_ExecuteSingleCommand(0, 0, command.data());
		}
		else
		{
			game::Cbuf_AddText(0, command.data());
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			game::Dvar_RegisterBool("iwz_gsc_diagnostics", true, game::DVAR_FLAG_SAVED,
				"Enable diagnostics emitted by custom GSC patches");
			game::Dvar_RegisterInt("iwz_powerup_drop_base_interval", 2250, 0, 10000, game::DVAR_FLAG_SAVED,
				"Base team-score interval between Zombies powerup drops (0 preserves stock behavior)");
			game::Dvar_RegisterInt("iwz_powerup_drop_interval_revision", 0, 0, 1, game::DVAR_FLAG_SAVED,
				"Internal migration revision for the Zombies powerup drop interval");
			game::Dvar_RegisterBool("iwz_spaceland_double_pap_unlocked", false, game::DVAR_FLAG_SAVED,
				"Whether inserting Spaceland's Alien fuses has permanently unlocked double Pack-a-Punch");
			game::Dvar_RegisterInt("iwz_powerup_weight_infinite_grenades", 2, 1, 100, game::DVAR_FLAG_SAVED,
				"Relative drop weight for the Infinite Grenades powerup (stock is 5)");
			game::Dvar_RegisterInt("iwz_powerup_weight_carpenter", 3, 1, 100, game::DVAR_FLAG_SAVED,
				"Relative drop weight for the Carpenter powerup (stock is 5)");
			game::Dvar_RegisterInt("iwz_powerup_weight_max_ammo", 12, 1, 100, game::DVAR_FLAG_SAVED,
				"Relative drop weight for the Max Ammo powerup (stock is 10)");
			game::Dvar_RegisterInt("iwz_powerup_weight_double_money", 6, 1, 100, game::DVAR_FLAG_SAVED,
				"Relative drop weight for the Double Money powerup (stock is 5)");
			game::Dvar_RegisterInt("iwz_powerup_weight_insta_kill", 12, 1, 100, game::DVAR_FLAG_SAVED,
				"Relative drop weight for the Insta-Kill powerup (stock is 10)");
			game::Dvar_RegisterFloat("iwz_low_health_blood_alpha", 0.75f, 0.0f, 0.85f, game::DVAR_FLAG_SAVED,
				"Maximum opacity of the Zombies low-health blood overlay (stock is 0.85)");
			game::Dvar_RegisterFloat("iwz_low_health_blood_scale", 0.25f, 0.10f, 1.0f, game::DVAR_FLAG_SAVED,
				"Center-origin scale of the Zombies low-health blood overlay (stock is 0.10; larger pushes blood toward the edges)");
			game::Dvar_RegisterBool("iwz_double_xp", false, game::DVAR_FLAG_SAVED,
				"Double Zombies level and weapon XP");
			game::Dvar_RegisterInt("iwz_challenge_tier5_xp", 2500, 1, 100000, game::DVAR_FLAG_SAVED,
				"Base XP awarded by Tier 5 Zombies challenges");
			game::Dvar_RegisterInt("iwz_challenge_splash_duration_ms", 3000, 2500, 10000, game::DVAR_FLAG_SAVED,
				"Display duration for Zombies challenge progression splashes (stock is 2500 ms)");
			game::Dvar_RegisterBool("iwz_collision_debug", true, game::DVAR_FLAG_SAVED,
				"Log zombie traversal collision and test-spawn diagnostics");
			game::Dvar_RegisterFloat("iwz_zombie_sprint_speed_scale", 0.95f, 0.10f, 1.0f, game::DVAR_FLAG_SAVED,
				"Movement-rate scale for standard sprinting Zombies (stock is 1.0)");

			utils::hook::jump(0x140BB1DC0, dvar_command_stub, true);
			client_command_mp_hook.create(0x140B105D0, &client_command_mp);
			client_command_sp_hook.create(0x140483130, &client_command_sp);

			parse_commandline_hook.create(0x140C039F0, parse_commandline); // SL_Init

			scheduler::once([]()
			{
				game::Dvar_RegisterString("iwz_match_calling_card_rewards", "", game::DVAR_FLAG_NONE,
					"Match-scoped Zombies calling-card refs and XP carried into the after-action report");
				game::Dvar_RegisterString("iwz_match_weapon_level_rewards", "", game::DVAR_FLAG_NONE,
					"Match-scoped Zombies weapon levels carried into the after-action report");
				console::info("[IWZ][MatchSummaryRewards] registered match calling-card and weapon-level bridge dvars on main scheduler\n");
			}, scheduler::main);

			add_commands();
		}

	private:
		static void add_commands()
		{
			add("quit", []()
			{
				*game::g_quitRequested = true;
			});

			add("crash", []()
			{
				*reinterpret_cast<int*>(1) = 0;
			});

			add("noMode", []()
			{
				game::Com_GameMode_SetDesiredGameMode(game::GAME_MODE_NONE);
			});

			add("spMode", []()
			{
				game::Com_GameMode_SetDesiredGameMode(game::GAME_MODE_SP);
			});

			add("mpMode", []()
			{
				game::Com_GameMode_SetDesiredGameMode(game::GAME_MODE_MP);
			});

			add("cpMode", []()
			{
				game::Com_GameMode_SetDesiredGameMode(game::GAME_MODE_CP);
			});

			add("bindlist", []()
			{
				game::Key_Bindlist_f();
			});

			add_sv("god", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				game::g_entities[client_num].flags ^= 1;
				game::shared::client_println(client_num,
					game::g_entities[client_num].flags & 1
					? "GAME_GODMODE_ON"
					: "GAME_GODMODE_OFF");
			});

			add_sv("demigod", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				game::g_entities[client_num].flags ^= 2;
				game::shared::client_println(client_num,
					game::g_entities[client_num].flags & 2
					? "GAME_DEMI_GODMODE_ON"
					: "GAME_DEMI_GODMODE_OFF");
			});

			add_sv("notarget", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				game::g_entities[client_num].flags ^= 4;
				game::shared::client_println(client_num,
					game::g_entities[client_num].flags & 4
					? "GAME_NOTARGETON"
					: "GAME_NOTARGETOFF");
			});

			add_sv("noclip", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				game::g_entities[client_num].client->flags ^= 1;
				game::shared::client_println(client_num,
					game::g_entities[client_num].client->flags & 1
					? "GAME_NOCLIPON"
					: "GAME_NOCLIPOFF");
			});

			add_sv("ufo", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				game::g_entities[client_num].client->flags ^= 2;
				game::shared::client_println(client_num,
					game::g_entities[client_num].client->flags & 2
					? "GAME_UFOON"
					: "GAME_UFOOFF");
			});

			add_sv("give", [](const int client_num, const params_sv& params)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				cmd_give(client_num, params.get_all());
			});

			add_sv("dropweapon", [](const int client_num, const params_sv& params)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				cmd_drop_weapon(client_num);
			});

			add_sv("take", [](const int client_num, const params_sv& params)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				cmd_take(client_num, params.get_all());
			});

			add_sv("spawnClown", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				cmd_spawn_clown(client_num);
			});

			add_sv("paproom", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				cmd_paproom(client_num);
			});

			add_sv("givePetn", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				cmd_give_petn(client_num);
			});

			add_sv("winGNS", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				cmd_win_gns(client_num);
			});

			add_sv("testBarrierTier1", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				cmd_test_barrier_tier(client_num, "testBarrierTier1", "iwz_test_barrier_tier1");
			});

			add_sv("testBarrierTier5", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				cmd_test_barrier_tier(client_num, "testBarrierTier5", "iwz_test_barrier_tier5");
			});

			add_sv("testAlienKill", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				cmd_test_alien_kill(client_num);
			});

			add_sv("spawnAlienFuses", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				cmd_spawn_alien_fuses(client_num);
			});

			add_sv("scene100", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				cmd_zombie_scene(client_num, "scene100", "iwz_scene_100");
			});

			add_sv("endScene", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				cmd_zombie_scene(client_num, "endScene", "iwz_end_scene");
			});
		}
	};
}

REGISTER_COMPONENT(command::component)
