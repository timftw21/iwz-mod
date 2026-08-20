#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "component/console/console.hpp"
#include "game/game.hpp"

#include <utils/hook.hpp>
#include <utils/string.hpp>

namespace branding
{
	namespace
	{
		constexpr auto display_version = "IWZ-MOD 0.1";
		utils::hook::detour ui_get_formatted_build_number_hook;
		const char* ui_get_formatted_build_number_stub()
		{
			static std::array<char, 0x100> buf {};
			static bool once = ([]()
			{
				const char* build_num = ui_get_formatted_build_number_hook.invoke<const char*>();
				utils::string::copy(buf, utils::string::va("%s (%s)", display_version, build_num));
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
			console::info("[IWZ][Branding] installed UI version label='%s'\n", display_version);
		}
	};
}

REGISTER_COMPONENT(branding::component)
