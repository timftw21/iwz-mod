#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"
#include "game/dvars.hpp"

#include "console/console.hpp"
#include "dvars.hpp"
#include "scheduler.hpp"
#include "thirdperson.hpp"

#include <utils/hook.hpp>

namespace thirdperson
{
	namespace
	{
		constexpr auto aim_projection_distance = 8192.0f;
		constexpr auto shoulder_offset = 20.0f;

		enum class reticle_state
		{
			inactive,
			hip,
			transition,
			ads,
			ui_suppressed,
		};

		struct aim_solution
		{
			game::vec3_t origin{};
			game::vec3_t direction{};
			game::vec3_t camera_offset{};
			game::vec2_t gun_angles{};
			game::vec2_t screen_position{};
		};

		struct camera_aim_cache
		{
			const game::cg_s* cgame_glob = nullptr;
			int frame_time = 0;
			aim_solution solution{};
			bool valid = false;
		};

		std::array<reticle_state, 2> last_reticle_states{};
		std::array<camera_aim_cache, 2> camera_aim{};
		bool use_camera_crosshair_position = false;
		utils::hook::detour cg_calc_crosshair_position_hook;

		void copy_vector(const float* source, game::vec3_t& destination)
		{
			std::copy_n(source, 3, destination);
		}

		bool finite_vector(const game::vec3_t& vector)
		{
			return std::all_of(std::begin(vector), std::end(vector),
				[](const float value) { return std::isfinite(value); });
		}

		bool third_person_enabled(const int local_client_num)
		{
			return local_client_num >= 0 && local_client_num < static_cast<int>(camera_aim.size()) &&
				dvars::cg_thirdPerson && dvars::cg_thirdPerson->current.enabled &&
				!game::Com_FrontEnd_IsInFrontEnd() &&
				game::clientUIActives[local_client_num].cgameInitialized;
		}

		void third_person_view_trace_stub(const int local_client_num, const int entity_num,
			const float* eye_origin, const float* camera_offset, const float* view_angles,
			const bool world_space_up, const bool alternate_physics_phase,
			float* camera_origin, float* gun_angles)
		{
			game::vec3_t offset{};
			copy_vector(camera_offset, offset);
			const auto enabled = third_person_enabled(local_client_num);
			const auto* cgame_glob = enabled ? game::CG_GetLocalClientGlobals(local_client_num) : nullptr;
			if (cgame_glob)
			{
				// Stock blends hip (-120,0,14) into ADS (-60,-20,4). Supply the
				// missing hip shoulder offset before its collision/convergence traces.
				// Keep the stock shoulder switch, ADS position, height and range.
				const auto fraction = std::clamp(cgame_glob->predictedPlayerState.fWeaponPosFrac, 0.0f, 1.0f);
				offset[1] -= shoulder_offset * cgame_glob->thirdPersonCameraSide * (1.0f - fraction);
			}

			utils::hook::invoke<void>(0x1408B9D60, local_client_num, entity_num, eye_origin, offset,
				view_angles, world_space_up, alternate_physics_phase, camera_origin, gun_angles);

			if (!cgame_glob)
				return;

			auto& cached = camera_aim[local_client_num];
			cached.cgame_glob = cgame_glob;
			cached.frame_time = cgame_glob->time;
			copy_vector(camera_origin, cached.solution.origin);
			copy_vector(offset, cached.solution.camera_offset);
			game::AngleVectors(view_angles, cached.solution.direction, nullptr, nullptr);
			cached.valid = finite_vector(cached.solution.origin) && finite_vector(cached.solution.direction);
		}

		bool calculate_projected_aim(const int local_client_num, const game::cg_s* cgame_glob,
			const game::ScreenPlacement* placement, aim_solution& solution)
		{
			if (!third_person_enabled(local_client_num) || !cgame_glob)
				return false;
			const auto& cached = camera_aim[local_client_num];
			if (!cached.valid || cached.cgame_glob != cgame_glob || cached.frame_time != cgame_glob->time)
				return false;

			solution = cached.solution;
			solution.gun_angles[0] = cgame_glob->thirdPersonGunPitch;
			solution.gun_angles[1] = cgame_glob->thirdPersonGunYaw;
			// CG's shoulder-camera trace already converges the bullet direction
			// (thirdPersonGunPitch/Yaw) on this camera ray. Project the ray itself:
			// tracing again from uncorrected player angles adds parallax and makes
			// the reticle jump between foreground and background surfaces.
			game::vec3_t point{};
			for (auto axis = 0; axis < 3; ++axis)
				point[axis] = solution.origin[axis] + solution.direction[axis] * aim_projection_distance;
			return game::CG_WorldPosToScreenPosReal(local_client_num, placement, point, solution.screen_position);
		}

