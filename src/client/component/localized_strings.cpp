#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "localized_strings.hpp"

#include "component/console/console.hpp"

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
		std::atomic_bool logged_binding_color_fix{false};

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
		const auto* lookup_key = key.starts_with('@') ? key.data() + 1 : key.data();
		const auto cache_key = std::format("{}\x1F{}", lookup_key, value);
		const auto* replacement = localized_asset_overrides.access<const char*>([&](localized_map& map)
		{
			const auto entry = map.try_emplace(cache_key, value).first;
			return entry->second.data();
		});

		bool found = false;
		game::DB_EnumXAssets(game::ASSET_TYPE_LOCALIZE_ENTRY, [&](const game::XAssetHeader header)
		{
			auto* asset = header.localize;
			if (asset == nullptr || asset->name == nullptr)
			{
				return;
			}

			const auto* asset_name = asset->name[0] == '@' ? asset->name + 1 : asset->name;
			if (_stricmp(asset_name, lookup_key) == 0)
			{
				asset->value = replacement;
				found = true;
			}
		});
		return found;
	}

	void override(const std::string& key, const std::string& value)
	{
		localized_overrides.access([&](localized_map& map)
		{
			map[key] = value;
		});
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			override("MENU_MASTER_VOLUME", "MASTER VOLUME");
			console::info("[IWZ][Localization] installed key-binding colorizer\n");

			seh_string_ed_get_string_hook.create(0x140CBBB10, &seh_string_ed_get_string);
		}
	};
}

REGISTER_COMPONENT(localized_strings::component)
