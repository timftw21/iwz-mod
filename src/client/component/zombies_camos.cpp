#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "command.hpp"
#include "console/console.hpp"
#include "fastfiles.hpp"

#include "game/game.hpp"

#include <array>
#include <list>

namespace zombies_camos
{
	namespace
	{
		constexpr auto camo_table_name = "mp/camotable.csv";
		constexpr auto menu_camos_table_name = "mp/menucamos.csv";
		constexpr auto camo_unlock_table_name = "mp/unlocks/camounlocks.csv";
		constexpr auto zombie_splash_table_name = "cp/zombies/zombie_splashtable.csv";
		constexpr auto weapon_ref = "iw7_m1c";
		constexpr auto camo_technique = "l_sm_replace_i0c0s0o0n0e0pa0_b1-0c1s1o1na1e1_2uvt_bafsp_vm";

		struct camo_definition
		{
			const char* index;
			const char* ref;
			const char* material;
			const char* color_image;
			const char* specular_image;
			const char* icon_material;
			const char* name_key;
			const char* unlock_key;
			const char* unlock_ref;
			const char* progress_dvar;
			int required_headshots;
			const char* splash_ref;
		};

		constexpr std::array camos{
			camo_definition{
				"253",
				"camo253",
				"iwz_camo_neon_rot",
				"iwz_camo_neon_rot_c",
				"iwz_camo_neon_rot_sg",
				"iwz_camo_neon_rot_icon",
				"IWZ_CAMO_NEON_ROT",
				"IWZ_CAMO_NEON_ROT_UNLOCK",
				"iw7_m1c+camo253",
				"iwz_neon_rot_headshots",
				5,
				"iwz_camo_neon_rot_unlock",
			},
		};

		constexpr auto neon_rot_reset_command_name = "resetneonrotcamo";
		constexpr auto neon_rot_reset_revision_dvar_name = "iwz_neon_rot_reset_revision";
		constexpr auto neon_rot_reset_request_dvar_name = "iwz_neon_rot_reset_requested";
		constexpr auto neon_rot_reset_revision = 2;

		std::mutex table_patch_mutex;
		std::list<std::string> owned_cell_values;
		std::list<std::unique_ptr<database::StringTableCell[]>> owned_expanded_table_values;
		std::unordered_map<std::string, std::size_t> table_patch_generations;
		game::dvar_t* neon_rot_reset_revision_dvar = nullptr;
		game::dvar_t* neon_rot_reset_request_dvar = nullptr;
		game::dvar_t* neon_rot_progress_dvar = nullptr;

		void audit_camo_material(database::Material* material)
		{
			if (material == nullptr || material->name == nullptr)
			{
				return;
			}

			const camo_definition* camo = nullptr;
			for (const auto& candidate : camos)
			{
				if (_stricmp(material->name, candidate.material) == 0)
				{
					camo = &candidate;
					break;
				}
			}
			if (camo == nullptr)
			{
				return;
			}

			const database::GfxImage* color_image = nullptr;
			const database::GfxImage* specular_image = nullptr;
			unsigned int color_semantic = 0;
			unsigned int specular_semantic = 0;
			for (auto index = 0u; material->textureTable != nullptr && index < material->textureCount; ++index)
			{
				const auto& texture = material->textureTable[index];
				if (texture.image == nullptr || texture.image->name == nullptr)
				{
					continue;
				}

				if (_stricmp(texture.image->name, camo->color_image) == 0)
				{
					color_image = texture.image;
					color_semantic = texture.semantic;
				}
				else if (_stricmp(texture.image->name, camo->specular_image) == 0)
				{
					specular_image = texture.image;
					specular_semantic = texture.semantic;
				}
			}

			const auto* const technique =
				material->techniqueSet && material->techniqueSet->name ? material->techniqueSet->name : "<missing>";
			const auto valid = _stricmp(technique, camo_technique) == 0 && color_image != nullptr &&
							   specular_image != nullptr && color_semantic == database::TS_COLOR_MAP &&
							   specular_semantic == database::TS_SPECULAR_MAP;

			console::print(valid ? console::print_type_info : console::print_type_error,
						   "[IWZ][ZombiesCamos] material audit ref=%s name=%s valid=%d "
						   "sourceZone=%s technique=%s "
						   "textures=%u color=%s(%ux%u semantic=%u) specular=%s(%ux%u "
						   "semantic=%u)\n",
						   camo->ref, material->name, valid, fastfiles::get_current_fastfile().c_str(), technique,
						   material->textureCount, color_image ? color_image->name : "<missing>",
						   color_image ? color_image->width : 0, color_image ? color_image->height : 0, color_semantic,
						   specular_image ? specular_image->name : "<missing>",
						   specular_image ? specular_image->width : 0, specular_image ? specular_image->height : 0,
						   specular_semantic);
		}

