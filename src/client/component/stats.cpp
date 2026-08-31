#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"
#include "game/dvars.hpp"

#include "command.hpp"
#include "console/console.hpp"
#include "dvars.hpp"
#include "fastfiles.hpp"
#include "scheduler.hpp"

#include <utils/hook.hpp>
#include <utils/string.hpp>

#include <array>
#include <list>

namespace stats
{
	namespace
	{
		utils::hook::detour is_item_unlocked_hook;
		utils::hook::detour is_item_unlocked_hook2;
		utils::hook::detour item_quantity_hook;

		game::dvar_t* cg_loot_count = nullptr;
		game::dvar_t* director_cut_dvar = nullptr;
		game::dvar_t* cg_unlimited_cards = nullptr;

		constexpr auto zombies_rank_table_name = "cp/zombies/rankTable.csv";
		constexpr auto zombies_rank_count = 999;
		constexpr auto rank_id_column = 0;
		constexpr auto rank_min_xp_column = 2;
		constexpr auto rank_next_xp_column = 3;
		constexpr auto rank_max_xp_column = 7;

		std::mutex zombies_rank_table_mutex;
		std::list<std::string> zombies_rank_table_values;
		std::unordered_set<const database::StringTable*> scaled_zombies_rank_tables;

		bool parse_nonnegative_integer(const char* value, int& result)
		{
			if (value == nullptr || *value == '\0')
			{
				return false;
			}

			char* end = nullptr;
			const auto parsed = std::strtol(value, &end, 10);
			if (end == value || *end != '\0' || parsed < 0 || parsed > INT_MAX)
			{
				return false;
			}

			result = static_cast<int>(parsed);
			return true;
		}

		int string_table_hash(const std::string_view value)
		{
			std::uint32_t hash = 0;
			for (const auto character : value)
			{
				hash = hash * 31 + static_cast<unsigned char>(std::tolower(static_cast<unsigned char>(character)));
			}
			return static_cast<int>(hash);
		}

		void assign_rank_table_integer(database::StringTable* table, const int row, const int column,
			const std::int64_t value)
		{
			zombies_rank_table_values.emplace_back(std::to_string(value));
			auto& cell = table->values[row * table->columnCount + column];
			cell.string = zombies_rank_table_values.back().c_str();
			cell.hash = string_table_hash(cell.string);
		}

		void reduce_zombies_rank_xp(database::StringTable* table)
		{
			if (table == nullptr || table->name == nullptr ||
				(_stricmp(table->name, zombies_rank_table_name) != 0 &&
					_stricmp(table->name, "cp\\zombies\\rankTable.csv") != 0))
			{
				return;
			}

			std::scoped_lock lock(zombies_rank_table_mutex);
			if (scaled_zombies_rank_tables.contains(table))
			{
				console::debug("[IWZ][Progression] skipped already-scaled Zombies rank table asset=%p\n", table);
				return;
			}

			if (table->values == nullptr || table->columnCount <= rank_max_xp_column)
			{
				console::error("[IWZ][Progression] could not scale Zombies rank table name='%s' rows=%d columns=%d values=%p\n",
					table->name, table->rowCount, table->columnCount, table->values);
				return;
			}

			std::array<int, zombies_rank_count> rows_by_rank;
			std::array<int, zombies_rank_count> original_xp_to_next;
			std::array<int, zombies_rank_count> reduced_xp_to_next;
			rows_by_rank.fill(-1);

			int found_ranks = 0;
			for (auto row = 0; row < table->rowCount; ++row)
			{
				int rank = 0;
				const auto* rank_value = table->values[row * table->columnCount + rank_id_column].string;
				if (!parse_nonnegative_integer(rank_value, rank) || rank >= zombies_rank_count)
				{
					continue;
				}

				if (rows_by_rank[rank] != -1)
				{
					console::error("[IWZ][Progression] could not scale Zombies rank table duplicateRank=%d firstRow=%d duplicateRow=%d\n",
						rank, rows_by_rank[rank], row);
					return;
				}

				int xp_to_next = 0;
				const auto* xp_value = table->values[row * table->columnCount + rank_next_xp_column].string;
				if (!parse_nonnegative_integer(xp_value, xp_to_next) || xp_to_next == 0)
				{
					console::error("[IWZ][Progression] could not scale Zombies rank table rank=%d row=%d xpToNext='%s'\n",
						rank, row, xp_value ? xp_value : "<null>");
					return;
				}

				rows_by_rank[rank] = row;
				original_xp_to_next[rank] = xp_to_next;
				reduced_xp_to_next[rank] = static_cast<int>((static_cast<std::int64_t>(xp_to_next) * 9 + 5) / 10);
				++found_ranks;
			}

			if (found_ranks != zombies_rank_count ||
				std::ranges::any_of(rows_by_rank, [](const int row) { return row < 0; }))
			{
				console::error("[IWZ][Progression] could not scale Zombies rank table expectedRanks=%d foundRanks=%d rows=%d\n",
					zombies_rank_count, found_ranks, table->rowCount);
				return;
			}

			std::int64_t original_total = 0;
			std::int64_t reduced_total = 0;
			for (auto rank = 0; rank < zombies_rank_count; ++rank)
			{
				const auto row = rows_by_rank[rank];
				const auto minimum_xp = reduced_total;
				original_total += original_xp_to_next[rank];
				reduced_total += reduced_xp_to_next[rank];

				assign_rank_table_integer(table, row, rank_min_xp_column, minimum_xp);
				assign_rank_table_integer(table, row, rank_next_xp_column, reduced_xp_to_next[rank]);
				assign_rank_table_integer(table, row, rank_max_xp_column, reduced_total);
			}

			scaled_zombies_rank_tables.emplace(table);
			console::info("[IWZ][Progression] reduced Zombies level XP by 10 percent ranks=1-%d rounding=nearest originalTotal=%lld reducedTotal=%lld level1=%d->%d level999=%d->%d\n",
				zombies_rank_count, original_total, reduced_total, original_xp_to_next.front(), reduced_xp_to_next.front(),
				original_xp_to_next.back(), reduced_xp_to_next.back());
		}

