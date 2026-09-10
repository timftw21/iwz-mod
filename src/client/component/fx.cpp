#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "component/console/console.hpp"
#include "component/gsc/script_extension.hpp"

#include "game/game.hpp"

#include <utils/hook.hpp>

namespace fx
{
	namespace
	{
		constexpr auto trailblazer_fx_name = "vfx/iw7/core/zombie/vfx_zmb_fire_trail_1st";
		constexpr auto trailblazer_emission_end = 0.6f;
		constexpr game::ParticleFloatRange trailblazer_particle_life{0.35f, 0.4f};

		bool nearly_equal(const float first, const float second)
		{
			return std::abs(first - second) < 0.001f;
		}

		bool extend_buoy_visibility(game::GfxWorld* world, const game::XModel* model,
			char* data, const unsigned int size, const unsigned int tome_index, const float distance)
		{
			// Umbra v20 stores bounds plus squared near/far distances separately
			// from XModel LODs. Objects can group several static model instances.
			if (!data || size < 84 || !world->dpvs.lodData || !world->dpvs.smodelInsts)
				return false;
			auto read_uint = [data](const size_t offset)
			{
				unsigned int value;
				std::memcpy(&value, data + offset, sizeof(value));
				return value;
			};
			auto in_range = [size](const size_t offset, const size_t count, const size_t stride)
			{
				return offset >= 84 && offset <= size && count <= (size - offset) / stride;
			};
			if (read_uint(0) != 0xd6000014 || read_uint(8) != size)
				return false;
			const size_t count = read_uint(0x40);
			const size_t distances = read_uint(0x48);
			const size_t starts = read_uint(0x4c);
			const size_t ids = read_uint(0x50);
			if (!in_range(distances, count, 32) || !in_range(starts, count + 1, 4))
				return false;
			const auto id_count = read_uint(starts + count * 4);
			if (!in_range(ids, id_count, 4) || read_uint(starts) != 0)
				return false;

			std::vector<std::pair<size_t, float>> changes;
			unsigned int instances = 0;
			for (size_t index = 0; index < count; ++index)
			{
				const auto begin = read_uint(starts + index * 4);
				const auto end = read_uint(starts + (index + 1) * 4);
				if (begin > end || end > id_count)
					return false;
				float record[8];
				std::memcpy(record, data + distances + index * 32, sizeof(record));
				unsigned int matches = 0;
				float scale = 0;
				for (auto entry = begin; entry < end; ++entry)
				{
					const auto id = read_uint(ids + entry * 4);
					const auto original_index = id & 0x0fffffff;
					if ((id >> 28) != 1 || original_index >= world->dpvs.smodelCount)
						continue;
					// Despite its inherited name, lodData maps Umbra's original
					// static model IDs to the renderer's sorted instance indices.
					const auto model_index = world->dpvs.lodData[original_index];
					if (model_index >= world->dpvs.smodelCount)
						return false;
					const auto& instance = world->dpvs.smodelDrawInsts[model_index];
					if (instance.model != model)
						continue;
					const auto& bounds = world->dpvs.smodelInsts[model_index].bounds;
					for (auto axis = 0; axis < 3; ++axis)
					{
						if (!std::isfinite(record[axis]) || !std::isfinite(record[axis + 4]) ||
							bounds.midPoint[axis] - bounds.halfSize[axis] < record[axis] - 0.001f ||
							bounds.midPoint[axis] + bounds.halfSize[axis] > record[axis + 4] + 0.001f)
							return false;
					}
					if (!std::isfinite(instance.placement.scale) || instance.placement.scale <= 0)
						return false;
					scale = std::max(scale, instance.placement.scale);
					++matches;
				}
				if (!matches)
					continue;
				const auto limit = distance * scale;
				const auto stock = 853.2838134765625f * scale;
				if (matches != end - begin || record[3] != 0 ||
					(std::abs(record[7] - stock * stock) > 0.125f && record[7] != limit * limit))
					return false;
				changes.emplace_back(distances + index * 32 + 28, limit * limit);
				instances += matches;
			}
			if (changes.empty())
				return false;
			// Validate the entire table before editing any distance. Leave bounds,
			// object grouping and occlusion data intact.
			for (const auto& [offset, limit] : changes)
				std::memcpy(data + offset, &limit, sizeof(limit));
			console::info("[IWZ][RaveBuoy] visibilityTome=%u objects=%zu instances=%u bakedDistance=853.284->%.0f\n",
				tome_index, changes.size(), instances, distance);
			return true;
		}

