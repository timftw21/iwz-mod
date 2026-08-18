#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"

#include "console/console.hpp"
#include "gsc/script_extension.hpp"
#include "gsc/script_error.hpp"

#include <utils/hook.hpp>

#include <array>

namespace zombie_collision
{
	namespace
	{
		constexpr auto max_gentities = 2048;
		constexpr auto entitynum_none = 0x7FF;
		constexpr auto character_collision_entity_number_offset = 0x1C;
		constexpr auto character_collision_origin_z_offset = 0x30;
		constexpr auto crawler_clearance_epsilon = 0.5f;
		constexpr auto crawler_word_count = max_gentities / 64;

		std::array<std::atomic<unsigned long long>, crawler_word_count> crawler_entities{};
		std::array<std::atomic<float>, max_gentities> crawler_top_offsets{};
		std::array<std::atomic_bool, max_gentities> crawler_retained_logged{};
		std::array<std::atomic_bool, max_gentities> crawler_cleared_logged{};
		utils::hook::detour pm_get_character_collision_type_hook;

		bool set_crawler_entity(const int entity_number, const bool enabled, const float top_offset)
		{
			if (entity_number < 0 || entity_number >= entitynum_none)
			{
				return false;
			}

			const auto word = static_cast<std::size_t>(entity_number / 64);
			const auto mask = 1ull << (entity_number % 64);
			if (enabled)
			{
				crawler_top_offsets[entity_number].store(top_offset, std::memory_order_release);
			}

			const auto previous = enabled
				? crawler_entities[word].fetch_or(mask, std::memory_order_release)
				: crawler_entities[word].fetch_and(~mask, std::memory_order_release);
			crawler_retained_logged[entity_number].store(false, std::memory_order_relaxed);
			crawler_cleared_logged[entity_number].store(false, std::memory_order_relaxed);
			return (previous & mask) != 0;
		}

		bool is_crawler_entity(const int entity_number)
		{
			if (entity_number < 0 || entity_number >= entitynum_none)
			{
				return false;
			}

			const auto word = static_cast<std::size_t>(entity_number / 64);
			const auto mask = 1ull << (entity_number % 64);
			return (crawler_entities[word].load(std::memory_order_acquire) & mask) != 0;
		}

		int pm_get_character_collision_type_stub(game::pmove_t* pm, const int local_entity_number,
			const bool allow_soft_push, const void* character_collision)
		{
			if (pm != nullptr && pm->ps != nullptr && character_collision != nullptr)
			{
				const auto* collision_data = static_cast<const std::uint8_t*>(character_collision);
				const auto entity_number = *reinterpret_cast<const std::uint16_t*>(
					collision_data + character_collision_entity_number_offset);
				if (is_crawler_entity(entity_number))
				{
					const auto player_feet_z = pm->ps->origin[2];
					const auto crawler_origin_z = *reinterpret_cast<const float*>(
						collision_data + character_collision_origin_z_offset);
					const auto crawler_top_z = crawler_origin_z +
						crawler_top_offsets[entity_number].load(std::memory_order_acquire);
					const auto vertical_clearance = player_feet_z - crawler_top_z;

					if (vertical_clearance >= crawler_clearance_epsilon)
					{
						if (!crawler_cleared_logged[entity_number].exchange(true,
							std::memory_order_relaxed))
						{
							console::info(
								"[IWZ][CrawlerCollision] vertical clearance passed ent=%i "
								"playerFeetZ=%.2f crawlerTopZ=%.2f clearance=%.2f; "
								"character response ignored\n",
								entity_number, player_feet_z, crawler_top_z, vertical_clearance);
						}

						// IW's character resolver does not account for the crawler's
						// shortened server capsule. Once the player's capsule no longer
						// overlaps its top, exclude only that character response.
						return 0;
					}

					if (!crawler_retained_logged[entity_number].exchange(true,
						std::memory_order_relaxed))
					{
						console::info(
							"[IWZ][CrawlerCollision] vertical overlap retained ent=%i "
							"playerFeetZ=%.2f crawlerTopZ=%.2f clearance=%.2f\n",
							entity_number, player_feet_z, crawler_top_z, vertical_clearance);
					}
				}
			}

			return pm_get_character_collision_type_hook.invoke<int>(pm, local_entity_number,
				allow_soft_push, character_collision);
		}

		float get_number(const scripting::value_wrap& argument)
		{
			if (argument.is<float>())
			{
				return argument.as<float>();
			}

			return static_cast<float>(argument.as<int>());
		}

		bool has_expected_agent_bounds(const game::Bounds& bounds, const float reported_radius,
			const float reported_half_height)
		{
			constexpr auto maximum_bounds_value = 256.0f;
			constexpr auto radius_tolerance = 0.5f;
			constexpr auto height_tolerance = 0.5f;

			for (auto axis = 0; axis < 3; ++axis)
			{
				if (!std::isfinite(bounds.midPoint[axis]) || !std::isfinite(bounds.halfSize[axis]) ||
					std::abs(bounds.midPoint[axis]) > maximum_bounds_value ||
					bounds.halfSize[axis] <= 0.0f || bounds.halfSize[axis] > maximum_bounds_value)
				{
					return false;
				}
			}

			return std::abs(bounds.halfSize[0] - reported_radius) <= radius_tolerance &&
				std::abs(bounds.halfSize[1] - reported_radius) <= radius_tolerance &&
				std::abs(bounds.midPoint[2] - reported_half_height) <= height_tolerance &&
				std::abs(bounds.halfSize[2] - reported_half_height) <= height_tolerance;
		}

