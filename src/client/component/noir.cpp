#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "command.hpp"
#include "party.hpp"
#include "console/console.hpp"
#include "scheduler.hpp"
#include "game/game.hpp"

#include <array>
#include <cmath>
#include <limits>
#include <utils/json.hpp>
#include <utils/hook.hpp>

namespace noir
{
	namespace
	{
		constexpr auto map_name = "mp_prime";
		constexpr auto world_name = "maps/mp/mp_prime.d3dbsp";
		constexpr auto output_directory = "iw7-mod/map-data/mp_prime";
		using json = nlohmann::ordered_json;
		game::dvar_t* audit_requested = nullptr;
		game::dvar_t* navigation_available = nullptr;
		game::dvar_t* zombie_assets_available = nullptr;
		bool launch_pending = false;
		bool launch_ui_ready = false;
		utils::hook::detour com_error_hook;

		void log_engine_error(const game::errorParm code, const char* format, ...)
		{
			char message[16384]{};
			va_list args;
			va_start(args, format);
			vsnprintf_s(message, _TRUNCATE, format, args);
			va_end(args);
			const auto* enabled = game::Dvar_FindVar("iwz_noir_foundation");
			if (enabled && enabled->current.enabled)
				console::error("[IWZ][Noir] engine error code=%d: %s\n", code, message);
			com_error_hook.invoke<void>(code, "%s", message);
		}

		bool active()
		{
			const auto* map = game::Dvar_FindVar("mapname");
			return game::Com_GameMode_GetActiveGameMode() == game::GAME_MODE_MP &&
				game::SV_Loaded() && !game::Com_FrontEndScene_IsActive() && map &&
				map->current.string && !std::strcmp(map->current.string, map_name);
		}

		game::XAssetHeader asset(const game::XAssetType type, const char* name)
		{
			if (!game::DB_XAssetExists(type, name) || game::DB_IsXAssetDefault(type, name))
				return {};
			return game::DB_FindXAssetHeader(type, name, 0);
		}

