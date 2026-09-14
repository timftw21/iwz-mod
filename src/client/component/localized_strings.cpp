#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "localized_strings.hpp"
#include "zombies_hintstrings.hpp"

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
		thread_local bool center_multiline_hud = false;
		std::atomic_bool logged_multiline_hud_fix{false};

		void draw_hud_text(const int client, const char* text, const void* element, void* draw_state)
		{
			// CG's alignOrg packs horizontal alignment into bits 2-3. Its text
			// renderer anchors the whole block but otherwise left-aligns each line.
			const auto* fields = static_cast<const std::byte*>(element);
			const auto alignment = *reinterpret_cast<const unsigned int*>(fields + 0x38);
			const auto text_fx_time = *reinterpret_cast<const int*>(fields + 0xA0);
			const auto previous = center_multiline_hud;
			center_multiline_hud = ((alignment >> 2) & 3) == 1 && text_fx_time == 0 &&
				game::Com_GameMode_GetActiveGameMode() == game::GAME_MODE_CP && text && std::strchr(text, '\n');
			utils::hook::invoke<void>(0x1407E2980, client, text, element, draw_state);
			center_multiline_hud = previous;
		}

		void draw_hud_text_lines(const char* text, const int max_chars, game::GfxFont* font,
			const float x, float y, const float x_scale, const float y_scale, const float* color, const int style)
		{
			if (!center_multiline_hud)
			{
				utils::hook::invoke<void>(0x140313C80, text, max_chars, font, x, y, x_scale, y_scale, color, style);
				return;
			}
			const auto block_width = game::R_TextWidth(text, max_chars, font);
			const auto line_height = static_cast<float>(game::R_GetFontHeight(font)) * y_scale;
			std::string_view remaining{text};
			std::string active_color;
			for (;;)
			{
				const auto end = remaining.find('\n');
				auto line_text = remaining.substr(0, end);
				if (line_text.ends_with('\r')) line_text.remove_suffix(1);
				const std::string line = active_color + std::string{line_text};
				const auto line_width = game::R_TextWidth(line.c_str(), max_chars, font);
				const auto line_x = x + (block_width - line_width) * x_scale * 0.5f;
				utils::hook::invoke<void>(0x140313C80, line.c_str(), max_chars, font,
					line_x, y, x_scale, y_scale, color, style);
				for (size_t i = 0; i + 1 < line_text.size(); ++i)
				{
					if (line_text[i] == '^' && line_text[i + 1] >= '0' && line_text[i + 1] <= ';')
						active_color = line_text.substr(i++, 2);
				}
				if (end == std::string_view::npos) break;
				remaining.remove_prefix(end + 1);
				y += line_height;
			}
			if (!logged_multiline_hud_fix.exchange(true))
				console::info("[IWZ][ZombieHints] centered multiline HUD text using native font widths and binding glyphs\n");
		}

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
			// Zombies also uses these five MP weapon-class descriptions.
			{"INTEL_MP_CONTRACT_KILLS_AR", "Earn ^3&&1^7 kills with an assault rifle."},
			{"INTEL_MP_CONTRACT_KILLS_LMG", "Earn ^3&&1^7 kills with a LMG."},
			{"INTEL_MP_CONTRACT_KILLS_SG", "Earn ^3&&1^7 kills with a shotgun."},
			{"INTEL_MP_CONTRACT_KILLS_SNIPER", "Earn ^3&&1^7 kills with a sniper rifle."},
			{"INTEL_MP_CONTRACT_KILLS_SMG", "Earn ^3&&1^7 kills with a SMG."},
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

		// Stock pickup wording from localize.json; zombies_pillage selects the
		// ZOMBIE/COOP keys below. Keep the authored binding and weapon placeholders.
		constexpr localization_override pickup_hint_overrides[]
		{
			{"ZOMBIE_PILLAGE_PICKUP_TICKETS", "Hold [{+activate}] to pick up tickets"},
			{"ZOMBIE_PILLAGE_PICKUP_CONCUSSION_GRENADE", "Hold [{+activate}] to pick up concussion grenades"},
			{"ZOMBIE_PILLAGE_PICKUP_BETTY", "Hold [{+activate}] to pick up a Bouncing Betty"},
			{"ZOMBIE_PILLAGE_PICKUP_POINTS", "Hold [{+activate}] to pick up cash"},
			{"ZOMBIE_PILLAGE_PICKUP_FRAG_GRENADE", "Hold [{+activate}] to pick up frag grenades"},
			{"ZOMBIE_PILLAGE_PICKUP_PLASMA_GRENADE", "Hold [{+activate}] to pick up plasma grenades"},
			{"ZOMBIE_PILLAGE_PICKUP_C4", "Hold [{+activate}] to pick up C4"},
			{"ZOMBIE_PILLAGE_PICKUP_SEMTEX", "Hold [{+activate}] to pick up Semtex grenades"},
			{"ZOMBIE_PILLAGE_PICKUP_BOLA_BARRAGE", "Hold [{+activate}] to pick up Bola Barrage"},
			{"COOP_PILLAGE_PICKUP_CLUSTER_GRENADE", "Hold [{+activate}] to pick up cluster grenades"},
			{"COOP_PILLAGE_PICKUP_GAS_GRENADE", "Hold [{+activate}] to pick up gas grenades"},
			{"PLATFORM_PICKUPNEWWEAPONGAMEPAD", "Hold &&1 to pick up &&2"},
			{"PLATFORM_PICKUPNEWWEAPONGAMEPADHEAVY", "Hold &&1 to pick up heavy weapon &&2"},
			{"PLATFORM_SWAPWEAPONSGAMEPAD", "Hold &&1 for &&2"},
			{"PLATFORM_SWAPWEAPONSGAMEPADHEAVY", "Hold &&1 for heavy weapon &&2"},
			{"WEAPON_CLAYMORE_PICKUP", "Hold^3 &&1 ^7to pick up Claymore mines"},
			{"WEAPON_PROXIMITY_EXPLOSIVE_PICKUP", "Hold^3 &&1 ^7to pick up an I.E.D."},
			{"WEAPON_PICKUP_AXE", "Hold^3 &&1 ^7for an axe"},
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
			"CP_RAVE_INTRO_LINE_4",
			"CP_DISCO_INTRO_LINE_4",
			"CP_TOWN_INTRO_LINE_3",
			"CP_TOWN_INTRO_LINE_4",
			"CP_FINAL_INTRO_LINE_4",
		};

		std::string normalize_key(const std::string_view key)
		{
			return utils::string::to_upper(std::string{key.starts_with('@') ? key.substr(1) : key});
		}

		std::optional<std::pair<std::string, std::string>> normalize_hint_text(
			const char* key, const char* value)
		{
			if (!key || !value)
				return std::nullopt;

			const auto lookup_key = normalize_key(key);
			const auto family_key = utils::string::to_upper(lookup_key);
			// All five maps share zombies_pillage::_id_7A06, but native equipment
			// pickups also use MP_PICKUP_* strings. Normalize the loaded wording
			// instead of guessing every item's name from incomplete string dumps.
			const auto pickup_family = family_key.starts_with("ZOMBIE_PILLAGE_PICKUP_") ||
				family_key.starts_with("COOP_PILLAGE_PICKUP_") || family_key.starts_with("MP_PICKUP_") ||
				family_key.starts_with("PLATFORM_PICKUPNEWWEAPON") || family_key.starts_with("PLATFORM_SWAPWEAPONS") ||
				(family_key.starts_with("WEAPON_") && family_key.find("PICKUP") != std::string::npos) ||
				family_key == "CP_TOWN_PILLAGE_BATTERY" || family_key == "CP_QUEST_WOR_PART";
			auto normalized = zombies_hintstrings::normalize(family_key, value);
			if (!pickup_family && !normalized)
				return std::nullopt;
			std::string result = normalized ? std::move(*normalized) : std::string{value};
			if (pickup_family)
			{
				constexpr std::string_view hold_prefix = "Press and hold";
				if (result.starts_with(hold_prefix))
					result.replace(0, hold_prefix.size(), "Hold");
				constexpr std::string_view some_phrase = "pick up some ";
				const auto some = result.find(some_phrase);
				if (some != std::string::npos)
					result.replace(some, some_phrase.size(), "pick up ");
			}
			if (result == value)
				return std::nullopt;
			return std::pair{lookup_key, std::move(result)};
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

			const auto lookup_key = normalize_key(key);
			return localized_overrides.access<std::optional<std::pair<std::string, std::string>>>(
				[&](const localized_map& map)
				{
					const auto entry = map.find(lookup_key);
					if (entry != map.end() && registered_override_is_enabled(entry->first))
						return std::optional{std::pair{entry->first, entry->second}};
					return std::optional<std::pair<std::string, std::string>>{};
				});
		}

		bool apply_registered_override(database::LocalizeEntry* asset, const char* source)
		{
			if (asset == nullptr || asset->name == nullptr)
			{
				return false;
			}

			auto registered_override = find_registered_override(asset->name);
			const auto hint_wording = !registered_override.has_value();
			if (hint_wording)
				registered_override = normalize_hint_text(asset->name, asset->value);
			else if (const auto normalized = normalize_hint_text(asset->name, registered_override->second.c_str()))
				registered_override = normalized;
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
				console::info("[IWZ][Localization] materialized %s key='%s' source=%s\n",
					hint_wording ? "hint wording" : "registered override", lookup_key.data(), source);
				if ((_stricmp(lookup_key.data(), "CP_ZMB_INTRO_LINE_4") == 0 ||
					_stricmp(lookup_key.data(), "CP_RAVE_INTRO_LINE_4") == 0 ||
					_stricmp(lookup_key.data(), "CP_DISCO_INTRO_LINE_4") == 0 ||
					_stricmp(lookup_key.data(), "CP_TOWN_INTRO_LINE_4") == 0 ||
					_stricmp(lookup_key.data(), "CP_FINAL_INTRO_LINE_4") == 0) &&
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
					// Parameterized HUD substitutions (FAKE_INTRO_SECONDS:11)
					// share the binding delimiters, but are not input commands.
					if (end != std::string_view::npos && end > i + 2 &&
						value.substr(i + 2, end - i - 2).find(':') == std::string_view::npos)
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
			const auto* key = reference && reference[0] == '@' ? reference + 1 : reference;
			if (key && _stricmp(key, "IWZ_DEATH_WISH_HINT") == 0)
			{
				// Keep one replicated hint index. Both text parameters and separate
				// activate/deactivate hints would consume Attack's full 255-slot pool.
				const auto* state = game::Dvar_FindVar("iwz_directors_death_active");
				const bool active = state && state->current.enabled;
				const auto* text = active
					? "Hold ^3[{+usereload,+activate}]^7 to deactivate ^1Death Wish^7"
					: "Hold ^3[{+usereload,+activate}]^7 to activate ^1Death Wish^7";
				static std::atomic<int> last_state{-1};
				if (last_state.exchange(active) != static_cast<int>(active))
				{
					// Native hint paths can read LocalizeEntry directly. Update that
					// value too, while keeping the replicated key and index stable.
					const auto resident = override_asset(key, text);
					console::info("[IWZ][DeathWish] hint action=%s nameColor=red hintStrings=1 resident=%d\n",
						active ? "deactivate" : "activate", resident);
				}
				return text;
			}
			const auto* value = localized_overrides.access<const char*>([&](const localized_map& map)
			{
				const auto entry = reference == nullptr ? map.end() : map.find(normalize_key(reference));
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
			// Cover resident/native prompts too, including assets loaded before
			// callbacks were registered. Keep stable storage and binding tokens.
			if (const auto hint = normalize_hint_text(reference, value))
			{
				value = cache_asset_override(hint->first, hint->second);
				const auto first = applied_registered_asset_keys.access<bool>([&](auto& keys)
				{
					return keys.emplace(hint->first).second;
				});
				if (first)
					console::info("[IWZ][Localization] materialized hint wording key='%s' source=lookup\n", hint->first.c_str());
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

		// Log deduplication is not residency: map changes can replace/unload an
		// asset, and lookup-only replacements never update its native value.
		// Revalidate the current asset even for hints without button bindings.
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
			// Body text only: keep HUD labels and animated text effects on their
			// original path. The shared lower message (including Forge Freeze)
			// retains its stock lifetime, position, alpha and font size.
			utils::hook::call(0x1407E3CCE, draw_hud_text);
			utils::hook::call(0x1407E3B56, draw_hud_text_lines);
			override("MENU_MASTER_VOLUME", "MASTER VOLUME");
			override("CP_ZMB_INTERACTIONS_NEED_TICKETS", "^1Not enough tickets^7");
			override("CP_ZMB_GHOST_TRACKING", "Tracking...");
			override("CP_ZMB_GHOST_OBJECTIVE", "Destroy all skulls before they escape!");
			override("IWZ_GNS_ARCADE_START_SPACELAND", "Hold [{+usereload,+activate}] to start Ghosts N Skulls");
			override("IWZ_GNS_ARCADE_START_RAVE", "Hold [{+usereload,+activate}] to start Ghosts N Skulls 2");
			override("IWZ_GNS_ARCADE_START_SHAOLIN", "Hold [{+usereload,+activate}] to start Skullbuster");
			override("IWZ_GNS_ARCADE_START_ATTACK", "Hold [{+usereload,+activate}] to start Skullhop");
			override("IWZ_GNS_ARCADE_START_BEAST", "Hold [{+usereload,+activate}] to start Skullbreaker");
			override("IWZ_GNS_ARCADE_START_GENERIC", "Hold [{+usereload,+activate}] to start Ghosts N Skulls arcade");
			override("IWZ_CAMO_NEON_ROT", "Neon Rot");
			override("IWZ_CAMO_NEON_ROT_UNLOCK", "Get 5 headshots with the M1 in Zombies.");
			override("IWZ_WEAPON_CAMO_EARNED", "WEAPON CAMO EARNED");
			override("IWZ_CP_DISCO_STANDARD_ENTER_THIS_AREA", "enter this area");
			// GSC localized-string operands require resident LocalizeEntry assets.
			// Reuse each map's authored fourth intro line and gate replacement on
			// the Survival dvar so ordinary matches retain their stock objectives.
			override("CP_ZMB_INTRO_LINE_4", "Survive until you die!");
			override("CP_RAVE_INTRO_LINE_4", "Survive until you die!");
			override("CP_DISCO_INTRO_LINE_4", "Survive until you die!");
			// Attack places its objective on line three and its clock on line four.
			// Preserve that stock clock above Survival's line-four objective.
			override("CP_TOWN_INTRO_LINE_3", "10:15:[{FAKE_INTRO_SECONDS:11}] in the morning");
			override("CP_TOWN_INTRO_LINE_4", "Survive until you die!");
			override("CP_FINAL_INTRO_LINE_4", "Survive until you die!");
			// zombie_doors uses the default key on Spaceland and each sequel map
			// assigns one of the three map-specific keys to level.enter_area_hint.
			// The interaction engine supplies Hold/bind/cost around this value.
			override("CP_ZMB_INTERACTIONS_ENTER_THIS_AREA", "enter this area");
			override("CP_RAVE_ENTER_THIS_AREA", "enter this area");
			override("CP_DISCO_INTERACTIONS_ENTER_THIS_AREA", "Enter this area");
			override("CP_TOWN_INTERACTIONS_ENTER_THIS_AREA", "enter this area");
			override("COOP_PILLAGE_FOUND_BIO_SPIKE", "Found Bio Spikes");
			override("COOP_PILLAGE_FOUND_GAS_GRENADE", "Found Gas Grenades");
			override("LUA_MENU_ZM_SELECT_SHOW_CAPS", "STANDARD FILMS");
			override("COOP_PILLAGE_FOUND_CLUSTER_GRENADE", "Found cluster grenades");
			override("COOP_GAME_PLAY_AMMO_MAX", "Ammunition already full");
			override("COOP_PERK_MACHINES_1000",
				"\"Improve your game with deadly aim!\"\n"
				"Hold [{+usereload,+activate}] to purchase ^2Deadeye Dewdrops^7 (^3$1500^7)");
			for (const auto& [key, value] : bounty_description_overrides)
			{
				override(key, value);
			}
			override("LUA_MENU_ZM_BOUNTY_TIMER", "BOUNTIES EXPIRE IN D:^1&&1^7 H:^1&&2^7 M:^1&&3^7");
			for (const auto& [key, value] : chi_primary_binding_overrides)
			{
				override(key, value);
			}
			for (const auto& [key, value] : pickup_hint_overrides)
			{
				override(key, value);
			}
			for (const auto& [key, value] : zombies_hintstrings::overrides)
			{
				override(key, value);
			}
			console::info("[IWZ][ZombieHints] registered audited text overrides=%zu style=sentence-case coverage=all-five-maps nativeAssets=1 lookup=1\n",
				std::size(zombies_hintstrings::overrides));
			console::info("[IWZ][ZombieHints] localization keys canonicalized; native hint assets revalidated across map changes; boss-fight parentheses covered\n");
			fastfiles::on_localize_loaded([](database::LocalizeEntry* asset)
			{
				apply_registered_override(asset, "asset-load");
			});
			console::info("[IWZ][Localization] installed key-binding colorizer; parameterized HUD tokens retain their authored color\n");
			console::info("[IWZ][Localization] film selection label='STANDARD FILMS' key=LUA_MENU_ZM_SELECT_SHOW_CAPS\n");
			console::info("[IWZ][Localization] registered red interaction warnings moneyKey=COOP_INTERACTIONS_NEED_MONEY powerKey=COOP_INTERACTIONS_REQUIRES_POWER ticketKey=CP_ZMB_INTERACTIONS_NEED_TICKETS\n");
			console::info("[IWZ][GhostsNSkullsHUD] registered shared text overrides tracking='Tracking...' objectivePunctuation=exclamation escapedPunctuationVerified=3\n");
			console::info("[IWZ][GhostsNSkullsArcade] registered per-game activation hints count=5\n");
			console::info("[IWZ][ZombiesCamos] registered localization camo=Neon_Rot:5-headshots splashHeader='WEAPON CAMO EARNED'\n");
			console::info("[IWZ][Localization] registered door-action overrides lowercaseCount=4 shaolinPapKey=CP_DISCO_INTERACTIONS_ENTER_THIS_AREA shaolinPapCapitalized=1 shaolinStandardKey=IWZ_CP_DISCO_STANDARD_ENTER_THIS_AREA residentZone=iwz_gns_arcade\n");
			console::info("[IWZ][Localization] registered plural pillage-item overrides bioSpikes=1 gasGrenades=1 clusterGrenades=1\n");
			console::info("[IWZ][Localization] registered pickup hint overrides count=%zu prefix=Hold removedSome=C4,ClusterGrenades,GasGrenades\n",
				std::size(pickup_hint_overrides));
			console::info("[IWZ][Localization] pickup wording coverage=all-maps families=ZOMBIE/COOP_PILLAGE,MP_PICKUP,PLATFORM,WEAPON,battery,quest sources=asset-load-and-lookup\n");
			console::info("[IWZ][Localization] registered wording override ammoFullKey=COOP_GAME_PLAY_AMMO_MAX\n");
			console::info("[IWZ][Localization] removed trailing periods from portal hints keys=CP_TOWN_INTERACTIONS_HIDDEN_LEAVE,CP_TOWN_INTERACTIONS_HIDDEN_TELEPORT\n");
			console::info("[IWZ][Localization] removed trailing period key=ZOMBIE_LOST_AND_FOUND_NO_ITEM\n");
			console::info("[IWZ][Localization] registered punctuation overrides deadeyeDewdrops=1 bountyDescriptions=%zu\n",
				std::size(bounty_description_overrides));
			console::info("[IWZ][BountyFixes] punctuation audit includes five shared MP weapon-class descriptions; timer wording='BOUNTIES EXPIRE IN'\n");
			console::info("[IWZ][Localization] registered bracketed Chi primary-binding overrides count=%zu scope=challenge-and-rank1-rewards numericPlaceholderYellow=1 bottomRightHud=unchanged\n",
				std::size(chi_primary_binding_overrides));
			console::info("[IWZ][Survival] registered mode-gated localization objectiveKeys=CP_ZMB_INTRO_LINE_4,CP_RAVE_INTRO_LINE_4,CP_DISCO_INTRO_LINE_4,CP_TOWN_INTRO_LINE_4,CP_FINAL_INTRO_LINE_4 beachClock=CP_TOWN_INTRO_LINE_3:10:15 lockedExitHint=disabled fallback=stock-values\n");

			seh_string_ed_get_string_hook.create(0x140CBBB10, &seh_string_ed_get_string);
		}
	};
}

REGISTER_COMPONENT(localized_strings::component)