		bool is_item_unlocked_stub(__int64 a1, int a2, const char* unlock_table, unsigned __int8* value)
		{
			if (dvars::cg_unlockall_items && dvars::cg_unlockall_items->current.enabled)
			{
				return true;
			}

			return is_item_unlocked_hook.invoke<bool>(a1, a2, unlock_table, value);
		}

		bool is_item_unlocked_stub2(__int64 a1, int a2, const char* unlock_table, unsigned __int8* value)
		{
			if (dvars::cg_unlockall_items && dvars::cg_unlockall_items->current.enabled)
			{
				return true;
			}

			return is_item_unlocked_hook2.invoke<bool>(a1, a2, unlock_table, value);
		}

		int item_quantity_stub(__int64 a1, int a2, int id)
		{
			auto result = item_quantity_hook.invoke<int>(a1, a2, id);

			if (id >= 170013 && id <= 170061 && cg_unlimited_cards && cg_unlimited_cards->current.enabled)
			{
				return 999;
			}

			// 30000 crashes
			if (id != 30000 && dvars::cg_unlockall_loot && dvars::cg_unlockall_loot->current.enabled)
			{
				if (cg_loot_count)
				{
					return cg_loot_count->current.integer;
				}
			}

			return result;
		}

		void com_ddl_print_state(const game::DDLState* state, const game::DDLContext* context)
		{
			if (game::DDL_StateIsLeaf(state))
			{
				const auto type = game::DDL_GetType(state);
				const auto value = game::DDL_GetValue(state, context);
				switch (type)
				{
				case game::DDL_BYTE_TYPE:
				case game::DDL_SHORT_TYPE:
				case game::DDL_UINT_TYPE:
				case game::DDL_INT_TYPE:
					console::info("%d\n", value.intValue);
					break;
				case game::DDL_UINT64_TYPE:
					console::info("%zu\n", value.uint64Value);
					break;
				case game::DDL_FLOAT_TYPE:
					console::info("%f\n", value.floatValue);
					break;
				case game::DDL_STRING_TYPE:
					console::info("%s\n", value.stringPtr);
					break;
				case game::DDL_ENUM_TYPE:
					console::info("%s\n", game::DDL_Lookup_GetEnumString(state, value.intValue));
					break;
				default:
					console::info("Unknown type (%d).\n", type);
					break;
				}
			}
			else
			{
				console::info("non leaf node named \"%s\"\n", state->member->name);
			}
		}

		bool can_run_command()
		{
			if (game::CL_IsGameClientActive(0))
			{
				console::error("Not allowed while ingame.");
				return false;
			}

			if (game::Com_GameMode_GetActiveGameMode() != game::GAME_MODE_MP && game::Com_GameMode_GetActiveGameMode() != game::GAME_MODE_CP)
			{
				console::error("Must be in multiplayer or coop.");
				return false;
			}

			return true;
		}

