#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "localized_strings.hpp"

#include "component/console/console.hpp"
#include "component/fastfiles.hpp"

#include "game/game.hpp"

#include <utils/hook.hpp>
#include <utils/string.hpp>
#include <utils/concurrency.hpp>

namespace localized_strings
{
	namespace
	{
		utils::hook::detour seh_string_ed_get_string_hook;

		using localized_map = std::unordered_map<std::string, std::string>;
		utils::concurrency::container<localized_map> localized_overrides;
		utils::concurrency::container<localized_map> colorized_bindings;
		utils::concurrency::container<localized_map> localized_asset_overrides;
		utils::concurrency::container<std::unordered_set<std::string>> applied_registered_asset_keys;
		utils::concurrency::container<std::unordered_set<std::string>> logged_missing_registered_asset_keys;
		std::atomic_bool logged_binding_color_fix{false};
		std::atomic_bool logged_survival_objective_override{false};

		struct localization_override
		{
			const char* key;
			const char* value;
		};

		constexpr localization_override bounty_description_overrides[]
		{
			{"ZM_CONTRACTS_WEEK_DESC", "New Zombies Bounties are available for the week."},
			{"ZM_CONTRACTS_KILLS_HEADSHOTS", "Earn ^3&&1^7 headshot kills."},
			{"ZM_CONTRACTS_CASH_EARNED", "Earn ^3&&1^7 cash."},
			{"ZM_CONTRACTS_KILLS_GOLF", "Earn ^3&&1^7 golf club kills."},
			{"ZM_CONTRACTS_KILLS_BAT", "Earn ^3&&1^7 bat kills."},
			{"ZM_CONTRACTS_KILLS_AXE", "Earn ^3&&1^7 axe kills."},
			{"ZM_CONTRACTS_KILLS_MACHETE", "Earn ^3&&1^7 machete kills."},
			{"ZM_CONTRACTS_KILLS_CLEAVER", "Earn ^3&&1^7 cleaver kills."},
			{"ZM_CONTRACTS_KILLS_CROWBAR", "Earn ^3&&1^7 crowbar kills."},
			{"ZM_CONTRACTS_BUY_DOORS", "Buy ^3&&1^7 doors."},
			{"ZM_CONTRACTS_KILLS_DRAGON", "Earn ^3&&1^7 Dragon Style kills."},
			{"ZM_CONTRACTS_KILLS_CRANE", "Earn ^3&&1^7 Crane Style kills."},
			{"ZM_CONTRACTS_KILLS_SNAKE", "Earn ^3&&1^7 Snake Style kills."},
			{"ZM_CONTRACTS_KILLS_TIGER", "Earn ^3&&1^7 Tiger Style kills."},
			{"ZM_CONTRACTS_CONSUMBALES_USED", "Use ^3&&1^7 Fate and Fortune Cards."},
			{"ZM_CONTRACTS_REBOARD_WINDOWS", "Board up ^3&&1^7 windows."},
			{"ZM_CONTRACTS_KILLS_CLOWNS", "Kill ^3&&1^7 Clowns."},
			{"ZM_CONTRACTS_KILLS_SASQUATCHES", "Kill ^3&&1^7 Sasquatches."},
			{"ZM_CONTRACTS_KILLS_SKATERS", "Kill ^3&&1^7 Roller Skaters."},
			{"ZM_CONTRACTS_KILL_CROGS", "Kill ^3&&1^7 Crogs."},
			{"ZM_CONTRACTS_WAVES", "Complete ^3&&1^7 scenes."},
			{"ZM_CONTRACTS_TRAP_KILLS", "Earn ^3&&1^7 trap kills."},
			{"ZM_CONTRACTS_MAGIC_WHEEL", "Use the magic wheel ^3&&1^7 times."},
			{"ZM_CONTRACTS_HOFF_SPAWN", "Call in The Hoff ^3&&1^7 times."},
			{"ZM_CONTRACTS_ELVIRA_SPAWN", "Summon Elvira ^3&&1^7 times."},
			{"ZM_CONTRACTS_CASH_SPENT", "Spend ^3&&1^7 cash."},
			{"ZM_CONTRACTS_CHALLENGE_BADGES", "Earn ^3&&1^7 Challenge Badges."},
			{"ZM_CONTRACTS_CRAFTED_KILLS", "Earn ^3&&1^7 kills with crafted items."},
			{"ZM_CONTRACTS_COASTER_TARGETS", "Hit ^3&&1^7 targets on the Polar Peak coaster."},
			{"ZM_CONTRACTS_SHOOTING_GALLERY", "Shoot ^3&&1^7 UFOs in Octonian Hunter."},
			{"ZM_CONTRACTS_TICKETS_SPEND", "Spend ^3&&1^7 tickets."},
			{"ZM_CONTRACTS_KILLS_EXPLOSIVE", "Earn ^3&&1^7 explosive kills."},
			{"ZM_CONTRACTS_KILLS_PISTOL", "Earn ^3&&1^7 pistol kills."},
			{"ZM_CONTRACTS_GOON_KILLS", "Kill ^3&&1^7 Scouts."},
			{"ZM_CONTRACTS_PHANTOM_KILLS", "Kill ^3&&1^7 Phantoms."},
			{"ZM_CONTRACTS_KILLS_ENTANGLER", "Earn ^3&&1^7 Entangler kills."},
			{"ZM_CONTRACTS_KILLS_VENOMX", "Earn ^3&&1^7 Venom-X kills."},
			{"ZM_CONTRACTS_SPECIAL_KILLS", "Kill ^3&&1^7 special guest zombies."},
		};