		json audit()
		{
			json report = {{"schemaVersion", 1}, {"baseMap", map_name},
				{"runtime", "mp"}, {"dedicated", game::environment::is_dedi()}, {"gameplayProven", false}};
			const auto* title = game::UI_GetMapDisplayName(map_name);
			report["baseMapDisplayName"] = title ? title : "";
			const auto* world = asset(game::ASSET_TYPE_GFXWORLD, world_name).gfxWorld;
			const auto* collision = asset(game::ASSET_TYPE_CLIPMAP, world_name).clipMap;
			const auto* navigation = asset(game::ASSET_TYPE_NAVMESH, world_name).navMeshData;
			const auto* paths = asset(game::ASSET_TYPE_PATHDATA, world_name).pathData;
			const auto checksum = world ? std::to_string(world->checksum) : "";
			game::Dvar_SetFromStringByName("iwz_noir_world_checksum", checksum.c_str(), game::DVAR_SOURCE_INTERNAL);
			report["worldPresent"] = world != nullptr;
			report["collisionPresent"] = collision != nullptr;
			report["navigationPresent"] = navigation != nullptr;
			if (world)
			{
				report["world"] = {{"surfaces", world->surfaceCount},
					{"staticSurfaces", world->dpvs.staticSurfaceCount}, {"staticProps", world->dpvs.smodelCount},
					{"transientZones", world->draw.transientZoneCount}, {"indices", world->draw.indexCount},
					{"checksum", world->checksum}};
			}
			if (collision)
				report["collisionBytes"] = collision->havokWorldShapeDataSize;
			if (paths)
				report["pathNodes"] = paths->nodeCount;
			bool ground_navigation = false;
			if (navigation)
			{
				report["navigation"] = {{"version", navigation->version},
					{"links", navigation->numLinkCreationData}, {"resources", json::array()}};
				if (navigation->navResources && navigation->numNavResources >= 0 && navigation->numNavResources <= 4096)
				{
					for (int i = 0; i < navigation->numNavResources; ++i)
					{
						const auto& resource = navigation->navResources[i];
						report["navigation"]["resources"].push_back({{"graphBytes", resource.graphSize},
							{"volume", resource.bIsVolume}, {"layerFlags", resource.layerFlags}});
						ground_navigation |= !resource.bIsVolume && resource.graphSize > 0 && resource.pGraphBuffer;
					}
				}
			}
			// A resource is evidence of baked data, not a successful path or a supported zombie unit type.
			game::Dvar_SetInt(navigation_available, ground_navigation ? 1 : 0);
			const bool zombie_assets = asset(game::ASSET_TYPE_ANIMCLASS, "zombie_asm_animclass").data &&
				asset(game::ASSET_TYPE_BEHAVIOR_TREE, "zombie").data &&
				asset(game::ASSET_TYPE_XMODEL, "zombie_male_outfit_1").data &&
				asset(game::ASSET_TYPE_SCRIPTABLE, "zombie_male_outfit_1").data;
			report["zombieAssetsPresent"] = zombie_assets;
			unsigned int animation_index = 0;
			// SpawnAgent uses this network index, not a direct animation-class DB lookup.
			const auto indexed = utils::hook::invoke<int>(0x1406D4F40, "zombie_asm_animclass", &animation_index);
			const auto* model_names = asset(game::ASSET_TYPE_NET_CONST_STRINGS, "ncs_mdl_iwz_noir").netConstStrings;
			game::Dvar_SetInt(zombie_assets_available, zombie_assets && indexed && model_names && model_names->entryCount ? 1 : 0);
			report["zombieAnimationIndex"] = indexed ? json(animation_index) : json(nullptr);
			console::info("[IWZ][Noir] zombie animation indexed=%d index=%u modelPrecacheCount=%u\n",
				indexed, animation_index, model_names ? model_names->entryCount : 0);
			const std::pair<game::XAssetType, const char*> dependencies[] =
			{
				{game::ASSET_TYPE_ANIMCLASS, "zombie_asm_animclass"},
				{game::ASSET_TYPE_BEHAVIOR_TREE, "zombie"},
				{game::ASSET_TYPE_XMODEL, "zombie_male_outfit_1"},
				{game::ASSET_TYPE_SCRIPTABLE, "zombie_male_outfit_1"},
				{game::ASSET_TYPE_WEAPON, "iw7_atomizer_mp"},
			};
			report["dependencies"] = json::array();
			for (const auto& [type, name] : dependencies)
			{
				const bool present = asset(type, name).data != nullptr;
				report["dependencies"].push_back({{"type", game::g_assetNames[type]}, {"name", name}, {"present", present}});
				console::info("[IWZ][Noir] asset type=%s name=%s present=%d\n", game::g_assetNames[type], name, present);
			}
			console::info("[IWZ][Noir] audit base=%s title=%s world=%d collision=%d navigation=%d groundData=%d gameplayProven=0\n",
				map_name, title ? title : "<unknown>", world != nullptr, collision != nullptr, navigation != nullptr, ground_navigation);
			return report;
		}

		void write_json(const std::filesystem::path& path, const json& value)
		{
			std::ofstream file(path, std::ios::binary | std::ios::trunc);
			file.exceptions(std::ios::failbit | std::ios::badbit);
			file << value.dump(2) << '\n';
			file.close();
		}