		void unlock_stats()
		{
			if (!can_run_command())
			{
				return;
			}

			// experience & prestige
			command::execute("setRankedPlayerData progression playerLevel xp 1457200", true);
			command::execute("setRankedPlayerData progression playerLevel prestige 30", true);

			command::execute("setCoopPlayerData progression playerLevel xp 95297348", true);

			// weapon experience
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_nrg mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_g18 mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_emc mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_revolver mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_erad mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_crb mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_ripper mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_ump45 mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_fhr mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_ar57 mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_ake mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_m4 mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_aracc mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_fmg mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_sdfar mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_kbs mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_cheytac mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_m8 mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_m1 mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_devastator mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_spas mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_sonic mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_sdfshotty mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_mauler mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_sdflmg mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_lmg03 mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_g18c mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_ump45c mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_cheytacc mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_m1c mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_spasc mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_arclassic mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_rvn mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_udm45 mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_crdb mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_vr mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_mp28 mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_minilmg mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_mod2187 mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_ba50cal mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_gauss mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_longshot mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_mag mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_unsalmg mpXP 54299", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_tacburst mpXP 54299", true);

			// weapon prestige
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_nrg prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_g18 prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_emc prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_revolver prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_erad prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_crb prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_ripper prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_ump45 prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_fhr prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_ar57 prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_ake prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_m4 prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_aracc prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_fmg prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_sdfar prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_kbs prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_cheytac prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_m8 prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_m1 prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_devastator prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_spas prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_sonic prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_sdfshotty prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_mauler prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_sdflmg prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_lmg03 prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_g18c prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_ump45c prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_cheytacc prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_m1c prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_spasc prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_arclassic prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_rvn prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_udm45 prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_crdb prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_vr prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_mp28 prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_minilmg prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_mod2187 prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_ba50cal prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_gauss prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_longshot prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_mag prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_unsalmg prestige 3", true);
			command::execute("setCommonPlayerData sharedProgression weaponLevel iw7_tacburst prestige 3", true);

			// classic weapons
			command::execute("setCommonPlayerData sharedProgression classicWeapons iw7_g18c 1", true);
			command::execute("setCommonPlayerData sharedProgression classicWeapons iw7_ump45c 1", true);
			command::execute("setCommonPlayerData sharedProgression classicWeapons iw7_cheytacc 1", true);
			command::execute("setCommonPlayerData sharedProgression classicWeapons iw7_spasc 1", true);
			command::execute("setCommonPlayerData sharedProgression classicWeapons iw7_m1c 1", true);

			// Unlock challenges
			game::StringTable* challenge_table = game::DB_FindXAssetHeader(game::XAssetType::ASSET_TYPE_STRINGTABLE, "mp/allchallengestable.csv", false).stringTable;
			if (challenge_table)
			{
				for (int i = 0; i < challenge_table->rowCount; i++)
				{
					// Find challenge
					const char* challenge = game::StringTable_GetColumnValueForRow(challenge_table, i, 0);

					int max_state = 0;
					int max_progress = 0;

					// Find correct tier and progress
					for (int j = 0; j < 10; j++) // iterate through states (max 10)
					{
						// progress, xp_reward, challenge_score

						int progress = atoi(game::StringTable_GetColumnValueForRow(challenge_table, i, 10 + (j * 3)));
						if (!progress) break;

						max_state = j + 1;
						max_progress = progress;
					}

					command::execute(utils::string::va("setRankedPlayerData challengeState %s %d", challenge, max_state), true);
					command::execute(utils::string::va("setRankedPlayerData challengeProgress %s %d", challenge, max_progress), true);
				}
			}

			game::StringTable* merit_table = game::DB_FindXAssetHeader(game::XAssetType::ASSET_TYPE_STRINGTABLE, "cp/allmeritstable.csv", false).stringTable;
			if (merit_table)
			{
				for (int i = 0; i < merit_table->rowCount; i++)
				{
					// Find challenge
					const char* challenge = game::StringTable_GetColumnValueForRow(merit_table, i, 0);

					int max_state = 0;
					int max_progress = 0;

					// Find correct tier and progress
					for (int j = 0; j < 10; j++) // iterate through states (max 10)
					{
						// progress, xp_reward, challenge_score

						int progress = atoi(game::StringTable_GetColumnValueForRow(merit_table, i, 10 + (j * 3)));
						if (!progress) break;

						max_state = j + 1;
						max_progress = progress;
					}

					command::execute(utils::string::va("setCoopPlayerData meritState %s %d", challenge, max_state), true);
					command::execute(utils::string::va("setCoopPlayerData meritProgress %s %d", challenge, max_progress), true);
				}
			}

