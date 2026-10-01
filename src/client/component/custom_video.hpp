#pragma once

#include <string>
#include <vector>

namespace custom_video
{
	struct file
	{
		std::string id;
		std::string name;
		std::string extension;
	};
	int rescan();
	std::vector<file> list();
	std::string folder();
	std::string selected();
	std::string status();
	bool play(const std::string& id);
	void clear();
	bool open_folder();
}
