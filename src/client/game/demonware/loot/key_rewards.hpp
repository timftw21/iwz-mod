#pragma once

#include <algorithm>
#include <cstdint>

namespace demonware::loot
{
	// Approximation v1, not the original Demonware rule. Currency 11 stores
	// hundredths of a key. See docs/key-earning.md for the chosen rates.
	constexpr std::uint32_t calculate_match_keys(const int mission_id,
		const int result, const int seconds, const bool double_keys)
	{
		if (seconds <= 0 || result < 0)
			return 0;

		std::int64_t units = 0;
		if (mission_id == 1)
		{
			// The reported Scene is the one reached, not the number completed.
			units = std::min<std::int64_t>(std::max(0, result - 1) * 80LL, 12500);
		}
		else if (mission_id == 0 && result <= 1)
		{
			// One key / 300 seconds, with a 25% win bonus. Multiply before
			// dividing so short matches retain fractional-key progress.
			return static_cast<std::uint32_t>(static_cast<std::int64_t>(seconds) *
				100 * (result == 1 ? 5 : 4) * (double_keys ? 2 : 1) / 1200);
		}
		return static_cast<std::uint32_t>(units * (double_keys ? 2 : 1));
	}
}
