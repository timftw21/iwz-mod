#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"

#include <utils/hook.hpp>

#include "utils/flags.hpp"

namespace intro
{
	namespace
	{
		game::dvar_t* skip_intro_cinematics;

		bool is_intro_cinematic(const char* name)
		{
			if (!name)
			{
				return false;
			}

			const std::string_view cinematic_name{name};
			return cinematic_name == "startup" || cinematic_name == "default" ||
				cinematic_name.ends_with("startup.bik") || cinematic_name.ends_with("default.bik");
		}

		void cinematic_start_playback(const char* name, const int playbackFlags, const int startOffsetMsec, 
			const bool fillerBink, const int pauseState)
		{
			if (is_intro_cinematic(name))
			{
				if (utils::flags::has_flag("nointro"))
				{
					return;
				}

				if (skip_intro_cinematics && skip_intro_cinematics->current.enabled)
				{
					return;
				}
				
				const auto* intro_dvar = game::Dvar_FindVar("intro");
				if (intro_dvar && !intro_dvar->current.enabled)
				{
					return;
				}
			}

			utils::hook::invoke<void>(0x140DD6A10, name, playbackFlags, startOffsetMsec, fillerBink, pauseState);
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			skip_intro_cinematics = game::Dvar_RegisterBool("iwz_skip_intro_cinematics", false,
				game::DVAR_FLAG_SAVED, "Skip the startup intro cinematics");

			utils::hook::call(0x140DD69FF, cinematic_start_playback);
			utils::hook::call(0x140DD69CF, cinematic_start_playback);
		}
	};
}

REGISTER_COMPONENT(intro::component)
