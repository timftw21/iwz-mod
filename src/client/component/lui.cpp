#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"
#include "game/dvars.hpp"

#include "command.hpp"
#include "console/console.hpp"

#include <utils/hook.hpp>
#include <utils/string.hpp>

namespace lui
{
	namespace
	{
		template<bool DrawStage>
		int attack_world_text_font_size(const float* top, const float* bottom)
		{
			const auto size = utils::hook::invoke<int>(0x140E32960, top, bottom);
			const auto* world = *game::g_world;
			if (size != 0 || !world || !world->name ||
				std::strcmp(world->name, "maps/cp/cp_town.d3dbsp") != 0)
			{
				return size;
			}

			// The world-text path rounds the projected height to a multiple of
			// twelve, then rejects zero. Chemistry labels consequently vanish
			// below six screen pixels while their adjacent UI icons still draw.
			// Keep the smallest raster font; the original world quad still sets
			// the displayed size, position, perspective and depth testing.
			static std::atomic_uint logged{0};
			if (logged.load(std::memory_order_relaxed) < 3 &&
				logged.fetch_add(1, std::memory_order_relaxed) < 3)
			{
				console::info("[IWZ][AttackBoardText] stage=%s retained distant world text rasterFont=0->12; world geometry unchanged\n",
					DrawStage ? "draw" : "layout");
			}
			return 12;
		}
	}

	void print_debug_lui(const char* msg, ...)
	{
		char buffer[0x1000]{ 0 };

		va_list ap;
		va_start(ap, msg);

		vsnprintf_s(buffer, sizeof(buffer), _TRUNCATE, msg, ap);

		va_end(ap);

		const auto lower_message = utils::string::to_lower(buffer);
		const auto is_error = lower_message.find("error") != std::string::npos ||
			lower_message.find("assert") != std::string::npos ||
			lower_message.find("stack traceback") != std::string::npos ||
			lower_message.find("failed") != std::string::npos;

		// Runtime LUI failures must remain visible in release logs even when the
		// verbose developer stream is disabled. The old console::debug call was
		// compiled out of release builds, leaving recovery loops without a cause.
		if (is_error)
		{
			console::error("[IWZ][LUI][Engine] %s", buffer);
		}
		else if (dvars::lui_debug && dvars::lui_debug->current.enabled)
		{
			console::info("[IWZ][LUI][Engine] %s", buffer);
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

			dvars::lui_debug = game::Dvar_RegisterBool("lui_debug", false, game::DvarFlags::DVAR_FLAG_SAVED,
				"Print LUI DebugPrint to console. (DEV)");

			// LUI_Interface_DebugPrint
			utils::hook::jump(0x14061C430, print_debug_lui);

			// World text computes this independently during layout AND drawing.
			// Fixing layout alone still lets the draw path reject the same text
			// at 0x140E323A7. Screen HUD font sizing is not changed.
			utils::hook::call(0x140613C16, attack_world_text_font_size<false>);
			utils::hook::call(0x140E3238F, attack_world_text_font_size<true>);

			command::add("luiOpenMenu", [](const command::params& params)
			{
				if (params.size() == 2)
				{
					game::LUI_OpenMenu(0, params.get(1), 0, 0, 0);
				}
				else
				{
					auto command = params.get(0);
					console::error("Incorrect number of arguments for \"%s\".\n", command);
				}
			});

			command::add("luiOpenPopup", [](const command::params& params)
			{
				if (params.size() == 2)
				{
					game::LUI_OpenMenu(0, params.get(1), 1, 0, 0);
				}
				else
				{
					auto command = params.get(0);
					console::error("Incorrect number of arguments for \"%s\".\n", command);
				}
			});

			command::add("luiOpenModalPopup", [](const command::params& params)
			{
				if (params.size() == 2)
				{
					game::LUI_OpenMenu(0, params.get(1), 1, 1, 0);
				}
				else
				{
					auto command = params.get(0);
					console::error("Incorrect number of arguments for \"%s\".\n", command);
				}
			});


			command::add("luiLeaveMenu", [](const command::params& params)
			{
				if (params.size() == 2)
				{
					game::LUI_CloseMenu(0, params.get(1), 0);
				}
				else
				{
					auto command = params.get(0);
					console::error("Incorrect number of arguments for \"%s\".\n", command);
				}
			});

			command::add("luiCloseAll", []()
			{
				game::LUI_CoD_CLoseAll(0);
			});

			command::add("luiReload", []()
			{
				game::CL_Keys_RemoveCatcher(0, -65);
				game::LUI_CoD_Shutdown();
				game::LUI_CoD_Init(game::Com_FrontEnd_IsInFrontEnd(), false);
			});

			command::add("runMenuScript", [](const command::params& params) 
			{
				const auto args_str = params.join(1);
				const auto* args = args_str.data();
				game::UI_RunMenuScript(0, &args);
			});
		}
	};
}

REGISTER_COMPONENT(lui::component)