		void reset_camo_progress(const char* command_name, const camo_definition& camo, const int reset_revision,
								 game::dvar_t* revision_dvar, game::dvar_t* request_dvar, game::dvar_t* progress_dvar)
		{
			if (game::Com_GameMode_GetActiveGameMode() != game::GAME_MODE_CP)
			{
				console::error("[IWZ][ZombiesCamos] command=%s rejected reason=not-in-zombies\n", command_name);
				return;
			}

			game::Dvar_SetInt(revision_dvar, reset_revision);
			game::Dvar_SetInt(progress_dvar, 0);
			if (game::CL_IsGameClientActive(0))
			{
				game::Dvar_SetBool(request_dvar, true);
				console::info("[IWZ][ZombiesCamos] command=%s queued in-game reset "
							  "progressSource=saved-dvar progressRef=%s target=0\n",
							  command_name, camo.progress_dvar);
				return;
			}

			console::info("[IWZ][ZombiesCamos] command=%s completed frontend reset "
						  "progressSource=saved-dvar progressRef=%s target=0\n",
						  command_name, camo.progress_dvar);
		}

		int string_table_hash(const std::string_view value)
		{
			std::uint32_t hash = 0;
			for (const auto character : value)
			{
				hash = hash * 31 + static_cast<unsigned char>(std::tolower(static_cast<unsigned char>(character)));
			}
			return static_cast<int>(hash);
		}

		bool table_name_matches(const char* name, const char* expected)
		{
			if (name == nullptr)
			{
				return false;
			}

			if (_stricmp(name, expected) == 0)
			{
				return true;
			}

			auto alternate = std::string{expected};
			std::ranges::replace(alternate, '/', '\\');
			return _stricmp(name, alternate.c_str()) == 0;
		}

		const char* cell_value(const database::StringTable* table, const int row, const int column)
		{
			return table->values[row * table->columnCount + column].string;
		}

		void assign_cell(database::StringTable* table, const int row, const int column, const std::string_view value)
		{
			owned_cell_values.emplace_back(value);
			auto& cell = table->values[row * table->columnCount + column];
			cell.string = owned_cell_values.back().c_str();
			cell.hash = string_table_hash(value);
		}

		int find_row(const database::StringTable* table, const int column, const std::string_view value)
		{
			for (auto row = 0; row < table->rowCount; ++row)
			{
				const auto* const candidate = cell_value(table, row, column);
				if (candidate != nullptr && _stricmp(candidate, value.data()) == 0)
				{
					return row;
				}
			}
			return -1;
		}

		bool is_blank(const char* value)
		{
			if (value == nullptr)
			{
				return true;
			}

			for (; *value != '\0'; ++value)
			{
				if (!std::isspace(static_cast<unsigned char>(*value)))
				{
					return false;
				}
			}
			return true;
		}

		int find_blank_row(const database::StringTable* table)
		{
			for (auto row = 0; row < table->rowCount; ++row)
			{
				bool blank = true;
				for (auto column = 0; column < table->columnCount; ++column)
				{
					if (!is_blank(cell_value(table, row, column)))
					{
						blank = false;
						break;
					}
				}

				if (blank)
				{
					return row;
				}
			}
			return -1;
		}

		int append_blank_row(database::StringTable* table)
		{
			const auto old_cell_count = static_cast<std::size_t>(table->rowCount) * table->columnCount;
			const auto new_cell_count = old_cell_count + table->columnCount;
			auto expanded_values = std::make_unique<database::StringTableCell[]>(new_cell_count);
			std::copy_n(table->values, old_cell_count, expanded_values.get());

			const auto row = table->rowCount;
			auto* const expanded_values_pointer = expanded_values.get();
			owned_expanded_table_values.emplace_back(std::move(expanded_values));
			table->values = expanded_values_pointer;
			table->rowCount++;
			return row;
		}

