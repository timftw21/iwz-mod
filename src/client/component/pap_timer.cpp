#include <std_include.hpp>

#include "pap_timer.hpp"

#include "console/console.hpp"
#include "scheduler.hpp"

#include <utils/memory.hpp>

namespace pap_timer
{
	namespace
	{
		constexpr auto zone_name = "iwz_pap_timer";
		constexpr auto material_name = "w/iwz_pap_timer_housing";
		constexpr auto lightmap_name = "iwz_pap_timer";

		struct map_config
		{
			const char* name;
			float origin[3];
		};

		constexpr map_config supported_maps[] =
		{
			{"cp_rave", {-10142.0f, 929.5f, -1544.0f}},
			{"cp_disco", {-10142.0f, 929.5f, -1544.0f}},
			{"cp_town", {-10142.0f, 929.5f, -1544.0f}},
			{"cp_final", {5237.5f, -5002.1f, 370.0f}},
		};

		struct source_vertex
		{
			float local[3];
			float binormal_sign;
			float tex_coord[2];
			float lightmap_coord[2];
			unsigned int normal;
			unsigned int tangent;
		};

		// Exact stock cp_zmb vertices 103152..103171, translated around the
		// housing midpoint. The lightmap coordinates are remapped into the
		// cropped 256x128/256 source atlas packaged in iwz_pap_timer.ff.
		constexpr source_vertex source_vertices[] =
		{
			{{-16.0f, -1.5f, 8.0f}, 0.031655762f, {-172.4375f, -77.0f}, {0.6512604f, 0.69942474f}, 0xFFF80200, 0xE00803FF},
			{{16.0f, 1.5f, 8.0f}, 0.0625f, {-171.4375f, -77.1875f}, {0.65238047f, 0.6990051f}, 0xFFF80200, 0xE00803FF},
			{{16.0f, -1.5f, 8.0f}, 0.0625f, {-171.4375f, -77.0f}, {0.65238047f, 0.69942474f}, 0xFFF80200, 0xE00803FF},
			{{-16.0f, 1.5f, 8.0f}, 0.0625f, {-172.4375f, -77.1875f}, {0.6512604f, 0.6990051f}, 0xFFF80200, 0xE00803FF},
			{{-16.0f, 1.5f, -8.0f}, 0.0625f, {174.09375f, 78.0f}, {0.6256974f, 0.68777466f}, 0xE0080000, 0x200FFE00},
			{{-16.0f, 1.5f, 8.0f}, 0.0625f, {174.09375f, 77.0f}, {0.6251373f, 0.68777466f}, 0xE0080000, 0x200FFE00},
			{{-16.0f, -1.5f, 8.0f}, 0.061698876f, {174.0f, 77.0f}, {0.6251373f, 0.6881943f}, 0xE0080000, 0x200FFE00},
			{{-16.0f, -1.5f, -8.0f}, 0.0625f, {174.0f, 78.0f}, {0.6256974f, 0.6881943f}, 0xE0080000, 0x200FFE00},
			{{16.0f, -1.5f, 8.0f}, 0.061698876f, {174.0f, 77.0f}, {0.6548219f, 0.6887512f}, 0xE00803FF, 0xE00FFE00},
			{{16.0f, 1.5f, 8.0f}, 0.0625f, {174.09375f, 77.0f}, {0.6549269f, 0.6887512f}, 0xE00803FF, 0xE00FFE00},
			{{16.0f, 1.5f, -8.0f}, 0.0625f, {174.09375f, 78.0f}, {0.6549269f, 0.6898713f}, 0xE00803FF, 0xE00FFE00},
			{{16.0f, -1.5f, -8.0f}, 0.0625f, {174.0f, 78.0f}, {0.6548219f, 0.6898713f}, 0xE00803FF, 0xE00FFE00},
			{{16.0f, -1.5f, -8.0f}, 0.0625f, {-171.4375f, -77.0f}, {0.65579844f, 0.6950302f}, 0xC0080200, 0x200803FF},
			{{16.0f, 1.5f, -8.0f}, 0.0625f, {-171.4375f, -77.1875f}, {0.65579844f, 0.6946106f}, 0xC0080200, 0x200803FF},
			{{-16.0f, 1.5f, -8.0f}, 0.031655762f, {-172.4375f, -77.1875f}, {0.65467834f, 0.6946106f}, 0xC0080200, 0x200803FF},
			{{-16.0f, -1.5f, -8.0f}, 0.0625f, {-172.4375f, -77.0f}, {0.65467834f, 0.6950302f}, 0xC0080200, 0x200803FF},
			{{-16.0f, -1.5f, -8.0f}, 0.0625f, {-172.4375f, 78.0f}, {0.6537018f, 0.6898713f}, 0xE0000200, 0xE00803FF},
			{{-16.0f, -1.5f, 8.0f}, 0.0625f, {-172.4375f, 77.0f}, {0.6537018f, 0.6887512f}, 0xE0000200, 0xE00803FF},
			{{16.0f, -1.5f, 8.0f}, 0.03952847f, {-171.4375f, 77.0f}, {0.6548219f, 0.6887512f}, 0xE0000200, 0xE00803FF},
			{{16.0f, -1.5f, -8.0f}, 0.0625f, {-171.4375f, 78.0f}, {0.6548219f, 0.6898713f}, 0xE0000200, 0xE00803FF},
		};