		constexpr localization_override chi_primary_binding_overrides[]
		{
			{"CP_DISCO_CHALLENGES_OFFHAND",
				"Kill ^3&&1^7 Zombies using the\n^3Shuriken [[{+frag}]]^7"},
			{"CP_DISCO_CHALLENGES_TIGER_1_REWARD",
				"Tiger Rank ^31 [[{+frag}]]^7"},
			{"CP_DISCO_CHALLENGES_CRANE_1_REWARD",
				"Crane Rank ^31 [[{+frag}]]^7"},
			{"CP_DISCO_CHALLENGES_DRAGON_1_REWARD",
				"Dragon Rank ^31 [[{+frag}]]^7"},
			{"CP_DISCO_CHALLENGES_SNAKE_1_REWARD",
				"Snake Rank ^31 [[{+frag}]]^7"},
		};

		constexpr std::string_view survival_only_override_keys[]
		{
			"CP_ZMB_INTRO_LINE_4",
		};

		std::string normalize_key(const std::string_view key)
		{
			return std::string{key.starts_with('@') ? key.substr(1) : key};
		}

		bool registered_override_is_enabled(const std::string_view key)
		{
			const auto lookup_key = normalize_key(key);
			const auto is_survival_only = std::ranges::any_of(survival_only_override_keys,
				[&](const std::string_view survival_key)
				{
					return _stricmp(lookup_key.c_str(), survival_key.data()) == 0;
				});
			if (!is_survival_only)
			{
				return true;
			}

			const auto* const survival_mode = game::Dvar_FindVar("iwz_survival_mode");
			return survival_mode != nullptr && survival_mode->current.enabled;
		}

		const char* cache_asset_override(const std::string_view key, const std::string_view value)
		{
			const auto cache_key = std::format("{}\x1F{}", key, value);
			return localized_asset_overrides.access<const char*>([&](localized_map& map)
			{
				const auto entry = map.try_emplace(cache_key, value).first;
				return entry->second.data();
			});
		}

		std::optional<std::string> get_registered_override(const std::string_view key)
		{
			const auto lookup_key = normalize_key(key);
			if (!registered_override_is_enabled(lookup_key))
			{
				return std::nullopt;
			}

			return localized_overrides.access<std::optional<std::string>>([&](const localized_map& map)
			{
				const auto entry = map.find(lookup_key);
				return entry == map.end() ? std::nullopt : std::optional{entry->second};
			});
		}

		std::optional<std::pair<std::string, std::string>> find_registered_override(const char* key)
		{
			if (key == nullptr)
			{
				return std::nullopt;
			}

			const auto* lookup_key = key[0] == '@' ? key + 1 : key;
			return localized_overrides.access<std::optional<std::pair<std::string, std::string>>>(
				[&](const localized_map& map)
				{
					for (const auto& [registered_key, value] : map)
					{
						if (_stricmp(registered_key.data(), lookup_key) == 0)
						{
							if (!registered_override_is_enabled(registered_key))
							{
								return std::optional<std::pair<std::string, std::string>>{};
							}

							return std::optional{std::pair{registered_key, value}};
						}
					}
					return std::optional<std::pair<std::string, std::string>>{};
				});
		}

