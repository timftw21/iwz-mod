#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "console/console.hpp"
#include "shader_preload.hpp"
#include <utils/hook.hpp>

namespace shader_preload
{
	namespace
	{
		combination_cache combinations;
		std::uint64_t lookups{};
		std::uint64_t reused{};
		bool capacity_logged{};

		bool find_combination(const std::uint64_t key)
		{
			// Like the native table, this is exclusively owned by the warm-draw
			// render path. Keep its count visible and honor any native reset.
			auto& native_count = *reinterpret_cast<int*>(0x141D4A0E0);
			if (native_count == 0 && combinations.size() != 0)
			{
				console::info("[IWZ][ShaderPreload] combination reset unique=%zu lookups=%llu reused=%llu\n",
					combinations.size(), lookups, reused);
				combinations.clear();
				lookups = reused = 0;
				capacity_logged = false;
			}
			const auto found = combinations.contains_or_insert(key);
			++lookups;
			reused += found;
			native_count = static_cast<int>(combinations.size());
			if (!capacity_logged && combinations.size() == combination_cache::limit)
			{
				capacity_logged = true;
				console::info("[IWZ][ShaderPreload] combination cache full unique=%zu; additional combinations warm normally\n",
					combinations.size());
			}
			return found;
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (game::environment::is_dedi()) return;
			// Replaces the stock binary-search/memmove table; preserves the stock
			// combination identity, capacity, pass eligibility and GPU completion.
			utils::hook::jump(0x1400BE380, find_combination);
			console::info("[IWZ][ShaderPreload] bounded combination hash cache installed bytes=%zu limit=%zu\n",
				sizeof(combinations), combination_cache::limit);
		}

		void pre_destroy() override
		{
			if (lookups)
				console::info("[IWZ][ShaderPreload] combinations unique=%zu lookups=%llu reused=%llu\n",
					combinations.size(), lookups, reused);
		}
	};
}

REGISTER_COMPONENT(shader_preload::component)