		scripting::script_value set_agent_collision_bounds(const gsc::function_args& args)
		{
			if (args.size() != 4)
			{
				gsc::scr_error("iwz_set_agent_collision_bounds requires an agent, current radius, current half-height, and target half-height");
				return {};
			}

			const auto agent = args[0].as<scripting::entity>();
			const auto ent_ref = agent.get_entity_reference();
			auto* entity = game::GetEntity(ent_ref);
			if (entity == nullptr || entity->agent == nullptr)
			{
				gsc::scr_error(utils::string::va("entity %i is not an agent", ent_ref));
				return {};
			}

			const auto radius = get_number(args[1]);
			const auto reported_half_height = get_number(args[2]);
			const auto target_half_height = get_number(args[3]);
			if (!std::isfinite(radius) || !std::isfinite(reported_half_height) ||
				!std::isfinite(target_half_height) || radius <= 0.0f || reported_half_height < radius ||
				target_half_height < radius)
			{
				gsc::scr_error(utils::string::va(
					"invalid agent collision bounds radius=%g current half-height=%g target half-height=%g",
					radius, reported_half_height, target_half_height));
				return {};
			}

			const auto previous = entity->box;
			if (!has_expected_agent_bounds(previous, radius, reported_half_height))
			{
				console::error(
					"[IWZ][CollisionBounds] rejected ent=%i: server bounds do not match reported capsule "
					"radius=%.2f halfHeight=%.2f "
					"mid=(%.2f %.2f %.2f) half=(%.2f %.2f %.2f)\n",
					entity->s.number, radius, reported_half_height,
					previous.midPoint[0], previous.midPoint[1], previous.midPoint[2],
					previous.halfSize[0], previous.halfSize[1], previous.halfSize[2]);
				return false;
			}

			entity->box.midPoint[2] = target_half_height;
			entity->box.halfSize[0] = radius;
			entity->box.halfSize[1] = radius;
			entity->box.halfSize[2] = target_half_height;

			console::info(
				"[IWZ][CollisionBounds] ent=%i beforeMid=(%.2f %.2f %.2f) beforeHalf=(%.2f %.2f %.2f) "
				"afterMid=(%.2f %.2f %.2f) afterHalf=(%.2f %.2f %.2f)\n",
				entity->s.number,
				previous.midPoint[0], previous.midPoint[1], previous.midPoint[2],
				previous.halfSize[0], previous.halfSize[1], previous.halfSize[2],
				entity->box.midPoint[0], entity->box.midPoint[1], entity->box.midPoint[2],
				entity->box.halfSize[0], entity->box.halfSize[1], entity->box.halfSize[2]);

			return true;
		}

		scripting::script_value set_agent_crawler(const gsc::function_args& args)
		{
			if (args.size() != 2)
			{
				gsc::scr_error("iwz_set_agent_crawler requires an agent and an enabled boolean");
				return {};
			}

			const auto agent = args[0].as<scripting::entity>();
			const auto ent_ref = agent.get_entity_reference();
			auto* entity = game::GetEntity(ent_ref);
			if (entity == nullptr || entity->agent == nullptr)
			{
				gsc::scr_error(utils::string::va("entity %i is not an agent", ent_ref));
				return {};
			}

			const auto enabled = args[1].as<int>() != 0;
			const auto top_offset = enabled
				? entity->box.midPoint[2] + entity->box.halfSize[2]
				: 0.0f;
			if (enabled && (!std::isfinite(top_offset) || top_offset <= 0.0f || top_offset > 256.0f))
			{
				gsc::scr_error(utils::string::va(
					"invalid crawler collision top offset ent=%i top=%g", entity->s.number, top_offset));
				return {};
			}

			const auto was_enabled = set_crawler_entity(entity->s.number, enabled, top_offset);
			if (enabled && !was_enabled)
			{
				console::info(
					"[IWZ][CrawlerCollision] marked crawler ent=%i topOffset=%.2f "
					"for vertical-clearance filtering\n",
					entity->s.number, top_offset);
			}
			else if (!enabled && was_enabled)
			{
				console::info("[IWZ][CrawlerCollision] cleared recycled crawler ent=%i\n",
					entity->s.number);
			}

			return true;
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			// IW7 resolves character-vs-character contacts after its ordinary movement
			// trace. Its resolver ignores a crawler's shortened server bounds and treats
			// the character as vertically infinite. Preserve overlap and filter only after
			// the player's feet clear the crawler's real capsule top.
			pm_get_character_collision_type_hook.create(0x1406FB040,
				pm_get_character_collision_type_stub);

			gsc::function::add("iwz_set_agent_collision_bounds", set_agent_collision_bounds);
			gsc::function::add("iwz_set_agent_crawler", set_agent_crawler);
			console::info(
				"[IWZ][CrawlerCollision] vertical-clearance character-response filter registered "
				"classifier=0x1406FB040 entityNumberOffset=0x1C originZOffset=0x30 epsilon=%.2f\n",
				crawler_clearance_epsilon);
			console::info("[IWZ][CollisionBounds] agent collision-bounds function registered boundsOffset=280\n");
		}
	};
}

REGISTER_COMPONENT(zombie_collision::component)