		bool patch_camo_table(database::StringTable* table)
		{
			constexpr auto required_columns = 18;
			if (table->values == nullptr || table->columnCount < required_columns)
			{
				console::error("[IWZ][ZombiesCamos] invalid camo table rows=%d columns=%d values=%p\n", table->rowCount,
							   table->columnCount, table->values);
				return false;
			}

			bool patched = false;
			for (const auto& camo : camos)
			{
				const std::array<std::string_view, required_columns> replacement{
					camo.index,
					camo.ref,
					"0",
					camo.material,
					"1 1 1",
					"1 1",
					camo.name_key,
					camo.icon_material,
					camo.index,
					"1",
					"",
					"cp",
					"unlock",
					"2",
					"1",
					"",
					"",
					camo.unlock_key,
				};

				const auto row = find_row(table, 0, camo.index);
				const auto* const existing_ref = row >= 0 ? cell_value(table, row, 1) : nullptr;
				if (row < 0 || existing_ref == nullptr || _stricmp(existing_ref, camo.ref) != 0)
				{
					console::error("[IWZ][ZombiesCamos] reserved camo row unavailable index=%s row=%d\n", camo.index,
								   row);
					continue;
				}

				for (auto column = 0; column < static_cast<int>(replacement.size()); ++column)
				{
					assign_cell(table, row, column, replacement[column]);
				}

				console::info("[IWZ][ZombiesCamos] registered camo index=%s ref=%s targetMaterial=%s "
							  "category=cp atlas=1x1 unlock=native-table\n",
							  camo.index, camo.ref, camo.material);
				patched = true;
			}

			return patched;
		}

		bool patch_menu_camos_table(database::StringTable* table)
		{
			if (table->values == nullptr || table->columnCount < 2)
			{
				console::error("[IWZ][ZombiesCamos] invalid menu-camos table rows=%d "
							   "columns=%d values=%p\n",
							   table->rowCount, table->columnCount, table->values);
				return false;
			}

			bool patched = false;
			for (const auto& camo : camos)
			{
				const auto row = find_row(table, 0, camo.index);
				if (row < 0)
				{
					console::error("[IWZ][ZombiesCamos] menu-camos row unavailable index=%s\n", camo.index);
					continue;
				}

				assign_cell(table, row, 1, weapon_ref);
				console::info("[IWZ][ZombiesCamos] restricted camo index=%s ref=%s weapon=%s\n", camo.index, camo.ref,
							  weapon_ref);
				patched = true;
			}

			return patched;
		}

		bool patch_camo_unlock_table(database::StringTable* table)
		{
			constexpr auto required_columns = 18;
			if (table->values == nullptr || table->columnCount != required_columns)
			{
				console::error("[IWZ][ZombiesCamos] invalid camo-unlock table rows=%d "
							   "columns=%d values=%p\n",
							   table->rowCount, table->columnCount, table->values);
				return false;
			}

			bool patched = false;
			for (const auto& camo : camos)
			{
				const auto required_headshots = std::to_string(camo.required_headshots);
				const std::array<std::string_view, required_columns> replacement{
					camo.unlock_ref,
					camo.unlock_key,
					"",
					"",
					"dvar",
					camo.progress_dvar,
					">=",
					required_headshots,
					"",
					"",
					"",
					"",
					"",
					"",
					"",
					"",
					"",
					"",
				};

				auto row = find_row(table, 0, camo.unlock_ref);
				if (row < 0)
				{
					row = append_blank_row(table);
				}

				for (auto column = 0; column < static_cast<int>(replacement.size()); ++column)
				{
					assign_cell(table, row, column, replacement[column]);
				}

				console::info("[IWZ][ZombiesCamos] registered native unlock ref=%s row=%d "
							  "progressSource=saved-dvar progressRef=%s threshold=%d\n",
							  camo.unlock_ref, row, camo.progress_dvar, camo.required_headshots);
				patched = true;
			}

			return patched;
		}

