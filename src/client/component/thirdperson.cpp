#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"
#include "game/dvars.hpp"

#include "console/console.hpp"
#include "dvars.hpp"
#include "scheduler.hpp"

#include <utils/hook.hpp>

namespace thirdperson
{
	namespace
	{
		constexpr auto entitynum_none = 0x7FF;
		constexpr auto weapon_position_fraction_offset = offsetof(game::cg_s, predictedPlayerState) +
			offsetof(game::playerState_s, fWeaponPosFrac);

		void sync_stock_third_person(const bool enabled, const char* reason, const bool log_unchanged = false)
		{
			auto* const camera_third_person = game::Dvar_FindVar("camera_thirdPerson");
			if (!camera_third_person)
			{
				static bool warned = false;
				if (!warned)
				{
					console::warn("[IWZ][Camera] camera_thirdPerson is not registered; stock camera sync deferred\n");
					warned = true;
				}
				return;
			}

			if (camera_third_person->current.enabled == enabled)
			{
				if (log_unchanged)
				{
					console::info("[IWZ][Camera] stock camera already synchronized enabled=%d reason=%s\n",
						enabled, reason);
				}
				return;
			}

			game::Dvar_SetFromStringFromSource(camera_third_person, enabled ? "1" : "0",
				game::DvarSetSource::DVAR_SOURCE_INTERNAL);
			console::info("[IWZ][Camera] synchronized camera_thirdPerson enabled=%d reason=%s applied=%d\n",
				enabled, reason, camera_third_person->current.enabled);
		}

		void* cg_offset_third_person_view_stub()
		{
			return utils::hook::assemble([](utils::hook::assembler& a)
			{
				a.push(rax);

				a.mov(rax, qword_ptr(reinterpret_cast<int64_t>(&dvars::cg_thirdPersonAngle)));
				a.movss(xmm11, dword_ptr(rax, 0x10));

				a.mov(rax, qword_ptr(reinterpret_cast<int64_t>(&dvars::cg_thirdPersonRange)));
				a.movss(xmm10, dword_ptr(rax, 0x10));

				a.pop(rax);

				// original code

				a.mulss(xmm7, xmm0);
				a.mulss(xmm6, xmm0);
				a.addss(xmm7, qword_ptr(rdi));

				a.jmp(0x140274596);
			});
		}

		void* cg_offset_chase_cam_view_stub()
		{
			return utils::hook::assemble([](utils::hook::assembler& a)
			{
				a.push(rax);

				a.mov(rax, qword_ptr(reinterpret_cast<int64_t>(&dvars::cg_thirdPersonAngle)));
				a.movss(xmm8, dword_ptr(rax, 0x10));

				a.mov(rax, qword_ptr(reinterpret_cast<int64_t>(&dvars::cg_thirdPersonRange)));
				a.movss(xmm7, dword_ptr(rax, 0x10));
				
				a.pop(rax);

				// original code

				a.mulss(xmm2, xmm2);
				a.mulss(xmm3, xmm3);
				a.addss(xmm2, xmm3);

				a.jmp(0x140272069);
			});
		}

		void* cg_draw_crosshair_third_person_stub()
		{
			return utils::hook::assemble([](utils::hook::assembler& a)
			{
				const auto stock_behavior = a.newLabel();
				const auto draw_crosshair = a.newLabel();
				const auto suppress_menu_crosshair = a.newLabel();
				const auto suppress_crosshair = a.newLabel();

				// CG_DrawCrosshair normally suppresses the reticle whenever renderingThirdPerson is set and
				// no remote-view entity is active. For the menu camera, bypass that guard only while ADS.
				a.push(rax);
				a.mov(rax, qword_ptr(reinterpret_cast<int64_t>(&dvars::cg_thirdPerson)));
				a.test(rax, rax);
				a.jz(stock_behavior);
				a.cmp(byte_ptr(rax, 0x10), 0);
				a.jz(stock_behavior);
				a.cmp(dword_ptr(rdi, weapon_position_fraction_offset), 0);
				a.jz(suppress_menu_crosshair);
				a.pop(rax);
				a.jmp(draw_crosshair);

				a.bind(suppress_menu_crosshair);
				a.pop(rax);
				a.jmp(0x140790A84);

				a.bind(stock_behavior);
				a.pop(rax);
				a.cmp(dword_ptr(rdi, offsetof(game::cg_s, renderingThirdPerson)), 0);
				a.jz(draw_crosshair);
				a.cmp(dword_ptr(rdi, 0xEC), entitynum_none);
				a.jz(suppress_crosshair);

				a.bind(draw_crosshair);
				a.jmp(0x140790647);

				a.bind(suppress_crosshair);
				a.jmp(0x140790A84);
			});
		}