		bool apply_registered_override(database::LocalizeEntry* asset, const char* source)
		{
			if (asset == nullptr || asset->name == nullptr)
			{
				return false;
			}

			const auto registered_override = find_registered_override(asset->name);
			if (!registered_override.has_value())
			{
				return false;
			}
			const auto& [lookup_key, replacement] = registered_override.value();

			asset->value = cache_asset_override(lookup_key, replacement);
			logged_missing_registered_asset_keys.access([&](auto& keys)
			{
				keys.erase(lookup_key);
			});
			const auto first_application = applied_registered_asset_keys.access<bool>([&](auto& keys)
			{
				return keys.emplace(lookup_key).second;
			});
			if (first_application)
			{
				console::info("[IWZ][Localization] materialized registered override key='%s' source=%s\n",
					lookup_key.data(), source);
				if (_stricmp(lookup_key.data(), "CP_ZMB_INTRO_LINE_4") == 0 &&
					!logged_survival_objective_override.exchange(true))
				{
					console::info("[IWZ][Survival] materialized objective localization key='%s' text='Survive until you die!' mode=survival-only\n",
						lookup_key.data());
				}
			}
			return true;
		}

		bool colorize_unmarked_bindings(const std::string_view value, std::string& result)
		{
			char active_color = '7';
			bool changed = false;
			result.reserve(value.size() + 16);

			for (size_t i = 0; i < value.size();)
			{
				if (value[i] == '^' && i + 1 < value.size() && value[i + 1] >= '0' && value[i + 1] <= '9')
				{
					active_color = value[i + 1];
					result.append(value.substr(i, 2));
					i += 2;
					continue;
				}

				if (active_color == '7' && value[i] == '[' && i + 1 < value.size() && value[i + 1] == '{')
				{
					const auto end = value.find("}]", i + 2);
					if (end != std::string_view::npos)
					{
						result.append("^3");
						result.append(value.substr(i, end + 2 - i));
						result.append("^7");
						i = end + 2;
						changed = true;
						continue;
					}
				}

				result.push_back(value[i++]);
			}

			return changed;
		}

		const char* get_colorized_binding(const char* reference, const char* value)
		{
			if (reference == nullptr || value == nullptr || strstr(value, "[{") == nullptr)
			{
				return value;
			}

			return colorized_bindings.access<const char*>([&](localized_map& map)
			{
				const auto existing = map.find(reference);
				if (existing != map.end())
				{
					return static_cast<const char*>(existing->second.data());
				}

				std::string colorized;
				if (!colorize_unmarked_bindings(value, colorized))
				{
					return value;
				}

				const auto entry = map.emplace(reference, std::move(colorized)).first;
				if (!logged_binding_color_fix.exchange(true))
				{
					console::info("[IWZ][Localization] colorized unmarked key binding in '%s'\n", reference);
				}
				return static_cast<const char*>(entry->second.data());
			});
		}

		const char* lookup_unformatted(const char* reference)
		{
			const auto* value = localized_overrides.access<const char*>([&](const localized_map& map)
			{
				const auto* lookup_reference = reference != nullptr && reference[0] == '@' ? reference + 1 : reference;
				const auto entry = lookup_reference == nullptr ? map.end() : map.find(lookup_reference);
				if (entry != map.end() && registered_override_is_enabled(entry->first))
				{
					return entry->second.data();
				}
				return static_cast<const char*>(nullptr);
			});
			if (value == nullptr)
			{
				value = seh_string_ed_get_string_hook.invoke<const char*>(reference);
			}
			return value;
		}

		const char* seh_string_ed_get_string(const char* reference)
		{
			return get_colorized_binding(reference, lookup_unformatted(reference));
		}
	}

	const char* lookup(const char* reference)
	{
		return lookup_unformatted(reference);
	}

	std::optional<std::string> colorize_key_bindings(const std::string_view value)
	{
		std::string result;
		if (!colorize_unmarked_bindings(value, result))
		{
			return std::nullopt;
		}
		return result;
	}