		constexpr unsigned short source_indices[] =
		{
			0, 1, 2, 0, 3, 1,
			4, 5, 6, 4, 6, 7,
			8, 9, 10, 8, 10, 11,
			12, 13, 14, 12, 14, 15,
			16, 17, 18, 16, 18, 19,
		};

		struct pending_install
		{
			game::GfxWorld* world;
			const map_config* config;
			bool installed;
		};

		std::mutex install_mutex;
		pending_install pending{};
		game::Material* housing_material;
		game::GfxLightMap* housing_lightmap;

		const map_config* find_config(const char* name)
		{
			if (!name)
			{
				return nullptr;
			}

			for (const auto& config : supported_maps)
			{
				if (strstr(name, config.name))
				{
					return &config;
				}
			}

			return nullptr;
		}

		const map_config* find_config(const game::GfxWorld* world)
		{
			if (!world)
			{
				return nullptr;
			}

			if (const auto* config = find_config(world->name))
			{
				return config;
			}

			return find_config(world->baseName);
		}

		template <typename T>
		T* allocate_array(const size_t count)
		{
			auto* result = utils::memory::get_allocator()->allocate_array<T>(count);
			std::memset(result, 0, sizeof(T) * count);
			return result;
		}

		template <typename T>
		T* insert_array(const T* source, const size_t count, const size_t index, const T& value)
		{
			auto* result = allocate_array<T>(count + 1);
			if (source && index)
			{
				std::memcpy(result, source, index * sizeof(T));
			}

			result[index] = value;
			if (source && index < count)
			{
				std::memcpy(&result[index + 1], &source[index], (count - index) * sizeof(T));
			}

			return result;
		}

		bool contains_point(const game::Bounds& bounds, const float point[3])
		{
			for (auto axis = 0; axis < 3; ++axis)
			{
				if (point[axis] < bounds.midPoint[axis] - bounds.halfSize[axis] ||
					point[axis] > bounds.midPoint[axis] + bounds.halfSize[axis])
				{
					return false;
				}
			}

			return true;
		}

		float bounds_volume(const game::Bounds& bounds)
		{
			return bounds.halfSize[0] * bounds.halfSize[1] * bounds.halfSize[2];
		}

		struct leaf_match
		{
			game::GfxWorldTransientZone* zone;
			game::GfxAabbTree* tree;
			unsigned int cell_index;
			unsigned int tree_index;
			unsigned int sorted_position;
			unsigned int neighbor_surface;
		};

		std::optional<leaf_match> find_leaf(game::GfxWorld* world, const float origin[3])
		{
			leaf_match best{};
			float best_volume = FLT_MAX;
			bool found = false;

			for (auto zone_index = 0u; zone_index < world->draw.transientZoneCount; ++zone_index)
			{
				auto* zone = world->draw.transientZones[zone_index];
				if (!zone || !zone->aabbTreeCounts || !zone->aabbTrees)
				{
					continue;
				}

				for (auto cell_index = 0u; cell_index < zone->cellCount; ++cell_index)
				{
					auto* trees = zone->aabbTrees[cell_index].aabbTree;
					const auto tree_count = zone->aabbTreeCounts[cell_index].aabbTreeCount;
					for (auto tree_index = 0; trees && tree_index < tree_count; ++tree_index)
					{
						auto* tree = &trees[tree_index];
						if (tree->childCount || !tree->surfaceCount || !contains_point(tree->bounds, origin) ||
							tree->startSurfIndex + tree->surfaceCount > world->dpvs.staticSurfaceCount)
						{
							continue;
						}

						const auto volume = bounds_volume(tree->bounds);
						if (volume >= best_volume)
						{
							continue;
						}

						best = {zone, tree, cell_index, static_cast<unsigned int>(tree_index),
							tree->startSurfIndex, 0};
						best_volume = volume;
						found = true;
					}
				}
			}

			if (!found)
			{
				return std::nullopt;
			}

			float nearest_distance = FLT_MAX;
			for (auto offset = 0u; offset < best.tree->surfaceCount; ++offset)
			{
				const auto sorted_position = best.tree->startSurfIndex + offset;
				const auto surface_index = world->dpvs.sortedSurfIndex[sorted_position];
				if (surface_index >= world->surfaceCount)
				{
					continue;
				}

				const auto& midpoint = world->dpvs.surfacesBounds[surface_index].bounds.midPoint;
				const auto dx = midpoint[0] - origin[0];
				const auto dy = midpoint[1] - origin[1];
				const auto dz = midpoint[2] - origin[2];
				const auto distance = dx * dx + dy * dy + dz * dz;
				if (distance < nearest_distance)
				{
					nearest_distance = distance;
					best.sorted_position = sorted_position;
					best.neighbor_surface = surface_index;
				}
			}

			return best;
		}

