#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "console/console.hpp"

#include "version.hpp"

#include <utils/io.hpp>

namespace updater
{
	namespace
	{
		constexpr auto release_page = "https://github.com/timftw21/iwz-mod/releases/latest";
		constexpr auto updater_log = "iw7-mod/logs/updater.log";

		void log_update_policy()
		{
			const auto message = std::format(
				"[IWZ][Updater] automatic updates disabled build={} reason='inherited IW7-Mod feed is incompatible' "
				"release_page={} timestamp={}\n",
				GIT_DESCRIBE, release_page, std::time(nullptr));

			console::info("%s", message.data());
			if (!utils::io::write_file(updater_log, message, true))
			{
				console::warn("[IWZ][Updater] failed to append policy log '%s'\n", updater_log);
			}
		}
	}

	class component final : public component_interface
	{
	public:
		void post_start() override
		{
			log_update_policy();
		}

		component_priority priority() override
		{
			return component_priority::updater;
		}
	};
}

REGISTER_COMPONENT(updater::component)