	bool override_asset(const std::string& key, const std::string& value)
	{
		const auto lookup_key = normalize_key(key);
		const auto* replacement = cache_asset_override(lookup_key, value);

		bool found = false;
		game::DB_EnumXAssets(game::ASSET_TYPE_LOCALIZE_ENTRY, [&](const game::XAssetHeader header)
		{
			auto* asset = header.localize;
			if (asset == nullptr || asset->name == nullptr)
			{
				return;
			}

			const auto* asset_name = asset->name[0] == '@' ? asset->name + 1 : asset->name;
			if (_stricmp(asset_name, lookup_key.data()) == 0)
			{
				asset->value = replacement;
				found = true;
			}
		});
		return found;
	}

	bool apply_registered_override_asset(const std::string& key)
	{
		const auto lookup_key = normalize_key(key);
		if (!get_registered_override(lookup_key).has_value())
		{
			return false;
		}

		const auto already_applied = applied_registered_asset_keys.access<bool>([&](const auto& keys)
		{
			return keys.contains(lookup_key);
		});
		if (already_applied)
		{
			return true;
		}

		bool found = false;
		game::DB_EnumXAssets(game::ASSET_TYPE_LOCALIZE_ENTRY, [&](const game::XAssetHeader header)
		{
			auto* asset = header.localize;
			if (asset == nullptr || asset->name == nullptr)
			{
				return;
			}

			const auto* asset_name = asset->name[0] == '@' ? asset->name + 1 : asset->name;
			if (_stricmp(asset_name, lookup_key.data()) == 0)
			{
				found = apply_registered_override(asset, "lookup-fallback");
			}
		});

		if (!found)
		{
			const auto first_miss = logged_missing_registered_asset_keys.access<bool>([&](auto& keys)
			{
				return keys.emplace(lookup_key).second;
			});
			if (first_miss)
			{
				console::warn("[IWZ][Localization] registered override asset is not resident key='%s'; lookup hook remains active\n",
					lookup_key.data());
			}
		}
		return found;
	}