		bool read_bit(const unsigned int* words, const unsigned int word_count, const unsigned int bit)
		{
			return words && bit / 32 < word_count && (words[bit / 32] & (1u << (bit % 32)));
		}

		void build_vertices(game::GfxWorldVertex* vertices, const float origin[3])
		{
			for (auto i = 0u; i < std::size(source_vertices); ++i)
			{
				const auto& source = source_vertices[i];
				auto& vertex = vertices[i];
				for (auto axis = 0; axis < 3; ++axis)
				{
					vertex.xyz[axis] = origin[axis] + source.local[axis];
				}

				vertex.binormalSign = source.binormal_sign;
				vertex.color.packed = 0xFFFFFFFF;
				std::memcpy(vertex.texCoord, source.tex_coord, sizeof(vertex.texCoord));
				vertex.lmapCoord[0] = source.lightmap_coord[0] * 16.0f - 9.75f;
				vertex.lmapCoord[1] = source.lightmap_coord[1] * 16.0f - 10.75f;
				vertex.normal.packed = source.normal;
				vertex.tangent.packed = source.tangent;
			}
		}

		bool create_buffer_like(ID3D11Buffer* source, const void* data, const unsigned int size,
			ID3D11Buffer** destination)
		{
			*destination = nullptr;
			if (!source)
			{
				return false;
			}

			ID3D11Device* device = nullptr;
			source->GetDevice(&device);
			if (!device)
			{
				return false;
			}

			D3D11_BUFFER_DESC description{};
			source->GetDesc(&description);
			description.ByteWidth = size;

			D3D11_SUBRESOURCE_DATA initial_data{};
			initial_data.pSysMem = data;
			const auto result = device->CreateBuffer(&description, &initial_data, destination);
			device->Release();
			return SUCCEEDED(result);
		}

		unsigned int* insert_bit_rows(const unsigned int* source, const unsigned int row_count,
			const unsigned int source_word_count, const unsigned int destination_word_count,
			const unsigned int insertion_bit, const bool insertion_value)
		{
			if (!source || !row_count)
			{
				return nullptr;
			}

			auto* result = allocate_array<unsigned int>(row_count * destination_word_count);
			const auto bit_count = destination_word_count * 32;
			for (auto row = 0u; row < row_count; ++row)
			{
				const auto* source_row = &source[row * source_word_count];
				auto* destination_row = &result[row * destination_word_count];
				for (auto bit = 0u; bit < bit_count; ++bit)
				{
					const auto set = bit == insertion_bit
						? insertion_value
						: read_bit(source_row, source_word_count, bit < insertion_bit ? bit : bit - 1);
					if (set)
					{
						destination_row[bit / 32] |= 1u << (bit % 32);
					}
				}
			}

			return result;
		}

		void update_aabb_trees(game::GfxWorld* world, const unsigned int sorted_position,
			const float origin[3])
		{
			for (auto zone_index = 0u; zone_index < world->draw.transientZoneCount; ++zone_index)
			{
				auto* zone = world->draw.transientZones[zone_index];
				if (!zone || !zone->aabbTreeCounts || !zone->aabbTrees)
				{
					continue;
				}

				for (auto cell_index = 0u; cell_index < zone->cellCount; ++cell_index)
				{
					auto* trees = zone->aabbTrees[cell_index].aabbTree;
					const auto tree_count = zone->aabbTreeCounts[cell_index].aabbTreeCount;
					for (auto tree_index = 0; trees && tree_index < tree_count; ++tree_index)
					{
						auto& tree = trees[tree_index];
						const auto end = tree.startSurfIndex + tree.surfaceCount;
						if (tree.surfaceCount && tree.startSurfIndex <= sorted_position && sorted_position < end &&
							contains_point(tree.bounds, origin))
						{
							++tree.surfaceCount;
						}
						else if (tree.startSurfIndex >= sorted_position)
						{
							++tree.startSurfIndex;
						}
					}
				}
			}
		}

