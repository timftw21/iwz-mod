#pragma once

namespace database
{
	struct SndBank;
}

namespace fastfiles
{
	using sound_bank_load_callback = std::function<void(database::SndBank*)>;

	std::string get_current_fastfile();
	bool exists(const std::string& zone);
	void on_sound_bank_loaded(sound_bank_load_callback callback);
}