		bool projected_aim_to_virtual_offset(const aim_solution& solution,
			const game::ScreenPlacement* placement, float& virtual_x, float& virtual_y)
		{
			if (placement->scaleVirtualToReal[0] == 0.0f || placement->scaleVirtualToReal[1] == 0.0f)
				return false;

			const auto center_x = placement->realViewportPosition[0] + placement->realViewportSize[0] * 0.5f;
			const auto center_y = placement->realViewportPosition[1] + placement->realViewportSize[1] * 0.5f;
			virtual_x = (solution.screen_position[0] - center_x) / placement->scaleVirtualToReal[0];
			virtual_y = (solution.screen_position[1] - center_y) / placement->scaleVirtualToReal[1];
			return std::isfinite(virtual_x) && std::isfinite(virtual_y);
		}

		void cg_calc_crosshair_position_stub(const game::cg_s* cgame_glob, float* x, float* y)
		{
			use_camera_crosshair_position = false;
			cg_calc_crosshair_position_hook.invoke<void>(cgame_glob, x, y);
			if (!cgame_glob || !third_person_enabled(cgame_glob->localClientNum))
				return;

			const auto* placement = game::ScrPlace_GetViewPlacement();
			aim_solution solution{};
			float virtual_x = 0.0f;
			float virtual_y = 0.0f;
			if (placement && calculate_projected_aim(cgame_glob->localClientNum, cgame_glob, placement, solution) &&
				projected_aim_to_virtual_offset(solution, placement, virtual_x, virtual_y))
			{
				*x = virtual_x;
				*y = virtual_y;
				use_camera_crosshair_position = true;
			}
		}

		void* preserve_hip_crosshair_position_stub()
		{
			return utils::hook::assemble([](utils::hook::assembler& a)
			{
				const auto preserve_position = a.newLabel();
				a.mov(rax, reinterpret_cast<int64_t>(&use_camera_crosshair_position));
				a.cmp(byte_ptr(rax), 0);
				a.jne(preserve_position);

				// Replay the stock dynamic-crosshair check for every other view.
				a.mov(rax, qword_ptr(0x141FA76F0));
				a.cmp(byte_ptr(rax, 0x10), 0);
				a.jne(preserve_position);
				a.jmp(0x140790938);

				a.bind(preserve_position);
				a.jmp(0x14079095B);
			});
		}

		void sync_stock_third_person(const bool enabled, const char* reason, const bool log_unchanged = false)
		{
			auto* const camera_third_person = game::Dvar_FindVar("camera_thirdPerson");
			if (!camera_third_person)
			{
				static bool warned = false;
				if (!warned)
				{
					console::warn("[IWZ][Camera] camera_thirdPerson is not registered; stock camera sync deferred\n");
					warned = true;
				}
				return;
			}

			if (camera_third_person->current.enabled == enabled)
			{
				if (log_unchanged)
				{
					console::info("[IWZ][Camera] stock camera already synchronized enabled=%d reason=%s\n",
						enabled, reason);
				}
				return;
			}

			game::Dvar_SetFromStringFromSource(camera_third_person, enabled ? "1" : "0",
				game::DvarSetSource::DVAR_SOURCE_INTERNAL);
			console::info("[IWZ][Camera] synchronized camera_thirdPerson enabled=%d reason=%s applied=%d\n",
				enabled, reason, camera_third_person->current.enabled);
		}

		void* cg_offset_third_person_view_stub()
		{
			return utils::hook::assemble([](utils::hook::assembler& a)
			{
				a.push(rax);

				a.mov(rax, qword_ptr(reinterpret_cast<int64_t>(&dvars::cg_thirdPersonAngle)));
				a.movss(xmm11, dword_ptr(rax, 0x10));

				a.mov(rax, qword_ptr(reinterpret_cast<int64_t>(&dvars::cg_thirdPersonRange)));
				a.movss(xmm10, dword_ptr(rax, 0x10));

				a.pop(rax);

				// original code

				a.mulss(xmm7, xmm0);
				a.mulss(xmm6, xmm0);
				a.addss(xmm7, qword_ptr(rdi));

				a.jmp(0x140274596);
			});
		}

		void* cg_offset_chase_cam_view_stub()
		{
			return utils::hook::assemble([](utils::hook::assembler& a)
			{
				a.push(rax);

				a.mov(rax, qword_ptr(reinterpret_cast<int64_t>(&dvars::cg_thirdPersonAngle)));
				a.movss(xmm8, dword_ptr(rax, 0x10));

				a.mov(rax, qword_ptr(reinterpret_cast<int64_t>(&dvars::cg_thirdPersonRange)));
				a.movss(xmm7, dword_ptr(rax, 0x10));
				
				a.pop(rax);

				// original code

				a.mulss(xmm2, xmm2);
				a.mulss(xmm3, xmm3);
				a.addss(xmm2, xmm3);

				a.jmp(0x140272069);
			});
		}

