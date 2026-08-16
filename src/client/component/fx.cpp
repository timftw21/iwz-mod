#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "component/console/console.hpp"
#include "component/gsc/script_extension.hpp"

#include "game/game.hpp"

#include <utils/hook.hpp>

namespace fx
{
	namespace
	{
		constexpr auto trailblazer_fx_name = "vfx/iw7/core/zombie/vfx_zmb_fire_trail_1st";
		constexpr auto trailblazer_emission_end = 0.6f;
		constexpr game::ParticleFloatRange trailblazer_particle_life{0.35f, 0.4f};

		bool nearly_equal(const float first, const float second)
		{
			return std::abs(first - second) < 0.001f;
		}

		bool range_matches(const game::ParticleFloatRange& range, const float minimum, const float maximum)
		{
			return nearly_equal(range.min, minimum) && nearly_equal(range.max, maximum);
		}

		game::ParticleSystemDef* find_trailblazer_fx()
		{
			return game::DB_FindXAssetHeader(game::ASSET_TYPE_VFX, trailblazer_fx_name, false).vfx;
		}

		bool emitter_is_already_patched(const game::ParticleEmitterDef& emitter,
			const float minimum_spawn_rate, const float maximum_spawn_rate)
		{
			return range_matches(emitter.particleSpawnRate, minimum_spawn_rate, maximum_spawn_rate) &&
				range_matches(emitter.particleLife, trailblazer_particle_life.min, trailblazer_particle_life.max) &&
				range_matches(emitter.emitterLife, trailblazer_emission_end, trailblazer_emission_end);
		}

		bool emitter_matches_stock(const game::ParticleEmitterDef& emitter,
			const float minimum_spawn_rate, const float maximum_spawn_rate,
			const float minimum_particle_life, const float maximum_particle_life)
		{
			return emitter.flags == 0 &&
				range_matches(emitter.particleSpawnRate, minimum_spawn_rate, maximum_spawn_rate) &&
				range_matches(emitter.particleLife, minimum_particle_life, maximum_particle_life) &&
				range_matches(emitter.emitterLife, 0.0f, 0.0f);
		}

		void patch_emitter(game::ParticleEmitterDef& emitter,
			const float minimum_spawn_rate, const float maximum_spawn_rate)
		{
			emitter.particleSpawnRate = {minimum_spawn_rate, maximum_spawn_rate};
			emitter.particleLife = trailblazer_particle_life;
			emitter.emitterLife = {trailblazer_emission_end, trailblazer_emission_end};
		}

		bool patch_trailblazer_fx()
		{
			auto* particle_system = find_trailblazer_fx();
			if (!particle_system)
			{
				console::warn("[IWZ][TrailblazerFX] first-person VFX asset is not loaded; finite timeline not installed\n");
				return false;
			}

			if (!particle_system->emitterDefs || particle_system->numEmitters != 5)
			{
				console::warn("[IWZ][TrailblazerFX] asset validation failed name='%s' emitters=%d; finite timeline not installed\n",
					particle_system->name ? particle_system->name : "<unnamed>", particle_system->numEmitters);
				return false;
			}

			auto& smoke_left = particle_system->emitterDefs[0];
			auto& flame = particle_system->emitterDefs[1];
			auto& smoke_right = particle_system->emitterDefs[2];

			if (emitter_is_already_patched(smoke_left, 10.0f, 15.0f) &&
				emitter_is_already_patched(flame, 22.0f, 28.0f) &&
				emitter_is_already_patched(smoke_right, 10.0f, 15.0f))
			{
				console::info("[IWZ][TrailblazerFX] finite first-person flame timeline already installed\n");
				return true;
			}

			if (!emitter_matches_stock(smoke_left, 4.0f, 6.0f, 0.85f, 1.0f) ||
				!emitter_matches_stock(flame, 14.0f, 18.0f, 0.54f, 0.62f) ||
				!emitter_matches_stock(smoke_right, 4.0f, 6.0f, 0.85f, 1.0f))
			{
				console::warn("[IWZ][TrailblazerFX] stock emitter validation failed; finite timeline not installed\n");
				return false;
			}

			// These emitters originally run until the GSC entity is deleted at 1.0 second. Ending emission
			// at 0.6 seconds lets their existing per-particle alpha curves reach zero by that same deadline.
			// Spawn rates are adjusted to retain the stock effect's approximate peak particle density.
			patch_emitter(smoke_left, 10.0f, 15.0f);
			patch_emitter(flame, 22.0f, 28.0f);
			patch_emitter(smoke_right, 10.0f, 15.0f);

			console::info("[IWZ][TrailblazerFX] installed finite first-person flame timeline emissionEnd=%.2fs particleLife=%.2f..%.2fs total=1.00s emitters=0,1,2\n",
				trailblazer_emission_end, trailblazer_particle_life.min, trailblazer_particle_life.max);
			return true;
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			// skip "fx/" and "vfx/" name prefix checks
			utils::hook::set<uint8_t>(0x140B34889, 0xEB); // Scr_LoadFx
			utils::hook::nop(0x140D0FBFD, 2); // ParticleSystem_Register

			gsc::function::add("iwz_patch_trailblazer_fx", [](const gsc::function_args&)
			{
				return patch_trailblazer_fx() ? 1 : 0;
			});
		}
	};
}

REGISTER_COMPONENT(fx::component)
