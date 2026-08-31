#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "command.hpp"
#include "scheduler.hpp"

#include "console/console.hpp"
#include "game/game.hpp"
#include "game/scripting/execution.hpp"

namespace crosshair_coordinates
{
	namespace
	{
		int find_local_client()
		{
			for (unsigned int client_num = 0; client_num < *game::svs_numclients; ++client_num)
			{
				if (game::SV_IsLocalClient(static_cast<int>(client_num)))
				{
					return static_cast<int>(client_num);
				}
			}

			return -1;
		}

		void print_coordinates()
		{
			const auto client_num = find_local_client();
			if (client_num < 0)
			{
				console::warn("[IWZ][CrosshairCoords] No local player was found\n");
				return;
			}

			try
			{
				const game::scr_entref_t player_ref{
					static_cast<unsigned short>(client_num), 0
				};
				const scripting::entity player(player_ref);
				if (!player.get_entity_id())
				{
					console::warn("[IWZ][CrosshairCoords] Local client %d has no script entity\n", client_num);
					return;
				}

				console::info("[IWZ][CrosshairCoords] Tracing for local client %d (script entity %u)\n",
					client_num, player.get_entity_id());
				scripting::call_script_function(player, "custom_scripts/cp/gsc_diagnostics",
					"print_crosshair_coordinates", {});
			}
			catch (const std::exception& error)
			{
				console::error("[IWZ][CrosshairCoords] Trace failed: %s\n", error.what());
			}
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			command::add("crosshaircoords", [](const command::params&)
			{
				if (!game::SV_Loaded() || game::Com_FrontEnd_IsInFrontEnd())
				{
					console::warn("[IWZ][CrosshairCoords] Start a match before using crosshaircoords\n");
					return;
				}

				scheduler::once(print_coordinates, scheduler::pipeline::server);
			});
		}
	};
}

REGISTER_COMPONENT(crosshair_coordinates::component)
