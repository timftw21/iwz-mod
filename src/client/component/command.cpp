#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "command.hpp"

#include "game/game.hpp"
#include "game/dvars.hpp"
#include "game/scripting/execution.hpp"

#include "console/console.hpp"
#include "game_console.hpp"
#include "scheduler.hpp"
#include "dvars.hpp"

#include <utils/hook.hpp>
#include <utils/string.hpp>
#include <utils/memory.hpp>
#include <utils/io.hpp>

namespace command
{
	namespace
	{
		utils::hook::detour client_command_mp_hook;
		utils::hook::detour client_command_sp_hook;
		utils::hook::detour parse_commandline_hook;

		std::unordered_map<std::string, std::function<void(params&)>> handlers;
		std::unordered_map<std::string, std::function<void(int, params_sv&)>> handlers_sv;

		void main_handler()
		{
			params params = {};

			const auto command = utils::string::to_lower(params[0]);
			if (handlers.find(command) != handlers.end())
			{
				handlers[command](params);
			}
		}

		void client_command_mp(const int client_num)
		{
			params_sv params = {};

			const auto command = utils::string::to_lower(params[0]);
			if (handlers_sv.find(command) != handlers_sv.end())
			{
				handlers_sv[command](client_num, params);
			}

			client_command_mp_hook.invoke<void>(client_num);
		}

		void client_command_sp(const int client_num, const char* s)
		{
			game::SV_Cmd_TokenizeString(s);
			params_sv params = {};

			const auto command = utils::string::to_lower(s);
			if (handlers_sv.find(command) != handlers_sv.end())
			{
				handlers_sv[command](client_num, params);
			}
			game::SV_Cmd_EndTokenizedString();

			client_command_sp_hook.invoke<void>(client_num, s);
		}

		// Shamelessly stolen from Quake3
		// https://github.com/id-Software/Quake-III-Arena/blob/dbe4ddb10315479fc00086f08e25d968b4b43c49/code/qcommon/common.c#L364
		void parse_command_line()
		{
			static auto parsed = false;
			if (parsed)
			{
				return;
			}

			static std::string comand_line_buffer = GetCommandLineA();
			auto* command_line = comand_line_buffer.data();

			auto& com_num_console_lines = *game::com_num_console_lines;
			auto* com_console_lines = game::com_console_lines.get();

			auto inq = false;
			com_console_lines[0] = command_line;
			com_num_console_lines = 0;

			while (*command_line)
			{
				if (*command_line == '"')
				{
					inq = !inq;
				}
				// look for a + separating character
				// if commandLine came from a file, we might have real line seperators
				if ((*command_line == '+' && !inq) || *command_line == '\n' || *command_line == '\r')
				{
					if (com_num_console_lines == 0x20) // MAX_CONSOLE_LINES
					{
						break;
					}
					com_console_lines[com_num_console_lines] = command_line + 1;
					com_num_console_lines++;
					*command_line = '\0';
				}
				command_line++;
			}
			parsed = true;
		}

		void parse_startup_variables()
		{
			auto& com_num_console_lines = *game::com_num_console_lines;
			auto* com_console_lines = game::com_console_lines.get();

			for (int i = 0; i < com_num_console_lines; i++)
			{
				game::Cmd_TokenizeString(com_console_lines[i]);

				// only +set dvar value
				if (game::Cmd_Argc() >= 3 && (game::Cmd_Argv(0) == "set"s || game::Cmd_Argv(0) == "seta"s))
				{
					const std::string& key = game::Cmd_Argv(1);
					const std::string& value = game::Cmd_Argv(2);

					const auto* dvar = game::Dvar_FindVar(key.data());
					if (dvar)
					{
						game::Dvar_SetCommand(key.data(), value.data());
					}
					else
					{
						dvars::callback::on_register(key, [key, value]()
						{
							game::Dvar_SetCommand(key.data(), value.data());
						});
					}
				}

				game::Cmd_EndTokenizeString();
			}
		}

		void parse_commandline()
		{
			parse_command_line();
			parse_startup_variables();

			parse_commandline_hook.invoke<void>();
		}

		game::dvar_t* dvar_command_stub()
		{
			const params args;

			if (args.size() <= 0)
			{
				return 0;
			}

			auto* dvar = game::Dvar_FindVar(args[0]);
			if (dvar == nullptr)
			{
				dvar = game::Dvar_FindMalleableVar(atoi(args[0]));
			}

			if (dvar)
			{
				if (args.size() == 1)
				{
					const std::string current = game::Dvar_ValueToString(dvar, dvar->current);
					const std::string reset = game::Dvar_ValueToString(dvar, dvar->reset);

					console::info("\"%s\" is: \"%s\" default: \"%s\" checksum: %d type: %i\n",
						dvars::dvar_get_name(dvar).data(), current.data(), reset.data(), dvar->checksum, dvar->type);

					const auto dvar_info = dvars::dvar_get_description(dvar);

					if (!dvar_info.empty())
						console::info("%s\n", dvar_info.data());

					console::info("   %s\n", dvars::dvar_get_domain(dvar->type, dvar->domain).data());
				}
				else
				{
					char command[0x1000]{};
					game::Dvar_GetCombinedString(command, 1);
					game::Dvar_SetCommand(args[0], command);
				}

				return dvar;
			}

			return 0;
		}

