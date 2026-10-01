#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "usermaps.hpp"

#include "command.hpp"
#include "console/console.hpp"
#include "filesystem.hpp"
#include "game/game.hpp"

#include <utils/hook.hpp>
#include <utils/io.hpp>
#include <utils/string.hpp>

namespace usermaps
{
	namespace
	{
		// Readers must not observe a partially scanned package registry.
		std::atomic<bool> ready{false};
		std::vector<map_info> maps;
		std::unordered_map<std::string, std::filesystem::path> package_files;
		std::mutex script_path_mutex;
		std::string script_path;
		utils::hook::detour db_file_exists_hook;
		utils::hook::detour ui_get_map_display_name_hook;

		bool valid_name(const std::string& name)
		{
			return !name.empty() && name.size() <= 48 &&
				name.find_first_not_of("abcdefghijklmnopqrstuvwxyz0123456789_") == std::string::npos;
		}

		void validate_fastfile(const std::filesystem::path& path)
		{
			// IW7 version 1619; reject empty files and fastfiles built for other games.
			std::ifstream stream(path, std::ios::binary);
			char magic[8]{};
			std::uint32_t version{};
			stream.read(magic, sizeof(magic));
			stream.read(reinterpret_cast<char*>(&version), sizeof(version));
			if (!stream || (std::memcmp(magic, "IWffu100", 8) && std::memcmp(magic, "IWff0100", 8)) || version != 1619)
			{
				throw std::runtime_error("not an IW7 fastfile (version 1619): " + path.generic_string());
			}
		}

		std::string metadata_string(const rapidjson::Document& doc, const char* key,
			const std::string& fallback, const size_t limit)
		{
			if (!doc.HasMember(key)) return fallback;
			const auto& value = doc[key];
			if (!value.IsString() || value.GetStringLength() > limit)
				throw std::runtime_error(std::string("invalid map.json field: ") + key);
			const std::string result(value.GetString(), value.GetStringLength());
			if (result.find('\0') != std::string::npos)
				throw std::runtime_error(std::string("invalid map.json field: ") + key);
			return result.empty() ? fallback : result;
		}

		void add_map(const std::filesystem::path& path)
		{
			map_info map{};
			map.name = path.filename().string();
			if (!valid_name(map.name) || !map.name.starts_with("cp_") || map.name.size() <= 3 ||
				map.name.ends_with("_load"))
				throw std::runtime_error("map folders must use a lowercase cp_ name, at most 48 characters");
			if (std::any_of(maps.begin(), maps.end(), [&](const map_info& item) { return item.name == map.name; }))
				throw std::runtime_error("duplicate map; the higher priority package is already registered");
			const std::array stock_maps{"cp_zmb", "cp_rave", "cp_disco", "cp_town", "cp_final", "cp_frontend"};
			if (std::find(stock_maps.begin(), stock_maps.end(), map.name) != stock_maps.end() ||
				db_file_exists_hook.invoke<bool>(map.name.c_str()))
				throw std::runtime_error("a stock map/zone already uses this name");

			map.path = path;
			map.title = map.name;
			map.description = "Custom Zombies map";
			const auto manifest = path / "map.json";
			if (std::filesystem::exists(manifest))
			{
				if (std::filesystem::file_size(manifest) > 65536)
					throw std::runtime_error("map.json exceeds 64 KiB");
				const auto contents = utils::io::read_file(manifest.generic_string());
				rapidjson::Document doc;
				doc.Parse(contents.data(), contents.size());
				if (doc.HasParseError() || !doc.IsObject()) throw std::runtime_error("invalid map.json");
				if (doc.HasMember("format_version") && (!doc["format_version"].IsInt() || doc["format_version"].GetInt() != 1))
					throw std::runtime_error("unsupported map.json format_version (expected 1)");
				map.title = metadata_string(doc, "title", map.title, 128);
				map.description = metadata_string(doc, "description", map.description, 2048);
				map.author = metadata_string(doc, "author", "", 128);
				map.version = metadata_string(doc, "version", "", 64);
				if (doc.HasMember("dependencies"))
				{
					const auto& dependencies = doc["dependencies"];
					if (!dependencies.IsArray() || dependencies.Size() > 32)
						throw std::runtime_error("dependencies must be an array of at most 32 zone names");
					for (const auto& dependency : dependencies.GetArray())
					{
						if (!dependency.IsString()) throw std::runtime_error("dependency names must be strings");
						const std::string name(dependency.GetString(), dependency.GetStringLength());
						if (!valid_name(name) || name == map.name || name == map.name + "_load" ||
							std::find(map.dependencies.begin(), map.dependencies.end(), name) != map.dependencies.end())
							throw std::runtime_error("invalid or repeated dependency: " + name);
						map.dependencies.push_back(name);
					}
				}
			}

			std::unordered_map<std::string, std::filesystem::path> files;
			for (const auto& folder : {path, path / "zone"})
			{
				if (!std::filesystem::is_directory(folder)) continue;
				for (const auto& file : std::filesystem::directory_iterator(folder))
				{
					if (!file.is_regular_file()) continue;
					const auto extension = utils::string::to_lower(file.path().extension().string());
					if (extension != ".ff" && extension != ".pak" && extension != ".sabl" && extension != ".sabs") continue;
					const auto filename = utils::string::to_lower(file.path().filename().string());
					if (package_files.contains(filename) || files.contains(filename))
						throw std::runtime_error("package filename is already in use: " + filename);
					if (extension == ".ff")
					{
						const auto stem = utils::string::to_lower(file.path().stem().string());
						for (const auto* stock : stock_maps)
							if (stem == stock || stem == std::string(stock) + "_load")
								throw std::runtime_error("package uses a reserved stock zone: " + filename);
						if (db_file_exists_hook.invoke<bool>(file.path().stem().string().c_str()) ||
							filesystem::exists("zone/" + filename))
							throw std::runtime_error("package would replace a stock zone: " + filename);
						validate_fastfile(file.path());
					}
					files.emplace(filename, file.path());
				}
			}
			for (const auto& name : {map.name, map.name + "_load"})
				if (!files.contains(name + ".ff")) throw std::runtime_error("missing required file: " + name + ".ff");
			for (const auto& name : map.dependencies)
				if (!files.contains(name + ".ff")) throw std::runtime_error("missing dependency: " + name + ".ff");

			console::info("[IWZ][Usermaps] registered map=%s title=\"%s\" path=\"%s\" files=%zu dependencies=%zu\n",
				map.name.c_str(), map.title.c_str(), path.generic_string().c_str(), files.size(), map.dependencies.size());
			maps.push_back(std::move(map));
			package_files.insert(files.begin(), files.end());
		}

