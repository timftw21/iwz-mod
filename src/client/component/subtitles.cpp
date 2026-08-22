#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"

#include "command.hpp"
#include "console/console.hpp"
#include "fastfiles.hpp"
#include "filesystem.hpp"
#include "localized_strings.hpp"
#include "scheduler.hpp"

#include <utils/concurrency.hpp>
#include <utils/io.hpp>
#include <utils/json.hpp>
#include <utils/memory.hpp>
#include <utils/string.hpp>

#include <fstream>

namespace subtitles
{
	namespace
	{
		constexpr std::array subtitle_config_paths = {
			"subtitles/spaceland.json",
		};
		constexpr auto alias_dump_path = "iw7-mod/subtitles/sound_aliases.csv";
		constexpr auto audio_export_directory = "iw7-mod/subtitles/audio";
		constexpr std::uint32_t sab_magic = 0x23585532;
		constexpr std::uint32_t iw_sab_version = 4;

#pragma pack(push, 1)
		struct sab_file_header
		{
			std::uint32_t magic;
			std::uint32_t version;
			std::uint32_t audio_entry_size;
			std::uint32_t hash_entry_size;
			std::uint32_t name_entry_size;
			std::uint32_t entry_count;
			std::uint8_t unknown[8];
			std::uint64_t file_size;
			std::uint64_t entry_table_offset;
			std::uint64_t hash_table_offset;
		};

		struct sab_audio_entry
		{
			std::uint32_t key;
			std::uint32_t size;
			std::uint32_t seek_table_length;
			std::uint32_t frame_count;
			std::uint32_t unknown;
			std::uint64_t offset;
			std::uint32_t frame_rate;
			std::uint8_t channel_count;
			std::uint8_t looping;
			std::uint8_t format;
			std::uint8_t padding[9];
		};
#pragma pack(pop)

		static_assert(sizeof(sab_file_header) == 56);
		static_assert(sizeof(sab_audio_entry) == 44);

		struct subtitle_definition
		{
			const char* text;
			bool force;
		};

		using subtitle_map = std::unordered_map<std::string, subtitle_definition>;
		using subtitle_id_map = std::unordered_map<std::uint32_t, subtitle_definition>;
		struct subtitle_maps
		{
			subtitle_map aliases;
			subtitle_map audio_assets;
			subtitle_id_map audio_asset_ids;
		};
		struct patch_statistics
		{
			size_t banks;
			size_t variants;
			size_t named_assets;
			size_t id_matches;
			size_t name_matches;
			size_t alias_matches;
			size_t patched;
		};
		struct original_subtitle
		{
			std::uint32_t asset_id;
			std::string alias_name;
			const char* text;
			bool force;
		};

		utils::concurrency::container<subtitle_maps> subtitle_definitions;
		utils::concurrency::container<std::unordered_map<database::SndAlias*, original_subtitle>>
			original_subtitles;

		std::string normalize_audio_asset(std::string value)
		{
			std::replace(value.begin(), value.end(), '/', '\\');
			return utils::string::to_lower(value);
		}

		std::uint32_t sound_asset_hash(const std::string_view value)
		{
			std::uint32_t hash = 5381;
			for (const auto character : value)
			{
				hash = 65599 * hash + static_cast<unsigned char>(character);
			}

			return hash ? hash : 1;
		}

		struct alias_audio
		{
			std::string alias;
			std::string asset;
			std::string bank;
			std::uint32_t asset_id;
			unsigned int type;
		};

		std::string csv_escape(const char* value)
		{
			std::string escaped = value ? value : "";
			size_t position{};

			while ((position = escaped.find('"', position)) != std::string::npos)
			{
				escaped.insert(position, 1, '"');
				position += 2;
			}

			return '"' + escaped + '"';
		}

