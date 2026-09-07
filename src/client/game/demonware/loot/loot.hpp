#pragma once

namespace demonware
{
	namespace loot
	{
		struct Item
		{
			std::uint32_t id;
			std::uint32_t quality;
			std::uint32_t salvageReturned;
			std::uint32_t cost;

			// Define equality operator for Item
			bool operator==(const Item& other) const {
				return id == other.id && quality == other.quality && salvageReturned == other.salvageReturned && cost == other.cost;
			}
		};

		enum CurrencyType
		{
			keys = 11,
			salvage = 12,
			codpoints = 20,
		};

		enum LootBoxType
		{
			LOOT_COMMON_CRATE = 70000,
			LOOT_RARE_CRATE = 70001,
			ZOMBIE_COMMON_CRATE = 70002,
			ZOMBIE_RARE_CRATE = 70003,
			ZOMBIE_COMMON_CARD_PACK = 70004,
			ZOMBIE_RARE_CARD_PACK = 70005,
		};

		std::vector<Item> get_random_loot(const std::uint32_t lootbox_id);
		std::vector<Item> get_all_loot();
		std::vector<Item> get_all_loot_owned();
		Item get_loot(const std::uint32_t item_id);

		std::uint32_t get_lootcrate_cost(const std::uint32_t id, const std::uint32_t type);

		void set_item_balance(const std::uint32_t item_id, const std::uint32_t amount);
		std::uint32_t get_item_balance(const std::uint32_t item_id);

		void set_currency_balance(const std::uint32_t currency_id, const std::uint32_t amount);
		std::uint32_t get_currency_balance(const std::uint32_t currency_id);

		struct match_key_reward
		{
			bool accepted;
			std::uint32_t before;
			std::uint32_t balance;
		};

		std::uint32_t begin_key_reward(int mission_id);
		match_key_reward finish_key_reward(std::uint32_t instance_id,
			int mission_id, std::uint32_t earned);

		// daily login
		bool is_new_day();
		int get_days_logged_in();
		void set_days_logged_in(const std::int32_t new_days);

		void save();
	}
}
