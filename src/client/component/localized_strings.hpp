#pragma once

namespace localized_strings
{
	const char* lookup(const char* reference);
	std::optional<std::string> colorize_key_bindings(std::string_view value);
	bool override_asset(const std::string& key, const std::string& value);
	void override(const std::string& key, const std::string& value);
}