		std::string sanitize_filename(std::string value)
		{
			for (auto& character : value)
			{
				if (character < 32 || std::string_view{"<>:\"/\\|?*"}.find(character) != std::string_view::npos)
				{
					character = '_';
				}
			}

			while (!value.empty() && (value.back() == ' ' || value.back() == '.'))
			{
				value.pop_back();
			}

			if (value.size() > 64)
			{
				value.resize(64);
			}

			return value.empty() ? "sound" : value;
		}

		std::string get_asset_leaf(const std::string& asset)
		{
			const auto separator = asset.find_last_of("\\/");
			return separator == std::string::npos ? asset : asset.substr(separator + 1);
		}

		std::filesystem::path get_game_path()
		{
			const auto* base_path = game::Dvar_FindVar("fs_basepath");
			if (base_path && base_path->current.string && *base_path->current.string)
			{
				return base_path->current.string;
			}

			return std::filesystem::current_path();
		}

		std::vector<std::filesystem::path> find_sab_files(const alias_audio& audio)
		{
			std::vector<std::filesystem::path> files;
			std::error_code error;
			const auto game_path = get_game_path();

			for (std::filesystem::recursive_directory_iterator iterator(game_path,
				std::filesystem::directory_options::skip_permission_denied, error), end;
				iterator != end; iterator.increment(error))
			{
				if (error)
				{
					error.clear();
					continue;
				}

				if (!iterator->is_regular_file(error))
				{
					error.clear();
					continue;
				}

				const auto extension = utils::string::to_lower(iterator->path().extension().string());
				if (extension == ".sabs" || extension == ".sabl")
				{
					files.emplace_back(iterator->path());
				}
			}

			const auto bank = utils::string::to_lower(audio.bank);
			const auto preferred_extension = audio.type == game::SAT_STREAMED ? ".sabl" : ".sabs";
			const auto score = [&bank, preferred_extension](const std::filesystem::path& path)
			{
				const auto stem = utils::string::to_lower(path.stem().string());
				const auto extension = utils::string::to_lower(path.extension().string());
				int value = 4;

				if (!bank.empty() && stem == bank)
				{
					value -= 2;
				}
				else if (!bank.empty() && (stem.find(bank) != std::string::npos || bank.find(stem) != std::string::npos))
				{
					--value;
				}

				if (extension == preferred_extension)
				{
					--value;
				}

				return value;
			};

			std::sort(files.begin(), files.end(), [&score](const auto& left, const auto& right)
			{
				const auto left_score = score(left);
				const auto right_score = score(right);
				return left_score == right_score ? left < right : left_score < right_score;
			});

			return files;
		}

		std::array<std::uint8_t, 42> make_flac_header(const sab_audio_entry& entry)
		{
			std::array<std::uint8_t, 42> header{};
			std::memcpy(header.data(), "fLaC", 4);
			header[4] = 0x80;
			header[7] = 0x22;
			header[8] = 0x04;
			header[10] = 0x04;

			const auto flags = (static_cast<std::uint64_t>(entry.frame_rate) << 44) |
				(static_cast<std::uint64_t>(entry.channel_count - 1) << 41) |
				(static_cast<std::uint64_t>(16 - 1) << 36) | entry.frame_count;

			for (size_t i = 0; i < 8; ++i)
			{
				header[18 + i] = static_cast<std::uint8_t>(flags >> (56 - i * 8));
			}

			return header;
		}

		bool write_flac(std::ifstream& input, const sab_audio_entry& entry,
			const std::filesystem::path& output_path)
		{
			if (!entry.frame_rate || !entry.channel_count || !entry.frame_count)
			{
				return false;
			}

			input.clear();
			input.seekg(static_cast<std::streamoff>(entry.offset + entry.seek_table_length));
			if (!input)
			{
				return false;
			}

			std::ofstream output(output_path, std::ios::binary | std::ios::trunc);
			if (!output)
			{
				return false;
			}

			const auto header = make_flac_header(entry);
			output.write(reinterpret_cast<const char*>(header.data()), header.size());

			std::array<char, 64 * 1024> buffer{};
			std::uint64_t remaining = entry.size;
			while (remaining > 0)
			{
				const auto block_size = static_cast<std::streamsize>(std::min<std::uint64_t>(remaining, buffer.size()));
				input.read(buffer.data(), block_size);
				if (input.gcount() != block_size)
				{
					output.close();
					std::error_code error;
					std::filesystem::remove(output_path, error);
					return false;
				}

				output.write(buffer.data(), block_size);
				remaining -= block_size;
			}

			output.flush();
			const auto success = output.good();
			output.close();

			if (!success)
			{
				std::error_code error;
				std::filesystem::remove(output_path, error);
			}

			return success;
		}