		void cmd_give(const int client_num, const std::vector<std::string>& params)
		{
			if (params.size() < 2)
			{
				game::shared::client_println(client_num, "You did not specify a weapon name");
				return;
			}

			try
			{
				const auto& arg = params[1];
				const auto player = scripting::entity({ static_cast<uint16_t>(client_num), 0 });

				if (arg == "ammo")
				{
					const auto weapon = player.call("getcurrentweapon").as<std::string>();
					player.call("givemaxammo", { weapon });
				}
				else if (arg == "allammo")
				{
					const auto weapons = player.call("getweaponslistall").as<scripting::array>();
					for (auto i = 0; i < weapons.size(); i++)
					{
						player.call("givemaxammo", { weapons[i] });
					}
				}
				else if (arg == "health")
				{
					if (params.size() > 2)
					{
						const auto amount = atoi(params[2].data());
						const auto health = player.get("health").as<int>();
						player.set("health", { health + amount });
					}
					else
					{
						const auto amount = atoi(game::Dvar_FindVar("scr_player_maxhealth")->current.string);
						player.set("health", { amount });
					}
				}
				else if (arg == "all")
				{
					const auto type = game::XAssetType::ASSET_TYPE_WEAPON;
					game::DB_EnumXAssets(type, [&player, type](const game::XAssetHeader header)
					{
						const auto asset = game::XAsset{ type, header };
						const auto asset_name = game::DB_GetXAssetName(&asset);

						player.call("giveweapon", { asset_name });
					});
				}
				else
				{
					player.call("giveweapon", { arg });
					player.call("switchtoweapon", { arg });
				}
			}
			catch (...)
			{
			}
		}

		void cmd_drop_weapon(int client_num)
		{
			try
			{
				const auto player = scripting::entity({ static_cast<uint16_t>(client_num), 0 });
				const auto weapon = player.call("getcurrentweapon");
				player.call("dropitem", { weapon });
			}
			catch (...)
			{
			}
		}

		void cmd_take(int client_num, const std::vector<std::string>& params)
		{
			if (params.size() < 2)
			{
				game::shared::client_println(client_num, "You did not specify a weapon name");
				return;
			}

			const auto& weapon = params[1];

			try
			{
				const auto player = scripting::entity({ static_cast<uint16_t>(client_num), 0 });
				if (weapon == "all"s)
				{
					player.call("takeallweapons");
				}
				else
				{
					player.call("takeweapon", { weapon });
				}
			}
			catch (...)
			{
			}
		}

		void cmd_spawn_clown(const int client_num)
		{
			try
			{
				const auto player = scripting::entity({ static_cast<uint16_t>(client_num), 0 });
				const scripting::entity level{ *game::levelEntityId };
				scripting::notify(level, "iwz_spawn_clown", { player });
				console::info("[IWZ][Collision] spawnClown request client=%d playerEnt=%d levelEnt=%u\n",
					client_num, player.get_entity_reference().entnum, *game::levelEntityId);
			}
			catch (const std::exception& e)
			{
				console::error("[IWZ][Collision] failed to dispatch spawnClown: %s\n", e.what());
				game::shared::client_println(client_num, "Unable to spawn clown");
			}
		}

		bool bounds_overlap(const game::Bounds& bounds, const game::vec3_t& center, const game::vec3_t& half_size)
		{
			for (auto axis = 0; axis < 3; ++axis)
			{
				if (std::abs(bounds.midPoint[axis] - center[axis]) > bounds.halfSize[axis] + half_size[axis])
				{
					return false;
				}
			}

			return true;
		}

		void log_pap_material(const char* source, const game::Material* material)
		{
			if (material == nullptr || material->name == nullptr)
			{
				console::error("[IWZ][PaPRoom] %s material=missing\n", source);
				return;
			}

			const auto* technique = material->techniqueSet != nullptr && material->techniqueSet->name != nullptr
				? material->techniqueSet->name
				: "<none>";
			console::info("[IWZ][PaPRoom] %s material=%s address=%p default=%d technique=%s textures=%u\n",
				source, material->name, material,
				game::DB_IsXAssetDefault(game::ASSET_TYPE_MATERIAL, material->name),
				technique, material->textureCount);
			if (material->textureTable == nullptr)
			{
				return;
			}

			for (auto index = 0u; index < material->textureCount; ++index)
			{
				const auto* image = material->textureTable[index].image;
				if (image != nullptr && image->name != nullptr)
				{
					console::info("[IWZ][PaPRoom] %s texture[%u]=%s size=%ux%u format=%u streamed=%u\n",
						source, index, image->name, image->width, image->height,
						static_cast<unsigned int>(image->imageFormat), image->streamed);
				}
				else
				{
					console::error("[IWZ][PaPRoom] %s texture[%u]=missing\n", source, index);
				}
			}
		}

		void log_pap_asset_zone(const game::XAssetType type, const char* name)
		{
			const auto* entry = game::DB_AssetEntryTable_FindAsset(game::s_assetManager_table, name, type);
			if (entry == nullptr)
			{
				console::error("[IWZ][PaPRoom] asset=%s type=%s has no active DB entry\n",
					name, game::g_assetNames[type]);
				return;
			}

			const auto* zone_name = game::DB_Zones_IsValidZoneIndex(entry->m_zoneIndex)
				? game::DB_Zones_GetZoneNameFromIndex(entry->m_zoneIndex)
				: "<invalid>";
			console::info("[IWZ][PaPRoom] asset=%s type=%s address=%p zone=%u(%s) inUse=%u\n",
				name, game::g_assetNames[type], entry->m_header.data, entry->m_zoneIndex,
				zone_name != nullptr ? zone_name : "<unnamed>", entry->m_inuse);
		}