		void update_surface_references(game::GfxWorld* world, const unsigned int direct_insertion,
			const unsigned int sorted_insertion)
		{
			for (auto sky_index = 0; sky_index < world->skyCount; ++sky_index)
			{
				auto& sky = world->skies[sky_index];
				for (auto surface_index = 0; sky.skyStartSurfs && surface_index < sky.skySurfCount; ++surface_index)
				{
					if (sky.skyStartSurfs[surface_index] >= static_cast<int>(sorted_insertion))
					{
						++sky.skyStartSurfs[surface_index];
					}
				}
			}

			for (auto model_index = 0; model_index < world->modelCount; ++model_index)
			{
				if (world->models[model_index].startSurfIndex >= direct_insertion)
				{
					++world->models[model_index].startSurfIndex;
				}
			}

			if (world->shadowGeomOptimized)
			{
				for (auto light_index = 0u; light_index < world->primaryLightCount; ++light_index)
				{
					auto& shadow = world->shadowGeomOptimized[light_index];
					for (auto surface_index = 0u; shadow.sortedSurfIndex && surface_index < shadow.surfaceCount; ++surface_index)
					{
						if (shadow.sortedSurfIndex[surface_index] >= direct_insertion)
						{
							++shadow.sortedSurfIndex[surface_index];
						}
					}
				}
			}
		}

		void schedule_post_load_audit(game::GfxWorld* world, const map_config& config,
			const unsigned int direct_surface, const unsigned int sorted_position,
			game::GfxWorldTransientZone* owning_zone, ID3D11Buffer* index_buffer,
			ID3D11Buffer* vertex_buffer, const unsigned int vertex_count,
			const unsigned int lightmap_index)
		{
			const auto world_name = world->name ? std::string(world->name) : std::string();
			const auto* expected_material = housing_material;
			const auto* expected_lightmap = housing_lightmap;
			scheduler::schedule([=]()
			{
				if (!game::SV_Loaded())
				{
					return scheduler::cond_continue;
				}

				const auto* mapname = game::Dvar_FindVar("mapname");
				if (!mapname || !mapname->current.string || strcmp(mapname->current.string, config.name))
				{
					console::warn("[IWZ][PaPTimer] post-load audit cancelled expectedMap=%s activeMap=%s\n",
						config.name, mapname && mapname->current.string ? mapname->current.string : "<none>");
					return scheduler::cond_end;
				}

				const auto active_world = world_name.empty()
					? nullptr
					: game::DB_FindXAssetHeader(game::ASSET_TYPE_GFXWORLD, world_name.c_str(), 0).gfxWorld;
				if (active_world != world)
				{
					console::warn("[IWZ][PaPTimer] post-load audit cancelled map=%s worldChanged=%u\n",
						config.name, active_world != nullptr);
					return scheduler::cond_end;
				}

				const auto direct_valid = world->dpvs.surfaces && world->dpvs.surfaceMaterials &&
					direct_surface < world->surfaceCount;
				const auto sorted_valid = world->dpvs.sortedSurfIndex &&
					sorted_position < world->dpvs.staticSurfaceCount;
				const auto* surface = direct_valid ? &world->dpvs.surfaces[direct_surface] : nullptr;
				const auto retained = surface && surface->material == expected_material &&
					surface->transientZone == owning_zone->transientZoneIndex;
				const auto object_id = direct_valid
					? static_cast<unsigned int>(world->dpvs.surfaceMaterials[direct_surface].fields.objectId)
					: 0u;
				const auto sorted_surface = sorted_valid
					? world->dpvs.sortedSurfIndex[sorted_position]
					: UINT_MAX;
				const auto zone_retained = owning_zone->transientZoneIndex < world->draw.transientZoneCount &&
					world->draw.transientZones[owning_zone->transientZoneIndex] == owning_zone;
				const auto vertex_buffer_retained = owning_zone->vd.worldVb == vertex_buffer;
				const auto vertex_count_retained = owning_zone->vertexCount == vertex_count;
				const auto lightmap_retained = lightmap_index < world->draw.lightMapCount && world->draw.lightMaps &&
					world->draw.lightMaps[lightmap_index] == expected_lightmap;

				console::info("[IWZ][PaPTimer] post-load audit map=%s retained=%u surface=%u/%u "
					"objectId=%u sorted=%u->%u zone=%u/%u vertexBuffer=%u vertexCount=%u(%u/%u) "
					"indexBuffer=%u lightmap=%u/%u\n",
					config.name, static_cast<unsigned int>(retained), direct_surface,
					world->surfaceCount, object_id, sorted_position, sorted_surface,
					static_cast<unsigned int>(zone_retained), world->draw.transientZoneCount,
					static_cast<unsigned int>(vertex_buffer_retained),
					static_cast<unsigned int>(vertex_count_retained), owning_zone->vertexCount, vertex_count,
					static_cast<unsigned int>(world->draw.indexBuffer == index_buffer),
					static_cast<unsigned int>(lightmap_retained), world->draw.lightMapCount);
				return scheduler::cond_end;
			}, scheduler::main, 250ms);
		}