		bool export_audio_from_bank(const std::filesystem::path& bank_path, const alias_audio& audio,
			const std::filesystem::path& output_path)
		{
			std::ifstream input(bank_path, std::ios::binary);
			if (!input)
			{
				return false;
			}

			sab_file_header header{};
			input.read(reinterpret_cast<char*>(&header), sizeof(header));
			if (!input || header.magic != sab_magic || header.version != iw_sab_version ||
				header.audio_entry_size < sizeof(sab_audio_entry))
			{
				return false;
			}

			input.seekg(static_cast<std::streamoff>(header.entry_table_offset));
			for (std::uint32_t i = 0; i < header.entry_count; ++i)
			{
				sab_audio_entry entry{};
				input.read(reinterpret_cast<char*>(&entry), sizeof(entry));
				if (!input)
				{
					return false;
				}

				if (header.audio_entry_size > sizeof(entry))
				{
					input.seekg(header.audio_entry_size - sizeof(entry), std::ios::cur);
				}

				if (entry.key == audio.asset_id)
				{
					return write_flac(input, entry, output_path);
				}
			}

			return false;
		}

		std::vector<alias_audio> find_alias_audio(const std::string& requested_alias)
		{
			std::vector<alias_audio> results;
			std::unordered_set<std::uint32_t> found_assets;
			const auto target = utils::string::to_lower(requested_alias);

			game::DB_EnumXAssets(game::ASSET_TYPE_SOUND_BANK, [&results, &found_assets, &target](const game::XAssetHeader header)
			{
				const auto* bank = header.soundBank;
				if (!bank || !bank->alias)
				{
					return;
				}

				for (unsigned int i = 0; i < bank->aliasCount; ++i)
				{
					const auto& alias_list = bank->alias[i];
					const auto list_name = alias_list.aliasName ? alias_list.aliasName : "";
					if (!alias_list.head)
					{
						continue;
					}

					const auto list_matches = utils::string::to_lower(list_name) == target;
					for (auto j = 0; j < alias_list.count; ++j)
					{
						const auto& alias = alias_list.head[j];
						const auto* alias_name = alias.aliasName ? alias.aliasName : list_name;
						if (!list_matches && utils::string::to_lower(alias_name) != target)
						{
							continue;
						}

						if (!alias.assetId || found_assets.contains(alias.assetId))
						{
							continue;
						}

						found_assets.emplace(alias.assetId);
						results.push_back({alias_name, alias.assetFileName ? alias.assetFileName : "",
							bank->name ? bank->name : "", alias.assetId, alias.flags.type});
					}
				}
			});

			return results;
		}

