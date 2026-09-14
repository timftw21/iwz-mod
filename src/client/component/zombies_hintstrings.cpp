#include <std_include.hpp>
#include "zombies_hintstrings.hpp"

namespace zombies_hintstrings
{
	namespace
	{
		void replace_all(std::string& text, const std::string_view from, const std::string_view to)
		{
			for (size_t pos = 0; (pos = text.find(from, pos)) != std::string::npos; pos += to.size())
				text.replace(pos, from.size(), to);
		}

		bool is_hint(const std::string_view key, std::string_view value)
		{
			// The Wonder Weapon standee's missing-parts hint has no input binding.
			if (key == "CP_QUEST_WOR_ASSEMBLY")
				return true;

			if (key.find("_INTERACTIONS_") != std::string_view::npos ||
				key.starts_with("DIRECT_BOSS_FIGHT_") ||
				key.starts_with("COOP_PERK_MACHINES_") || key.starts_with("COOP_PILLAGE_PICKUP_") ||
				key.starts_with("ZOMBIE_PILLAGE_PICKUP_"))
				return true;

			while (value.size() >= 2 && value[0] == '^' && value[1] >= '0' && value[1] <= '9')
				value.remove_prefix(2);
			// Several Rave/Shaolin strings are absent from the public localization
			// dump. Edit their loaded action text without inventing bindings, prices
			// or item names. Exclude narrative/tutorial paragraphs and menu labels.
			return value.find("[{") != std::string_view::npos &&
				(value.starts_with("Hold ") || value.starts_with("Press "));
		}

		std::string trim_parentheses(const std::string_view value)
		{
			const auto color_at = [&](const size_t i)
			{
				return i + 1 < value.size() && value[i] == '^' && value[i + 1] >= '0' && value[i + 1] <= '9';
			};
			const auto padding_at = [&](const size_t i) -> size_t
			{
				if (i >= value.size()) return 0;
				if (value[i] == ' ' || value[i] == '\t') return 1;
				return value.substr(i, 2) == "\xC2\xA0" ? 2 : 0;
			};
			std::string result;
			result.reserve(value.size());
			char previous = 0;
			for (size_t i = 0; i < value.size();)
			{
				// Bind tokens are opaque. Color codes have no visible width.
				if (value.substr(i, 2) == "[{")
				{
					const auto end = value.find("}]", i + 2);
					if (end != std::string_view::npos)
					{
						result.append(value.substr(i, end + 2 - i));
						i = end + 2;
						previous = ']';
						continue;
					}
				}
				if (color_at(i))
				{
					result.append(value.substr(i, 2));
					i += 2;
					continue;
				}
				if (const auto padding = padding_at(i))
				{
					auto next = i + padding;
					while (next < value.size())
					{
						if (color_at(next)) next += 2;
						else if (const auto size = padding_at(next)) next += size;
						else break;
					}
					if (previous != '(' && (next == value.size() || value[next] != ')'))
						result.append(value.substr(i, padding));
					i += padding;
					continue;
				}
				previous = value[i];
				result += value[i++];
			}
			return result;
		}

		void normalize_player_requirement(std::string& text)
		{
			char color = '7';
			for (size_t i = 0; i < text.size(); ++i)
			{
				if (text.compare(i, 2, "[{") == 0)
				{
					const auto end = text.find("}]", i + 2);
					if (end != std::string::npos) { i = end + 1; continue; }
				}
				if (text[i] == '^' && i + 1 < text.size() && text[i + 1] >= '0' && text[i + 1] <= '9')
				{
					color = text[++i];
					continue;
				}
				if (text[i] != '(') continue;
				const auto end = text.find(')', i + 1);
				if (end == std::string::npos) break;
				std::string visible;
				auto end_color = color;
				for (auto j = i + 1; j < end; ++j)
				{
					if (text[j] == '^' && j + 1 < end && text[j + 1] >= '0' && text[j + 1] <= '9') end_color = text[++j];
					else visible += static_cast<char>(std::tolower(static_cast<unsigned char>(text[j])));
				}
				if (visible != "requires all players" && visible != "all players required") continue;
				visible.front() = static_cast<char>(std::toupper(static_cast<unsigned char>(visible.front())));
				// Color the whole annotation and restore the surrounding text's color.
				// Already-yellow annotations need no extra codes (idempotent on lookup).
				const auto replacement = (color == '3' ? std::string{} : "^3") + "(" + visible + ")" +
					(end_color == '3' ? std::string{} : std::string{"^"} + end_color);
				text.replace(i, end + 1 - i, replacement);
				i += replacement.size() - 1;
				color = end_color;
			}
		}
	}