		struct dds_pixel_format
		{
			std::uint32_t size;
			std::uint32_t flags;
			std::uint32_t four_cc;
			std::uint32_t rgb_bit_count;
			std::uint32_t red_mask;
			std::uint32_t green_mask;
			std::uint32_t blue_mask;
			std::uint32_t alpha_mask;
		};

		struct dds_header
		{
			std::uint32_t size;
			std::uint32_t flags;
			std::uint32_t height;
			std::uint32_t width;
			std::uint32_t pitch_or_linear_size;
			std::uint32_t depth;
			std::uint32_t mip_map_count;
			std::uint32_t reserved[11];
			dds_pixel_format pixel_format;
			std::uint32_t caps;
			std::uint32_t caps2;
			std::uint32_t caps3;
			std::uint32_t caps4;
			std::uint32_t reserved2;
		};

		struct dds_header_dx10
		{
			DXGI_FORMAT format;
			std::uint32_t resource_dimension;
			std::uint32_t misc_flag;
			std::uint32_t array_size;
			std::uint32_t misc_flags2;
		};

		static_assert(sizeof(dds_pixel_format) == 32);
		static_assert(sizeof(dds_header) == 124);
		static_assert(sizeof(dds_header_dx10) == 20);

		bool get_dds_layout(const DXGI_FORMAT format, const std::uint32_t width, const std::uint32_t height,
			std::uint32_t& row_bytes, std::uint32_t& row_count, bool& block_compressed)
		{
			block_compressed = true;
			row_count = std::max(1u, (height + 3u) / 4u);
			switch (format)
			{
			case DXGI_FORMAT_BC1_TYPELESS:
			case DXGI_FORMAT_BC1_UNORM:
			case DXGI_FORMAT_BC1_UNORM_SRGB:
				row_bytes = std::max(1u, (width + 3u) / 4u) * 8u;
				return true;
			case DXGI_FORMAT_BC2_TYPELESS:
			case DXGI_FORMAT_BC2_UNORM:
			case DXGI_FORMAT_BC2_UNORM_SRGB:
			case DXGI_FORMAT_BC3_TYPELESS:
			case DXGI_FORMAT_BC3_UNORM:
			case DXGI_FORMAT_BC3_UNORM_SRGB:
			case DXGI_FORMAT_BC5_TYPELESS:
			case DXGI_FORMAT_BC5_UNORM:
			case DXGI_FORMAT_BC5_SNORM:
			case DXGI_FORMAT_BC6H_TYPELESS:
			case DXGI_FORMAT_BC6H_UF16:
			case DXGI_FORMAT_BC6H_SF16:
			case DXGI_FORMAT_BC7_TYPELESS:
			case DXGI_FORMAT_BC7_UNORM:
			case DXGI_FORMAT_BC7_UNORM_SRGB:
				row_bytes = std::max(1u, (width + 3u) / 4u) * 16u;
				return true;
			case DXGI_FORMAT_R8G8B8A8_TYPELESS:
			case DXGI_FORMAT_R8G8B8A8_UNORM:
			case DXGI_FORMAT_R8G8B8A8_UNORM_SRGB:
				block_compressed = false;
				row_count = height;
				row_bytes = width * 4u;
				return true;
			default:
				return false;
			}
		}