		size_t patch_sound_bank(database::SndBank* bank, const bool refresh_originals,
			patch_statistics* statistics = nullptr)
		{
			if (!bank || !bank->alias)
			{
				return 0;
			}

			if (statistics)
			{
				++statistics->banks;
			}

			return original_subtitles.access<size_t>([bank, refresh_originals, statistics](auto& originals)
			{
				return subtitle_definitions.access<size_t>([bank, refresh_originals, statistics, &originals](
					const subtitle_maps& definitions)
				{
					size_t patched{};

					for (unsigned int i = 0; i < bank->aliasCount; ++i)
					{
						auto& alias_list = bank->alias[i];
						if (!alias_list.head)
						{
							continue;
						}

						const auto list_name = alias_list.aliasName ?
							utils::string::to_lower(alias_list.aliasName) : std::string{};

						for (auto j = 0; j < alias_list.count; ++j)
						{
							auto& alias = alias_list.head[j];
							const auto asset_name = alias.assetFileName ?
								normalize_audio_asset(alias.assetFileName) : std::string{};
							const auto alias_name = alias.aliasName ?
								utils::string::to_lower(alias.aliasName) : list_name;
							if (statistics)
							{
								++statistics->variants;
								statistics->named_assets += !asset_name.empty();
							}

							auto original = originals.find(&alias);
							if (refresh_originals || original == originals.end() ||
								original->second.asset_id != alias.assetId ||
								original->second.alias_name != alias_name)
							{
								original = originals.insert_or_assign(&alias, original_subtitle{
									alias.assetId, alias_name, alias.subtitle,
									alias.flags.ForceSubtitle != 0,
								}).first;
							}

							alias.subtitle = original->second.text;
							alias.flags.ForceSubtitle = original->second.force;

							const subtitle_definition* selected_definition{};
							if (alias.assetId)
							{
								const auto id_definition = definitions.audio_asset_ids.find(alias.assetId);
								if (id_definition != definitions.audio_asset_ids.end())
								{
									selected_definition = &id_definition->second;
									if (statistics)
									{
										++statistics->id_matches;
									}
								}
							}

							if (!selected_definition && !asset_name.empty())
							{
								const auto name_definition = definitions.audio_assets.find(asset_name);
								if (name_definition != definitions.audio_assets.end())
								{
									selected_definition = &name_definition->second;
									if (statistics)
									{
										++statistics->name_matches;
									}
								}
							}

							if (!selected_definition)
							{
								auto alias_definition = definitions.aliases.find(alias_name);
								if (alias_definition == definitions.aliases.end() && alias_name != list_name)
								{
									alias_definition = definitions.aliases.find(list_name);
								}

								if (alias_definition != definitions.aliases.end())
								{
									selected_definition = &alias_definition->second;
									if (statistics)
									{
										++statistics->alias_matches;
									}
								}
							}

							if (selected_definition)
							{
								alias.subtitle = selected_definition->text;
								alias.flags.ForceSubtitle = selected_definition->force;
								++patched;
								if (statistics)
								{
									++statistics->patched;
								}
							}
						}
					}

					return patched;
				});
			});
		}

		void patch_new_sound_bank(database::SndBank* bank)
		{
			patch_statistics statistics{};
			const auto patched = patch_sound_bank(bank, true, &statistics);
			if (patched)
			{
				console::info("[Subtitles] Patched %zu aliases in newly loaded bank \"%s\" "
					"(matches: %zu asset ID, %zu asset path, %zu alias)\n", patched,
					bank->name ? bank->name : "", statistics.id_matches, statistics.name_matches,
					statistics.alias_matches);
			}
		}

		patch_statistics patch_loaded_sound_banks()
		{
			patch_statistics statistics{};
			game::DB_EnumXAssets(game::ASSET_TYPE_SOUND_BANK, [&statistics](const game::XAssetHeader header)
			{
				patch_sound_bank(header.soundBank, false, &statistics);
			});
			return statistics;
		}