		int append_lightmap(game::GfxWorld* world)
		{
			if (!housing_lightmap || !housing_lightmap->textures[0] ||
				!housing_lightmap->textures[1] || !housing_lightmap->textures[2] ||
				world->draw.lightMapCount >= 255)
			{
				return -1;
			}

			const auto old_count = world->draw.lightMapCount;
			auto** lightmaps = allocate_array<game::GfxLightMap*>(old_count + 1);
			if (world->draw.lightMaps && old_count)
			{
				std::memcpy(lightmaps, world->draw.lightMaps, old_count * sizeof(*lightmaps));
			}
			lightmaps[old_count] = housing_lightmap;

			auto* textures = allocate_array<game::GfxTexture>(old_count + 1);
			if (world->draw.lightmapTextures && old_count)
			{
				std::memcpy(textures, world->draw.lightmapTextures, old_count * sizeof(*textures));
			}

			auto texture_slot = 0;
			if (old_count && world->draw.lightmapTextures && world->draw.lightMaps && world->draw.lightMaps[0])
			{
				for (auto slot = 0; slot < 3; ++slot)
				{
					const auto* image = world->draw.lightMaps[0]->textures[slot];
					if (image && !std::memcmp(&world->draw.lightmapTextures[0], &image->texture, sizeof(game::GfxTexture)))
					{
						texture_slot = slot;
						break;
					}
				}
			}

			if (!housing_lightmap->textures[texture_slot])
			{
				texture_slot = 0;
			}
			textures[old_count] = housing_lightmap->textures[texture_slot]->texture;

			auto& reindex = world->draw.lightmapReindexData;
			auto* packed = allocate_array<game::GfxWorldPackedLightmap>(reindex.packedLightmapCount + 1);
			if (reindex.packedLightmap && reindex.packedLightmapCount)
			{
				std::memcpy(packed, reindex.packedLightmap,
					reindex.packedLightmapCount * sizeof(*packed));
			}
			packed[reindex.packedLightmapCount].imageWidth = housing_lightmap->textures[0]->width;
			packed[reindex.packedLightmapCount].imageHeight = housing_lightmap->textures[0]->height;

			world->draw.lightMaps = lightmaps;
			world->draw.lightmapTextures = textures;
			world->draw.lightMapCount = old_count + 1;
			reindex.packedLightmap = packed;
			++reindex.packedLightmapCount;

			console::info("[IWZ][PaPTimer] lightmap appended index=%u textureSlot=%d primary=%s(%ux%u) "
				"secondary=%s(%ux%u) secondUnorm=%s(%ux%u)\n",
				old_count, texture_slot,
				housing_lightmap->textures[0] && housing_lightmap->textures[0]->name
					? housing_lightmap->textures[0]->name : "<none>",
				housing_lightmap->textures[0] ? housing_lightmap->textures[0]->width : 0,
				housing_lightmap->textures[0] ? housing_lightmap->textures[0]->height : 0,
				housing_lightmap->textures[1] && housing_lightmap->textures[1]->name
					? housing_lightmap->textures[1]->name : "<none>",
				housing_lightmap->textures[1] ? housing_lightmap->textures[1]->width : 0,
				housing_lightmap->textures[1] ? housing_lightmap->textures[1]->height : 0,
				housing_lightmap->textures[2] && housing_lightmap->textures[2]->name
					? housing_lightmap->textures[2]->name : "<none>",
				housing_lightmap->textures[2] ? housing_lightmap->textures[2]->width : 0,
				housing_lightmap->textures[2] ? housing_lightmap->textures[2]->height : 0);

			return static_cast<int>(old_count);
		}