		void export_world(const game::GfxWorld* world)
		{
			if (!world || !world->dpvs.surfaces || !world->dpvs.sortedSurfIndex || !world->draw.indices ||
				!world->dpvs.staticSurfaceCount || world->dpvs.staticSurfaceCount > world->surfaceCount ||
				world->draw.transientZoneCount > std::size(world->draw.transientZones))
				throw std::runtime_error("World buffers are incomplete; export rejected");

			// Copy only vertices used by static world surfaces. No engine pointers leave this callback.
			// Surface indices are relative to firstVertex in the owning transient zone.
			std::vector<std::array<float, 3>> positions;
			std::vector<std::uint32_t> indices;
			std::map<unsigned int, std::vector<std::uint32_t>> remaps;
			std::map<unsigned int, const game::GfxWorldTransientZone*> zones;
			constexpr auto absent = std::numeric_limits<std::uint32_t>::max();
			unsigned int total_vertices = 0;
			for (unsigned int i = 0; i < world->draw.transientZoneCount; ++i)
			{
				const auto* zone = world->draw.transientZones[i];
				if (!zone || !zone->vd.vertices || zone->vertexCount > 4000000 - total_vertices || zones.contains(zone->transientZoneIndex))
					throw std::runtime_error("Missing, oversized or duplicate vertex chunk; export rejected");
				total_vertices += zone->vertexCount;
				zones[zone->transientZoneIndex] = zone;
				remaps[zone->transientZoneIndex].resize(zone->vertexCount, absent);
			}
			std::array<float, 3> lower{FLT_MAX, FLT_MAX, FLT_MAX};
			std::array<float, 3> upper{-FLT_MAX, -FLT_MAX, -FLT_MAX};
			for (unsigned int i = 0; i < world->dpvs.staticSurfaceCount; ++i)
			{
				const auto surface_index = world->dpvs.sortedSurfIndex[i];
				if (surface_index >= world->surfaceCount)
					throw std::runtime_error("Invalid static surface index");
				const auto& surface = world->dpvs.surfaces[surface_index];
				const auto& tris = surface.tris;
				const auto zone_it = zones.find(surface.transientZone);
				const auto count = static_cast<unsigned int>(tris.triCount) * 3;
				if (zone_it == zones.end() || tris.baseIndex > world->draw.indexCount ||
					count > world->draw.indexCount - tris.baseIndex || indices.size() + count > 12000000)
					throw std::runtime_error("Missing surface chunk or invalid index range");
				const auto* zone = zone_it->second;
				auto& remap = remaps.at(surface.transientZone);
				if (tris.firstVertex > zone->vertexCount || tris.vertexCount > zone->vertexCount - tris.firstVertex)
					throw std::runtime_error("Invalid surface vertex range");
				for (unsigned int j = 0; j < count; ++j)
				{
					const auto local_index = world->draw.indices[tris.baseIndex + j];
					if (local_index >= tris.vertexCount)
						throw std::runtime_error("Triangle references a vertex outside its surface");
					const auto source_index = tris.firstVertex + local_index;
					auto& destination = remap[source_index];
					if (destination == absent)
					{
						std::array<float, 3> position;
						std::memcpy(position.data(), zone->vd.vertices[source_index].xyz, sizeof(position));
						for (int axis = 0; axis < 3; ++axis)
						{
							if (!std::isfinite(position[axis]))
								throw std::runtime_error("Non-finite world coordinate");
							lower[axis] = std::min(lower[axis], position[axis]);
							upper[axis] = std::max(upper[axis], position[axis]);
						}
						destination = static_cast<std::uint32_t>(positions.size());
						positions.push_back(position);
					}
					indices.push_back(destination);
				}
			}
			if (positions.empty() || indices.empty())
				throw std::runtime_error("No static world triangles available");

			const auto position_bytes = static_cast<std::uint32_t>(positions.size() * sizeof(positions[0]));
			const auto index_bytes = static_cast<std::uint32_t>(indices.size() * sizeof(indices[0]));
			json gltf = {
				{"asset", {{"version", "2.0"}, {"generator", "iwz-mod Noir foundation exporter"}}},
				{"scene", 0}, {"scenes", {{{"nodes", {0}}}}},
				{"nodes", {{{"name", map_name}, {"mesh", 0},
					{"matrix", {1,0,0,0, 0,0,-1,0, 0,1,0,0, 0,0,0,1}}}}},
				{"meshes", {{{"primitives", {{{"attributes", {{"POSITION", 0}}}, {"indices", 1}, {"material", 0}}}}}}},
				{"materials", {{{"doubleSided", true}, {"pbrMetallicRoughness", {
					{"baseColorFactor", {0.55, 0.59, 0.64, 1.0}}, {"metallicFactor", 0}, {"roughnessFactor", 1}}}}}},
				{"buffers", {{{"byteLength", position_bytes + index_bytes}}}},
				{"bufferViews", {{{"buffer", 0}, {"byteOffset", 0}, {"byteLength", position_bytes}, {"target", 34962}},
					{{"buffer", 0}, {"byteOffset", position_bytes}, {"byteLength", index_bytes}, {"target", 34963}}}},
				{"accessors", {{{"bufferView", 0}, {"componentType", 5126}, {"count", positions.size()},
					{"type", "VEC3"}, {"min", lower}, {"max", upper}},
					{{"bufferView", 1}, {"componentType", 5125}, {"count", indices.size()}, {"type", "SCALAR"}}}},
				{"extras", {{"baseMap", map_name}, {"worldChecksum", world->checksum},
					{"scope", "Static world surfaces only; visual geometry is not collision"},
					{"omittedStaticProps", world->dpvs.smodelCount}, {"omittedBrushModels", world->modelCount},
					{"omitted", {"static prop meshes", "dynamic entities", "script-created props", "collision", "navigation"}},
					{"gameCoordinates", "Z-up; original origin and game units"},
					{"gameToViewer", "(x, y, z) -> (x, z, -y)"}, {"viewerToGame", "(x, y, z) -> (x, -z, y)"}}}
			};
			auto json_chunk = gltf.dump();
			json_chunk.append((4 - json_chunk.size() % 4) % 4, ' ');
			const auto json_bytes = static_cast<std::uint32_t>(json_chunk.size());
			const std::uint32_t header[] = {0x46546c67, 2, 12 + 8 + json_bytes + 8 + position_bytes + index_bytes,
				json_bytes, 0x4e4f534a};
			const std::uint32_t binary_header[] = {position_bytes + index_bytes, 0x004e4942};
			const auto path = std::filesystem::path(output_directory) / "world.glb";
			const auto temporary = std::filesystem::path(output_directory) / "world.glb.tmp";
			std::ofstream file(temporary, std::ios::binary | std::ios::trunc);
			file.exceptions(std::ios::failbit | std::ios::badbit);
			file.write(reinterpret_cast<const char*>(header), sizeof(header));
			file.write(json_chunk.data(), json_bytes);
			file.write(reinterpret_cast<const char*>(binary_header), sizeof(binary_header));
			file.write(reinterpret_cast<const char*>(positions.data()), position_bytes);
			file.write(reinterpret_cast<const char*>(indices.data()), index_bytes);
			file.close();
			if (!MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING))
				throw std::runtime_error("Could not publish completed world.glb");
			console::info("[IWZ][MapLayout] exported=%s vertices=%zu triangles=%zu staticSurfaces=%u omittedProps=%u omittedBrushModels=%d gameUnits=unchanged\n",
				path.string().c_str(), positions.size(), indices.size() / 3, world->dpvs.staticSurfaceCount,
				world->dpvs.smodelCount, world->modelCount);
		}