		void reload_subtitles()
		{
			subtitle_maps definitions;
			std::unordered_map<std::uint32_t, std::string> audio_asset_id_names;
			size_t loaded_configs{};
			console::info("[Subtitles] Active manifest: %s (zombies.json disabled)\n",
				subtitle_config_paths.front());
			try
			{
				for (const auto* config_path : subtitle_config_paths)
				{
					const auto buffer = filesystem::read_file(config_path);
					if (buffer.empty())
					{
						console::warn("[Subtitles] Could not find %s\n", config_path);
						continue;
					}

					const auto data = nlohmann::json::parse(buffer);
					if (!data.is_object())
					{
						throw std::runtime_error(std::string{config_path} +
							" root value must be an object");
					}

					for (auto entry = data.begin(); entry != data.end(); ++entry)
					{
						if (entry.key().starts_with('_'))
						{
							continue;
						}

						std::string text;
						std::string audio_asset;
						bool force{};

						if (entry.value().is_string())
						{
							text = entry.value().get<std::string>();
						}
						else if (entry.value().is_object() && entry.value().contains("text") &&
							entry.value()["text"].is_string())
						{
							text = entry.value()["text"].get<std::string>();
							force = entry.value().value("force", false);
							if (entry.value().contains("asset"))
							{
								if (!entry.value()["asset"].is_string())
								{
									throw std::runtime_error("entry \"" + entry.key() +
										"\" asset must be a string");
								}

								audio_asset = entry.value()["asset"].get<std::string>();
							}
						}
						else
						{
							throw std::runtime_error("entry \"" + entry.key() +
								"\" must be a string or an object containing a text string");
						}

						if (entry.key().empty() || text.empty())
						{
							throw std::runtime_error("subtitle keys and text cannot be empty");
						}

						const auto* stable_text = utils::memory::get_allocator()->duplicate_string(text);
						localized_strings::override(text, text);
						if (!audio_asset.empty())
						{
							const auto normalized_asset = normalize_audio_asset(audio_asset);
							const auto asset_id = sound_asset_hash(normalized_asset);
							const auto [asset_id_name, inserted] = audio_asset_id_names.emplace(
								asset_id, normalized_asset);
							if (!inserted && asset_id_name->second != normalized_asset)
							{
								throw std::runtime_error(utils::string::va(
									"audio assets \"%s\" and \"%s\" collide at sound asset ID 0x%08X",
									asset_id_name->second.data(), normalized_asset.data(), asset_id));
							}

							definitions.audio_assets[normalized_asset] = {stable_text, force};
							definitions.audio_asset_ids[asset_id] = {stable_text, force};
						}
						else
						{
							definitions.aliases[utils::string::to_lower(entry.key())] =
								{stable_text, force};
						}
					}

					++loaded_configs;
				}
			}
			catch (const std::exception& error)
			{
				console::error("[Subtitles] Failed to parse subtitle config: %s\n", error.what());
				return;
			}

			if (!loaded_configs)
			{
				console::warn("[Subtitles] No subtitle configuration files were loaded\n");
				return;
			}

			const auto alias_count = definitions.aliases.size();
			const auto audio_asset_count = definitions.audio_assets.size();
			const auto audio_asset_id_count = definitions.audio_asset_ids.size();
			subtitle_definitions.access([&definitions](subtitle_maps& current)
			{
				current = std::move(definitions);
			});

			const auto statistics = patch_loaded_sound_banks();
			console::info("[Subtitles] Loaded %zu alias and %zu audio-asset definitions (%zu hashed IDs) "
				"from %zu files; patched %zu active sound aliases across %zu banks "
				"(%zu variants, %zu named assets; matches: %zu asset ID, %zu asset path, %zu alias)\n",
				alias_count, audio_asset_count, audio_asset_id_count, loaded_configs, statistics.patched,
				statistics.banks, statistics.variants, statistics.named_assets, statistics.id_matches,
				statistics.name_matches, statistics.alias_matches);
		}

