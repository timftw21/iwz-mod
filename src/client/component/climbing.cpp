#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "console/console.hpp"
#include "game/game.hpp"

#include <utils/hook.hpp>

namespace climbing
{
	namespace
	{
		constexpr auto pm_ladder_pitch_clamp = 0x1406FD172;
		constexpr auto pm_ladder_pitch_clamp_end = 0x1406FD184;
		constexpr auto pm_ladder_cmd_scale_call = 0x1406FD227;
		constexpr auto pm_cmd_scale = 0x1406F9130;

		bool is_zombies()
		{
			return game::Com_GameMode_GetActiveGameMode() == game::GAME_MODE_CP;
		}

		float pm_ladder_cmd_scale_stub(void* ps, void* cmd)
		{
			const auto scale = utils::hook::invoke<float>(pm_cmd_scale, ps, cmd);
			return is_zombies() ? scale * 3.5f : scale;
		}

		void* pm_ladder_pitch_stub()
		{
			return utils::hook::assemble([](utils::hook::assembler& a)
			{
				const auto stock_pitch = a.newLabel();
				const auto pitch_ready = a.newLabel();

				a.pushad64();
				a.call_aligned(is_zombies);
				a.test(al, al);
				a.jz(stock_pitch);

				// Make forward/back movement select the climbing direction without
				// deriving its magnitude from the player's view pitch.
				a.mov(eax, 0x3F800000);
				a.movd(xmm6, eax);
				a.popad64();
				a.jmp(pitch_ready);

				a.bind(stock_pitch);
				// Reproduce the stock [-1, 1] pitch clamp outside Zombies.
				a.mov(eax, 0xBF800000);
				a.movd(xmm0, eax);
				a.popad64();
				a.comiss(xmm6, xmm7);
				const auto lower_clamp = a.newLabel();
				a.jbe(lower_clamp);
				a.movaps(xmm6, xmm7);
				a.jmp(pitch_ready);
				a.bind(lower_clamp);
				a.maxss(xmm6, xmm0);

				a.bind(pitch_ready);
				a.jmp(pm_ladder_pitch_clamp_end);
			});
		}

		bool validate_patch_sites()
		{
			constexpr std::array<std::uint8_t, 18> pitch_bytes{
				0x0F, 0x2F, 0xF7, 0x76, 0x05, 0x0F, 0x28, 0xF7, 0xEB,
				0x08, 0xF3, 0x0F, 0x5F, 0x35, 0xB8, 0xC6, 0xD3, 0x00,
			};
			constexpr std::array<std::uint8_t, 5> cmd_scale_call_bytes{0xE8, 0x04, 0xBF, 0xFF, 0xFF};

			return std::memcmp(reinterpret_cast<const void*>(pm_ladder_pitch_clamp),
				pitch_bytes.data(), pitch_bytes.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(pm_ladder_cmd_scale_call),
					cmd_scale_call_bytes.data(), cmd_scale_call_bytes.size()) == 0;
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (!validate_patch_sites())
			{
				console::error("[IWZ][ClimbingNative] ladder patch validation failed; changes disabled\n");
				return;
			}

			constexpr auto pitch_clamp_size = pm_ladder_pitch_clamp_end - pm_ladder_pitch_clamp;
			utils::hook::nop(pm_ladder_pitch_clamp, pitch_clamp_size);
			utils::hook::jump(pm_ladder_pitch_clamp, pm_ladder_pitch_stub(), true, true);
			utils::hook::call(pm_ladder_cmd_scale_call, pm_ladder_cmd_scale_stub);

			console::info("[IWZ][ClimbingNative] installed pitch-independent 3.5x ladder movement\n");
		}
	};
}

REGISTER_COMPONENT(climbing::component)
