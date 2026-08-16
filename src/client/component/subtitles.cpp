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
		constexpr auto subtitle_config_path = "subtitles/zombies.json";
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
		utils::concurrency::container<subtitle_map> subtitle_definitions;

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

		size_t patch_sound_bank(database::SndBank* bank)
		{
			if (!bank || !bank->alias)
			{
				return 0;
			}

			return subtitle_definitions.access<size_t>([bank](const subtitle_map& definitions)
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
						const auto alias_name = alias.aliasName ?
							utils::string::to_lower(alias.aliasName) : list_name;
						auto definition = definitions.find(alias_name);

						if (definition == definitions.end() && alias_name != list_name)
						{
							definition = definitions.find(list_name);
						}

						if (definition != definitions.end())
						{
							alias.subtitle = definition->second.text;
							alias.flags.ForceSubtitle = definition->second.force;
							++patched;
						}
					}
				}

				return patched;
			});
		}

		size_t patch_loaded_sound_banks()
		{
			size_t patched{};
			game::DB_EnumXAssets(game::ASSET_TYPE_SOUND_BANK, [&patched](const game::XAssetHeader header)
			{
				patched += patch_sound_bank(header.soundBank);
			});
			return patched;
		}

		void reload_subtitles()
		{
			const auto buffer = filesystem::read_file(subtitle_config_path);
			if (buffer.empty())
			{
				console::warn("[Subtitles] Could not find %s\n", subtitle_config_path);
				return;
			}

			subtitle_map definitions;
			try
			{
				const auto data = nlohmann::json::parse(buffer);
				if (!data.is_object())
				{
					throw std::runtime_error("the root value must be an object");
				}

				for (auto entry = data.begin(); entry != data.end(); ++entry)
				{
					if (entry.key().starts_with('_'))
					{
						continue;
					}

					std::string text;
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
					}
					else
					{
						throw std::runtime_error("entry \"" + entry.key() +
							"\" must be a string or an object containing a text string");
					}

					if (entry.key().empty() || text.empty())
					{
						throw std::runtime_error("subtitle aliases and text cannot be empty");
					}

					const auto* stable_text = utils::memory::get_allocator()->duplicate_string(text);
					localized_strings::override(text, text);
					definitions[utils::string::to_lower(entry.key())] = {stable_text, force};
				}
			}
			catch (const std::exception& error)
			{
				console::error("[Subtitles] Failed to parse %s: %s\n", subtitle_config_path, error.what());
				return;
			}

			const auto definition_count = definitions.size();
			subtitle_definitions.access([&definitions](subtitle_map& current)
			{
				current = std::move(definitions);
			});

			const auto patched_count = patch_loaded_sound_banks();
			console::info("[Subtitles] Loaded %zu definitions and patched %zu active sound aliases\n",
				definition_count, patched_count);
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

			fastfiles::on_sound_bank_loaded(patch_sound_bank);
			command::add("iwz_reload_subtitles", reload_subtitles);
			command::add("iwz_dump_sound_aliases", dump_sound_aliases);
			command::add("iwz_export_sound_alias", export_sound_alias);
			scheduler::once(reload_subtitles, scheduler::pipeline::main, 1s);
		}
	};
}

REGISTER_COMPONENT(subtitles::component)