		void dump_pap_image(const char* image_name)
		{
			const auto* image = game::DB_FindXAssetHeader(game::ASSET_TYPE_IMAGE, image_name, false).image;
			if (image == nullptr || image->texture.map == nullptr)
			{
				console::error("[IWZ][PaPRoom] DDS dump image=%s has no resident texture\n", image_name);
				return;
			}

			D3D11_TEXTURE2D_DESC source_desc{};
			image->texture.map->GetDesc(&source_desc);
			std::uint32_t row_bytes{};
			std::uint32_t row_count{};
			bool block_compressed{};
			if (!get_dds_layout(source_desc.Format, source_desc.Width, source_desc.Height,
				row_bytes, row_count, block_compressed))
			{
				console::error("[IWZ][PaPRoom] DDS dump image=%s unsupported format=%u\n",
					image_name, static_cast<unsigned int>(source_desc.Format));
				return;
			}

			ID3D11Device* device{};
			ID3D11DeviceContext* context{};
			ID3D11Texture2D* staging{};
			image->texture.map->GetDevice(&device);
			if (device == nullptr)
			{
				console::error("[IWZ][PaPRoom] DDS dump image=%s could not acquire D3D device\n", image_name);
				return;
			}

			device->GetImmediateContext(&context);
			auto staging_desc = source_desc;
			staging_desc.MipLevels = 1;
			staging_desc.ArraySize = 1;
			staging_desc.SampleDesc = {1, 0};
			staging_desc.Usage = D3D11_USAGE_STAGING;
			staging_desc.BindFlags = 0;
			staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
			staging_desc.MiscFlags = 0;
			const auto create_result = device->CreateTexture2D(&staging_desc, nullptr, &staging);
			if (FAILED(create_result) || staging == nullptr)
			{
				console::error("[IWZ][PaPRoom] DDS dump image=%s staging creation failed hr=0x%08X\n",
					image_name, static_cast<unsigned int>(create_result));
				context->Release();
				device->Release();
				return;
			}

			context->CopySubresourceRegion(staging, 0, 0, 0, 0, image->texture.map, 0, nullptr);
			D3D11_MAPPED_SUBRESOURCE mapped{};
			const auto map_result = context->Map(staging, 0, D3D11_MAP_READ, 0, &mapped);
			if (FAILED(map_result))
			{
				console::error("[IWZ][PaPRoom] DDS dump image=%s map failed hr=0x%08X\n",
					image_name, static_cast<unsigned int>(map_result));
				staging->Release();
				context->Release();
				device->Release();
				return;
			}

			constexpr auto dds_magic = 0x20534444u;
			constexpr auto dds_four_cc = 0x4u;
			constexpr auto dx10_four_cc = 0x30315844u;
			constexpr auto ddsd_caps = 0x1u;
			constexpr auto ddsd_height = 0x2u;
			constexpr auto ddsd_width = 0x4u;
			constexpr auto ddsd_pitch = 0x8u;
			constexpr auto ddsd_pixel_format = 0x1000u;
			constexpr auto ddsd_linear_size = 0x80000u;
			constexpr auto dds_caps_texture = 0x1000u;
			dds_header header{};
			header.size = sizeof(dds_header);
			header.flags = ddsd_caps | ddsd_height | ddsd_width | ddsd_pixel_format |
				(block_compressed ? ddsd_linear_size : ddsd_pitch);
			header.height = source_desc.Height;
			header.width = source_desc.Width;
			header.pitch_or_linear_size = block_compressed ? row_bytes * row_count : row_bytes;
			header.pixel_format = {sizeof(dds_pixel_format), dds_four_cc, dx10_four_cc};
			header.caps = dds_caps_texture;
			const dds_header_dx10 dx10_header{
				source_desc.Format, D3D11_RESOURCE_DIMENSION_TEXTURE2D, 0, 1, 0
			};

			std::string dds_data;
			dds_data.reserve(sizeof(dds_magic) + sizeof(header) + sizeof(dx10_header) + row_bytes * row_count);
			dds_data.append(reinterpret_cast<const char*>(&dds_magic), sizeof(dds_magic));
			dds_data.append(reinterpret_cast<const char*>(&header), sizeof(header));
			dds_data.append(reinterpret_cast<const char*>(&dx10_header), sizeof(dx10_header));
			for (auto row = 0u; row < row_count; ++row)
			{
				const auto* row_data = static_cast<const char*>(mapped.pData) + row * mapped.RowPitch;
				dds_data.append(row_data, row_bytes);
			}
			context->Unmap(staging, 0);

			const auto* base_path_dvar = game::Dvar_FindVar("fs_basepath");
			const std::string base_path = base_path_dvar != nullptr && base_path_dvar->current.string != nullptr
				? base_path_dvar->current.string
				: ".";
			const auto output_path = base_path + "\\iw7-mod\\dump\\pap_timer\\" + image_name + ".dds";
			if (utils::io::write_file(output_path, dds_data))
			{
				console::info("[IWZ][PaPRoom] DDS dump image=%s source=%ux%u format=%u pitch=%u output=%s\n",
					image_name, source_desc.Width, source_desc.Height,
					static_cast<unsigned int>(source_desc.Format), mapped.RowPitch, output_path.data());
			}
			else
			{
				console::error("[IWZ][PaPRoom] DDS dump image=%s failed to write output=%s\n",
					image_name, output_path.data());
			}

			staging->Release();
			context->Release();
			device->Release();
		}

		std::string get_pap_dump_path(const char* filename)
		{
			const auto* base_path_dvar = game::Dvar_FindVar("fs_basepath");
			const std::string base_path = base_path_dvar != nullptr && base_path_dvar->current.string != nullptr
				? base_path_dvar->current.string
				: ".";
			return base_path + "\\iw7-mod\\dump\\pap_timer\\" + filename;
		}

		void append_pap_model_surface(std::string& obj, const game::XSurface& surface,
			const game::GfxPackedPlacement& placement, std::uint32_t& vertex_base)
		{
			if (surface.verts0.packedVerts0 == nullptr || surface.triIndices == nullptr)
			{
				return;
			}

			for (auto vertex_index = 0u; vertex_index < surface.vertCount; ++vertex_index)
			{
				const auto& vertex = surface.verts0.packedVerts0[vertex_index];
				game::vec3_t position{};
				for (auto axis = 0; axis < 3; ++axis)
				{
					position[axis] = placement.origin[axis] + placement.scale *
						(vertex.xyz[0] * placement.axis[0][axis] +
							vertex.xyz[1] * placement.axis[1][axis] +
							vertex.xyz[2] * placement.axis[2][axis]);
				}
				obj.append(utils::string::va("v %.6f %.6f %.6f\n", position[0], position[1], position[2]));
			}

			for (auto triangle_index = 0u; triangle_index < surface.triCount; ++triangle_index)
			{
				const auto& triangle = surface.triIndices[triangle_index];
				obj.append(utils::string::va("f %u %u %u\n",
					vertex_base + triangle.v1, vertex_base + triangle.v2, vertex_base + triangle.v3));
			}
			vertex_base += surface.vertCount;
		}

