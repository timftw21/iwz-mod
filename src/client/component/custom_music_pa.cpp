#include <std_include.hpp>
#include "custom_music_pa.hpp"
#include "console/console.hpp"
#include <utils/hook.hpp>

namespace custom_music::pa
{
	namespace
	{
		constexpr auto alias_name = "iwz_custom_dj";
		constexpr auto reference_alias = "mus_pa_an_obsession";
		utils::hook::detour setup_source_hook;
		thread_local track* starting_track{};
		std::vector<std::shared_ptr<track>> retired;
		bool available{};

		struct sound_lock
		{
			sound_lock() { utils::hook::invoke<void>(0x140CFE750, 0x2E); }
			~sound_lock() { utils::hook::invoke<void>(0x140CFE7C0, 0x2E); }
		};

		// SND_SetupSound's source fields, verified at 0x140C90BB0 and
		// SD_StartVoice (0x140C75FC0). All other playback parameters remain native.
		struct start_alias_info
		{
			game::SndAlias* alias;
			char parameters[0x50];
			game::SndAssetBankEntry* entry;
			const void* data;
			unsigned int size;
			bool cinematic;
			char padding[3];
			int arcade_channel;
			int file_id;
			bool valid;
		};
		static_assert(offsetof(start_alias_info, entry) == 0x58);
		static_assert(offsetof(start_alias_info, valid) == 0x78);

		bool setup_source(start_alias_info* info)
		{
			const auto* audio = starting_track;
			if (!audio || info->alias != &audio->alias)
			{
				return setup_source_hook.invoke<bool>(info);
			}
			info->entry = const_cast<game::SndAssetBankEntry*>(&audio->entry);
			info->data = audio->frames.data();
			info->size = audio->entry.size;
			info->cinematic = false;
			info->arcade_channel = -1;
			info->file_id = -1;
			info->valid = true;
			return true;
		}

		std::uintptr_t voice_address(const track& audio)
		{
			return 0x147216418ull + static_cast<std::uintptr_t>(audio.voice) * 0x208;
		}

		bool owns_voice(const track& audio)
		{
			return audio.voice >= 0 && audio.voice < 94 && audio.playback_id &&
				*reinterpret_cast<const unsigned int*>(voice_address(audio) + 0x24) == audio.playback_id &&
				*reinterpret_cast<const game::SndAlias* const*>(voice_address(audio) + 0xB8) == &audio.alias &&
				*reinterpret_cast<const int*>(0x1472018C8ull + audio.voice * 4) != 0;
		}

		template <unsigned int Bits, unsigned int Polynomial>
		unsigned int crc(const std::uint8_t* bytes, const std::size_t count)
		{
			unsigned int value{};
			for (std::size_t i = 0; i < count; ++i)
			{
				value ^= static_cast<unsigned int>(bytes[i]) << (Bits - 8);
				for (int bit = 0; bit < 8; ++bit)
					value = (value << 1) ^ ((value & (1u << (Bits - 1))) ? Polynomial : 0);
			}
			return value & ((1u << Bits) - 1);
		}
	}

