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
		constexpr auto bg_get_gesture = 0x140040990;
		constexpr auto bg_is_gesture_active = 0x1400417E0;
		constexpr auto bg_offhand_gesture_is_active = 0x140717210;
		constexpr auto bg_offhand_gesture_get_gesture = 0x140716F60;
		constexpr auto cg_get_weapon_map = 0x140212330;
		constexpr auto cg_gesture_get_info = 0x140158570;
		constexpr auto dobj_should_submit = 0x140A80960;
		constexpr auto dobj_get_num_models = 0x140D7FB20;
		constexpr auto dobj_get_model = 0x140D62520;
		constexpr auto dobj_get_hierarchy_bits = 0x140D5DA10;
		constexpr auto dobj_get_hide_part_bits = 0x140D624D0;
		constexpr auto xmodel_get_surfaces = 0x140D87940;
		constexpr auto xmodel_num_bones = 0x140D879E0;
		constexpr auto dobj_remap_part_bits = 0x140A81FC0;
		constexpr auto cg_dobj_get_world_bone_matrix = 0x140144ED0;

		struct dobj_part_bits
		{
			std::array<std::uint32_t, 8> array{};
		};

		using get_hierarchy_bits_t = void(const void* obj, int bone_index, dobj_part_bits* part_bits);
		using get_hide_part_bits_t = void(const void* obj, dobj_part_bits* part_bits);
		using get_num_models_t = unsigned int(const void* obj);
		using get_model_t = const game::XModel*(const void* obj, int model_index);
		using get_surfaces_t = int(const game::XModel* model, const game::XSurface** surfaces, int lod);
		using num_bones_t = int(const game::XModel* model);
		using remap_part_bits_t = void(const dobj_part_bits* source, int bone_offset, dobj_part_bits* result);

		// CG_Gesture_GetInfo returns cg + 0x59814 + (slot * 2 + hand) * 0x44.
		// UpdateAnimationState writes +0x38; UpdateMainTree consumes +0x34.
		struct gesture_animation_info
		{
			std::byte prefix[0x2C];
			float time;
			float normalized_time;
			float main_tree_weight;
			int state; // 0 off, 1 playing, 2 in, 3 out
			unsigned int main_anim;
			unsigned int last_gesture;
		};
		static_assert(sizeof(gesture_animation_info) == 0x44);
		static_assert(offsetof(gesture_animation_info, main_tree_weight) == 0x34);
		static_assert(offsetof(gesture_animation_info, state) == 0x38);
		static_assert(offsetof(gesture_animation_info, last_gesture) == 0x40);

		enum class suppression_reason
		{
			visible,
			dobj_not_submitted,
			selected_bone_hidden,
			selected_model_hidden,
			offhand_gesture_owns_hand,
			gesture_animation,
			gesture_keeps_primary,
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
			const game::Gesture* gesture{};
			unsigned int hand{};
			unsigned int gesture_index{0x100};
			game::OffhandGestureTypes gesture_type{game::OHGT_NUM_TYPES};
			int gesture_slot{-1};
			bool submitted{true};
			bool gesture_resolved{};
			bool gesture_cached{};
			int animation_state{};
			float main_tree_weight{1.0f};
			bool primary_preserved{};
		};

		struct gesture_hand_selection
		{
			const game::Gesture* gesture{};
			unsigned int hand{1};
			unsigned int index{0x100};
			game::OffhandGestureTypes type{game::OHGT_NUM_TYPES};
			int slot{-1};
			bool active{};
			bool resolved{};
			bool cached{};
		};

		struct gesture_hand_cache
		{
			const game::playerState_s* ps{};
			const game::Gesture* gesture{};
			unsigned int hand{1};
			unsigned int index{0x100};
			game::OffhandGestureTypes type{game::OHGT_NUM_TYPES};
			int slot{-1};
		};

		struct gesture_log_snapshot
		{
			const game::playerState_s* ps{};
			const game::Gesture* gesture{};
			unsigned int flags{};
			unsigned int hand{1};
			unsigned int index{0x100};
			game::OffhandGestureTypes type{game::OHGT_NUM_TYPES};
			int slot{-1};
			bool active{};
			bool resolved{};
			bool cached{};
		};

		struct model_visibility
		{
			const game::XModel* model{};
			unsigned int selected_bone{};
			unsigned int model_index{};
			unsigned int first_bone{};
			unsigned int bone_count{};
			unsigned int visible_surfaces{};
			unsigned int total_surfaces{};
			unsigned int offhand_gesture_flags{};
			dobj_part_bits hide_part_bits{};
			bool valid{};
		};

		thread_local submission_result last_submission{};
		thread_local laser_context current_laser{};
		thread_local std::array<suppression_reason, 2> suppression_reasons{};
		thread_local std::array<model_visibility, 2> last_model_visibility{};
		thread_local gesture_hand_cache last_offhand_gesture{};
		thread_local gesture_log_snapshot last_gesture_log{};
		std::atomic_bool logged_missing_submission{false};

		gesture_hand_selection get_offhand_gesture_hand(const int local_client_num,
			const game::playerState_s* ps)
		{
			gesture_hand_selection selection{};
			if (ps == nullptr || !utils::hook::invoke<bool>(bg_offhand_gesture_is_active, ps))
			{
				if (last_offhand_gesture.ps == ps)
				{
					last_offhand_gesture = {};
				}

				return selection;
			}

			selection.active = true;
			const auto* weapon_map = utils::hook::invoke<const void*>(cg_get_weapon_map, local_client_num);
			for (auto type = game::OHGT_WEAPON; weapon_map != nullptr && type < game::OHGT_NUM_TYPES;
				type = static_cast<game::OffhandGestureTypes>(type + 1))
			{
				const auto gesture_index = utils::hook::invoke<unsigned int>(
					bg_offhand_gesture_get_gesture, weapon_map, ps, type);
				if (gesture_index >= 0x100)
				{
					continue;
				}

				int slot = -1;
				if (!utils::hook::invoke<bool>(bg_is_gesture_active, ps, gesture_index, &slot))
				{
					continue;
				}

				const auto* gesture = utils::hook::invoke<const game::Gesture*>(
					bg_get_gesture, gesture_index);
				if (gesture == nullptr)
				{
					continue;
				}

				selection.gesture = gesture;
				// This selects the special left-akimbo idle path, NOT exclusive gesture
				// ownership. The right hand has an independent client animation state.
				selection.hand = gesture->weaponSettings.useLeftIdleAkimbo ? 1u : 0u;
				selection.index = gesture_index;
				selection.type = type;
				selection.slot = slot;
				selection.resolved = true;
				last_offhand_gesture = {ps, gesture, selection.hand, gesture_index, type, slot};
				return selection;
			}

			// The active gesture slot can disappear just before the ending flag clears.
			// Retain the asset's hand choice so suppression lasts through visual blend-out.
			if (last_offhand_gesture.ps == ps && last_offhand_gesture.gesture != nullptr)
			{
				selection.gesture = last_offhand_gesture.gesture;
				selection.hand = last_offhand_gesture.hand;
				selection.index = last_offhand_gesture.index;
				selection.type = last_offhand_gesture.type;
				selection.slot = last_offhand_gesture.slot;
				selection.resolved = true;
				selection.cached = true;
			}

			return selection;
		}

		bool gesture_log_changed(const gesture_log_snapshot& first, const gesture_log_snapshot& second)
		{
			return first.ps != second.ps
				|| first.gesture != second.gesture
				|| first.flags != second.flags
				|| first.hand != second.hand
				|| first.index != second.index
				|| first.type != second.type
				|| first.slot != second.slot
				|| first.active != second.active
				|| first.resolved != second.resolved
				|| first.cached != second.cached;
		}

		void log_gesture_hand_selection(const game::playerState_s* ps,
			const gesture_hand_selection& selection)
		{
			const gesture_log_snapshot snapshot{
				ps,
				selection.gesture,
				ps == nullptr ? 0u : ps->offhandGestureFlags,
				selection.hand,
				selection.index,
				selection.type,
				selection.slot,
				selection.active,
				selection.resolved,
				selection.cached,
			};

			if (!gesture_log_changed(last_gesture_log, snapshot))
			{
				return;
			}

			last_gesture_log = snapshot;
			if (!selection.active)
			{
				return;
			}

			if (!selection.resolved)
			{
				console::warn("[IWZ][LaserVisibility] active offhand gesture %08X could not be resolved from "
					"weapon handle %u (slot0 state %d index %u, slot1 state %d index %u); retaining the "
					"confirmed left-hand fallback\n",
					snapshot.flags, ps == nullptr ? 0u : ps->offhandGestureWeaponHandle,
					ps == nullptr ? 0 : ps->gestureState[0].state,
					ps == nullptr ? 0u : ps->gestureState[0].gestureIndex,
					ps == nullptr ? 0 : ps->gestureState[1].state,
					ps == nullptr ? 0u : ps->gestureState[1].gestureIndex);
				return;
			}

			const auto* gesture_name = selection.gesture->name == nullptr
				? "<unnamed>"
				: selection.gesture->name;
			console::info("[IWZ][LaserVisibility] offhand gesture type %d index %u slot %d '%s' priority %d "
				"idle fallback %s hand %u (not exclusive animation ownership) "
				"(useLeftIdleAkimbo %u splitAnimsAkimbo %u flags %08X%s)\n",
				static_cast<int>(selection.type), selection.index, selection.slot, gesture_name,
				static_cast<int>(selection.gesture->priority),
				selection.hand == 0 ? "right" : "left", selection.hand,
				selection.gesture->weaponSettings.useLeftIdleAkimbo,
				selection.gesture->weaponSettings.splitAnimsAkimbo, snapshot.flags,
				selection.cached ? " cached through blend-out" : "");
		}

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
			const auto offhand_weapon = ps == nullptr ? 0u : ps->offhandGestureWeaponHandle;
			const auto gesture_flags = ps == nullptr ? 0u : ps->offhandGestureFlags;

			switch (reason)
			{
			case suppression_reason::dobj_not_submitted:
				console::info("[IWZ][LaserVisibility] suppressed hand %u laser: stock renderer skipped its DObj "
					"(state %d anim %d time %d delay %d flags %08X:%08X offhand %u gesture %08X)\n",
					hand, weapon_state, weapon_anim, weapon_time, weapon_delay, flags_1, flags_0,
					offhand_weapon, gesture_flags);
				break;

			case suppression_reason::selected_bone_hidden:
				console::info("[IWZ][LaserVisibility] suppressed hand %u laser: selected bone %u/ancestor %u hidden "
					"(state %d anim %d time %d delay %d flags %08X:%08X offhand %u gesture %08X)\n",
					hand, laser_bone_index, hidden_bone_index, weapon_state, weapon_anim,
					weapon_time, weapon_delay, flags_1, flags_0, offhand_weapon, gesture_flags);
				break;

			case suppression_reason::selected_model_hidden:
				console::info("[IWZ][LaserVisibility] suppressed hand %u laser: selected bone %u belongs to a model "
					"with no visible LOD0 surfaces (offhand %u gesture %08X)\n",
					hand, laser_bone_index, offhand_weapon, gesture_flags);
				break;

			case suppression_reason::offhand_gesture_owns_hand:
			{
				if (!current_laser.gesture_resolved)
				{
					console::info("[IWZ][LaserVisibility] suppressed hand %u laser: unresolved active offhand "
						"gesture uses the confirmed left-hand fallback (offhand weapon %u gesture %08X state %d "
						"anim %d time %d delay %d flags %08X:%08X)\n",
						hand, offhand_weapon, gesture_flags, weapon_state, weapon_anim, weapon_time,
						weapon_delay, flags_1, flags_0);
					break;
				}

				const auto* gesture_name = current_laser.gesture != nullptr && current_laser.gesture->name != nullptr
					? current_laser.gesture->name
					: "<unresolved>";
				console::info("[IWZ][LaserVisibility] suppressed hand %u laser: offhand gesture '%s' type %d "
					"index %u slot %d owns that hand (offhand weapon %u gesture %08X state %d anim %d "
					"time %d delay %d "
					"flags %08X:%08X%s)\n",
					hand, gesture_name, static_cast<int>(current_laser.gesture_type),
					current_laser.gesture_index, current_laser.gesture_slot, offhand_weapon, gesture_flags,
					weapon_state, weapon_anim, weapon_time, weapon_delay, flags_1, flags_0,
					current_laser.gesture_cached ? " cached through blend-out" : "");
				break;
			}

			case suppression_reason::gesture_animation:
				console::info("[IWZ][LaserVisibility] suppressed hand %u laser: client gesture '%s' "
					"index %u priority %d slot %d animationState %d primaryWeight %.3f "
					"(weaponState %d offhand %u gesture %08X)\n",
					hand, current_laser.gesture && current_laser.gesture->name
						? current_laser.gesture->name : "<unknown>",
					current_laser.gesture_index,
					current_laser.gesture ? static_cast<int>(current_laser.gesture->priority) : -1,
					current_laser.gesture_slot,
					current_laser.animation_state, current_laser.main_tree_weight,
					weapon_state, offhand_weapon, gesture_flags);
				break;

			case suppression_reason::gesture_keeps_primary:
				console::info("[IWZ][LaserVisibility] preserved hand %u laser: offhand gesture '%s' "
					"leaves primary weapon available (gesturesDisablePrimary=0, slot %d gesture %08X)\n",
					hand, current_laser.gesture && current_laser.gesture->name
						? current_laser.gesture->name : "<unknown>",
					current_laser.gesture_slot, gesture_flags);
				break;

			case suppression_reason::visible:
				console::info("[IWZ][LaserVisibility] restored hand %u laser with its viewmodel "
					"(state %d anim %d time %d delay %d flags %08X:%08X offhand %u gesture %08X)\n",
					hand, weapon_state, weapon_anim, weapon_time, weapon_delay, flags_1, flags_0,
					offhand_weapon, gesture_flags);
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

		bool part_bits_intersect(const dobj_part_bits& first, const dobj_part_bits& second)
		{
			for (auto word_index = 0u; word_index < first.array.size(); ++word_index)
			{
				if ((first.array[word_index] & second.array[word_index]) != 0)
				{
					return true;
				}
			}

			return false;
		}

		bool get_selected_model_visibility(const void* obj, const unsigned int selected_bone,
			const game::playerState_s* ps, model_visibility& visibility)
		{
			dobj_part_bits hide_part_bits{};
			reinterpret_cast<get_hide_part_bits_t*>(dobj_get_hide_part_bits)(obj, &hide_part_bits);

			const auto model_count = reinterpret_cast<get_num_models_t*>(dobj_get_num_models)(obj);
			auto first_bone = 0u;
			for (auto model_index = 0u; model_index < model_count; ++model_index)
			{
				const auto* model = reinterpret_cast<get_model_t*>(dobj_get_model)(obj, model_index);
				if (model == nullptr)
				{
					continue;
				}

				const auto bone_count = static_cast<unsigned int>(
					reinterpret_cast<num_bones_t*>(xmodel_num_bones)(model));
				if (selected_bone >= first_bone + bone_count)
				{
					first_bone += bone_count;
					continue;
				}

				const game::XSurface* surfaces = nullptr;
				const auto surface_count = reinterpret_cast<get_surfaces_t*>(xmodel_get_surfaces)(model, &surfaces, 0);
				auto visible_surfaces = 0u;
				for (auto surface_index = 0; surface_index < surface_count; ++surface_index)
				{
					dobj_part_bits surface_part_bits{};
					dobj_part_bits remapped_part_bits{};
					std::memcpy(surface_part_bits.array.data(), surfaces[surface_index].partBits,
						surface_part_bits.array.size() * sizeof(surface_part_bits.array[0]));
					reinterpret_cast<remap_part_bits_t*>(dobj_remap_part_bits)(
						&surface_part_bits, static_cast<int>(first_bone), &remapped_part_bits);
					if (!part_bits_intersect(remapped_part_bits, hide_part_bits))
					{
						++visible_surfaces;
					}
				}

				visibility.model = model;
				visibility.selected_bone = selected_bone;
				visibility.model_index = model_index;
				visibility.first_bone = first_bone;
				visibility.bone_count = bone_count;
				visibility.visible_surfaces = visible_surfaces;
				visibility.total_surfaces = static_cast<unsigned int>(surface_count);
				visibility.offhand_gesture_flags = ps == nullptr ? 0u : ps->offhandGestureFlags;
				visibility.hide_part_bits = hide_part_bits;
				visibility.valid = true;
				return true;
			}

			return false;
		}

		bool model_visibility_changed(const model_visibility& first, const model_visibility& second)
		{
			return first.model != second.model
				|| first.selected_bone != second.selected_bone
				|| first.model_index != second.model_index
				|| first.first_bone != second.first_bone
				|| first.bone_count != second.bone_count
				|| first.visible_surfaces != second.visible_surfaces
				|| first.total_surfaces != second.total_surfaces
				|| first.offhand_gesture_flags != second.offhand_gesture_flags
				|| first.hide_part_bits.array != second.hide_part_bits.array
				|| first.valid != second.valid;
		}

		void log_model_visibility(const unsigned int hand, const model_visibility& visibility)
		{
			if (hand >= last_model_visibility.size()
				|| !model_visibility_changed(last_model_visibility[hand], visibility))
			{
				return;
			}

			last_model_visibility[hand] = visibility;
			const auto* model_name = visibility.model != nullptr && visibility.model->name != nullptr
				? visibility.model->name
				: "<unknown>";
			console::info("[IWZ][LaserVisibility] hand %u bone %u owner model %u '%s' bones [%u,%u) "
				"LOD0 surfaces %u/%u visible hide %08X:%08X:%08X:%08X:%08X:%08X:%08X:%08X gesture %08X\n",
				hand, visibility.selected_bone, visibility.model_index, model_name, visibility.first_bone,
				visibility.first_bone + visibility.bone_count, visibility.visible_surfaces,
				visibility.total_surfaces, visibility.hide_part_bits.array[7], visibility.hide_part_bits.array[6],
				visibility.hide_part_bits.array[5], visibility.hide_part_bits.array[4],
				visibility.hide_part_bits.array[3], visibility.hide_part_bits.array[2],
				visibility.hide_part_bits.array[1], visibility.hide_part_bits.array[0],
				visibility.offhand_gesture_flags);
		}

		int record_viewmodel_dobj_submission(const void* obj)
		{
			const auto submitted = utils::hook::invoke<int>(dobj_should_submit, obj);
			last_submission = {obj, submitted != 0};
			return submitted;
		}

		bool gesture_replaces_weapon_animation(const gesture_animation_info& info)
		{
			// -1 means this slot did not contribute to the tree this frame. A weight
			// of 1 leaves the normal weapon animation in control. Checking the client
			// state also respects right-hand cancellation and the visual OUT phase.
			return info.state >= 1 && info.state <= 3
				&& info.main_tree_weight >= 0.0f && info.main_tree_weight < 1.0f;
		}

		bool is_weapon_interaction_gesture(const game::Gesture* gesture)
		{
			if (!gesture)
			{
				return false;
			}

			// Movement and demeanor also blend the primary animation, without
			// replacing the gun. Classify the slot's asset, not the player's movement
			// state: an interaction in the other slot must still hide its own laser.
			switch (gesture->priority)
			{
			case game::GESTURE_PRIORITY_OFFHAND_SHIELD:
			case game::GESTURE_PRIORITY_OFFHAND_THROWN_WEAPON:
			case game::GESTURE_PRIORITY_OFFHAND_SCRIPT_WEAPON:
			case game::GESTURE_PRIORITY_SCRIPT:
				return true;
			default:
				return false;
			}
		}

		const game::WeaponDef* get_offhand_weapon_def(const int local_client_num,
			const game::playerState_s* ps)
		{
			if (!ps || !ps->offhandGestureWeaponHandle)
			{
				return nullptr;
			}
			const auto* weapon_map = utils::hook::invoke<const std::byte*>(cg_get_weapon_map, local_client_num);
			if (!weapon_map)
			{
				return nullptr;
			}

			// Same handle -> weapon index lookup as BG_Offhand_GetGesture at
			// 0x140716F73. Do not gate on offhand flags: the client OUT animation
			// can outlive them, and the weapon handle remains available then.
			std::uint16_t weapon_index{};
			std::memcpy(&weapon_index, weapon_map + 0xA +
				static_cast<std::size_t>(ps->offhandGestureWeaponHandle) * 0x10, sizeof(weapon_index));
			return weapon_index ? game::bg_weaponDefs[weapon_index] : nullptr;
		}

		bool offhand_preserves_primary(const game::WeaponDef* weapon, const game::Gesture* gesture)
		{
			static_assert(offsetof(game::WeaponDef, gesturesDisablePrimary) == 0xCE0);
			if (!weapon || !gesture || weapon->gesturesDisablePrimary)
			{
				return false;
			}

			// Match the slot to this weapon, so a different overlapping gesture
			// cannot inherit the exemption. These are the nine native offhand types.
			return gesture == weapon->gestureAnimation || gesture == weapon->gesturePullback
				|| gesture == weapon->gestureThrow || gesture == weapon->gestureDetonate
				|| gesture == weapon->shieldDeployGesture || gesture == weapon->shieldFireWeapGesture
				|| gesture == weapon->shieldDeployWhileFiring || gesture == weapon->shieldRetractWhileFiring
				|| gesture == weapon->shieldBashGesture;
		}

		bool suppress_for_gesture_animation(const int local_client_num, const unsigned int hand)
		{
			const auto* offhand_weapon = hand == 0 ? get_offhand_weapon_def(local_client_num, current_laser.ps) : nullptr;
			for (auto slot = 0u; slot < 2; ++slot)
			{
				const auto* info = utils::hook::invoke<const gesture_animation_info*>(
					cg_gesture_get_info, local_client_num, slot, hand);
				if (!info || !gesture_replaces_weapon_animation(*info))
				{
					continue;
				}

				const auto* gesture = info->last_gesture < 0x100
					? utils::hook::invoke<const game::Gesture*>(bg_get_gesture, info->last_gesture) : nullptr;
				if (!is_weapon_interaction_gesture(gesture))
				{
					continue;
				}

				current_laser.gesture = gesture;
				current_laser.gesture_index = info->last_gesture;
				current_laser.gesture_slot = static_cast<int>(slot);
				current_laser.animation_state = info->state;
				current_laser.main_tree_weight = info->main_tree_weight;
				if (hand == 0 && offhand_preserves_primary(offhand_weapon, gesture))
				{
					current_laser.primary_preserved = true;
					continue;
				}
				log_state(hand, suppression_reason::gesture_animation);
				return true;
			}
			return false;
		}

		bool prepare_viewmodel_laser(const int local_client_num, const game::playerState_s* ps,
			const unsigned int hand, const void* obj)
		{
			const auto has_submission_result = last_submission.obj == obj;
			const auto gesture = get_offhand_gesture_hand(local_client_num, ps);
			current_laser = {
				ps,
				obj,
				gesture.gesture,
				hand,
				gesture.index,
				gesture.type,
				gesture.slot,
				!has_submission_result || last_submission.submitted,
				gesture.resolved,
				gesture.cached,
			};
			log_gesture_hand_selection(ps, gesture);

			if (!has_submission_result && !logged_missing_submission.exchange(true))
			{
				console::warn("[IWZ][LaserVisibility] could not correlate a laser DObj with the stock renderer decision\n");
			}

			if (hand >= suppression_reasons.size())
			{
				return true;
			}

			if (!current_laser.submitted)
			{
				log_state(hand, suppression_reason::dobj_not_submitted);
				return false;
			}

			// Read both slots for THIS hand, including direct viewmodel gestures and
			// blend-out after the offhand server flag clears. Akimbo metadata cannot
			// describe a single-wield or two-handed action such as drinking a gourd.
			if (suppress_for_gesture_animation(local_client_num, hand))
			{
				return false;
			}

			// Preserve the tested left-akimbo idle suppression through the short
			// interval after its slot ends but before the offhand ending flag clears.
			if (gesture.active && hand == 1 && gesture.hand == 1)
			{
				log_state(hand, suppression_reason::offhand_gesture_owns_hand);
				return false;
			}

			return true;
		}

		bool should_use_selected_laser_bone(const void* obj, const unsigned int bone_index)
		{
			if (obj == nullptr || obj != current_laser.obj || current_laser.hand >= suppression_reasons.size())
			{
				return true;
			}

			const auto hand = current_laser.hand;

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

			model_visibility visibility{};
			if (get_selected_model_visibility(obj, bone_index, current_laser.ps, visibility))
			{
				log_model_visibility(hand, visibility);
				if (visibility.total_surfaces != 0 && visibility.visible_surfaces == 0)
				{
					log_state(hand, suppression_reason::selected_model_hidden, bone_index);
					return false;
				}
			}

			log_state(hand, current_laser.primary_preserved
				? suppression_reason::gesture_keeps_primary : suppression_reason::visible);
			return true;
		}

		void* viewmodel_laser_draw_stub()
		{
			return utils::hook::assemble([](utils::hook::assembler& a)
			{
				const auto draw_laser = a.newLabel();

				// The stock call receives localClientNum in ECX, playerState_s in RDX,
				// and the hand's DObj in R9; the viewmodel loop keeps the hand in R14D.
				a.pushad64();
				a.mov(r8d, r14d);
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
			constexpr std::array<std::uint8_t, 5> get_gesture_entry{0x8B, 0xC1, 0x48, 0x8D, 0x0D};
			constexpr std::array<std::uint8_t, 5> is_gesture_active_entry{0x45, 0x33, 0xC9, 0x48, 0x8D};
			constexpr std::array<std::uint8_t, 6> gesture_active_entry{0x8B, 0x81, 0x74, 0x08, 0x00, 0x00};
			constexpr std::array<std::uint8_t, 5> get_offhand_gesture_entry{0x48, 0x83, 0xEC, 0x48, 0x48};
			constexpr std::array<std::uint8_t, 5> get_weapon_map_entry{0x48, 0x63, 0xC1, 0x48, 0x8D};
			constexpr std::array<std::uint8_t, 7> get_gesture_info_entry{0x40, 0x53, 0x48, 0x63, 0xC1, 0x8B, 0xDA};
			constexpr std::array<std::uint8_t, 15> get_gesture_info_layout{
				0x49, 0x8D, 0x14, 0x5B, 0x48, 0x6B, 0xCA, 0x44,
				0x48, 0x81, 0xC1, 0x14, 0x98, 0x05, 0x00};
			constexpr std::array<std::uint8_t, 8> gesture_state_and_weight{
				0x8B, 0x48, 0x38, 0xF3, 0x0F, 0x10, 0x40, 0x34};
			constexpr std::array<std::uint8_t, 7> disable_primary_field{0x80, 0xB8, 0xE0, 0x0C, 0x00, 0x00, 0x00};
			constexpr std::array<std::uint8_t, 4> num_models_entry{0x0F, 0xB6, 0x41, 0x0F};
			constexpr std::array<std::uint8_t, 7> get_model_entry{0x48, 0x8B, 0x81, 0xF0, 0x00, 0x00, 0x00};
			constexpr std::array<std::uint8_t, 6> get_surfaces_entry{0x49, 0x63, 0xC0, 0x48, 0xC1, 0xE0};
			constexpr std::array<std::uint8_t, 4> num_bones_entry{0x0F, 0xB7, 0x41, 0x18};
			constexpr std::array<std::uint8_t, 5> remap_part_bits_entry{0x48, 0x89, 0x6C, 0x24, 0x10};

			return std::memcmp(reinterpret_cast<const void*>(viewmodel_dobj_submission_call),
				submission_call.data(), submission_call.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(viewmodel_laser_draw_call),
					laser_draw_call.data(), laser_draw_call.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(cg_get_laser_orient_bone_matrix_call),
					bone_matrix_call.data(), bone_matrix_call.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(bg_get_gesture),
					get_gesture_entry.data(), get_gesture_entry.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(bg_is_gesture_active),
					is_gesture_active_entry.data(), is_gesture_active_entry.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(bg_offhand_gesture_is_active),
					gesture_active_entry.data(), gesture_active_entry.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(bg_offhand_gesture_get_gesture),
					get_offhand_gesture_entry.data(), get_offhand_gesture_entry.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(cg_get_weapon_map),
					get_weapon_map_entry.data(), get_weapon_map_entry.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(cg_gesture_get_info),
					get_gesture_info_entry.data(), get_gesture_info_entry.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(0x140159569),
					get_gesture_info_layout.data(), get_gesture_info_layout.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(0x140161C6F),
					gesture_state_and_weight.data(), gesture_state_and_weight.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(0x14071AFB7),
					disable_primary_field.data(), disable_primary_field.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(dobj_get_num_models),
					num_models_entry.data(), num_models_entry.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(dobj_get_model),
					get_model_entry.data(), get_model_entry.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(xmodel_get_surfaces),
					get_surfaces_entry.data(), get_surfaces_entry.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(xmodel_num_bones),
					num_bones_entry.data(), num_bones_entry.size()) == 0
				&& std::memcmp(reinterpret_cast<const void*>(dobj_remap_part_bits),
					remap_part_bits_entry.data(), remap_part_bits_entry.size()) == 0;
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
				console::error("[IWZ][LaserVisibility] patch validation failed; fix disabled\n");
				return;
			}

			utils::hook::call(viewmodel_dobj_submission_call, record_viewmodel_dobj_submission);
			utils::hook::call(viewmodel_laser_draw_call, viewmodel_laser_draw_stub());
			utils::hook::call(cg_get_laser_orient_bone_matrix_call, selected_laser_bone_stub());
			console::info("[IWZ][LaserVisibility] installed interaction-only per-hand client-animation laser suppression "
				"for single/akimbo weapons, preserving available primary guns, with left-idle blend-out "
				"and model visibility checks\n");
		}
	};
}

REGISTER_COMPONENT(laser_visibility::component)