			// fix
			command::execute("setRankedPlayerData mp challengeScore 0", true);

			command::execute("uploadstats", true); // needed to update stats i think
			console::debug("unlocked all normal stats!\n");
		}
		
		void unlock_stats_ee()
		{
			if (!can_run_command())
			{
				return;
			}

			// soul keys (secret characters)
			command::execute("setCoopPlayerData haveSoulKeys any_soul_key 1", true); // useless stat?
			command::execute("setCoopPlayerData haveSoulKeys soul_key_1 1", true);
			command::execute("setCoopPlayerData haveSoulKeys soul_key_2 1", true);
			command::execute("setCoopPlayerData haveSoulKeys soul_key_3 1", true);
			command::execute("setCoopPlayerData haveSoulKeys soul_key_4 1", true);
			command::execute("setCoopPlayerData haveSoulKeys soul_key_5 1", true);

			// secret character 5 on cp_zmb
			command::execute("setCoopPlayerData meritState mt_dlc4_troll2 1", true); // Conditions.HasBeatenMeph
			command::execute("setCoopPlayerData meritState mt_dc_camo 1", true);

			// lobby songs unlocked
			command::execute("setCoopPlayerData hasSongsUnlocked any_song 1", true);
			for (int index = 1; index < 11; index++)
			{
				command::execute(utils::string::va("setCoopPlayerData hasSongsUnlocked song_%d 1", index), true);
			}

			command::execute("uploadstats", true); // needed to update stats i think
			console::debug("unlocked all easter egg stats!\n");
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			fastfiles::on_string_table_loaded(reduce_zombies_rank_xp);
			console::info("[IWZ][Progression] registered Zombies rank-table XP reduction table='%s' ranks=1-%d percent=10 rounding=nearest\n",
				zombies_rank_table_name, zombies_rank_count);

			if (!game::environment::is_dedi())
			{
				command::add("unlockstats", unlock_stats);
				command::add("unlockall", unlock_stats);
				command::add("unlockstatsEE", unlock_stats_ee);
				command::add("unlockallEE", unlock_stats_ee);

				director_cut_dvar = game::Dvar_RegisterBool("director_cut", false, game::DVAR_FLAG_SAVED, "Whether the Directors Cut features and perks should be enabled or disabled.");
				dvars::callback::on_new_value("director_cut", [](game::DvarValue* value)
				{
					const auto is_enabled = value->integer;
					command::execute(utils::string::va("setCoopPlayerData dc %d", is_enabled), true);
					command::execute(utils::string::va("setCoopPlayerData dc_available %d", is_enabled), true);
					command::execute("uploadstats", true);
				});
			}

			// register dvars
			auto default_value = false;
			auto default_flag = game::DVAR_FLAG_SAVED;

			if (game::environment::is_dedi())
			{
				default_value = true;
				default_flag = game::DVAR_FLAG_READ;
			}

			dvars::cg_unlockall_items = game::Dvar_RegisterBool("cg_unlockall_items", default_value, default_flag, "Whether items should be locked based on the player's stats or always unlocked.");
			game::Dvar_RegisterBool("cg_unlockall_classes", default_value, default_flag, "Whether classes should be locked based on the player's stats or always unlocked."); // TODO: need LUI scripting
			dvars::cg_unlockall_loot = game::Dvar_RegisterBool("cg_unlockall_loot", default_value, default_flag, "Whether loot should be locked based on the player's stats or always unlocked.");

			cg_loot_count = game::Dvar_RegisterInt("cg_loot_count", 1, 1, 99999, game::DVAR_FLAG_SAVED, "Amount of loot to give for items");
			cg_unlimited_cards = game::Dvar_RegisterBool("cg_unlimited_cards", default_value, default_flag, "Whether Fortune Cards should be unlimited.");

			// unlockables
			is_item_unlocked_hook.create(0x14034E020, is_item_unlocked_stub);
			is_item_unlocked_hook2.create(0x14034CF40, is_item_unlocked_stub2);

			// loot
			item_quantity_hook.create(0x14051DBE0, item_quantity_stub);

			if (!game::environment::is_dedi())
			{
				// GetPlayerData print
				utils::hook::jump(0x140B84F00, com_ddl_print_state); // Com_DDL_PrintState

				utils::hook::set<byte>(0x140B86230, 0xEB); // Allow setting stats with connstate > 9
			}
		}
	};
}

REGISTER_COMPONENT(stats::component)
