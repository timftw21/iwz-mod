#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "console/console.hpp"
#include "game/game.hpp"
#include "gsc/script_extension.hpp"
#include "scheduler.hpp"

#include <utils/cryptography.hpp>

#include <array>
#include <sstream>

namespace survival_film_records
{
	namespace
	{
		constexpr std::array maps{"cp_zmb", "cp_rave", "cp_disco", "cp_town", "cp_final"};
		constexpr std::array fields{"highestWave", "kills", "rounds", "headshots", "downs", "revives"};
		std::array<std::array<game::dvar_t*, fields.size()>, maps.size()> records{};
		game::dvar_t* incoming = nullptr;
		std::string last_snapshot;
		std::string last_session;
		std::string last_map;
		std::array<int, fields.size()> previous{};

		void save_snapshot()
		{
			const std::string snapshot = incoming->current.string;
			if (snapshot.empty() || snapshot == last_snapshot)
				return;
			last_snapshot = snapshot;

			std::istringstream stream(snapshot);
			std::string session, map, trailing;
			std::array<int, fields.size()> values{};
			bool valid = static_cast<bool>(stream >> session >> map);
			for (auto& value : values)
				valid = static_cast<bool>(stream >> value) && value >= 0 && valid;
			const auto entry = std::ranges::find(maps, map);
			if (!valid || (stream >> trailing) || entry == maps.end())
			{
				console::warn("[IWZ][SurvivalFilms] rejected invalid record snapshot\n");
				return;
			}

			const bool new_session = session != last_session || map != last_map;
			if (new_session)
			{
				previous.fill(0);
				last_session = session;
				last_map = map;
				console::info("[IWZ][SurvivalFilms] saving local records map=%s session=%s\n",
					map.c_str(), session.c_str());
			}

			const bool scene_changed = values[2] > previous[2];
			auto& record = records[static_cast<std::size_t>(entry - maps.begin())];
			for (std::size_t index = 0; index < fields.size(); ++index)
			{
				const auto current = record[index]->current.integer;
				const auto delta = std::max(0, values[index] - previous[index]);
				const auto updated = index == 0 ? std::max(current, values[index]) :
					static_cast<int>(std::min<std::int64_t>(INT_MAX, static_cast<std::int64_t>(current) + delta));
				if (updated != current)
					game::Dvar_SetInt(record[index], updated);
				previous[index] = std::max(previous[index], values[index]);
			}
			if (new_session || scene_changed)
			{
				console::info("[IWZ][SurvivalFilms] saved map=%s highest=%d kills=%d scenes=%d headshots=%d downs=%d revives=%d\n",
					map.c_str(), record[0]->current.integer, record[1]->current.integer,
					record[2]->current.integer, record[3]->current.integer,
					record[4]->current.integer, record[5]->current.integer);
			}
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			gsc::function::add("iwzfilmrecordsession", [](const gsc::function_args&) -> scripting::script_value
			{
				return utils::cryptography::random::get_challenge() + utils::cryptography::random::get_challenge();
			});

			if (game::environment::is_dedi())
				return;

			for (std::size_t map = 0; map < maps.size(); ++map)
			{
				for (std::size_t field = 0; field < fields.size(); ++field)
				{
					const auto name = std::string("iwz_survival_record_") + maps[map] + "_" + fields[field];
					records[map][field] = game::Dvar_RegisterInt(name.c_str(), 0, 0, INT_MAX,
						game::DVAR_FLAG_SAVED, "Persistent Survival Film combat record");
				}
			}
			// String dvars allocate through SL/MT, which is not initialized during
			// post_unpack. Keep saved integers early for config loading, then create
			// the transient string and its reader on the first main-thread frame.
			scheduler::once([]()
			{
				incoming = game::Dvar_RegisterString("iwz_survival_film_snapshot", "", game::DVAR_FLAG_NONE,
					"Current player's cumulative Survival Film match records");
				scheduler::loop(save_snapshot, scheduler::main);
				console::info("[IWZ][SurvivalFilms] initialized snapshot bridge on main scheduler; saved records maps=5 stats=6\n");
			}, scheduler::main);
		}
	};
}

REGISTER_COMPONENT(survival_film_records::component)