		void launch_prototype()
		{
			if (launch_pending || game::environment::is_dedi() || !game::Com_FrontEnd_IsInFrontEnd())
			{
				console::warn("[IWZ][Noir] launch rejected: pending=%d dedicated=%d frontend=%d mode=%d\n",
					launch_pending, game::environment::is_dedi(), game::Com_FrontEnd_IsInFrontEnd(),
					game::Com_GameMode_GetActiveGameMode());
				return;
			}
			if (!game::SV_MapExists(map_name) || !std::filesystem::exists("iw7-mod/zone/iwz_noir_zombies.ff"))
			{
				console::error("[IWZ][Noir] launch rejected: installed Noir map or zombie dependency is missing\n");
				return;
			}
			launch_pending = true;
			launch_ui_ready = false;
			const auto source_mode = game::Com_GameMode_GetActiveGameMode();
			// The native setter rejects switching directly between two active modes.
			// Release CP first; request MP only once the engine has reached NONE.
			const auto desired_mode = source_mode == game::GAME_MODE_MP || source_mode == game::GAME_MODE_NONE
				? game::GAME_MODE_MP : game::GAME_MODE_NONE;
			game::Com_GameMode_SetDesiredGameMode(desired_mode);
			console::info("[IWZ][Noir] prototype transition requested: active=%d desired=%d title=TBA\n", source_mode, desired_mode);
			const auto deadline = std::chrono::steady_clock::now() + 60s;
			scheduler::schedule([deadline, last_mode = game::GAME_MODE_NONE, last_sync = ~0u, last_ui_ready = false]() mutable
			{
				const auto mode = game::Com_GameMode_GetActiveGameMode();
				const auto sync = mode == game::GAME_MODE_MP ? game::Live_SyncOnlineDataFlags(0) : 0u;
				if (mode != last_mode || sync != last_sync || launch_ui_ready != last_ui_ready)
				{
					console::info("[IWZ][Noir] prototype transition state: active=%d frontend=%d sync=0x%X menuReady=%d\n",
						mode, game::Com_FrontEnd_IsInFrontEnd(), sync, launch_ui_ready);
					last_mode = mode;
					last_sync = sync;
					last_ui_ready = launch_ui_ready;
				}
				if (std::chrono::steady_clock::now() >= deadline ||
					(game::SV_Loaded() && !game::Com_FrontEndScene_IsActive() && !game::Com_FrontEnd_IsInFrontEnd()))
				{
					launch_pending = false;
					console::error("[IWZ][Noir] prototype launch canceled: frontend left or transition timed out; active=%d sync=0x%X menuReady=%d\n",
						mode, sync, launch_ui_ready);
					return scheduler::cond_end;
				}
				if (mode == game::GAME_MODE_NONE)
					game::Com_GameMode_SetDesiredGameMode(game::GAME_MODE_MP);
				if (!game::Com_FrontEnd_IsInFrontEnd() ||
					mode != game::GAME_MODE_MP || sync || !launch_ui_ready)
					return scheduler::cond_continue;
				// Configure the solo foundation only after the destination mode has registered its dvars.
				for (const auto& [name, value] : std::initializer_list<std::pair<const char*, const char*>>{
					{"iwz_noir_foundation", "1"}, {"iwz_noir_placement", "1"}, {"iwz_noir_test_bot", "0"},
					{"iwz_survival_mode", "0"}, {"iwz_survival_browse", "0"}, {"g_gametype", "dm"},
					{"g_hardcore", "0"}, {"party_maxplayers", "1"}, {"xblive_privatematch", "1"},
					{"scr_dm_timelimit", "0"}, {"scr_dm_scorelimit", "0"}})
					game::Dvar_SetFromStringByName(name, value, game::DVAR_SOURCE_INTERNAL);
				launch_pending = false;
				console::info("[IWZ][Noir] prototype launch ready: map=mp_prime runtime=MP players=1 placement=1\n");
				party::start_map(map_name);
				return scheduler::cond_end;
			}, scheduler::main, 250ms);
		}