		void fix_rave_buoy_distance(game::GfxWorld* world)
		{
			constexpr auto model_name = "cp_rave_lake_buoy_01";
			constexpr auto stock_distance = 853.2838134765625f;
			constexpr auto lake_distance = 8192.0f;
			auto* model = game::DB_FindXAssetHeader(game::ASSET_TYPE_XMODEL, model_name, false).model;
			if (!world->dpvs.smodelDrawInsts || !model || !model->name ||
				std::strcmp(model->name, model_name) != 0 || model->numLods != 2 ||
				!nearly_equal(model->lodInfo[0].dist, 341.31353759765625f) ||
				(!nearly_equal(model->lodInfo[1].dist, stock_distance) &&
					!nearly_equal(model->lodInfo[1].dist, lake_distance)))
			{
				console::warn("[IWZ][RaveBuoy] lake buoy model or LOD validation failed; distances unchanged\n");
				return;
			}

			// The logged lake position (-3373.34, 2279.15, -209.004) is beside
			// this 79-instance boundary chain. Its last LOD ends at 853 units,
			// although the chain spans almost 5000 units. Keep the existing near
			// LOD switch and extend only the cheap 88-triangle final mesh.
			const auto previous_distance = model->lodInfo[1].dist;
			model->lodInfo[1].dist = lake_distance;
			unsigned int instances = 0;
			unsigned int extended = 0;
			for (auto index = 0u; index < world->dpvs.smodelCount; ++index)
			{
				auto& instance = world->dpvs.smodelDrawInsts[index];
				if (instance.model != model)
					continue;

				++instances;
				// The map also stores a separate per-instance cutoff (854 at scale
				// one). Updating the XModel alone leaves that early rejection intact.
				const auto distance = static_cast<unsigned short>(std::clamp(
					std::ceil(lake_distance * instance.placement.scale), 1.0f, 65535.0f));
				if (instance.cullDist < distance)
				{
					instance.cullDist = distance;
					++extended;
				}
			}
			console::info("[IWZ][RaveBuoy] model='%s' finalLodDistance=%.3f->%.0f instances=%u extendedCullDistances=%u nearLodDistance=%.3f\n",
				model_name, previous_distance, lake_distance, instances, extended, model->lodInfo[0].dist);
			if (!extend_buoy_visibility(world, model, world->umbraTomeData, world->umbraTomeSize, 1, lake_distance))
				console::warn("[IWZ][RaveBuoy] visibility tome 1 validation failed; baked distances unchanged\n");
			if (!extend_buoy_visibility(world, model, world->umbraTomeData2, world->umbraTomeSize2, 2, lake_distance))
				console::warn("[IWZ][RaveBuoy] visibility tome 2 validation failed; baked distances unchanged\n");
		}

		void fix_shaolin_window_frames(game::GfxWorld* world)
		{
			constexpr auto model_name = "cp_disco_bsp_window_01";
			constexpr std::array distances{841.96563720703125f, 2000.0f, 4210.2236328125f};
			constexpr std::array<unsigned short, 3> triangles{300, 116, 44};
			auto* model = game::DB_FindXAssetHeader(game::ASSET_TYPE_XMODEL, model_name, false).model;
			if (!world->dpvs.smodelDrawInsts || !model || !model->name ||
				std::strcmp(model->name, model_name) != 0 || model->numLods != distances.size())
			{
				console::warn("[IWZ][ShaolinWindows] window model validation failed; LOD meshes unchanged\n");
				return;
			}
			for (size_t index = 0; index < distances.size(); ++index)
			{
				const auto& lod = model->lodInfo[index];
				const auto* mesh = lod.modelSurfs;
				const auto expected_triangles = mesh == model->lodInfo[0].modelSurfs ? triangles[0] : triangles[index];
				if (!nearly_equal(lod.dist, distances[index]) || lod.numsurfs != 1 ||
					!mesh || mesh->numsurfs != 1 || !mesh->surfs || mesh->surfs[0].triCount != expected_triangles)
				{
					console::warn("[IWZ][ShaolinWindows] window LOD validation failed lod=%zu; meshes unchanged\n", index);
					return;
				}
			}

			// The reported hit (500,1050.22,1160.96) belongs to this 16-window
			// facade. Its auto-generated middle LOD removes the outer trim; the
			// final LOD has zero front-facing area. Keep the intact 300-triangle
			// mesh at each tier, including its material indices and surface data.
			// The map's existing cull distances and Umbra visibility stay valid.
			for (size_t index = 1; index < distances.size(); ++index)
			{
				model->lodInfo[index] = model->lodInfo[0];
				model->lodInfo[index].dist = distances[index];
			}
			unsigned int instances = 0;
			for (auto index = 0u; index < world->dpvs.smodelCount; ++index)
				instances += world->dpvs.smodelDrawInsts[index].model == model;
			console::info("[IWZ][ShaolinWindows] repaired model='%s' instances=%u LODTriangles=300/116/44->300/300/300 finalDistance=%.3f\n",
				model_name, instances, distances.back());
		}