		bool install_housing(game::GfxWorld* world, const map_config& config)
		{
			if (!world->dpvs.surfaces || !world->dpvs.surfacesBounds || !world->dpvs.sortedSurfIndex ||
				!world->dpvs.surfaceMaterials || !world->draw.indices || !world->draw.indexBuffer ||
				!world->draw.transientZoneCount || !housing_lightmap ||
				!housing_lightmap->textures[0] || !housing_lightmap->textures[1] ||
				!housing_lightmap->textures[2] || world->draw.lightMapCount >= 255)
			{
				console::error("[IWZ][PaPTimer] install rejected map=%s incomplete world data\n", config.name);
				return false;
			}
			const auto leaf = find_leaf(world, config.origin);
			if (!leaf)
			{
				console::error("[IWZ][PaPTimer] install rejected map=%s no containing BSP leaf "
					"origin=(%.1f %.1f %.1f)\n", config.name,
					config.origin[0], config.origin[1], config.origin[2]);
				return false;
			}
			auto* owning_zone = leaf->zone;
			if (!owning_zone || !owning_zone->vd.vertices || !owning_zone->vd.worldVb)
			{
				console::error("[IWZ][PaPTimer] install rejected map=%s BSP leaf zone has no vertex data "
					"zone=%u\n", config.name,
					owning_zone ? owning_zone->transientZoneIndex : UINT_MAX);
				return false;
			}

			const auto old_surface_count = world->surfaceCount;
			const auto old_static_count = world->dpvs.staticSurfaceCount;
			const auto old_index_count = world->draw.indexCount;
			const auto old_vertex_count = owning_zone->vertexCount;
			const auto new_vertex_count = old_vertex_count + static_cast<unsigned int>(std::size(source_vertices));
			const auto direct_insertion = world->dpvs.litOpaqueSurfsEnd;
			if (direct_insertion > old_static_count || leaf->neighbor_surface >= old_surface_count)
			{
				console::error("[IWZ][PaPTimer] install rejected map=%s invalid surface ranges "
					"insert=%u static=%u neighbor=%u total=%u\n", config.name,
					direct_insertion, old_static_count, leaf->neighbor_surface, old_surface_count);
				return false;
			}

			auto* indices = allocate_array<unsigned short>(old_index_count + std::size(source_indices));
			std::memcpy(indices, world->draw.indices, old_index_count * sizeof(*indices));
			std::memcpy(&indices[old_index_count], source_indices, sizeof(source_indices));

			auto* vertices = allocate_array<game::GfxWorldVertex>(new_vertex_count);
			std::memcpy(vertices, owning_zone->vd.vertices, old_vertex_count * sizeof(*vertices));
			build_vertices(&vertices[old_vertex_count], config.origin);

			ID3D11Buffer* index_buffer = nullptr;
			ID3D11Buffer* vertex_buffer = nullptr;
			if (!create_buffer_like(world->draw.indexBuffer, indices,
				static_cast<unsigned int>((old_index_count + std::size(source_indices)) * sizeof(*indices)),
				&index_buffer) || !create_buffer_like(owning_zone->vd.worldVb, vertices,
				static_cast<unsigned int>(new_vertex_count * sizeof(*vertices)), &vertex_buffer))
			{
				if (index_buffer)
				{
					index_buffer->Release();
				}
				if (vertex_buffer)
				{
					vertex_buffer->Release();
				}
				console::error("[IWZ][PaPTimer] install rejected map=%s GPU buffer creation failed\n", config.name);
				return false;
			}

			auto surface = world->dpvs.surfaces[leaf->neighbor_surface];
			const auto* neighbor_material = surface.material;
			const auto neighbor_lightmap = surface.lightmapIndex;
			const auto neighbor_flags = surface.flags;
			surface.tris = {};
			surface.tris.firstVertex = old_vertex_count;
			surface.tris.maxEdgeLength = 35.77709f;
			surface.tris.vertexCount = static_cast<unsigned short>(std::size(source_vertices));
			surface.tris.triCount = static_cast<unsigned short>(std::size(source_indices) / 3);
			surface.tris.baseIndex = old_index_count;
			surface.material = housing_material;
			surface.transientZone = static_cast<unsigned char>(owning_zone->transientZoneIndex);

			auto bounds = world->dpvs.surfacesBounds[leaf->neighbor_surface];
			std::memcpy(bounds.bounds.midPoint, config.origin, sizeof(bounds.bounds.midPoint));
			bounds.bounds.halfSize[0] = 17.0f;
			bounds.bounds.halfSize[1] = 2.5f;
			bounds.bounds.halfSize[2] = 9.0f;

			auto* surfaces = insert_array(world->dpvs.surfaces, old_surface_count,
				direct_insertion, surface);
			auto* surface_bounds = insert_array(world->dpvs.surfacesBounds, old_surface_count,
				direct_insertion, bounds);
			const auto material_object_id = housing_material->info.drawSurf.fields.objectId;
			const auto neighbor_object_id = world->dpvs.surfaceMaterials[leaf->neighbor_surface].fields.objectId;
			auto* surface_materials = insert_array(world->dpvs.surfaceMaterials, old_surface_count,
				direct_insertion, housing_material->info.drawSurf);

			auto* sorted_surfaces = allocate_array<unsigned int>(old_static_count + 1);
			for (auto position = 0u; position < old_static_count + 1; ++position)
			{
				if (position == leaf->sorted_position)
				{
					sorted_surfaces[position] = direct_insertion;
					continue;
				}

				const auto source_position = position < leaf->sorted_position ? position : position - 1;
				const auto source_surface = world->dpvs.sortedSurfIndex[source_position];
				sorted_surfaces[position] = source_surface >= direct_insertion
					? source_surface + 1
					: source_surface;
			}

			const auto old_vis_word_count = world->dpvs.surfaceVisDataCount;
			const auto new_vis_word_count = (old_static_count + 32) / 32;
			for (auto index = 0; index < 30; ++index)
			{
				const auto surface_visible = read_bit(world->dpvs.surfaceVisData[index],
					old_vis_word_count, leaf->neighbor_surface);
				world->dpvs.surfaceVisData[index] = insert_bit_rows(world->dpvs.surfaceVisData[index], 1,
					old_vis_word_count, new_vis_word_count, direct_insertion, surface_visible);
				const auto tessellation_visible = read_bit(world->dpvs.tessellationCutoffVisData[index],
					old_vis_word_count, leaf->neighbor_surface);
				world->dpvs.tessellationCutoffVisData[index] = insert_bit_rows(
					world->dpvs.tessellationCutoffVisData[index], 1, old_vis_word_count,
					new_vis_word_count, direct_insertion, tessellation_visible);
			}

			const auto casts_sun_shadow = read_bit(world->dpvs.surfaceCastsSunShadow,
				old_vis_word_count, leaf->neighbor_surface);
			world->dpvs.surfaceCastsSunShadow = insert_bit_rows(world->dpvs.surfaceCastsSunShadow, 1,
				old_vis_word_count, new_vis_word_count, direct_insertion, casts_sun_shadow);

			const auto old_sun_word_count = world->dpvs.sunSurfVisDataCount;
			const auto new_sun_word_count = std::max(old_sun_word_count, (direct_insertion + 32) / 32);
			world->dpvs.surfaceCastsSunShadowOpt = insert_bit_rows(world->dpvs.surfaceCastsSunShadowOpt,
				world->dpvs.sunShadowOptCount, old_sun_word_count, new_sun_word_count,
				direct_insertion, false);
			world->dpvs.sunSurfVisDataCount = new_sun_word_count;

			update_surface_references(world, direct_insertion, leaf->sorted_position);
			update_aabb_trees(world, leaf->sorted_position, config.origin);

			world->dpvs.surfaces = surfaces;
			world->dpvs.surfacesBounds = surface_bounds;
			world->dpvs.surfaceMaterials = surface_materials;
			world->dpvs.sortedSurfIndex = sorted_surfaces;
			world->dpvs.surfaceVisDataCount = new_vis_word_count;
			world->surfaceCount = old_surface_count + 1;
			world->dpvs.staticSurfaceCount = old_static_count + 1;
			++world->dpvs.litOpaqueSurfsEnd;
			++world->dpvs.litDecalSurfsBegin;
			++world->dpvs.litDecalSurfsEnd;
			++world->dpvs.litTransSurfsBegin;
			++world->dpvs.litTransSurfsEnd;
			++world->dpvs.emissiveSurfsBegin;
			++world->dpvs.emissiveSurfsEnd;

			world->draw.indices = indices;
			world->draw.indexCount = old_index_count + static_cast<unsigned int>(std::size(source_indices));
			if (world->draw.indexBuffer)
			{
				world->draw.indexBuffer->Release();
			}
			world->draw.indexBuffer = index_buffer;
			if (owning_zone->vd.worldVb)
			{
				owning_zone->vd.worldVb->Release();
			}
			owning_zone->vd.vertices = vertices;
			owning_zone->vd.worldVb = vertex_buffer;
			owning_zone->vertexCount = new_vertex_count;

			const auto lightmap_index = append_lightmap(world);
			if (lightmap_index < 0)
			{
				console::error("[IWZ][PaPTimer] map=%s surface installed but lightmap append failed\n", config.name);
				return false;
			}
			world->dpvs.surfaces[direct_insertion].lightmapIndex = static_cast<unsigned char>(lightmap_index);

			console::info("[IWZ][PaPTimer] BSP housing restored map=%s directSurface=%u "
				"sortedPosition=%u leaf=zone%u/cell%u/tree%u neighbor=%u lightmap=%d "
				"origin=(%.1f %.1f %.1f) zoneVertices=%u->%u firstVertex=%u vertices=%zu triangles=%zu "
				"material=%s technique=%s "
				"neighborMaterial=%s neighborLightmap=%u neighborFlags=0x%02X visWords=%u->%u "
				"sunWords=%u->%u drawObject=%u neighborObject=%u\n",
				config.name, direct_insertion, leaf->sorted_position,
				leaf->zone->transientZoneIndex, leaf->cell_index, leaf->tree_index,
				leaf->neighbor_surface, lightmap_index,
				config.origin[0], config.origin[1], config.origin[2],
				old_vertex_count, new_vertex_count, old_vertex_count,
				std::size(source_vertices), std::size(source_indices) / 3,
				housing_material->name ? housing_material->name : "<none>",
				housing_material->techniqueSet && housing_material->techniqueSet->name
					? housing_material->techniqueSet->name : "<none>",
				neighbor_material && neighbor_material->name ? neighbor_material->name : "<none>",
				static_cast<unsigned int>(neighbor_lightmap), static_cast<unsigned int>(neighbor_flags),
				old_vis_word_count, new_vis_word_count, old_sun_word_count, new_sun_word_count,
				static_cast<unsigned int>(material_object_id), static_cast<unsigned int>(neighbor_object_id));
			schedule_post_load_audit(world, config, direct_insertion, leaf->sorted_position,
				owning_zone, index_buffer, vertex_buffer, new_vertex_count,
				static_cast<unsigned int>(lightmap_index));
			return true;
		}

