#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"

#include "console/console.hpp"
#include "fastfiles.hpp"

#include <utils/hook.hpp>

namespace ammo
{
	namespace
	{
		constexpr auto stock_reserve_ammo_bits = 10;
		constexpr auto extended_reserve_ammo_bits = 16;
		constexpr auto stock_reserve_ammo_max = (1 << stock_reserve_ammo_bits) - 1;
		constexpr auto extended_reserve_ammo_max = (1 << extended_reserve_ammo_bits) - 1;

		constexpr auto reserve_ammo_read_call = 0x140BBCD27;
		constexpr auto reserve_ammo_write_clamp_compare = 0x140BC1A8A;
		constexpr auto reserve_ammo_write_clamp_move = 0x140BC1A93;
		constexpr auto reserve_ammo_write_call = 0x140BC1A97;

		std::atomic_bool extended_write_logged{};
		std::atomic_bool extended_read_logged{};
		std::atomic_bool extended_saturation_logged{};

		constexpr auto osa_zombies_weapon = "iw7_arclassic_zm";
		constexpr auto osa_standard_reserve_ammo = 350;
		constexpr auto forge_freeze_reserve = 450;
		constexpr auto forge_freeze_recharge_ms = 400;
		constexpr auto forge_freeze_shatter_angle = 12.0f;

		bool is_forge_freeze(const char* name)
		{
			if (!name) return false;
			const std::string_view value{name};
			return value == "iw7_forgefreeze_zm" || value == "iw7_forgefreeze_zm_pap1" ||
				value == "iw7_forgefreeze_zm_pap2";
		}

		void get_reticle_target_assist(const unsigned short* weapon, const bool alternate,
			const float spread, const float range, float* angle_out, float* range_out)
		{
			utils::hook::invoke<void>(0x1407433A0, weapon, alternate, spread, range, angle_out, range_out);
			if (!weapon || !*weapon || !alternate ||
				game::Com_GameMode_GetActiveGameMode() != game::GAME_MODE_CP) return;
			const auto* def = game::bg_weaponCompleteDefs[*weapon];
			if (!def || !is_forge_freeze(def->szInternalName)) return;

			// CG's reticle projection shares the damage cone query. Restore the stock
			// spread-based visual radius here; gameplay still receives the wider cone.
			*angle_out = spread;
		}

		void patch_forge_freeze(game::WeaponCompleteDef* weapon)
		{
			if (!weapon || !weapon->weapDef || !is_forge_freeze(weapon->szInternalName)) return;
			auto* def = weapon->weapDef;
			const auto old_reserve = def->iMaxAmmo;
			const auto old_recharge = def->regenerationAddTimeMs;
			weapon->iClipSize = 50;
			def->iStartAmmo = def->iMaxAmmo = forge_freeze_reserve;
			def->regenerationTimeMs = def->regenerationAddTimeMs = forge_freeze_recharge_ms;

			// The dumped weapons share 50/200 base ammo. Their PaP and alternate
			// fire attachments override it, including regeneration for both PaP tiers.
			// Keep the stock 1.5x/2x PaP capacities and 2/3-round recharge amounts.
			const auto patch_attachments = [](game::WeaponAttachment** attachments, unsigned int count)
			{
				for (unsigned int i = 0; attachments && i < count; ++i)
				{
					auto* attachment = attachments[i];
					if (!attachment || !attachment->szInternalName) continue;
					const std::string_view name{attachment->szInternalName};
					if (name != "forgefreezealtfire" && name != "freezepap1" && name != "freezepap2") continue;
					const auto reserve = name == "freezepap1" ? 675 : name == "freezepap2" ? 900 : forge_freeze_reserve;
					if (attachment->ammunition)
					{
						attachment->ammunition->startAmmo = attachment->ammunition->maxAmmo = reserve;
					}
					if (attachment->regeneration)
					{
						attachment->regeneration->regenerationTimeMs = forge_freeze_recharge_ms;
						attachment->regeneration->regenerationAddTimeMs = forge_freeze_recharge_ms;
					}
					if (name == "forgefreezealtfire" && attachment->targetAssist)
					{
						// BG's cone query (0x1407433A0) uses the first active attachment's
						// angle. Zero falls back to weapon spread (normally 5-8 degrees).
						// The alt-fire attachment takes priority over PaP attachments,
						// so this widens only the shatter pulse at every upgrade tier.
						attachment->targetAssist->targetAssistAngle = forge_freeze_shatter_angle;
						console::info("[IWZ][ForgeFreeze] shatter pulse cone half-angle=%.1f degrees; range and target limit unchanged\n",
							forge_freeze_shatter_angle);
					}
				}
			};
			patch_attachments(weapon->attachments, weapon->numAttachments);
			patch_attachments(weapon->attachments3, weapon->numAttachments3);
			console::info("[IWZ][ForgeFreeze] weapon=%s baseAmmo=50/%i (reserve was %i) rechargeMs=%i->%i PaPAmmo=75/675,100/900 fireTimeMs=%i ammoConsumption=stock\n",
				weapon->szInternalName, forge_freeze_reserve, old_reserve, old_recharge,
				forge_freeze_recharge_ms, def->iFireTime);
		}