	void append_pcm(track& output, const std::int16_t* samples, const unsigned int count)
	{
		if (!count || count > 1024 || output.frames.size() > 256ull * 1024 * 1024 - 4120)
			throw std::runtime_error("DJ audio exceeds the 256 MiB per-track buffer limit");

		// RFC 9639 section 9: verbatim FLAC frames. IW's resident sound banks
		// store frames without a FLAC file header (metadata lives in the entry).
		// https://www.rfc-editor.org/rfc/rfc9639.html#section-9
		auto& bytes = output.frames;
		const auto start = bytes.size();
		bytes.insert(bytes.end(), {0xFF, 0xF8, 0x7A, 0x18}); // fixed blocks, 48 kHz, stereo, 16-bit
		const auto number = output.frame_count / 1024;
		if (number < 0x80)
			bytes.push_back(static_cast<std::uint8_t>(number));
		else
		{
			const auto length = number < 0x800 ? 2 : number < 0x10000 ? 3 : 4;
			bytes.push_back(static_cast<std::uint8_t>((0xFFu << (8 - length)) | (number >> (6 * (length - 1)))));
			for (int i = length - 2; i >= 0; --i)
				bytes.push_back(static_cast<std::uint8_t>(0x80 | ((number >> (6 * i)) & 0x3F)));
		}
		bytes.push_back(static_cast<std::uint8_t>((count - 1) >> 8));
		bytes.push_back(static_cast<std::uint8_t>(count - 1));
		bytes.push_back(static_cast<std::uint8_t>(crc<8, 0x07>(bytes.data() + start, bytes.size() - start)));
		for (unsigned int channel = 0; channel < 2; ++channel)
		{
			bytes.push_back(0x02); // verbatim subframe, no wasted bits
			for (unsigned int i = 0; i < count; ++i)
			{
				const auto sample = static_cast<std::uint16_t>(samples[i * 2 + channel]);
				bytes.push_back(static_cast<std::uint8_t>(sample >> 8));
				bytes.push_back(static_cast<std::uint8_t>(sample));
			}
		}
		const auto checksum = crc<16, 0x8005>(bytes.data() + start, bytes.size() - start);
		bytes.push_back(static_cast<std::uint8_t>(checksum >> 8));
		bytes.push_back(static_cast<std::uint8_t>(checksum));
		output.frame_count += count;
	}

	bool initialize()
	{
		// Disable only custom DJ playback if this executable's native API differs.
		constexpr std::uint8_t setup_prologue[]{0x48, 0x89, 0x5C, 0x24, 0x08, 0x57, 0x48, 0x83, 0xEC, 0x20};
		constexpr std::uint8_t play_prologue[]{0x48, 0x8B, 0xC4, 0x48, 0x89, 0x58, 0x10, 0x57};
		available = !std::memcmp(reinterpret_cast<void*>(0x140C90BB0), setup_prologue, sizeof(setup_prologue)) &&
			!std::memcmp(reinterpret_cast<void*>(0x140C976F0), play_prologue, sizeof(play_prologue));
		if (available) setup_source_hook.create(0x140C90BB0, setup_source);
		console::info("[IWZ][CustomMusicDJ] native PA source integration available=%d reference=%s\n",
			available, reference_alias);
		return available;
	}