		void try_install()
		{
			if (!pending.world || !pending.config || pending.installed || !housing_material || !housing_lightmap)
			{
				return;
			}

			if (!housing_material->techniqueSet || !housing_material->techniqueSet->name ||
				strcmp(housing_material->techniqueSet->name, "w_l_sm_replace_i0c0s0n0p0"))
			{
				console::error("[IWZ][PaPTimer] install deferred map=%s invalid world technique=%s\n",
					pending.config->name,
					housing_material->techniqueSet && housing_material->techniqueSet->name
						? housing_material->techniqueSet->name : "<none>");
				return;
			}

			pending.installed = install_housing(pending.world, *pending.config);
		}
	}

	const char* get_zone_name()
	{
		return zone_name;
	}

	bool requires_housing(const char* candidate_zone_name)
	{
		if (!candidate_zone_name)
		{
			return false;
		}

		for (const auto& config : supported_maps)
		{
			if (!strcmp(candidate_zone_name, config.name))
			{
				return true;
			}
		}

		return false;
	}

	void on_asset_loaded(const game::XAssetType type, const game::XAssetHeader header, const char* source_zone)
	{
		std::lock_guard lock(install_mutex);
		const auto* source = source_zone && *source_zone ? source_zone : "<unknown>";

		if (type == game::ASSET_TYPE_GFXWORLD && header.gfxWorld)
		{
			if (const auto* config = find_config(header.gfxWorld))
			{
				pending = {header.gfxWorld, config, false};
				console::info("[IWZ][PaPTimer] captured world map=%s asset=%s surfaces=%u static=%u "
					"indices=%u transientZones=%u lightmaps=%u sourceZone=%s materialReady=%u lightmapReady=%u\n",
					config->name, header.gfxWorld->name ? header.gfxWorld->name : "<none>",
					header.gfxWorld->surfaceCount, header.gfxWorld->dpvs.staticSurfaceCount,
					header.gfxWorld->draw.indexCount, header.gfxWorld->draw.transientZoneCount,
					header.gfxWorld->draw.lightMapCount, source,
					housing_material != nullptr, housing_lightmap != nullptr);
				try_install();
			}
			return;
		}

		if (type == game::ASSET_TYPE_MATERIAL && header.material && header.material->name &&
			!strcmp(header.material->name, material_name))
		{
			housing_material = header.material;
			console::info("[IWZ][PaPTimer] world material ready material=%s technique=%s textures=%u "
				"sourceZone=%s worldReady=%u lightmapReady=%u\n",
				header.material->name,
				header.material->techniqueSet && header.material->techniqueSet->name
					? header.material->techniqueSet->name : "<none>",
				static_cast<unsigned int>(header.material->textureCount), source,
				pending.world != nullptr, housing_lightmap != nullptr);
			try_install();
			return;
		}

		if (type == game::ASSET_TYPE_GFXLIGHTMAP && header.lightMap && header.lightMap->name &&
			!strcmp(header.lightMap->name, lightmap_name))
		{
			housing_lightmap = header.lightMap;
			console::info("[IWZ][PaPTimer] baked lightmap ready asset=%s sourceZone=%s worldReady=%u "
				"materialReady=%u\n", header.lightMap->name, source,
				pending.world != nullptr, housing_material != nullptr);
			try_install();
		}
	}
}