		bool fix_beast_glare()
		{
			auto* world = *game::g_world;
			if (!world || !world->name || std::strcmp(world->name, "maps/cp/cp_final.d3dbsp") != 0 ||
				!world->dpvs.surfaces || !world->dpvs.surfacesBounds || !world->dpvs.surfaceMaterials)
			{
				console::warn("[IWZ][BeastGlare] Beast world surfaces unavailable; floor material unchanged\n");
				return false;
			}

			// Live scene inspection places the reported hit (1734.17, 4366.39, 15.998)
			// on this seven-triangle floor patch. Its second layer is glossy pooled
			// blood. Retain its existing deck layer, geometry, lightmap and collision.
			constexpr auto deck_name = "w/metal_deck_perforated_02";
			for (auto index = 0u; index < world->surfaceCount; ++index)
			{
				auto& surface = world->dpvs.surfaces[index];
				const auto& bounds = world->dpvs.surfacesBounds[index].bounds;
				if (!nearly_equal(bounds.midPoint[0], 1791.5f) ||
					!nearly_equal(bounds.midPoint[1], 4361.5f) || !nearly_equal(bounds.midPoint[2], 16.0f) ||
					!nearly_equal(bounds.halfSize[0], 137.5f) || !nearly_equal(bounds.halfSize[1], 39.5f) ||
					!nearly_equal(bounds.halfSize[2], 1.0f) || surface.tris.triCount != 7)
				{
					continue;
				}

				const auto* material = surface.material;
				if (material && material->info.name && std::strcmp(material->info.name, deck_name) == 0)
				{
					console::info("[IWZ][BeastGlare] floor patch already uses deck material surface=%u\n", index);
					return true;
				}
				if (!material || !material->info.name || std::strcmp(material->info.name, "*506n_176n") != 0 ||
					material->layerCount != 2 || !material->subMaterials || !material->subMaterials[0] ||
					!material->subMaterials[1] || std::strcmp(material->subMaterials[0], deck_name) != 0 ||
					std::strcmp(material->subMaterials[1], "w/t7_decal_blood_pool_01_dark_top") != 0)
				{
					console::warn("[IWZ][BeastGlare] floor layer validation failed surface=%u; material unchanged\n", index);
					return false;
				}
				auto* deck = game::DB_FindXAssetHeader(game::ASSET_TYPE_MATERIAL, deck_name, false).material;
				if (!deck || !deck->info.name || std::strcmp(deck->info.name, deck_name) != 0 ||
					deck->info.sortKey != material->info.sortKey || !deck->techniqueSet)
				{
					console::warn("[IWZ][BeastGlare] underlying deck material unavailable or incompatible; material unchanged\n");
					return false;
				}

				surface.material = deck;
				world->dpvs.surfaceMaterials[index] = deck->info.drawSurf;
				console::info("[IWZ][BeastGlare] removed pooled-blood layer surface=%u center=(1791.5,4361.5,16) material='%s' -> '%s'\n",
					index, material->info.name, deck->info.name);
				return true;
			}
			console::warn("[IWZ][BeastGlare] reported floor patch not found; material unchanged\n");
			return false;
		}

		void load_world_stub(const char* name)
		{
			// R_LoadWorld acquires the GfxWorld here, after the server's GSC main
			// has already run. Patch before the remaining renderer initialization
			// builds its world caches; no waiting or arbitrary delay is needed.
			utils::hook::invoke<void>(0x140DD1950, name);
			const auto* world = *game::g_world;
			if (world && world->name && std::strcmp(world->name, "maps/cp/cp_final.d3dbsp") == 0)
			{
				console::info("[IWZ][BeastGlare] Beast render world acquired; applying floor correction\n");
				fix_beast_glare();
			}
			else if (world && world->name && std::strcmp(world->name, "maps/cp/cp_rave.d3dbsp") == 0)
			{
				fix_rave_buoy_distance(*game::g_world);
			}
			else if (world && world->name && std::strcmp(world->name, "maps/cp/cp_disco.d3dbsp") == 0)
			{
				fix_shaolin_window_frames(*game::g_world);
			}
		}

		bool range_matches(const game::ParticleFloatRange& range, const float minimum, const float maximum)
		{
			return nearly_equal(range.min, minimum) && nearly_equal(range.max, maximum);
		}

