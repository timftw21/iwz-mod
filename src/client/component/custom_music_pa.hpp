#pragma once

#include "game/game.hpp"

namespace custom_music::pa
{
	// One immutable source is retained until the game's decoder releases it.
	struct track
	{
		std::vector<std::uint8_t> frames;
		std::uint32_t frame_count{};
		std::atomic_bool cancelled{};
		std::atomic_bool ready{};
		std::atomic_bool failed{};
		game::SndAlias alias{};
		game::SndAliasList aliases{};
		game::SndAssetBankEntry entry{};
		int voice{-1};
		unsigned int playback_id{};
		std::uintptr_t source{};
		float volume{-1.0f};
	};

	// Fixed 48 kHz, stereo, signed 16-bit PCM; blocks contain at most 1024 frames.
	void append_pcm(track& output, const std::int16_t* samples, unsigned int count);
	bool initialize();
	bool play(track& audio, float volume);
	bool is_playing(const track& audio);
	void set_volume(track& audio, float volume);
	void retire(std::shared_ptr<track> audio);
	void collect();
}
