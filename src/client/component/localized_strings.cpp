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

		std::string normalize_key(const std::string_view key)
		{
			return std::string{key.starts_with('@') ? key.substr(1) : key};
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
				if (entry != map.end())
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
			override("CP_ZMB_INTERACTIONS_NEED_TICKETS", "^1NEED MORE TICKETS!^7");
			override("CP_ZMB_GHOST_TRACKING", "Tracking...");
			override("CP_ZMB_GHOST_OBJECTIVE", "Destroy all skulls before they escape!");
			override("IWZ_GNS_ARCADE_START_SPACELAND", "Hold [{+usereload,+activate}] to start GHOSTS N SKULLS");
			override("IWZ_GNS_ARCADE_START_RAVE", "Hold [{+usereload,+activate}] to start GHOSTS N SKULLS 2");
			override("IWZ_GNS_ARCADE_START_SHAOLIN", "Hold [{+usereload,+activate}] to start SKULLBUSTER");
			override("IWZ_GNS_ARCADE_START_ATTACK", "Hold [{+usereload,+activate}] to start SKULLHOP");
			override("IWZ_GNS_ARCADE_START_BEAST", "Hold [{+usereload,+activate}] to start SKULLBREAKER");
			override("IWZ_GNS_ARCADE_START_GENERIC", "Hold [{+usereload,+activate}] to start GHOSTS N SKULLS ARCADE");
			// zombie_doors uses the default key on Spaceland and each sequel map
			// assigns one of the three map-specific keys to level.enter_area_hint.
			// The interaction engine supplies Hold/bind/cost around this value.
			override("CP_ZMB_INTERACTIONS_ENTER_THIS_AREA", "enter this area");
			override("CP_RAVE_ENTER_THIS_AREA", "enter this area");
			override("CP_DISCO_INTERACTIONS_ENTER_THIS_AREA", "enter this area");
			override("CP_TOWN_INTERACTIONS_ENTER_THIS_AREA", "enter this area");
			override("COOP_PILLAGE_FOUND_BIO_SPIKE", "Found Bio Spikes");
			override("COOP_PILLAGE_FOUND_GAS_GRENADE", "Found Gas Grenades");
			fastfiles::on_localize_loaded([](database::LocalizeEntry* asset)
			{
				apply_registered_override(asset, "asset-load");
			});
			console::info("[IWZ][Localization] installed key-binding colorizer\n");
			console::info("[IWZ][Localization] registered red interaction warnings moneyKey=COOP_INTERACTIONS_NEED_MONEY ticketKey=CP_ZMB_INTERACTIONS_NEED_TICKETS\n");
			console::info("[IWZ][GhostsNSkullsHUD] registered shared text overrides tracking='Tracking...' objectivePunctuation=exclamation escapedPunctuationVerified=3\n");
			console::info("[IWZ][GhostsNSkullsArcade] registered per-game activation hints count=5\n");
			console::info("[IWZ][Localization] registered lowercase door-action overrides count=4\n");
			console::info("[IWZ][Localization] registered plural pillage-item overrides bioSpikes=1 gasGrenades=1\n");

			seh_string_ed_get_string_hook.create(0x140CBBB10, &seh_string_ed_get_string);
		}
	};
}

REGISTER_COMPONENT(localized_strings::component)
