#pragma once

namespace custom_music
{
	int rescan();
	int count();
	std::string get_name(int index);
	std::string get_extension(int index);
	std::string get_folder();
	std::string get_selected_name();
	int get_selected_index();
	bool play(int index);
	bool resume();
	bool is_playing();
	struct dj_track_info { int sequence; std::string title; };
	dj_track_info get_dj_track();
	void fade_out();
	bool claim(const std::string& reason);
	void release(const std::string& reason);
	bool is_claimed();
	bool is_lobby_session_active();
	void set_frontend_scene(const std::string& section_name);
	bool open_folder();
	void stop(bool clear_selection, const char* reason);
}