		bool db_file_exists_stub(const char* name)
		{
			return name && (zone_exists(name) || db_file_exists_hook.invoke<bool>(name));
		}

		const char* ui_get_map_display_name_stub(const char* name)
		{
			const auto* map = name ? find(name) : nullptr;
			return map ? map->title.c_str() : ui_get_map_display_name_hook.invoke<const char*>(name);
		}
	}

	void initialize()
	{
		static std::once_flag initialized;
		std::call_once(initialized, []
		{
			auto roots = filesystem::get_search_paths();
			roots.push_back(std::filesystem::current_path().generic_string());
			std::unordered_set<std::string> seen;
			for (const auto& root : roots)
			{
				const auto folder = std::filesystem::path(root) / "usermaps";
				if (!seen.insert(utils::string::to_lower(folder.lexically_normal().generic_string())).second) continue;
				try
				{
					if (!std::filesystem::is_directory(folder)) continue;
					std::vector<std::filesystem::path> candidates;
					for (const auto& entry : std::filesystem::directory_iterator(folder))
						if (entry.is_directory()) candidates.push_back(entry.path());
					std::sort(candidates.begin(), candidates.end());
					for (const auto& path : candidates)
					{
						try { add_map(path); }
						catch (const std::exception& error)
						{
							console::warn("[IWZ][Usermaps] rejected path=\"%s\" reason=%s\n", path.generic_string().c_str(), error.what());
						}
					}
				}
				catch (const std::exception& error)
				{
					console::warn("[IWZ][Usermaps] scan failed path=\"%s\" reason=%s\n", folder.generic_string().c_str(), error.what());
				}
			}
			std::sort(maps.begin(), maps.end(), [](const map_info& a, const map_info& b) { return a.name < b.name; });
			ready.store(true);
			console::info("[IWZ][Usermaps] discovery complete maps=%zu; install packages in iw7-mod/usermaps/<cp_name>/ and restart\n", maps.size());
		});
	}

	const std::vector<map_info>& get_maps()
	{
		static const std::vector<map_info> empty;
		return ready.load() ? maps : empty;
	}

	const map_info* find(const std::string& name)
	{
		if (!ready.load()) return nullptr;
		const auto lower = utils::string::to_lower(name);
		const auto map = std::find_if(maps.begin(), maps.end(), [&](const map_info& item) { return item.name == lower; });
		return map == maps.end() ? nullptr : &*map;
	}

	bool find_file(const std::string& filename, std::string* path)
	{
		if (!ready.load()) return false;
		const auto entry = package_files.find(utils::string::to_lower(filename));
		if (entry == package_files.end()) return false;
		std::error_code error;
		if (!std::filesystem::is_regular_file(entry->second, error)) return false;
		if (path) *path = entry->second.generic_string();
		return true;
	}

	bool zone_exists(const std::string& name) { return find_file(name + ".ff", nullptr); }

	void set_script_map(const char* name)
	{
		const auto* map = name ? find(name) : nullptr;
		const auto path = map ? map->path.generic_string() : std::string{};
		std::lock_guard lock(script_path_mutex);
		if (script_path == path) return;
		script_path = path;
		console::info("[IWZ][Usermaps] script mount map=%s path=\"%s\"\n", name ? name : "<none>", path.c_str());
	}

	std::string get_script_path()
	{
		std::lock_guard lock(script_path_mutex);
		return script_path;
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			db_file_exists_hook.create(game::DB_FileExists, db_file_exists_stub);
			ui_get_map_display_name_hook.create(game::UI_GetMapDisplayName, ui_get_map_display_name_stub);
			command::add("usermaps", []
			{
				console::info("[IWZ][Usermaps] %zu installed map(s)\n", get_maps().size());
				for (const auto& map : get_maps())
					console::info("  %s - %s (author=%s version=%s)\n    %s\n", map.name.c_str(), map.title.c_str(),
						map.author.c_str(), map.version.c_str(), map.path.generic_string().c_str());
			});
		}
	};
}

REGISTER_COMPONENT(usermaps::component)
