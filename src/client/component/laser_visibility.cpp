#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "console/console.hpp"
#include "game/game.hpp"

#include <utils/hook.hpp>

#include <bit>

namespace laser_visibility
{
	namespace
	{
		constexpr auto cg_laser_draw_player = 0x1407FAF20;
		constexpr auto cg_get_laser_orient_not_found = 0x1407EF718;
		constexpr auto cg_get_laser_orient_bone_matrix_call = 0x1407EF73E;
		constexpr auto viewmodel_dobj_submission_call = 0x1408D277F;
		constexpr auto viewmodel_laser_draw_call = 0x1408D2938;
		constexpr auto dobj_should_submit = 0x140A80960;
		constexpr auto dobj_get_hierarchy_bits = 0x140D5DA10;
		constexpr auto dobj_get_hide_part_bits = 0x140D624D0;
		constexpr auto cg_dobj_get_world_bone_matrix = 0x140144ED0;

		struct dobj_part_bits
		{
			std::array<std::uint32_t, 8> array{};
		};

		using get_hierarchy_bits_t = void(const void* obj, int bone_index, dobj_part_bits* part_bits);
		using get_hide_part_bits_t = void(const void* obj, dobj_part_bits* part_bits);

		enum class suppression_reason
		{
			visible,
			dobj_not_submitted,
			selected_bone_hidden,
		};

		struct submission_result
		{
			const void* obj{};
			bool submitted{true};
		};

		struct laser_context
		{
			const game::playerState_s* ps{};
			const void* obj{};
			unsigned int hand{};
			bool submitted{true};
		};

		thread_local submission_result last_submission{};
		thread_local laser_context current_laser{};
		thread_local std::array<suppression_reason, 2> suppression_reasons{};
		thread_local std::array<bool, 2> logged_selected_bone{};
		std::atomic_bool logged_missing_submission{false};

		void log_state(const unsigned int hand, const suppression_reason reason,
			const unsigned int laser_bone_index = 0, const unsigned int hidden_bone_index = 0)
		{
			if (hand >= suppression_reasons.size() || suppression_reasons[hand] == reason)
			{
				return;
			}

			suppression_reasons[hand] = reason;
			const auto* ps = current_laser.ps;
			const auto weapon_state = ps == nullptr ? -1 : ps->weapState[hand].weaponState;
			const auto weapon_anim = ps == nullptr ? -1 : ps->weapState[hand].weapAnim;
			const auto weapon_time = ps == nullptr ? -1 : ps->weapState[hand].weaponTime;
			const auto weapon_delay = ps == nullptr ? -1 : ps->weapState[hand].weaponDelay;
			const auto flags_0 = ps == nullptr ? 0u : ps->weapFlags.m_flags[0];
			const auto flags_1 = ps == nullptr ? 0u : ps->weapFlags.m_flags[1];

			switch (reason)
			{
			case suppression_reason::dobj_not_submitted:
				console::info("[IWZ][LaserVisibility] suppressed hand %u laser: stock renderer skipped its DObj "
					"(state %d anim %d time %d delay %d flags %08X:%08X)\n",
					hand, weapon_state, weapon_anim, weapon_time, weapon_delay, flags_1, flags_0);
				break;

			case suppression_reason::selected_bone_hidden:
				console::info("[IWZ][LaserVisibility] suppressed hand %u laser: selected bone %u/ancestor %u hidden "
					"(state %d anim %d time %d delay %d flags %08X:%08X)\n",
					hand, laser_bone_index, hidden_bone_index, weapon_state, weapon_anim,
					weapon_time, weapon_delay, flags_1, flags_0);
				break;

			case suppression_reason::visible:
				console::info("[IWZ][LaserVisibility] restored hand %u laser with its viewmodel "
					"(state %d anim %d time %d delay %d flags %08X:%08X)\n",
					hand, weapon_state, weapon_anim, weapon_time, weapon_delay, flags_1, flags_0);
				break;
			}
		}

		bool find_hidden_hierarchy_bone(const dobj_part_bits& hierarchy_bits,
			const dobj_part_bits& hide_part_bits, unsigned int& hidden_bone_index)
		{
			for (auto word_index = 0u; word_index < hierarchy_bits.array.size(); ++word_index)
			{
				const auto hidden_bits = hierarchy_bits.array[word_index] & hide_part_bits.array[word_index];
				if (hidden_bits != 0)
				{
					hidden_bone_index = word_index * 32 + std::countl_zero(hidden_bits);
					return true;
				}
			}

			return false;
		}

		int record_viewmodel_dobj_submission(const void* obj)
		{
			const auto submitted = utils::hook::invoke<int>(dobj_should_submit, obj);
			last_submission = {obj, submitted != 0};
			return submitted;
		}