		game::ParticleSystemDef* find_trailblazer_fx()
		{
			return game::DB_FindXAssetHeader(game::ASSET_TYPE_VFX, trailblazer_fx_name, false).vfx;
		}

		bool emitter_is_already_patched(const game::ParticleEmitterDef& emitter,
			const float minimum_spawn_rate, const float maximum_spawn_rate)
		{
			return range_matches(emitter.particleSpawnRate, minimum_spawn_rate, maximum_spawn_rate) &&
				range_matches(emitter.particleLife, trailblazer_particle_life.min, trailblazer_particle_life.max) &&
				range_matches(emitter.emitterLife, trailblazer_emission_end, trailblazer_emission_end);
		}

		bool emitter_matches_stock(const game::ParticleEmitterDef& emitter,
			const float minimum_spawn_rate, const float maximum_spawn_rate,
			const float minimum_particle_life, const float maximum_particle_life)
		{
			return emitter.flags == 0 &&
				range_matches(emitter.particleSpawnRate, minimum_spawn_rate, maximum_spawn_rate) &&
				range_matches(emitter.particleLife, minimum_particle_life, maximum_particle_life) &&
				range_matches(emitter.emitterLife, 0.0f, 0.0f);
		}

		void patch_emitter(game::ParticleEmitterDef& emitter,
			const float minimum_spawn_rate, const float maximum_spawn_rate)
		{
			emitter.particleSpawnRate = {minimum_spawn_rate, maximum_spawn_rate};
			emitter.particleLife = trailblazer_particle_life;
			emitter.emitterLife = {trailblazer_emission_end, trailblazer_emission_end};
		}

		bool patch_trailblazer_fx()
		{
			auto* particle_system = find_trailblazer_fx();
			if (!particle_system)
			{
				console::warn("[IWZ][TrailblazerFX] first-person VFX asset is not loaded; finite timeline not installed\n");
				return false;
			}

			if (!particle_system->emitterDefs || particle_system->numEmitters != 5)
			{
				console::warn("[IWZ][TrailblazerFX] asset validation failed name='%s' emitters=%d; finite timeline not installed\n",
					particle_system->name ? particle_system->name : "<unnamed>", particle_system->numEmitters);
				return false;
			}

			auto& smoke_left = particle_system->emitterDefs[0];
			auto& flame = particle_system->emitterDefs[1];
			auto& smoke_right = particle_system->emitterDefs[2];

			if (emitter_is_already_patched(smoke_left, 10.0f, 15.0f) &&
				emitter_is_already_patched(flame, 22.0f, 28.0f) &&
				emitter_is_already_patched(smoke_right, 10.0f, 15.0f))
			{
				console::info("[IWZ][TrailblazerFX] finite first-person flame timeline already installed\n");
				return true;
			}

			if (!emitter_matches_stock(smoke_left, 4.0f, 6.0f, 0.85f, 1.0f) ||
				!emitter_matches_stock(flame, 14.0f, 18.0f, 0.54f, 0.62f) ||
				!emitter_matches_stock(smoke_right, 4.0f, 6.0f, 0.85f, 1.0f))
			{
				console::warn("[IWZ][TrailblazerFX] stock emitter validation failed; finite timeline not installed\n");
				return false;
			}

			// These emitters originally run until the GSC entity is deleted at 1.0 second. Ending emission
			// at 0.6 seconds lets their existing per-particle alpha curves reach zero by that same deadline.
			// Spawn rates are adjusted to retain the stock effect's approximate peak particle density.
			patch_emitter(smoke_left, 10.0f, 15.0f);
			patch_emitter(flame, 22.0f, 28.0f);
			patch_emitter(smoke_right, 10.0f, 15.0f);

			console::info("[IWZ][TrailblazerFX] installed finite first-person flame timeline emissionEnd=%.2fs particleLife=%.2f..%.2fs total=1.00s emitters=0,1,2\n",
				trailblazer_emission_end, trailblazer_particle_life.min, trailblazer_particle_life.max);
			return true;
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			// skip "fx/" and "vfx/" name prefix checks
			utils::hook::set<uint8_t>(0x140B34889, 0xEB); // Scr_LoadFx
			utils::hook::nop(0x140D0FBFD, 2); // ParticleSystem_Register

			gsc::function::add("iwz_patch_trailblazer_fx", [](const gsc::function_args&)
			{
				return patch_trailblazer_fx() ? 1 : 0;
			});
			utils::hook::call(0x140DD14F7, load_world_stub);
		}
	};
}

REGISTER_COMPONENT(fx::component)
