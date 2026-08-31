#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"
#include "game/dvars.hpp"

#include "console/console.hpp"
#include "dvars.hpp"
#include "scheduler.hpp"
#include "thirdperson.hpp"

#include <utils/hook.hpp>

namespace ui
{
	namespace
	{
		utils::hook::detour cg_draw2d_hook;
		game::dvar_t* zombies_hud = nullptr;

		void cg_draw2d_stub(__int64 a1)
		{
			if (dvars::cg_draw2D && !dvars::cg_draw2D->current.enabled)
			{
				return;
			}
			
			cg_draw2d_hook.invoke<void>(a1);

			// CG_Draw2D's draw-system object stores localClientNum at +8. Preserve the same
			// client that stock HUD rendering just used when resolving its cgame globals.
			const auto local_client_num = *reinterpret_cast<const int*>(a1 + 8);
			thirdperson::draw_reticle(local_client_num);
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
				dvars::cg_draw2D = game::Dvar_RegisterBool("cg_draw2D", true, game::DVAR_FLAG_NONE,
					"Draw 2D screen elements");
				zombies_hud = game::Dvar_RegisterBool("iwz_zombies_hud", true, game::DVAR_FLAG_SAVED,
					"Draw the standard in-game Zombies HUD");
				const auto in_game_timer = game::Dvar_RegisterBool("iwz_in_game_timer", false, game::DVAR_FLAG_SAVED,
					"Draw an elapsed match timer using the Zombies Boss Battle HUD widget");
				console::info("[IWZ][HUD] registered iwz_zombies_hud enabled=%d iwz_in_game_timer=%d saved=1 stockCgDraw2D=%d\n",
					zombies_hud->current.enabled, in_game_timer->current.enabled, dvars::cg_draw2D->current.enabled);
			}, scheduler::main);

			dvars::callback::on_new_value("iwz_zombies_hud", [](game::DvarValue* value)
			{
				console::info("[IWZ][HUD] iwz_zombies_hud changed enabled=%d mode=%s\n", value->enabled,
					value->enabled ? "standard" : "no_hud");
			});

			dvars::callback::on_new_value("iwz_in_game_timer", [](game::DvarValue* value)
			{
				console::info("[IWZ][InGameTimer] iwz_in_game_timer changed enabled=%d\n", value->enabled);
			});

			cg_draw2d_hook.create(0x140781D90, cg_draw2d_stub);
		}
	};
}

REGISTER_COMPONENT(ui::component)