		void dump_sound_aliases(const command::params& params)
		{
			const auto filter = params.size() > 1 ? utils::string::to_lower(params.get(1)) : std::string{};
			std::vector<std::string> rows;

			game::DB_EnumXAssets(game::ASSET_TYPE_SOUND_BANK, [&rows, &filter](const game::XAssetHeader header)
			{
				const auto* bank = header.soundBank;
				if (!bank || !bank->alias)
				{
					return;
				}

				for (unsigned int i = 0; i < bank->aliasCount; ++i)
				{
					const auto& alias_list = bank->alias[i];
					if (!alias_list.head)
					{
						continue;
					}

					for (auto j = 0; j < alias_list.count; ++j)
					{
						const auto& alias = alias_list.head[j];
						const auto* alias_name = alias.aliasName ? alias.aliasName : alias_list.aliasName;
						const auto* asset_name = alias.assetFileName ? alias.assetFileName : "";
						const auto* bank_name = bank->name ? bank->name : "";

						if (!filter.empty() && !utils::string::find_lower(alias_name ? alias_name : "", filter) &&
							!utils::string::find_lower(asset_name, filter) &&
							!utils::string::find_lower(bank_name, filter))
						{
							continue;
						}

						rows.emplace_back(csv_escape(bank_name) + ',' + csv_escape(alias_name) + ',' +
							csv_escape(asset_name) + ',' + csv_escape(alias.subtitle) + ',' +
							(alias.flags.ForceSubtitle ? "true" : "false") + "\n");
					}
				}
			});

			std::sort(rows.begin(), rows.end());
			std::string output = "sound_bank,alias,audio_asset,subtitle,force_subtitle\n";
			for (const auto& row : rows)
			{
				output.append(row);
			}

			utils::io::create_directory("iw7-mod/subtitles");
			if (utils::io::write_file(alias_dump_path, output))
			{
				console::info("[Subtitles] Wrote %zu sound aliases to %s\n", rows.size(), alias_dump_path);
			}
			else
			{
				console::error("[Subtitles] Failed to write %s\n", alias_dump_path);
			}
		}

		void export_sound_alias(const command::params& params)
		{
			if (params.size() < 2)
			{
				console::info("usage: iwz_export_sound_alias <exact alias>\n");
				return;
			}

			const std::string requested_alias = params.get(1);
			const auto audio_entries = find_alias_audio(requested_alias);
			if (audio_entries.empty())
			{
				console::error("[Subtitles] Sound alias \"%s\" is not loaded. Enter its map and try again.\n",
					requested_alias.data());
				return;
			}

			utils::io::create_directory(audio_export_directory);
			const auto safe_alias = sanitize_filename(requested_alias);
			const auto sab_files = find_sab_files(audio_entries.front());
			size_t exported{};

			for (size_t index = 0; index < audio_entries.size(); ++index)
			{
				const auto& audio = audio_entries[index];
				const auto safe_asset = sanitize_filename(get_asset_leaf(audio.asset));
				const auto output_name = safe_alias + "__" + std::to_string(index + 1) + "__" + safe_asset + ".flac";
				const auto output_path = std::filesystem::path{audio_export_directory} / output_name;

				std::error_code error;
				if (std::filesystem::is_regular_file(output_path, error))
				{
					console::info("[Subtitles] Already exported %s\n", output_path.generic_string().data());
					++exported;
					continue;
				}

				bool found{};
				for (const auto& bank_path : sab_files)
				{
					if (export_audio_from_bank(bank_path, audio, output_path))
					{
						console::info("[Subtitles] Exported %s from %s\n",
							output_path.generic_string().data(), bank_path.filename().string().data());
						found = true;
						++exported;
						break;
					}
				}

				if (!found)
				{
					console::error("[Subtitles] Could not locate audio asset \"%s\" (0x%08X) in an IW sound bank.\n",
						audio.asset.data(), audio.asset_id);
				}
			}

			console::info("[Subtitles] Exported %zu of %zu variants to %s\n", exported,
				audio_entries.size(), audio_export_directory);
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (game::environment::is_dedi())
			{
				return;
			}

			fastfiles::on_sound_bank_loaded(patch_new_sound_bank);
			command::add("iwz_reload_subtitles", reload_subtitles);
			command::add("iwz_dump_sound_aliases", dump_sound_aliases);
			command::add("iwz_export_sound_alias", export_sound_alias);
			scheduler::once(reload_subtitles, scheduler::pipeline::main, 1s);
		}
	};
}

REGISTER_COMPONENT(subtitles::component)
