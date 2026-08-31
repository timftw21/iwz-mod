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
		constexpr auto aim_trace_distance = 32000.0f;
		constexpr auto bullet_trace_mask = 0x280E931;
		constexpr auto invalid_command_time = std::numeric_limits<int>::min();

		enum class reticle_state
		{
			inactive,
			hip,
			transition,
			ads,
			ui_suppressed,
		};

		struct legacy_trace_result
		{
			float fraction;
			std::byte opaque[0x7C];
		};

		struct aim_solution
		{
			game::vec3_t origin{};
			game::vec3_t direction{};
			game::vec3_t hit_position{};
			game::vec2_t screen_position{};
			float trace_fraction = 1.0f;
		};

		struct aim_trace_cache
		{
			const game::cg_s* cgame_glob = nullptr;
			int command_time = invalid_command_time;
			game::vec3_t view_angles{};
			game::vec3_t origin{};
			game::vec3_t direction{};
			game::vec3_t hit_position{};
			float trace_fraction = 1.0f;
			bool valid = false;
		};

		reticle_state last_reticle_state = reticle_state::inactive;
		aim_trace_cache cached_aim_trace{};
		utils::hook::detour cg_calc_crosshair_position_hook;

		bool vectors_equal(const game::vec3_t& lhs, const game::vec3_t& rhs)
		{
			return lhs[0] == rhs[0] && lhs[1] == rhs[1] && lhs[2] == rhs[2];
		}

		void copy_vector(const game::vec3_t& source, game::vec3_t& destination)
		{
			destination[0] = source[0];
			destination[1] = source[1];
			destination[2] = source[2];
		}

		bool calculate_aim_world_point(const int local_client_num, const game::cg_s* cgame_glob,
			aim_solution& solution)
		{
			game::vec3_t origin{};
			game::CG_GetPlayerViewOrigin(local_client_num, &cgame_glob->predictedPlayerState, &origin);

			const auto& view_angles = cgame_glob->predictedPlayerState.viewangles;
			const auto command_time = cgame_glob->predictedPlayerState.commandTime;
			if (cached_aim_trace.valid && cached_aim_trace.cgame_glob == cgame_glob &&
				cached_aim_trace.command_time == command_time &&
				vectors_equal(cached_aim_trace.view_angles, view_angles) &&
				vectors_equal(cached_aim_trace.origin, origin))
			{
				copy_vector(cached_aim_trace.origin, solution.origin);
				copy_vector(cached_aim_trace.direction, solution.direction);
				copy_vector(cached_aim_trace.hit_position, solution.hit_position);
				solution.trace_fraction = cached_aim_trace.trace_fraction;
				return true;
			}

			game::vec3_t angles{view_angles[0], view_angles[1], view_angles[2]};
			game::vec3_t direction{};
			game::AngleVectors(angles, direction, nullptr, nullptr);

			game::vec3_t end
			{
				origin[0] + direction[0] * aim_trace_distance,
				origin[1] + direction[1] * aim_trace_distance,
				origin[2] + direction[2] * aim_trace_distance,
			};

			// IW7's client weapon-style traces use the detail-client physics world,
			// point bounds, and the same MASK_SHOT value used by GSC bullettrace.
			legacy_trace_result trace{};
			game::Bounds bounds{};
			game::PhysicsQuery_LegacyTrace(local_client_num * 3 + 2, &trace, origin, end, &bounds,
				local_client_num, 0, bullet_trace_mask, 1, nullptr, 0);

			if (!std::isfinite(trace.fraction))
			{
				return false;
			}

			trace.fraction = std::clamp(trace.fraction, 0.0f, 1.0f);
			game::vec3_t hit_position
			{
				origin[0] + (end[0] - origin[0]) * trace.fraction,
				origin[1] + (end[1] - origin[1]) * trace.fraction,
				origin[2] + (end[2] - origin[2]) * trace.fraction,
			};

			cached_aim_trace.cgame_glob = cgame_glob;
			cached_aim_trace.command_time = command_time;
			copy_vector(view_angles, cached_aim_trace.view_angles);
			copy_vector(origin, cached_aim_trace.origin);
			copy_vector(direction, cached_aim_trace.direction);
			copy_vector(hit_position, cached_aim_trace.hit_position);
			cached_aim_trace.trace_fraction = trace.fraction;
			cached_aim_trace.valid = true;

			copy_vector(origin, solution.origin);
			copy_vector(direction, solution.direction);
			copy_vector(hit_position, solution.hit_position);
			solution.trace_fraction = trace.fraction;
			return true;
		}

		bool calculate_projected_aim(const int local_client_num, const game::cg_s* cgame_glob,
			const game::ScreenPlacement* placement, aim_solution& solution)
		{
			if (!calculate_aim_world_point(local_client_num, cgame_glob, solution))
			{
				return false;
			}

			return game::CG_WorldPosToScreenPosReal(local_client_num, placement,
				solution.hit_position, solution.screen_position);
		}

		bool projected_aim_to_virtual_offset(const aim_solution& solution,
			const game::ScreenPlacement* placement, float& virtual_x, float& virtual_y)
		{
			if (placement->scaleVirtualToReal[0] == 0.0f || placement->scaleVirtualToReal[1] == 0.0f)
			{
				return false;
			}

			const auto center_x = placement->realViewportPosition[0] + placement->realViewportSize[0] * 0.5f;
			const auto center_y = placement->realViewportPosition[1] + placement->realViewportSize[1] * 0.5f;
			virtual_x = (solution.screen_position[0] - center_x) / placement->scaleVirtualToReal[0];
			virtual_y = (solution.screen_position[1] - center_y) / placement->scaleVirtualToReal[1];
			return std::isfinite(virtual_x) && std::isfinite(virtual_y);
		}

		void cg_calc_crosshair_position_stub(const game::cg_s* cgame_glob, float* x, float* y)
		{
			cg_calc_crosshair_position_hook.invoke<void>(cgame_glob, x, y);

			if (!dvars::cg_thirdPerson || !dvars::cg_thirdPerson->current.enabled ||
				game::Com_FrontEnd_IsInFrontEnd() || !game::clientUIActives[0].cgameInitialized ||
				cgame_glob != game::CG_GetLocalClientGlobals(0))
			{
				return;
			}

			const auto* const placement = game::ScrPlace_GetViewPlacement();
			aim_solution solution{};
			float virtual_x = 0.0f;
			float virtual_y = 0.0f;
			if (placement && calculate_projected_aim(0, cgame_glob, placement, solution) &&
				projected_aim_to_virtual_offset(solution, placement, virtual_x, virtual_y))
			{
				*x = virtual_x;
				*y = virtual_y;
			}
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

		void log_reticle_state(const reticle_state state, const float weapon_position_fraction = 0.0f,
			const aim_solution* solution = nullptr, const float virtual_x = 0.0f,
			const float virtual_y = 0.0f)
		{
			if (state == last_reticle_state)
			{
				return;
			}

			last_reticle_state = state;
			if (state == reticle_state::ui_suppressed)
			{
				console::info("[IWZ][Camera] third-person ADS reticle suppressed keyCatchers=0x%X\n",
					*game::keyCatchers);
				return;
			}

			const char* state_name = "inactive";
			switch (state)
			{
			case reticle_state::hip:
				state_name = "hip-stock-only";
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
				console::info("[IWZ][Camera] third-person reticle state=%s weaponPosFrac=%.3f "
					"aimOrigin=(%.1f,%.1f,%.1f) aimDirection=(%.3f,%.3f,%.3f) "
					"traceFraction=%.4f hit=(%.1f,%.1f,%.1f) screen=(%.1f,%.1f) "
					"virtualOffset=(%.2f,%.2f)\n",
					state_name, weapon_position_fraction,
					solution->origin[0], solution->origin[1], solution->origin[2],
					solution->direction[0], solution->direction[1], solution->direction[2],
					solution->trace_fraction,
					solution->hit_position[0], solution->hit_position[1], solution->hit_position[2],
					solution->screen_position[0], solution->screen_position[1], virtual_x, virtual_y);
			}
		}
	}

	void draw_reticle(const int local_client_num)
	{
		if (!dvars::cg_thirdPerson || !dvars::cg_thirdPerson->current.enabled ||
			game::Com_FrontEnd_IsInFrontEnd() || !game::clientUIActives[0].cgameInitialized)
		{
			last_reticle_state = reticle_state::inactive;
			return;
		}

		if (*game::keyCatchers != 0)
		{
			log_reticle_state(reticle_state::ui_suppressed);
			return;
		}

		const auto* const draw_crosshair = game::Dvar_FindVar("cg_drawCrosshair");
		auto* const material = *game::whiteMaterial;
		const auto* const placement = game::ScrPlace_GetViewPlacement();
		const auto* const cgame_glob = game::CG_GetLocalClientGlobals(local_client_num);
		if (!draw_crosshair || !draw_crosshair->current.enabled || !material || !placement || !cgame_glob)
		{
			last_reticle_state = reticle_state::inactive;
			return;
		}

		const auto viewport_width = placement->realViewportSize[0];
		const auto viewport_height = placement->realViewportSize[1];
		const auto scale = std::max(0.75f, std::min(viewport_width / 1920.0f, viewport_height / 1080.0f));
		aim_solution solution{};
		if (!calculate_projected_aim(local_client_num, cgame_glob, placement, solution))
		{
			last_reticle_state = reticle_state::inactive;
			return;
		}

		float virtual_x = 0.0f;
		float virtual_y = 0.0f;
		projected_aim_to_virtual_offset(solution, placement, virtual_x, virtual_y);
		const auto center_x = solution.screen_position[0];
		const auto center_y = solution.screen_position[1];
		const auto weapon_position_fraction = std::clamp(cgame_glob->predictedPlayerState.fWeaponPosFrac,
			0.0f, 1.0f);
		const auto state = weapon_position_fraction <= 0.001f
			? reticle_state::hip
			: weapon_position_fraction >= 0.999f
				? reticle_state::ads
				: reticle_state::transition;
		log_reticle_state(state, weapon_position_fraction, &solution, virtual_x, virtual_y);

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
				console::info("[IWZ][Camera] configured third-person reticle convergence hip=stock ADS=custom "
					"anchor=projected-player-aim traceWorld=detail-client traceMask=0x%X "
					"traceDistance=%.0f uiGate=keyCatchers respectCgDrawCrosshair=1\n",
					bullet_trace_mask, aim_trace_distance);
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
			cg_calc_crosshair_position_hook.create(game::CG_CalcCrosshairPosition,
				cg_calc_crosshair_position_stub);
		}
	};
}

REGISTER_COMPONENT(thirdperson::component)
