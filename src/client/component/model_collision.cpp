#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "console/console.hpp"
#include "model_collision.hpp"
#include <utils/hook.hpp>
#include <array>
#include <mutex>

namespace model_collision
{
	namespace
	{
		struct collision_model
		{
			const char* name;
			const char* source;
			int contents;
			game::XModel model{};
			const game::XModel* source_model{};
			bool ready{};
		};

		// Distinct model names travel through the stock model configstrings. Every
		// client, including late joiners, therefore constructs the same collision.
		std::array<collision_model, 3> models{{
			{"iwz_solid_cp_disco_street_barricade", "cp_disco_street_barricade", 0x2081},
			{"iwz_solid_cp_rave_woodboard_01", "cp_rave_woodboard_01", 0x2081},
			{"iwz_playerclip_town_magic_wheel", "town_magic_wheel", 0x12080},
		}};
		std::mutex model_mutex;
		utils::hook::detour instantiate_asset_hook;
		utils::hook::detour instantiate_detail_model_hook;
		std::atomic_uint32_t collision_log_count{0};

		const collision_model* find_profile(const game::XModel* model)
		{
			for (const auto& entry : models)
				if (model == &entry.model)
					return &entry;
			return nullptr;
		}

		void apply_profile(int world, unsigned int instance, const collision_model* entry, bool detail)
		{
			if (!entry || instance == UINT_MAX)
				return;
			// XModel::contents does not update Havok's body filters. Include
			// prediction (2/5) and detailed collision (1/4/7), not only server 0.
			utils::hook::invoke<void>(0x140550EC0, world, instance, entry->contents);
			if (collision_log_count.fetch_add(1) < 48)
				console::info("[IWZ][ModelCollision] created model=%s world=%i instance=%u contents=0x%X prediction=%i detail=%i\n",
					entry->name, world, instance, entry->contents, world == 2 || world == 5, detail);
		}

		unsigned int instantiate_detail_model_stub(int world, const game::XModel* model,
			unsigned int reference, const float* position, const float* orientation,
			bool add_to_world, bool try_make_dynamic, bool query_only)
		{
			const auto* entry = find_profile(model);
			// The detail-shape registry at 0x140578CC0 is keyed by the original
			// XModel pointer, not its copied fields. An alias has no registration:
			// passing it to 0x14057C8A0 crashes at 0x14057C95F (null + 8).
			// Instantiate the registered source, then apply the alias's mask.
			const auto instance = instantiate_detail_model_hook.invoke<unsigned int>(world,
				entry ? entry->source_model : model, reference, position, orientation,
				add_to_world, try_make_dynamic, query_only);
			apply_profile(world, instance, entry, true);
			return instance;
		}

		unsigned int instantiate_asset_stub(int world, const game::XModel* model,
			const game::PhysicsAsset* asset, unsigned int reference, const float* position,
			const float* orientation, bool add_to_world, bool force_static, bool try_make_dynamic,
			const void* shape_override, int force_type, int filter_type, bool query_only)
		{
			const auto instance = instantiate_asset_hook.invoke<unsigned int>(world, model,
				asset, reference, position, orientation, add_to_world, force_static,
				try_make_dynamic, shape_override, force_type, filter_type, query_only);
			apply_profile(world, instance, find_profile(model), false);
			return instance;
		}
	}

	const char* source_name(const char* name)
	{
		if (name)
			for (const auto& entry : models)
				if (!std::strcmp(name, entry.name))
					return entry.source;
		return name;
	}

	game::XModel* resolve(const char* name, game::XModel* source)
	{
		std::lock_guard lock(model_mutex);
		for (auto& entry : models)
		{
			if (std::strcmp(name, entry.name))
				continue;
			if (!source || !source->name || std::strcmp(source->name, entry.source) || !source->physicsAsset)
			{
				console::error("[IWZ][ModelCollision] missing source physics model=%s source=%s\n", name, entry.source);
				return nullptr;
			}
			if (!entry.ready)
			{
				entry.model = *source;
				entry.model.name = entry.name;
				entry.model.contents = entry.contents;
				entry.model.physicsUsageCounter = {};
				entry.source_model = source;
				entry.ready = true;
				console::info("[IWZ][ModelCollision] profile ready model=%s source=%s contents=0x%X bodies=%i\n",
					name, entry.source, entry.contents, source->physicsAsset->numRigidBodies);
			}
			return &entry.model;
		}
		return source;
	}

	void on_model_loaded(const game::XModel* model)
	{
		if (!model || !model->name)
			return;
		std::lock_guard lock(model_mutex);
		for (auto& entry : models)
			if (!std::strcmp(model->name, entry.source))
				entry.ready = false;
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			instantiate_asset_hook.create(0x14054F8D0, instantiate_asset_stub);
			instantiate_detail_model_hook.create(0x14054FF20, instantiate_detail_model_stub);
		}
	};
}

REGISTER_COMPONENT(model_collision::component)