		void dump_pap_model_geometry(const game::GfxStaticModelDrawInst& draw)
		{
			const auto* model = draw.model;
			if (model == nullptr || model->name == nullptr)
			{
				return;
			}

			const game::XModelLodInfo* lod{};
			for (auto lod_index = 0u; lod_index < model->numLods && lod_index < 6; ++lod_index)
			{
				if (model->lodInfo[lod_index].surfs != nullptr && model->lodInfo[lod_index].numsurfs > 0)
				{
					lod = &model->lodInfo[lod_index];
					break;
				}
			}
			if (lod == nullptr)
			{
				console::error("[IWZ][PaPRoom] model geometry export failed model=%s reason=no loaded LOD\n", model->name);
				return;
			}

			std::string obj{"# iwz-mod Pack-a-Punch timer geometry diagnostic\n"};
			std::uint32_t vertex_base = 1;
			for (auto surface_index = 0u; surface_index < lod->numsurfs; ++surface_index)
			{
				const auto material_index = lod->surfIndex + surface_index;
				const auto* material = model->materialHandles != nullptr && material_index < model->numsurfs
					? model->materialHandles[material_index]
					: nullptr;
				obj.append(utils::string::va("g surface_%u\n# material %s\n", surface_index,
					material != nullptr && material->name != nullptr ? material->name : "<none>"));
				append_pap_model_surface(obj, lod->surfs[surface_index], draw.placement, vertex_base);
			}

			const auto output_path = get_pap_dump_path("zmb_pap_wire_01.obj");
			if (utils::io::write_file(output_path, obj))
			{
				console::info("[IWZ][PaPRoom] model geometry exported model=%s lodSurfaces=%u vertices=%u output=%s\n",
					model->name, lod->numsurfs, vertex_base - 1, output_path.data());
			}
			else
			{
				console::error("[IWZ][PaPRoom] model geometry export write failed model=%s output=%s\n",
					model->name, output_path.data());
			}
		}

		void dump_pap_world_geometry()
		{
			const auto* world = *game::g_world;
			if (world == nullptr || world->dpvs.surfaces == nullptr || world->dpvs.surfacesBounds == nullptr ||
				world->draw.indices == nullptr)
			{
				console::error("[IWZ][PaPRoom] world geometry export failed reason=world data unavailable\n");
				return;
			}

			const auto* map_dvar = game::Dvar_FindVar("ui_mapname");
			const std::string map_name = map_dvar != nullptr && map_dvar->current.string != nullptr
				? map_dvar->current.string
				: "<unknown>";
			game::vec3_t timer_center{-10142.0f, 927.0f, -1550.0f};
			if (map_name == "cp_final")
			{
				timer_center[0] = 5237.5f;
				timer_center[1] = -5004.6f;
				timer_center[2] = 364.0f;
			}
			const game::vec3_t probe_half_size{160.0f, 24.0f, 100.0f};

			std::string obj{"# iwz-mod Pack-a-Punch black world-surface diagnostic\n"};
			std::uint32_t vertex_base = 1;
			auto exported_surfaces = 0u;
			for (auto surface_index = 0u; surface_index < world->surfaceCount; ++surface_index)
			{
				const auto& surface = world->dpvs.surfaces[surface_index];
				const auto* material = surface.material;
				if (material == nullptr || material->name == nullptr ||
					std::strcmp(material->name, "w/plastic_fiberglass_black_01") != 0 ||
					!bounds_overlap(world->dpvs.surfacesBounds[surface_index].bounds, timer_center, probe_half_size))
				{
					continue;
				}

				const auto transient_zone = surface.transientZone;
				const auto* zone = transient_zone < world->draw.transientZoneCount
					? world->draw.transientZones[transient_zone]
					: nullptr;
				if (zone == nullptr || zone->vd.vertices == nullptr)
				{
					console::error("[IWZ][PaPRoom] world surface export skipped index=%u transientZone=%u reason=no vertices\n",
						surface_index, transient_zone);
					continue;
				}

				obj.append(utils::string::va("g world_surface_%u\n# material %s\n", surface_index, material->name));
				for (auto vertex_index = 0u; vertex_index < surface.tris.vertexCount; ++vertex_index)
				{
					const auto& vertex = zone->vd.vertices[surface.tris.firstVertex + vertex_index];
					obj.append(utils::string::va("v %.6f %.6f %.6f\n", vertex.xyz[0], vertex.xyz[1], vertex.xyz[2]));
				}
				for (auto triangle_index = 0u; triangle_index < surface.tris.triCount; ++triangle_index)
				{
					const auto* indices = &world->draw.indices[surface.tris.baseIndex + triangle_index * 3u];
					obj.append(utils::string::va("f %u %u %u\n",
						vertex_base + indices[0], vertex_base + indices[1], vertex_base + indices[2]));
				}

				const auto& bounds = world->dpvs.surfacesBounds[surface_index].bounds;
				console::info("[IWZ][PaPRoom] black world surface index=%u zone=%u bounds=(%.1f %.1f %.1f)/(%.1f %.1f %.1f) vertices=%u triangles=%u\n",
					surface_index, transient_zone, bounds.midPoint[0], bounds.midPoint[1], bounds.midPoint[2],
					bounds.halfSize[0], bounds.halfSize[1], bounds.halfSize[2],
					surface.tris.vertexCount, surface.tris.triCount);
				vertex_base += surface.tris.vertexCount;
				++exported_surfaces;
			}

			for (auto model_index = 0u; model_index < world->dpvs.smodelCount; ++model_index)
			{
				const auto& draw = world->dpvs.smodelDrawInsts[model_index];
				if (draw.model != nullptr && draw.model->name != nullptr &&
					std::strcmp(draw.model->name, "zmb_pap_wire_01") == 0 &&
					bounds_overlap(world->dpvs.smodelInsts[model_index].bounds, timer_center, probe_half_size))
				{
					dump_pap_model_geometry(draw);
					break;
				}
			}

			const auto output_path = get_pap_dump_path("black_world_surface.obj");
			if (exported_surfaces > 0 && utils::io::write_file(output_path, obj))
			{
				console::info("[IWZ][PaPRoom] black world geometry exported surfaces=%u vertices=%u output=%s\n",
					exported_surfaces, vertex_base - 1, output_path.data());
			}
			else
			{
				console::error("[IWZ][PaPRoom] black world geometry export failed surfaces=%u output=%s\n",
					exported_surfaces, output_path.data());
			}
		}