		void patch_osa_standard_max_ammo(game::WeaponCompleteDef* weapon)
		{
			if (!weapon || !weapon->szInternalName ||
				std::strcmp(weapon->szInternalName, osa_zombies_weapon) != 0)
			{
				return;
			}

			if (!weapon->weapDef)
			{
				console::warn("[IWZ][Ammo] cannot patch weapon=%s: missing WeaponDef\n",
					osa_zombies_weapon);
				return;
			}

			const auto stock_start_ammo = weapon->weapDef->iStartAmmo;
			const auto stock_max_ammo = weapon->weapDef->iMaxAmmo;
			weapon->weapDef->iStartAmmo = osa_standard_reserve_ammo;
			weapon->weapDef->iMaxAmmo = osa_standard_reserve_ammo;

			// BG_GetWeaponMaxAmmo (0x14074A890) begins with this base field, then
			// lets an equipped AttAmmunition override maxAmmo. The Zombies attachment
			// map assigns arcpap1/arcpap2 to the OSA, so their stock PaP values remain
			// authoritative while only the un-PaP weapon receives this new capacity.
			console::info(
				"[IWZ][Ammo] patched base weapon=%s startAmmo=%i->%i maxAmmo=%i->%i; PaP attachment overrides unchanged\n",
				osa_zombies_weapon, stock_start_ammo, weapon->weapDef->iStartAmmo,
				stock_max_ammo, weapon->weapDef->iMaxAmmo);
		}

		bool use_extended_reserve_ammo()
		{
			return game::Com_GameMode_GetActiveGameMode() == game::GAME_MODE_CP;
		}

		void msg_write_reserve_ammo_stub(game::msg_t* msg, int ammo_count, const int bit_count)
		{
			if (!use_extended_reserve_ammo())
			{
				// Reproduce the stock saturation removed at the call site. This keeps
				// the MP snapshot format and behavior byte-for-byte compatible.
				if (ammo_count > stock_reserve_ammo_max)
				{
					ammo_count = stock_reserve_ammo_max;
				}

				game::MSG_WriteBits(msg, ammo_count, bit_count);
				return;
			}

			const auto encoded_count = std::clamp(ammo_count, 0, extended_reserve_ammo_max);
			if (encoded_count != ammo_count &&
				!extended_saturation_logged.exchange(true, std::memory_order_relaxed))
			{
				console::warn(
					"[IWZ][Ammo] CP reserve ammo saturated value=%i encoded=%i range=0..%i\n",
					ammo_count, encoded_count, extended_reserve_ammo_max);
			}

			if (encoded_count > stock_reserve_ammo_max &&
				!extended_write_logged.exchange(true, std::memory_order_relaxed))
			{
				console::info(
					"[IWZ][Ammo] writing extended CP reserve ammo value=%i bits=%i stockMax=%i\n",
					encoded_count, extended_reserve_ammo_bits, stock_reserve_ammo_max);
			}

			game::MSG_WriteBits(msg, encoded_count, extended_reserve_ammo_bits);
		}

		int msg_read_reserve_ammo_stub(game::msg_t* msg, const int bit_count)
		{
			const auto extended = use_extended_reserve_ammo();
			const auto ammo_count = game::MSG_ReadBits(msg,
				extended ? extended_reserve_ammo_bits : bit_count);

			if (extended && ammo_count > stock_reserve_ammo_max &&
				!extended_read_logged.exchange(true, std::memory_order_relaxed))
			{
				console::info(
					"[IWZ][Ammo] read extended CP reserve ammo value=%i bits=%i stockMax=%i\n",
					ammo_count, extended_reserve_ammo_bits, stock_reserve_ammo_max);
			}

			return ammo_count;
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			fastfiles::on_weapon_loaded(patch_osa_standard_max_ammo);
			fastfiles::on_weapon_loaded(patch_forge_freeze);
			// Only CG's crosshair-radius calculation calls this wrapper.
			utils::hook::call(0x140789F6A, get_reticle_target_assist);
			console::info("[IWZ][ForgeFreeze] reticle uses stock spread recovery; shatter targeting retains the wider cone\n");

			// The stock writer clamps reserve-ammo counts >= 0x400 to 0x3FF before
			// MSG_WriteBits(..., 10); the paired reader also requests 10 bits. The
			// GSC inventory APIs and playerState reserve slots already use full ints,
			// so widen only this CP wire field and leave MP's protocol untouched.
			utils::hook::nop(reserve_ammo_write_clamp_compare, 6);
			utils::hook::nop(reserve_ammo_write_clamp_move, 4);
			utils::hook::call(reserve_ammo_write_call, msg_write_reserve_ammo_stub);
			utils::hook::call(reserve_ammo_read_call, msg_read_reserve_ammo_stub);

			console::info(
				"[IWZ][Ammo] installed CP reserve-ammo snapshot extension bits=%i->%i max=%i; MP unchanged\n",
				stock_reserve_ammo_bits, extended_reserve_ammo_bits, extended_reserve_ammo_max);
		}
	};
}

REGISTER_COMPONENT(ammo::component)