		bool prepare_viewmodel_laser(const game::playerState_s* ps, const unsigned int hand, const void* obj)
		{
			const auto has_submission_result = last_submission.obj == obj;
			current_laser = {ps, obj, hand, !has_submission_result || last_submission.submitted};

			if (!has_submission_result && !logged_missing_submission.exchange(true))
			{
				console::warn("[IWZ][LaserVisibility] could not correlate a laser DObj with the stock renderer decision\n");
			}

			if (hand >= suppression_reasons.size() || current_laser.submitted)
			{
				return true;
			}

			log_state(hand, suppression_reason::dobj_not_submitted);
			return false;
		}

		bool should_use_selected_laser_bone(const void* obj, const unsigned int bone_index)
		{
			if (obj == nullptr || obj != current_laser.obj || current_laser.hand >= suppression_reasons.size())
			{
				return true;
			}

			const auto hand = current_laser.hand;
			if (!logged_selected_bone[hand])
			{
				logged_selected_bone[hand] = true;
				console::info("[IWZ][LaserVisibility] hand %u is monitoring stock DObj submission and selected laser bone %u\n",
					hand, bone_index);
			}

			dobj_part_bits hierarchy_bits{};
			dobj_part_bits hide_part_bits{};
			reinterpret_cast<get_hierarchy_bits_t*>(dobj_get_hierarchy_bits)(obj, bone_index, &hierarchy_bits);
			reinterpret_cast<get_hide_part_bits_t*>(dobj_get_hide_part_bits)(obj, &hide_part_bits);

			unsigned int hidden_bone_index = 0;
			if (find_hidden_hierarchy_bone(hierarchy_bits, hide_part_bits, hidden_bone_index))
			{
				log_state(hand, suppression_reason::selected_bone_hidden, bone_index, hidden_bone_index);
				return false;
			}

			log_state(hand, suppression_reason::visible);
			return true;
		}

		void* viewmodel_laser_draw_stub()
		{
			return utils::hook::assemble([](utils::hook::assembler& a)
			{
				const auto draw_laser = a.newLabel();

				// The stock call receives playerState_s in RDX and the hand's DObj in
				// R9; the surrounding viewmodel loop keeps the hand index in R14D.
				a.pushad64();
				a.mov(rcx, rdx);
				a.mov(edx, r14d);
				a.mov(r8, r9);
				a.call_aligned(prepare_viewmodel_laser);
				a.mov(byte_ptr(rsp, 0x78), al);
				a.popad64();
				a.test(al, al);
				a.jnz(draw_laser);
				a.xor_(eax, eax);
				a.ret();

				a.bind(draw_laser);
				a.jmp(cg_laser_draw_player);
			});
		}

		void* selected_laser_bone_stub()
		{
			return utils::hook::assemble([](utils::hook::assembler& a)
			{
				const auto use_bone = a.newLabel();

				// CG_GetLaserOrient has already selected the precise laser/flash bone.
				// RDX is its DObj and R8D is the selected bone index at this call site.
				a.pushad64();
				a.mov(rcx, rdx);
				a.mov(edx, r8d);
				a.call_aligned(should_use_selected_laser_bone);
				a.mov(byte_ptr(rsp, 0x78), al);
				a.popad64();
				a.test(al, al);
				a.jnz(use_bone);

				// This stub replaced a call. Discard its return address and take the
				// stock "bone not found" exit so no laser is emitted for a hidden bone.
				a.add(rsp, 8);
				a.jmp(cg_get_laser_orient_not_found);

				a.bind(use_bone);
				a.jmp(cg_dobj_get_world_bone_matrix);
			});
		}

		bool validate_patch_sites()
		{
			constexpr std::array<std::uint8_t, 5> submission_call{0xE8, 0xDC, 0xE1, 0x1A, 0x00};
			constexpr std::array<std::uint8_t, 5> laser_draw_call{0xE8, 0xE3, 0x85, 0xF2, 0xFF};
			constexpr std::array<std::uint8_t, 5> bone_matrix_call{0xE8, 0x8D, 0x57, 0x95, 0xFF};

			return std::memcmp(reinterpret_cast<const void*>(viewmodel_dobj_submission_call),
				submission_call.data(), submission_call.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(viewmodel_laser_draw_call),
					laser_draw_call.data(), laser_draw_call.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(cg_get_laser_orient_bone_matrix_call),
					bone_matrix_call.data(), bone_matrix_call.size()) == 0;
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

			if (!validate_patch_sites())
			{
				console::error("[IWZ][LaserVisibility] renderer-parity patch validation failed; fix disabled\n");
				return;
			}

			utils::hook::call(viewmodel_dobj_submission_call, record_viewmodel_dobj_submission);
			utils::hook::call(viewmodel_laser_draw_call, viewmodel_laser_draw_stub());
			utils::hook::call(cg_get_laser_orient_bone_matrix_call, selected_laser_bone_stub());
			console::info("[IWZ][LaserVisibility] installed renderer-parity viewmodel laser suppression\n");
		}
	};
}

REGISTER_COMPONENT(laser_visibility::component)
