#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "version.hpp"

#include "game/game.hpp"

#include <utils/hook.hpp>
#include <utils/string.hpp>

namespace branding
{
	namespace
	{
		utils::hook::detour ui_get_formatted_build_number_hook;
		const char* ui_get_formatted_build_number_stub()
		{
			static std::array<char, 0x100> buf {};
			static bool once = ([]()
			{
				const char* build_num = ui_get_formatted_build_number_hook.invoke<const char*>();
				utils::string::copy(buf, utils::string::va("%s (%s)", VERSION, build_num));
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
		}
	};
}

REGISTER_COMPONENT(branding::component)