		void draw_reticle_rect(const float x, const float y, const float width, const float height,
			float* color, game::Material* material)
		{
			game::R_AddCmdDrawStretchPic(x, y, width, height, 0.0f, 0.0f, 0.0f, 0.0f,
				color, material, 0);
		}

		void log_reticle_state(const int local_client_num, const reticle_state state, const float weapon_position_fraction = 0.0f,
			const aim_solution* solution = nullptr, const float virtual_x = 0.0f,
			const float virtual_y = 0.0f)
		{
			if (state == last_reticle_states[local_client_num])
			{
				return;
			}

			last_reticle_states[local_client_num] = state;
			if (state == reticle_state::ui_suppressed)
			{
				console::info("[IWZ][Camera] third-person ADS reticle suppressed client=%d keyCatchers=0x%X\n",
					local_client_num, *game::keyCatchers);
				return;
			}

			const char* state_name = "inactive";
			switch (state)
			{
			case reticle_state::hip:
				state_name = "hip-shoulder";
				break;
			case reticle_state::transition:
				state_name = "ADS-transition";
				break;
			case reticle_state::ads:
				state_name = "ADS-custom";
				break;
			default:
				break;
			}

			if (state != reticle_state::inactive && solution)
			{
				console::info("[IWZ][Camera] third-person reticle client=%d state=%s weaponPosFrac=%.3f "
					"anchor=camera-ray cameraOrigin=(%.1f,%.1f,%.1f) aimDirection=(%.3f,%.3f,%.3f) "
					"cameraOffset=(%.1f,%.1f,%.1f) gunAngles=(%.3f,%.3f) screen=(%.1f,%.1f) "
					"virtualOffset=(%.2f,%.2f)\n",
					local_client_num, state_name, weapon_position_fraction,
					solution->origin[0], solution->origin[1], solution->origin[2],
					solution->direction[0], solution->direction[1], solution->direction[2],
					solution->camera_offset[0], solution->camera_offset[1], solution->camera_offset[2],
					solution->gun_angles[0], solution->gun_angles[1],
					solution->screen_position[0], solution->screen_position[1], virtual_x, virtual_y);
			}
		}
	}