		bool patch_zombie_splash_table(database::StringTable* table)
		{
			constexpr auto required_columns = 9;
			if (table->values == nullptr || table->columnCount < required_columns)
			{
				console::error("[IWZ][ZombiesCamos] invalid Zombies splash table rows=%d "
							   "columns=%d values=%p\n",
							   table->rowCount, table->columnCount, table->values);
				return false;
			}

			bool patched = false;
			for (const auto& camo : camos)
			{
				const std::array<std::string_view, required_columns> replacement{
					camo.splash_ref,
					"IWZ_WEAPON_CAMO_EARNED",
					camo.name_key,
					camo.icon_material,
					"zmb_merit_splash",
					"camo_splash",
					"local",
					"",
					"camo",
				};

				auto row = find_row(table, 0, camo.splash_ref);
				if (row < 0)
				{
					row = find_blank_row(table);
				}
				if (row < 0)
				{
					row = append_blank_row(table);
					console::info("[IWZ][ZombiesCamos] expanded Zombies splash table ref=%s "
								  "row=%d\n",
								  camo.splash_ref, row);
				}

				for (auto column = 0; column < static_cast<int>(replacement.size()); ++column)
				{
					assign_cell(table, row, column, replacement[column]);
				}

				console::info("[IWZ][ZombiesCamos] registered Zombies splash ref=%s row=%d "
							  "icon=%s copy=weapon-camo-earned\n",
							  camo.splash_ref, row, camo.icon_material);
				patched = true;
			}

			return patched;
		}

		void patch_tables(database::StringTable* table)
		{
			if (table == nullptr || table->name == nullptr)
			{
				return;
			}

			std::scoped_lock lock(table_patch_mutex);
			bool patched = false;
			if (table_name_matches(table->name, camo_table_name))
			{
				patched = patch_camo_table(table);
			}
			else if (table_name_matches(table->name, menu_camos_table_name))
			{
				patched = patch_menu_camos_table(table);
			}
			else if (table_name_matches(table->name, camo_unlock_table_name))
			{
				patched = patch_camo_unlock_table(table);
			}
			else if (table_name_matches(table->name, zombie_splash_table_name))
			{
				patched = patch_zombie_splash_table(table);
			}

			if (patched)
			{
				auto table_name = std::string{table->name};
				std::ranges::transform(table_name, table_name.begin(), [](const unsigned char character)
									   { return static_cast<char>(std::tolower(character)); });
				const auto generation = ++table_patch_generations[table_name];
				console::info("[IWZ][ZombiesCamos] table patch applied table=%s generation=%zu "
							  "address=%p rows=%d columns=%d sourceZone=%s\n",
							  table->name, generation, table, table->rowCount, table->columnCount,
							  fastfiles::get_current_fastfile().c_str());
			}
		}
	} // namespace

	class component final : public component_interface
	{
	  public:
		void post_unpack() override
		{
			if (game::environment::is_dedi())
			{
				return;
			}

			neon_rot_reset_revision_dvar = game::Dvar_RegisterInt(
				neon_rot_reset_revision_dvar_name, 0, 0, neon_rot_reset_revision, game::DVAR_FLAG_SAVED,
				"Internal one-time revision for Neon Rot camo progress resets");
			neon_rot_reset_request_dvar =
				game::Dvar_RegisterBool(neon_rot_reset_request_dvar_name, false, game::DVAR_FLAG_NONE,
										"Request an in-match Neon Rot camo progress reset");
			neon_rot_progress_dvar =
				game::Dvar_RegisterInt(camos[0].progress_dvar, 0, 0, camos[0].required_headshots, game::DVAR_FLAG_SAVED,
									   "Persistent M1 headshot progress for the Neon Rot Zombies camo");
			command::add(neon_rot_reset_command_name,
						 []
						 {
							 reset_camo_progress(neon_rot_reset_command_name, camos[0], neon_rot_reset_revision,
												 neon_rot_reset_revision_dvar, neon_rot_reset_request_dvar,
												 neon_rot_progress_dvar);
						 });
			fastfiles::on_string_table_loaded(patch_tables);
			fastfiles::on_material_loaded(audit_camo_material);
			console::info("[IWZ][ZombiesCamos] registered table patches camos=%zu weapon=%s "
						  "neonRot=%s:%d resetCommand=%s resetRevision=%d\n",
						  camos.size(), weapon_ref, camos[0].progress_dvar, camos[0].required_headshots,
						  neon_rot_reset_command_name, neon_rot_reset_revision);
		}
	};
} // namespace zombies_camos

REGISTER_COMPONENT(zombies_camos::component)
