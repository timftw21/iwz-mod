#pragma once

namespace usermaps
{
	struct map_info
	{
		std::string name;
		std::string title;
		std::string description;
		std::string author;
		std::string version;
		std::filesystem::path path;
		std::vector<std::string> dependencies;
	};

	void initialize();
	const std::vector<map_info>& get_maps();
	const map_info* find(const std::string& name);
	bool find_file(const std::string& filename, std::string* path);
	bool zone_exists(const std::string& name);
	void set_script_map(const char* name);
	std::string get_script_path();
}