		void log_pap_timer_asset_status()
		{
			constexpr std::array material_names = {
				"mopw/vfx_zmb_paproom",
				"el/vfx_zmb_paproom",
				"eq/vfx_energy_digitalg",
				"eq/vfx_energy_digitalg_01",
				"eq/vfx_energy_digitalg_red",
			};

			for (const auto* material_name : material_names)
			{
				const auto* material = game::DB_FindXAssetHeader(
					game::ASSET_TYPE_MATERIAL, material_name, false).material;
				log_pap_asset_zone(game::ASSET_TYPE_MATERIAL, material_name);
				log_pap_material("active", material);
			}

			game::DB_EnumXAssets(game::ASSET_TYPE_MATERIAL, [](const game::XAssetHeader header)
			{
				if (header.material == nullptr || header.material->name == nullptr)
				{
					return;
				}

				constexpr std::array material_names = {
					"mopw/vfx_zmb_paproom",
					"el/vfx_zmb_paproom",
					"eq/vfx_energy_digitalg",
					"eq/vfx_energy_digitalg_01",
					"eq/vfx_energy_digitalg_red",
				};
				for (const auto* material_name : material_names)
				{
					if (std::strcmp(material_name, header.material->name) == 0)
					{
						log_pap_material("enumerated", header.material);
						return;
					}
				}
			});

			constexpr std::array image_names = {
				"wdg_pnb_timer_background",
				"vfx_zmb_paproom",
				"vfx_zmb_paproom_surf",
				"vfx_energy_digitalg",
				"vfx_energy_digitalg_01",
				"vfx_energy_digitalg_red",
			};

			for (const auto* image_name : image_names)
			{
				const auto* image = game::DB_FindXAssetHeader(
					game::ASSET_TYPE_IMAGE, image_name, false).image;
				if (image != nullptr)
				{
					log_pap_asset_zone(game::ASSET_TYPE_IMAGE, image_name);
					console::info("[IWZ][PaPRoom] candidate image=%s address=%p default=%d size=%ux%u format=%u streamed=%u\n",
						image_name, image, game::DB_IsXAssetDefault(game::ASSET_TYPE_IMAGE, image_name),
						image->width, image->height, static_cast<unsigned int>(image->imageFormat), image->streamed);
				}
				else
				{
					console::error("[IWZ][PaPRoom] candidate image=%s missing\n", image_name);
				}
			}
		}

		void log_pap_timer_geometry()
		{
			const auto* world = *game::g_world;
			if (world == nullptr || world->dpvs.surfaces == nullptr || world->dpvs.surfacesBounds == nullptr)
			{
				console::error("[IWZ][PaPRoom] timer geometry unavailable: no GfxWorld\n");
				return;
			}

			const auto* map_dvar = game::Dvar_FindVar("ui_mapname");
			const std::string map_name = map_dvar != nullptr && map_dvar->current.string != nullptr
				? map_dvar->current.string
				: "<unknown>";
			game::vec3_t timer_center{-10142.0f, 927.0f, -1550.0f};
			if (map_name == "cp_final")
			{
				timer_center[0] = 5237.5f;
				timer_center[1] = -5004.6f;
				timer_center[2] = 364.0f;
			}
			const game::vec3_t probe_half_size{260.0f, 48.0f, 180.0f};

			std::unordered_map<const game::Material*, unsigned int> nearby_materials;
			for (auto index = 0u; index < world->surfaceCount; ++index)
			{
				if (bounds_overlap(world->dpvs.surfacesBounds[index].bounds, timer_center, probe_half_size))
				{
					++nearby_materials[world->dpvs.surfaces[index].material];
				}
			}

			console::info("[IWZ][PaPRoom] timer geometry map=%s center=(%.1f %.1f %.1f) nearbySurfaces=%zu\n",
				map_name.data(), timer_center[0], timer_center[1], timer_center[2], nearby_materials.size());
			for (const auto& [material, count] : nearby_materials)
			{
				console::info("[IWZ][PaPRoom] world surface count=%u\n", count);
				log_pap_material("world-surface", material);
			}

			if (world->dpvs.smodelInsts == nullptr || world->dpvs.smodelDrawInsts == nullptr)
			{
				console::error("[IWZ][PaPRoom] timer model geometry unavailable\n");
				return;
			}

			auto nearby_model_count = 0u;
			for (auto index = 0u; index < world->dpvs.smodelCount; ++index)
			{
				if (!bounds_overlap(world->dpvs.smodelInsts[index].bounds, timer_center, probe_half_size))
				{
					continue;
				}

				const auto& draw = world->dpvs.smodelDrawInsts[index];
				const auto* model = draw.model;
				if (model == nullptr || model->name == nullptr)
				{
					continue;
				}

				++nearby_model_count;
				console::info("[IWZ][PaPRoom] nearby model=%s origin=(%.1f %.1f %.1f) scale=%.3f bounds=(%.1f %.1f %.1f)/(%.1f %.1f %.1f) surfaces=%u flags=0x%X\n",
					model->name, draw.placement.origin[0], draw.placement.origin[1], draw.placement.origin[2], draw.placement.scale,
					world->dpvs.smodelInsts[index].bounds.midPoint[0], world->dpvs.smodelInsts[index].bounds.midPoint[1],
					world->dpvs.smodelInsts[index].bounds.midPoint[2], world->dpvs.smodelInsts[index].bounds.halfSize[0],
					world->dpvs.smodelInsts[index].bounds.halfSize[1], world->dpvs.smodelInsts[index].bounds.halfSize[2],
					model->numsurfs, model->flags);

				for (auto surface = 0u; model->materialHandles != nullptr && surface < model->numsurfs; ++surface)
				{
					log_pap_material(model->name, model->materialHandles[surface]);
				}
			}
			console::info("[IWZ][PaPRoom] timer geometry nearbyModels=%u\n", nearby_model_count);
		}