	void override(const std::string& key, const std::string& value)
	{
		const auto lookup_key = normalize_key(key);
		localized_overrides.access([&](localized_map& map)
		{
			map[lookup_key] = value;
		});
		applied_registered_asset_keys.access([&](auto& keys)
		{
			keys.erase(lookup_key);
		});
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			override("MENU_MASTER_VOLUME", "MASTER VOLUME");
			override("COOP_INTERACTIONS_NEED_MONEY", "^1NEED MORE MONEY!^7");
			override("COOP_INTERACTIONS_REQUIRES_POWER", "^1NEEDS POWER!^7");
			override("CP_ZMB_INTERACTIONS_NEED_TICKETS", "^1NEED MORE TICKETS!^7");
			override("CP_ZMB_GHOST_TRACKING", "Tracking...");
			override("CP_ZMB_GHOST_OBJECTIVE", "Destroy all skulls before they escape!");
			override("IWZ_GNS_ARCADE_START_SPACELAND", "Hold [{+usereload,+activate}] to start GHOSTS N SKULLS");
			override("IWZ_GNS_ARCADE_START_RAVE", "Hold [{+usereload,+activate}] to start GHOSTS N SKULLS 2");
			override("IWZ_GNS_ARCADE_START_SHAOLIN", "Hold [{+usereload,+activate}] to start SKULLBUSTER");
			override("IWZ_GNS_ARCADE_START_ATTACK", "Hold [{+usereload,+activate}] to start SKULLHOP");
			override("IWZ_GNS_ARCADE_START_BEAST", "Hold [{+usereload,+activate}] to start SKULLBREAKER");
			override("IWZ_GNS_ARCADE_START_GENERIC", "Hold [{+usereload,+activate}] to start GHOSTS N SKULLS ARCADE");
			override("IWZ_CAMO_NEON_ROT", "Neon Rot");
			override("IWZ_CAMO_NEON_ROT_UNLOCK", "Get 5 headshots with the M1 in Zombies.");
			override("IWZ_WEAPON_CAMO_EARNED", "WEAPON CAMO EARNED");
			override("IWZ_CP_DISCO_STANDARD_ENTER_THIS_AREA", "enter this area");
			// GSC localized-string operands require a resident LocalizeEntry. Reuse
			// Spaceland's authored fourth intro line and gate its replacement on the
			// Survival dvar so ordinary Spaceland retains its stock objective.
			override("CP_ZMB_INTRO_LINE_4", "Survive until you die!");
			// zombie_doors uses the default key on Spaceland and each sequel map
			// assigns one of the three map-specific keys to level.enter_area_hint.
			// The interaction engine supplies Hold/bind/cost around this value.
			override("CP_ZMB_INTERACTIONS_ENTER_THIS_AREA", "enter this area");
			override("CP_RAVE_ENTER_THIS_AREA", "enter this area");
			override("CP_DISCO_INTERACTIONS_ENTER_THIS_AREA", "Enter this area");
			override("CP_TOWN_INTERACTIONS_ENTER_THIS_AREA", "enter this area");
			override("COOP_PILLAGE_FOUND_BIO_SPIKE", "Found Bio Spikes");
			override("COOP_PILLAGE_FOUND_GAS_GRENADE", "Found Gas Grenades");
			override("COOP_PILLAGE_FOUND_CLUSTER_GRENADE", "Found Cluster Grenades");
			override("ZOMBIE_PILLAGE_PICKUP_C4", "Press and hold [{+activate}] to pick up C4");
			override("COOP_GAME_PLAY_AMMO_MAX", "Ammunition already full");
			override("COOP_PERK_MACHINES_1000",
				"\"Improve your game with deadly aim!\"\n"
				"Hold [{+usereload,+activate}] to purchase ^2Deadeye Dewdrops^7 (^3$1500^7)");
			for (const auto& [key, value] : bounty_description_overrides)
			{
				override(key, value);
			}
			for (const auto& [key, value] : chi_primary_binding_overrides)
			{
				override(key, value);
			}
			fastfiles::on_localize_loaded([](database::LocalizeEntry* asset)
			{
				apply_registered_override(asset, "asset-load");
			});
			console::info("[IWZ][Localization] installed key-binding colorizer\n");
			console::info("[IWZ][Localization] registered red interaction warnings moneyKey=COOP_INTERACTIONS_NEED_MONEY powerKey=COOP_INTERACTIONS_REQUIRES_POWER ticketKey=CP_ZMB_INTERACTIONS_NEED_TICKETS\n");
			console::info("[IWZ][GhostsNSkullsHUD] registered shared text overrides tracking='Tracking...' objectivePunctuation=exclamation escapedPunctuationVerified=3\n");
			console::info("[IWZ][GhostsNSkullsArcade] registered per-game activation hints count=5\n");
			console::info("[IWZ][ZombiesCamos] registered localization camo=Neon_Rot:5-headshots splashHeader='WEAPON CAMO EARNED'\n");
			console::info("[IWZ][Localization] registered door-action overrides lowercaseCount=4 shaolinPapKey=CP_DISCO_INTERACTIONS_ENTER_THIS_AREA shaolinPapCapitalized=1 shaolinStandardKey=IWZ_CP_DISCO_STANDARD_ENTER_THIS_AREA residentZone=iwz_gns_arcade\n");
			console::info("[IWZ][Localization] registered plural pillage-item overrides bioSpikes=1 gasGrenades=1 clusterGrenades=1\n");
			console::info("[IWZ][Localization] registered wording overrides c4PickupKey=ZOMBIE_PILLAGE_PICKUP_C4 ammoFullKey=COOP_GAME_PLAY_AMMO_MAX\n");
			console::info("[IWZ][Localization] registered punctuation overrides deadeyeDewdrops=1 bountyDescriptions=%zu\n",
				std::size(bounty_description_overrides));
			console::info("[IWZ][Localization] registered bracketed Chi primary-binding overrides count=%zu scope=challenge-and-rank1-rewards numericPlaceholderYellow=1 bottomRightHud=unchanged\n",
				std::size(chi_primary_binding_overrides));
			console::info("[IWZ][Survival] registered mode-gated localization objectiveKey=CP_ZMB_INTRO_LINE_4 lockedExitHint=disabled fallback=stock-values\n");

			seh_string_ed_get_string_hook.create(0x140CBBB10, &seh_string_ed_get_string);
		}
	};
}

REGISTER_COMPONENT(localized_strings::component)