		void* cg_load_crosshair_weapon_position_fraction_stub()
		{
			return utils::hook::assemble([](utils::hook::assembler& a)
			{
				const auto stock_behavior = a.newLabel();

				// The stock crosshair fades away as fWeaponPosFrac rises. The preceding gate already used
				// the real fraction to make this an ADS-only reticle, so render it at full hip-reticle alpha.
				a.push(rax);
				a.mov(rax, qword_ptr(reinterpret_cast<int64_t>(&dvars::cg_thirdPerson)));
				a.test(rax, rax);
				a.jz(stock_behavior);
				a.cmp(byte_ptr(rax, 0x10), 0);
				a.jz(stock_behavior);
				a.pop(rax);
				a.xorps(xmm10, xmm10);
				a.jmp(0x1407906EA);

				a.bind(stock_behavior);
				a.pop(rax);
				a.movss(xmm10, dword_ptr(rdi, weapon_position_fraction_offset));
				a.jmp(0x1407906EA);
			});
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (game::environment::is_dedi())
			{
				return;
			}

			scheduler::once([]()
			{
				// cp_globallogic copies scr_thirdPerson to camera_thirdPerson at map startup. Keep the saved
				// preference separate, then synchronize it internally so the stock shoulder camera is used.
				dvars::cg_thirdPerson = game::Dvar_RegisterBool("cg_thirdPerson", false, game::DVAR_FLAG_SAVED,
					"Use third person view");

				dvars::cg_thirdPersonAngle = game::Dvar_RegisterFloat("cg_thirdPersonAngle", 356.0f, -180.0f, 360.0f, game::DVAR_FLAG_CHEAT,
					"The angle of the camera from the player in third person view");

				dvars::cg_thirdPersonRange = game::Dvar_RegisterFloat("cg_thirdPersonRange", 120.0f, 0.0f, 1024, game::DVAR_FLAG_CHEAT,
					"The range of the camera from the player in third person view");

				console::info("[IWZ][Camera] registered cg_thirdPerson enabled=%d saved=1 angle=%.1f range=%.1f\n",
					dvars::cg_thirdPerson->current.enabled, dvars::cg_thirdPersonAngle->current.value,
					dvars::cg_thirdPersonRange->current.value);
				sync_stock_third_person(dvars::cg_thirdPerson->current.enabled, "initialization", true);
			}, scheduler::main);

			dvars::callback::on_new_value("cg_thirdPerson", [](game::DvarValue* value)
			{
				console::info("[IWZ][Camera] cg_thirdPerson changed enabled=%d perspective=%s\n", value->enabled,
					value->enabled ? "third-person" : "first-person");
				sync_stock_third_person(value->enabled, "preference-change");
			});

			// Zombies scripts can overwrite camera_thirdPerson during map initialization. Reapply only
			// when it diverges from the saved preference; the normal per-frame camera path remains stock.
			scheduler::loop([]()
			{
				if (dvars::cg_thirdPerson)
				{
					sync_stock_third_person(dvars::cg_thirdPerson->current.enabled, "script-reset");
				}
			}, scheduler::main, 100ms);

			utils::hook::jump(0x14027205D, cg_offset_chase_cam_view_stub(), true);
			utils::hook::jump(0x14027458A, cg_offset_third_person_view_stub(), true);

			utils::hook::nop(0x14079062E, 25);
			utils::hook::jump(0x14079062E, cg_draw_crosshair_third_person_stub(), true);
			utils::hook::nop(0x1407906E1, 9);
			utils::hook::jump(0x1407906E1, cg_load_crosshair_weapon_position_fraction_stub());
			console::info("[IWZ][Camera] installed ADS-only third-person crosshair support respectCgDrawCrosshair=1\n");
		}
	};
}

REGISTER_COMPONENT(thirdperson::component)