	std::optional<std::string> normalize(const std::string_view key, const std::string_view value)
	{
		if (!key.starts_with("CP_") && !key.starts_with("COOP_") &&
			!key.starts_with("ZOMBIE_") && !key.starts_with("ZM_") &&
			!key.starts_with("DIRECT_BOSS_FIGHT_") && !key.starts_with("IWZ_"))
			return std::nullopt;

		std::string result = trim_parentheses(value);
		normalize_player_requirement(result);
		if (!is_hint(key, value))
			return result == value ? std::nullopt : std::optional{std::move(result)};
		// Literal edits leave controller/keyboard bindings, && parameters, color
		// codes, sentence fragments and intentional HUD line breaks intact.
		replace_all(result, ". (^", " (^");
		replace_all(result, ".^7 (", "^7 (");
		replace_all(result, ".\n(", "\n(");
		replace_all(result, ".  ", ". ");
		replace_all(result, "Card Deck(", "Card Deck (");
		replace_all(result, "Card Deck", "Fate and Fortune deck");
		replace_all(result, "Press and hold ", "Hold ");
		replace_all(result, "to pickup ", "to pick up ");
		replace_all(result, "pick up some ", "pick up ");
		replace_all(result, "Venom - X", "Venom-X");
		replace_all(result, "Venom X", "Venom-X");
		replace_all(result, "Pack A Punch", "Pack-a-Punch");
		replace_all(result, "Pack a Punch", "Pack-a-Punch");
		replace_all(result, "Pack-A-Punch", "Pack-a-Punch");
		replace_all(result, "magic wheel", "Magic Wheel");
		replace_all(result, "projection room", "Projection Room");
		replace_all(result, "soul key", "Soul Key");
		replace_all(result, "afterlife arcade", "Afterlife Arcade");
		replace_all(result, "afterlife theater", "Afterlife Theater");
		replace_all(result, "Guided Tour", "guided tour");
		replace_all(result, "Time Period", "time period");

		constexpr std::string_view verbs[]{"Activate", "Deactivate", "Purchase", "Pick up",
			"Pick Up", "Place", "Install", "Enter", "Exit", "Start", "Select", "Use", "Take", "Repair"};
		for (const auto verb : verbs)
		{
			std::string lower{verb};
			std::ranges::transform(lower, lower.begin(), [](const unsigned char c) { return static_cast<char>(std::tolower(c)); });
			replace_all(result, std::string{"to "} + std::string{verb}, std::string{"to "} + lower);
		}

		if (key.ends_with("UPGRADE_WEAPON") || key.ends_with("UPGRADE_WEAPON_GENERIC"))
			replace_all(result, "upgrade your", "Pack-a-Punch your");

		// These keys refer to specific objects in the map scripts. The shared
		// CP_QUEST_WOR_PART/PLACE_PART and CP_RAVE_PICKUP_ITEM must stay generic.
		if (key.starts_with("CP_ZMB_INTERACTIONS_"))
		{
			replace_all(result, "NEIL", "N31L");
			replace_all(result, "N3IL", "N31L");
			replace_all(result, "Neil", "N31L");
			if (key.ends_with("NEIL_HEAD_PICKUP") && result.find("N31L") == std::string::npos)
			{
				replace_all(result, "the head", "N31L's head");
				replace_all(result, "robot head", "N31L's head");
			}
			if (key.ends_with("RIDE_COASTER") && result.find("Polar Peak") == std::string::npos)
			{
				replace_all(result, "the roller coaster", "the Polar Peak coaster");
				replace_all(result, "the coaster", "the Polar Peak coaster");
			}
		}
		if (key == "CP_DISCO_CHALLENGES_TALK_TO_TRAINER")
			replace_all(result, "the trainer", "Pam Grier");

		// Trim horizontal padding without collapsing deliberate arcade HUD lines.
		while (result.find(" \n") != std::string::npos)
			replace_all(result, " \n", "\n");
		while (!result.empty() && result.back() == ' ')
			result.pop_back();

		// Compact prompts do not end in a period. Preserve ellipses, dotted
		// abbreviations, quotations and complete multi-sentence instructions.
		auto end = result.find_last_not_of(" \r\n");
		while (end != std::string::npos && end > 0 && result[end - 1] == '^' &&
			result[end] >= '0' && result[end] <= '9')
			end = end >= 2 ? end - 2 : std::string::npos;
		if (end != std::string::npos && result[end] == '.' &&
			result.find('.') == end)
			result.erase(end, 1);

		return result == value ? std::nullopt : std::optional{std::move(result)};
	}
}