	bool play(track& audio, const float volume)
	{
		if (!available || audio.frames.empty()) return false;
		const sound_lock lock;
		const auto* reference = utils::hook::invoke<game::SndAliasList*>(0x140CA44C0, reference_alias);
		if (!reference || !reference->head || reference->count < 1)
		{
			console::error("[IWZ][CustomMusicDJ] native PA reference alias unavailable: %s\n", reference_alias);
			return false;
		}
		const auto* globals = *reinterpret_cast<game::SndGlobals**>(0x147209AB8);
		if (!globals || reference->head->flags.channel >= globals->entchannelCount ||
			globals->entchannelInfo[reference->head->flags.channel].spatialType != game::SND_ENTCHAN_TYPE_PA_SPEAKER)
		{
			console::error("[IWZ][CustomMusicDJ] reference alias has no native PA channel\n");
			return false;
		}

		audio.alias = *reference->head;
		audio.alias.aliasName = alias_name;
		audio.alias.assetFileName = alias_name;
		audio.alias.subtitle = nullptr;
		audio.alias.secondaryAliasName = nullptr;
		audio.alias.stopAliasName = nullptr;
		audio.alias.secondaryId = audio.alias.stopAliasID = 0;
		audio.alias.contextType = audio.alias.contextValue = 0;
		audio.alias.id = audio.alias.assetId = utils::hook::invoke<unsigned int>(0x140CBA010, alias_name);
		audio.alias.flags.type = game::SAT_LOADED;
		audio.alias.flags.looping = 0;
		audio.alias.startDelay = 0;
		audio.aliases = {alias_name, audio.alias.id, &audio.alias, 1, 0};
		audio.entry = {};
		audio.entry.id = audio.alias.assetId;
		audio.entry.size = static_cast<unsigned int>(audio.frames.size());
		audio.entry.frameCount = audio.frame_count;
		audio.entry.frameRate = 48000;
		audio.entry.channelCount = 2;
		audio.entry.format = game::SND_ASSET_FORMAT_FLAC;
		const game::vec3_t origin{649.0f, 683.0f, 254.0f}; // cp_zmb.gsc jukebox_start
		const auto handle = utils::hook::invoke<std::uint64_t>(0x140C86660, 0, 2046);
		starting_track = &audio;
		// SND_PlayAlias: stock selection, gain, PA spatialization, filters,
		// reverb, pause, mixer routing and output device all remain in-game.
		audio.playback_id = utils::hook::invoke<unsigned int>(0x140C976F0, &audio.aliases,
			1.0f, 1.0f, 1.0f, handle, &origin, &audio.voice, 0, false, 0);
		starting_track = nullptr;
		if (audio.voice >= 0 && audio.voice < 94)
			audio.source = *reinterpret_cast<std::uintptr_t*>(0x1471EA180ull + audio.voice * 8);
		if (!owns_voice(audio)) return false;
		set_volume(audio, volume);
		const auto* map = *reinterpret_cast<const game::MapEnts* const*>(0x145D5F9D8);
		console::info("[IWZ][CustomMusicDJ] native PA started voice=%d playback=%u channel=%u volmod=%d "
			"aliasGain=%.3f..%.3f range=%.1f..%.1f frames=%u bytes=%zu speakers=%u source=%p\n", audio.voice, audio.playback_id,
			static_cast<unsigned int>(audio.alias.flags.channel), audio.alias.volModIndex, audio.alias.volMin, audio.alias.volMax,
			audio.alias.distMin, audio.alias.distMax, audio.frame_count, audio.frames.size(),
			map ? map->audioPASpeakerCount : 0, reinterpret_cast<void*>(audio.source));
		return true;
	}

	bool is_playing(const track& audio)
	{
		const sound_lock lock;
		return owns_voice(audio);
	}

	void set_volume(track& audio, const float volume)
	{
		const sound_lock lock;
		if (volume == audio.volume || !owns_voice(audio)) return;
		// Only the user's extra custom gain is applied here; native music,
		// playlist, master and PA mix gains are already applied by the game.
		// SND_InitSoundLerp operates on the additional voice gain directly.
		// SND_SetSoundVolume also multiplies by alias gain, which would apply it twice.
		utils::hook::invoke<void>(0x140C9E190, reinterpret_cast<void*>(voice_address(audio) + 0x7C),
			volume, 0.0f, 1.0f, audio.volume < 0.0f || volume == 0.0f ? 0 : 100);
		audio.volume = volume;
		console::info("[IWZ][CustomMusicDJ] native custom gain=%.3f playback=%u\n", volume, audio.playback_id);
	}

	void retire(std::shared_ptr<track> audio)
	{
		audio->cancelled = true;
		retired.push_back(std::move(audio));
	}

	void collect()
	{
		if (retired.empty()) return;
		const sound_lock lock;
		std::erase_if(retired, [](const std::shared_ptr<track>& audio)
		{
			if (owns_voice(*audio)) utils::hook::invoke<void>(0x140CA0DC0, audio->voice);
			// SD_StopVoice releases its decoder asynchronously. A zero source
			// state or a different alias means it no longer references our bytes.
			return !audio->source || !*reinterpret_cast<volatile int*>(audio->source) ||
				*reinterpret_cast<game::SndAlias* volatile*>(audio->source + 0xA0) != &audio->alias;
		});
	}
}
