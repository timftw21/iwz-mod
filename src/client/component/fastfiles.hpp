#pragma once

namespace database
{
	struct LocalizeEntry;
	struct SndBank;
	struct WeaponCompleteDef;
}

namespace fastfiles
{
	using localize_load_callback = std::function<void(database::LocalizeEntry*)>;
	using sound_bank_load_callback = std::function<void(database::SndBank*)>;
	using weapon_load_callback = std::function<void(database::WeaponCompleteDef*)>;

	std::string get_current_fastfile();
	bool exists(const std::string& zone);
	void on_localize_loaded(localize_load_callback callback);
	void on_sound_bank_loaded(sound_bank_load_callback callback);
	void on_weapon_loaded(weapon_load_callback callback);
}
