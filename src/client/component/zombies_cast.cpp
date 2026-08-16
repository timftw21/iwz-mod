#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "component/gsc/script_extension.hpp"

#include "zombies_cast.hpp"

namespace zombies_cast
{
	namespace
	{
		std::atomic<int> selected_character{0};
	}

	int get_selection()
	{
		return selected_character.load(std::memory_order_relaxed);
	}

	void set_selection(const int selection)
	{
		selected_character.store(selection >= 0 && selection <= 9 ? selection : 0,
			std::memory_order_relaxed);
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			gsc::function::add("iwz_get_zombies_character_selection", [](const gsc::function_args&)
			{
				return get_selection();
			});
		}
	};
}

REGISTER_COMPONENT(zombies_cast::component)