		void cmd_paproom(const int client_num)
		{
			try
			{
				const auto player = scripting::entity({static_cast<uint16_t>(client_num), 0});
				const scripting::entity level{*game::levelEntityId};
				scripting::notify(level, "iwz_paproom", {player});
				console::info("[IWZ][PaPRoom] teleport request client=%d playerEnt=%d levelEnt=%u\n",
					client_num, player.get_entity_reference().entnum, *game::levelEntityId);
				log_pap_timer_asset_status();
				dump_pap_world_geometry();
				scheduler::once([]
				{
					dump_pap_image("wdg_pnb_timer_background");
				}, scheduler::renderer);
			}
			catch (const std::exception& e)
			{
				console::error("[IWZ][PaPRoom] failed to dispatch teleport: %s\n", e.what());
				game::shared::client_println(client_num, "Unable to teleport to Pack-a-Punch room");
			}
		}
	}

	params::params()
		: nesting_(game::cmd_args->nesting)
	{
	}

	int params::size() const
	{
		return game::cmd_args->argc[this->nesting_];
	}

	const char* params::get(const int index) const
	{
		if (index >= this->size())
		{
			return "";
		}

		return game::cmd_args->argv[this->nesting_][index];
	}

	std::string params::join(const int index) const
	{
		std::string result = {};

		for (auto i = index; i < this->size(); i++)
		{
			if (i > index) result.append(" ");
			result.append(this->get(i));
		}
		return result;
	}

	std::vector<std::string> params::get_all() const
	{
		std::vector<std::string> params_;
		for (auto i = 0; i < this->size(); i++)
		{
			params_.push_back(this->get(i));
		}
		return params_;
	}

	params_sv::params_sv()
		: nesting_(game::sv_cmd_args->nesting)
	{
	}

	int params_sv::size() const
	{
		return game::sv_cmd_args->argc[this->nesting_];
	}

	const char* params_sv::get(const int index) const
	{
		if (index >= this->size())
		{
			return "";
		}

		return game::sv_cmd_args->argv[this->nesting_][index];
	}

	std::string params_sv::join(const int index) const
	{
		std::string result = {};

		for (auto i = index; i < this->size(); i++)
		{
			if (i > index) result.append(" ");
			result.append(this->get(i));
		}
		return result;
	}

	std::vector<std::string> params_sv::get_all() const
	{
		std::vector<std::string> params_;
		for (auto i = 0; i < this->size(); i++)
		{
			params_.push_back(this->get(i));
		}
		return params_;
	}

	void add_raw(const char* name, void (*callback)())
	{
		game::Cmd_AddCommandInternal(name, callback, utils::memory::get_allocator()->allocate<game::cmd_function_s>());
	}

	void add(const char* name, const std::function<void(const params&)>& callback)
	{
		const auto command = utils::string::to_lower(name);

		if (handlers.find(command) == handlers.end())
			add_raw(name, main_handler);

		handlers[command] = callback;
	}

	void add(const char* name, const std::function<void()>& callback)
	{
		add(name, [callback](const params&)
		{
			callback();
		});
	}

	void add_sv(const char* name, std::function<void(int, const params_sv&)> callback)
	{
		// doing this so the sv command would show up in the console
		add_raw(name, nullptr);

		const auto command = utils::string::to_lower(name);

		if (handlers_sv.find(command) == handlers_sv.end())
			handlers_sv[command] = std::move(callback);
	}