	void draw_reticle(const int local_client_num)
	{
		if (local_client_num < 0 || local_client_num >= static_cast<int>(last_reticle_states.size()))
			return;
		if (!third_person_enabled(local_client_num))
		{
			last_reticle_states[local_client_num] = reticle_state::inactive;
			return;
		}

		if (*game::keyCatchers != 0)
		{
			log_reticle_state(local_client_num, reticle_state::ui_suppressed);
			return;
		}

		const auto* const draw_crosshair = game::Dvar_FindVar("cg_drawCrosshair");
		auto* const material = *game::whiteMaterial;
		const auto* const placement = game::ScrPlace_GetViewPlacement();
		const auto* const cgame_glob = game::CG_GetLocalClientGlobals(local_client_num);
		if (!draw_crosshair || !draw_crosshair->current.enabled || !material || !placement || !cgame_glob)
		{
			last_reticle_states[local_client_num] = reticle_state::inactive;
			return;
		}

		const auto viewport_width = placement->realViewportSize[0];
		const auto viewport_height = placement->realViewportSize[1];
		const auto scale = std::max(0.75f, std::min(viewport_width / 1920.0f, viewport_height / 1080.0f));
		aim_solution solution{};
		if (!calculate_projected_aim(local_client_num, cgame_glob, placement, solution))
		{
			last_reticle_states[local_client_num] = reticle_state::inactive;
			return;
		}

		float virtual_x = 0.0f;
		float virtual_y = 0.0f;
		if (!projected_aim_to_virtual_offset(solution, placement, virtual_x, virtual_y))
			return;
		const auto center_x = solution.screen_position[0];
		const auto center_y = solution.screen_position[1];
		const auto weapon_position_fraction = std::clamp(cgame_glob->predictedPlayerState.fWeaponPosFrac,
			0.0f, 1.0f);
		const auto state = weapon_position_fraction <= 0.001f
			? reticle_state::hip
			: weapon_position_fraction >= 0.999f
				? reticle_state::ads
				: reticle_state::transition;
		log_reticle_state(local_client_num, state, weapon_position_fraction, &solution, virtual_x, virtual_y);

		// Stock CG_DrawCrosshair owns hip-fire and fades its spread reticle as ADS progresses.
		// Fade this compact reticle in with the engine's weapon-position fraction.
		if (state == reticle_state::hip)
		{
			return;
		}

		const auto arm_length = 5.0f * scale;
		const auto arm_thickness = 1.5f * scale;
		const auto center_gap = 3.0f * scale;
		const auto outline = 1.0f * scale;
		game::vec4_t outline_color = {0.0f, 0.0f, 0.0f, 0.85f * weapon_position_fraction};
		game::vec4_t reticle_color = {1.0f, 1.0f, 1.0f, 0.9f * weapon_position_fraction};

		const std::array<std::array<float, 4>, 4> arms
		{
			std::array{center_x - center_gap - arm_length, center_y - arm_thickness * 0.5f,
				arm_length, arm_thickness},
			std::array{center_x + center_gap, center_y - arm_thickness * 0.5f,
				arm_length, arm_thickness},
			std::array{center_x - arm_thickness * 0.5f, center_y - center_gap - arm_length,
				arm_thickness, arm_length},
			std::array{center_x - arm_thickness * 0.5f, center_y + center_gap,
				arm_thickness, arm_length},
		};

		for (const auto& arm : arms)
		{
			draw_reticle_rect(arm[0] - outline, arm[1] - outline, arm[2] + outline * 2.0f,
				arm[3] + outline * 2.0f, outline_color, material);
			draw_reticle_rect(arm[0], arm[1], arm[2], arm[3], reticle_color, material);
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

			scheduler::once([]()
			{
				// cp_globallogic copies scr_thirdPerson to camera_thirdPerson at map startup. Keep the saved
				// preference separate, then synchronize it internally so the stock shoulder camera is used.
				dvars::cg_thirdPerson = game::Dvar_RegisterBool("cg_thirdPerson", false, game::DVAR_FLAG_SAVED,
					"Use third person view");

				dvars::cg_thirdPersonAngle = game::Dvar_RegisterFloat("cg_thirdPersonAngle", 356.0f, -180.0f, 360.0f, game::DVAR_FLAG_CHEAT,
					"The angle of the camera from the player in third person view");

				dvars::cg_thirdPersonRange = game::Dvar_RegisterFloat("cg_thirdPersonRange", 120.0f, 0.0f, 1024, game::DVAR_FLAG_CHEAT,
					"The range of the camera from the player in third person view");

				console::info("[IWZ][Camera] registered cg_thirdPerson enabled=%d saved=1 angle=%.1f range=%.1f\n",
					dvars::cg_thirdPerson->current.enabled, dvars::cg_thirdPersonAngle->current.value,
					dvars::cg_thirdPersonRange->current.value);
				console::info("[IWZ][Camera] configured third-person reticle hip=stock ADS=custom "
					"anchor=stock-camera-ray shoulderOffset=%.0f convergence=stock extraTraces=0 "
					"hipPositionReset=bypassed uiGate=keyCatchers respectCgDrawCrosshair=1\n", shoulder_offset);
				sync_stock_third_person(dvars::cg_thirdPerson->current.enabled, "initialization", true);
			}, scheduler::main);

			dvars::callback::on_new_value("cg_thirdPerson", [](game::DvarValue* value)
			{
				console::info("[IWZ][Camera] cg_thirdPerson changed enabled=%d perspective=%s\n", value->enabled,
					value->enabled ? "third-person" : "first-person");
				sync_stock_third_person(value->enabled, "preference-change");
			});

			// Zombies scripts can overwrite camera_thirdPerson during map initialization. Reapply only
			// when it diverges from the saved preference; the normal per-frame camera path remains stock.
			scheduler::loop([]()
			{
				if (dvars::cg_thirdPerson)
				{
					sync_stock_third_person(dvars::cg_thirdPerson->current.enabled, "script-reset");
				}
			}, scheduler::main, 100ms);

			utils::hook::jump(0x14027205D, cg_offset_chase_cam_view_stub(), true);
			utils::hook::jump(0x14027458A, cg_offset_third_person_view_stub(), true);
			utils::hook::call(0x14027B1EA, third_person_view_trace_stub);
			cg_calc_crosshair_position_hook.create(game::CG_CalcCrosshairPosition,
				cg_calc_crosshair_position_stub);
			// CG_DrawCrosshair normally discards the calculated hip position when
			// its dynamic-crosshair setting is off. Preserve our camera anchor
			// without changing that setting or replacing the weapon's spread UI.
			utils::hook::nop(0x14079092B, 13);
			utils::hook::jump(0x14079092B, preserve_hip_crosshair_position_stub());
		}
	};
}

REGISTER_COMPONENT(thirdperson::component)