		void run(const bool geometry)
		{
			if (!active())
			{
				game::Dvar_SetInt(navigation_available, 0);
				console::warn("[IWZ][Noir] probe rejected: start a local mp_prime match first\n");
				return;
			}
			try
			{
				std::filesystem::create_directories(output_directory);
				write_json(std::filesystem::path(output_directory) / "audit.json", audit());
				if (geometry)
					export_world(asset(game::ASSET_TYPE_GFXWORLD, world_name).gfxWorld);
			}
			catch (const std::exception& error)
			{
				console::error("[IWZ][Noir] probe failed: %s\n", error.what());
			}
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			com_error_hook.create(game::Com_Error, log_engine_error);
			game::Dvar_RegisterBool("iwz_noir_foundation", false, game::DVAR_FLAG_NONE, "Enable the opt-in Noir foundation script");
			game::Dvar_RegisterBool("iwz_noir_placement", false, game::DVAR_FLAG_NONE, "Load saved Noir placement markers and the EMC wall buy");
			// String dvars need the engine string allocator, which is not ready in post_unpack.
			scheduler::once([]
			{
				game::Dvar_RegisterString("iwz_noir_world_checksum", "", game::DVAR_FLAG_NONE, "Audited Noir world identity for placement validation");
				console::info("[IWZ][MapLayout] world identity dvar initialized\n");
			}, scheduler::main);
			audit_requested = game::Dvar_RegisterInt("iwz_noir_audit_requested", 0, 0, 2, game::DVAR_FLAG_NONE, "Noir audit request: 1=assets, 2=assets and geometry");
			navigation_available = game::Dvar_RegisterInt("iwz_noir_nav_available", 0, 0, 1, game::DVAR_FLAG_NONE, "Noir ground navigation resource present");
			zombie_assets_available = game::Dvar_RegisterInt("iwz_noir_zombie_assets", 0, 0, 1, game::DVAR_FLAG_NONE, "Noir zombie assets present");
			game::Dvar_RegisterBool("iwz_noir_test_bot", false, game::DVAR_FLAG_NONE, "Add a local bot for the Noir server combat test");
			command::add("iwz_noir_audit", [] { scheduler::once([] { run(false); }, scheduler::server); });
			command::add("iwz_noir_export", [] { scheduler::once([] { run(true); }, scheduler::server); });
			command::add("iwz_noir_play", [] { scheduler::once(launch_prototype, scheduler::main); });
			command::add("iwz_noir_menu_ready", []
			{
				scheduler::once([]
				{
					if (launch_pending && game::Com_FrontEnd_IsInFrontEnd() &&
						game::Com_GameMode_GetActiveGameMode() == game::GAME_MODE_MP)
					{
						launch_ui_ready = true;
						console::info("[IWZ][Noir] destination Multiplayer menu initialized\n");
					}
				}, scheduler::main);
			});
			scheduler::loop([]
			{
				if (audit_requested->current.integer && active())
				{
					run(audit_requested->current.integer == 2);
					game::Dvar_SetInt(audit_requested, 0);
				}
			}, scheduler::server, 100ms);
		}
	};
}

REGISTER_COMPONENT(noir::component)