	void execute(std::string command, const bool sync)
	{
		command += "\n";

		if (sync)
		{
			game::Cmd_ExecuteSingleCommand(0, 0, command.data());
		}
		else
		{
			game::Cbuf_AddText(0, command.data());
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			game::Dvar_RegisterBool("iwz_gsc_diagnostics", true, game::DVAR_FLAG_SAVED,
				"Enable diagnostics emitted by custom GSC patches");
			game::Dvar_RegisterInt("iwz_powerup_drop_base_interval", 1750, 0, 10000, game::DVAR_FLAG_SAVED,
				"Base team-score interval between Zombies powerup drops (0 preserves stock behavior)");
			game::Dvar_RegisterInt("iwz_powerup_weight_infinite_grenades", 2, 1, 100, game::DVAR_FLAG_SAVED,
				"Relative drop weight for the Infinite Grenades powerup (stock is 5)");
			game::Dvar_RegisterInt("iwz_powerup_weight_max_ammo", 12, 1, 100, game::DVAR_FLAG_SAVED,
				"Relative drop weight for the Max Ammo powerup (stock is 10)");
			game::Dvar_RegisterInt("iwz_powerup_weight_double_money", 6, 1, 100, game::DVAR_FLAG_SAVED,
				"Relative drop weight for the Double Money powerup (stock is 5)");
			game::Dvar_RegisterInt("iwz_powerup_weight_insta_kill", 12, 1, 100, game::DVAR_FLAG_SAVED,
				"Relative drop weight for the Insta-Kill powerup (stock is 10)");
			game::Dvar_RegisterFloat("iwz_low_health_blood_alpha", 0.75f, 0.0f, 0.85f, game::DVAR_FLAG_SAVED,
				"Maximum opacity of the Zombies low-health blood overlay (stock is 0.85)");
			game::Dvar_RegisterFloat("iwz_low_health_blood_scale", 0.25f, 0.10f, 1.0f, game::DVAR_FLAG_SAVED,
				"Center-origin scale of the Zombies low-health blood overlay (stock is 0.10; larger pushes blood toward the edges)");
			game::Dvar_RegisterBool("iwz_double_xp", false, game::DVAR_FLAG_SAVED,
				"Double Zombies level and weapon XP");
			game::Dvar_RegisterBool("iwz_collision_debug", true, game::DVAR_FLAG_SAVED,
				"Log zombie traversal collision and test-spawn diagnostics");

			utils::hook::jump(0x140BB1DC0, dvar_command_stub, true);
			client_command_mp_hook.create(0x140B105D0, &client_command_mp);
			client_command_sp_hook.create(0x140483130, &client_command_sp);

			parse_commandline_hook.create(0x140C039F0, parse_commandline); // SL_Init

			add_commands();
		}

	private:
		static void add_commands()
		{
			add("quit", []()
			{
				*game::g_quitRequested = true;
			});

			add("crash", []()
			{
				*reinterpret_cast<int*>(1) = 0;
			});

			add("noMode", []()
			{
				game::Com_GameMode_SetDesiredGameMode(game::GAME_MODE_NONE);
			});

			add("spMode", []()
			{
				game::Com_GameMode_SetDesiredGameMode(game::GAME_MODE_SP);
			});

			add("mpMode", []()
			{
				game::Com_GameMode_SetDesiredGameMode(game::GAME_MODE_MP);
			});

			add("cpMode", []()
			{
				game::Com_GameMode_SetDesiredGameMode(game::GAME_MODE_CP);
			});

			add("bindlist", []()
			{
				game::Key_Bindlist_f();
			});

			add_sv("god", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				game::g_entities[client_num].flags ^= 1;
				game::shared::client_println(client_num,
					game::g_entities[client_num].flags & 1
					? "GAME_GODMODE_ON"
					: "GAME_GODMODE_OFF");
			});

			add_sv("demigod", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				game::g_entities[client_num].flags ^= 2;
				game::shared::client_println(client_num,
					game::g_entities[client_num].flags & 2
					? "GAME_DEMI_GODMODE_ON"
					: "GAME_DEMI_GODMODE_OFF");
			});

			add_sv("notarget", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				game::g_entities[client_num].flags ^= 4;
				game::shared::client_println(client_num,
					game::g_entities[client_num].flags & 4
					? "GAME_NOTARGETON"
					: "GAME_NOTARGETOFF");
			});

			add_sv("noclip", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				game::g_entities[client_num].client->flags ^= 1;
				game::shared::client_println(client_num,
					game::g_entities[client_num].client->flags & 1
					? "GAME_NOCLIPON"
					: "GAME_NOCLIPOFF");
			});

			add_sv("ufo", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				game::g_entities[client_num].client->flags ^= 2;
				game::shared::client_println(client_num,
					game::g_entities[client_num].client->flags & 2
					? "GAME_UFOON"
					: "GAME_UFOOFF");
			});

			add_sv("give", [](const int client_num, const params_sv& params)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				cmd_give(client_num, params.get_all());
			});

			add_sv("dropweapon", [](const int client_num, const params_sv& params)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				cmd_drop_weapon(client_num);
			});

			add_sv("take", [](const int client_num, const params_sv& params)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				cmd_take(client_num, params.get_all());
			});

			add_sv("spawnClown", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				cmd_spawn_clown(client_num);
			});

			add_sv("paproom", [](const int client_num, const params_sv&)
			{
				if (!game::shared::cheats_ok(client_num, true))
				{
					return;
				}

				cmd_paproom(client_num);
			});
		}
	};
}

REGISTER_COMPONENT(command::component)
