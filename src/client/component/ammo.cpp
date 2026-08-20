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
