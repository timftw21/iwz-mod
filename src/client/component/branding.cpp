#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "component/console/console.hpp"
#include "game/game.hpp"
#include <version.hpp>

#include <utils/hook.hpp>
#include <utils/string.hpp>

namespace branding
{
	namespace
	{
		const auto display_version = []
		{
			std::string version = SHORTVERSION;
			if (version.ends_with(".0"))
				version.resize(version.size() - 2);
			return "IWZ-MOD " + version;
		}();
		utils::hook::detour ui_get_formatted_build_number_hook;
		const char* ui_get_formatted_build_number_stub()
		{
			static std::array<char, 0x100> buf {};
			static bool once = ([]()
			{
				const char* build_num = ui_get_formatted_build_number_hook.invoke<const char*>();
				utils::string::copy(buf, utils::string::va("%s (%s)", display_version.c_str(), build_num));
				return true;
			})();

			return buf.data();
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

			ui_get_formatted_build_number_hook.create(0x140CD1170, ui_get_formatted_build_number_stub);
			console::info("[IWZ][Branding] installed UI version label='%s' release='%s'\n",
				display_version.c_str(), SHORTVERSION);
		}
	};
}

REGISTER_COMPONENT(branding::component)
