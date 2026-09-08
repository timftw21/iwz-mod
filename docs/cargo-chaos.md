# Cargo Chaos

The Beast from Beyond (`cp_final`) is available as **CARGO CHAOS** under
Survival Films. The map script loads only with `iwz_survival_mode=1`.
The regular Beast map keeps its stock startup and travel routes.

## Recorded placements

The five September 7 CrosshairCoords records, in order:

| Time | Purpose | Hit position |
| --- | --- | --- |
| 445250 | Player spawn | (1615.91, 3415.9, 15.998) |
| 491250 | Permanent Magic Wheel | (1490.66, 3600.26, -133.512) |
| 623050 | PaP teleporter | (1740.77, 1719, 50.6194) |
| 780950 | Perk wall | (1016.51, 2146.27, -121.799) |
| 978900 | Death Wish | (1269.19, 3138.23, -128.711) |

Spawn is one unit above the measured floor, facing the recorded yaw -89.1986.
Occupied spawn positions use the cargo portal's authored landing points,
grounded and checked for player overlap. The perk wall sits four units off the
measured surface normal (0.736097, 0.676876, 0), yaw 222.6 because the board
faces along negative forward. Death Wish sits on the measured glass surface,
without a barrel, facing yaw 87.121. The shared jar code applies its model-base
offset and provides the red effect, toggle sounds, faster zombies, shorter
between-Scene waits, and red Scene counter. Beast's laser trap supplies the
`zmb_trap_laser_start` / `zmb_trap_laser_end` sound pair.

The follow-up screenshot places the perk board about one board-width left of
the cargo panel's center strap. Its model is 30.08 units wide. The corrected
surface is (994.84997,2169.82511,-121.799): 32 units to the right when facing
the board, tangent to the measured wall normal. Height and wall clearance
remain unchanged; the logged surface and interaction positions follow it.

## Map and script evidence

Decoded the 395,095-byte text entity table at
`dumps/CODIW-Source/maps/cp/cp_final.d3dbsp`. Numeric keys resolve to origin
(543), angles (65), target (820), targetname (822), script_noteworthy (638),
script_parameters (61049), script_area (60666), and model (497).

- The combat volume is `cargo`, with authored `cargo_spawner` entrances.
  Initial and active volumes are restricted to cargo; its windows are enabled.
- The wheel's out-of-order sign is `pf19_auto2` at (1491, 3603, -139), only
  6.1 units from the wheel trace. Its spinner is at (1493.73, 3606.94, -120.6).
  `cp_final::init_magic_wheel` normally chooses op_room, cargo or planet_outside.
  Cargo is selected before the shared initializer runs, the actual nearby
  cargo wheel is activated with `interaction_magicwheel::init_magic_wheel`,
  and the same no-teddy counters as Arcade Attack are reset after each spin.
  The relocation callback also keeps this physical wheel active.
- The one exit is `pf28_auto667`, with purchase structs at (1472, 3648.5, 44)
  and (1472, 3677.5, 46). Both are removed from the interaction list after
  initialization; its stock doors and solid brush remain closed.
- The portal struct is `cargo_room`, target `pf4_auto1`, at (1744, 1870, 64).
  Its stock destination is the theater. The measured third trace hits the
  wall behind the portal. Its authored trigger is (1745, 1820, 64), FX spot
  (1745, 1803, 20), and blocking clip (1743, 1810, 64).
  The stock power-on door animation leaves the center leaves blocking entry.
  The player must use `portal_gun_button` at (1918,3506,72). Stock
  `portal_gun_activate_func` moves and charges the cannon;
  `blast_doors_with_gun` fires its beam, plays the impact and deletes the leaves.
  The PaP image is visible behind the cracked door leaves from power-on.
  Only after the laser completes is the local clip made nonsolid and travel enabled.
  The visible ring is centered on the cannon's authored doorway target
  (1745,1827,68). Its three ring emitters spawn an average 12.15 units forward
  of the FX origin, so the effect starts at (1745,1814.85,68). This moves the
  ring 11.85 units forward and five down, aligning it with the doorway plane
  instead of leaving it behind the frame.
- Cargo return points are (1696,1886,64), (1728,1918,64), (1776,1918,64),
  and (1792,1886,64). The last point uses the stock fast-travel correction
  to (1752,1918,64). Return yaw is 90 degrees.

Compared the organized map scripts with the retail names and method calls in
`dumps/iw7-gsc-dump/decompiled/scripts/cp/maps/cp_final/`. The organized dump
mislabels `playershow` as `gold_teeth_pickup`; the return callback uses the
retail method. The second dump also preserves fields such as `level._id_BEC5`.

Power uses the normal quest progression in `zombie_quest::start_quest_line`.
The retrieval wait completes only after `spawnn31lhead` publishes its one
randomly selected head model. Placement waits for `zombie_power::_id_96F4`
to initialize `power_on`, then completes automatically before Scene 1.
Stock `completeretrieveneilshead` removes the pickup; `completeplaceneilshead`
places the dynamic head in the terminal, runs `turnonfacilitypower`, enables
area power and Fire Sales, and sets NEIL happy. Its normal completion rewards
are retained. The stock Scene selector and event handlers run unchanged.
Power remains on, so Scene 1 uses zombies and later events use `alien_goon`.
The powered cryptid budgets are 6, 9, 12, then 16 enemies per player on
successive special rounds. Stock event music and the final-kill Max Ammo
callback remain responsible for those round effects.

PaP entry calls Beast's stock hidden-tube path. Both the manual exit and the
30-second timeout call the overridden `teleport_to_safe_spot`, returning to
cargo. Stock protection, consumable restoration, timer and audio cleanup remain
in their original callers. Re-entry respects Beast's timer cooldown, which
continues briefly after leaving. Double PaP is enabled after its fuse flag
and player machines exist: `fuses_inserted=1`, `placed_alien_fuses=1`,
`pap_max=3`. Beast's own machine helpers apply the upgraded model and part
states; its join-in-progress path reads `placed_alien_fuses` for later players.

The first playtest identified seven GSC runtime errors. Two flag waits and
the power completion ran before the five-second stock power initializer;
that initializer subsequently reset power to zero, also causing the wrong
cryptid round type, counts, missing music and missing Max Ammo. Initialization
now precedes both the power completion and portal wait. The remaining four
errors came from remote glyph watchers using an effect removed with the normal
portal initializer. Their `portal_console_init_func` is disabled for survival,
since those paired theater routes are not initialized. The laser's two effects
are explicitly loaded for the retained stock cannon sequence.

The Entangler's authored pickup at (1523.6,2772.9,-267) unlocks by default
after `init_interaction_done`. `crafted_entangler::init` has already registered
its one-shot `complete_stay_on_pressure_plates` listener. Sending that stock
event enables the pickup, creates its floating weapon and floor FX, and keeps
the normal per-player collection and death/recollection behavior. Cargo logs
readiness after the stock listener publishes the pickup's `_id_870F` model.
The latest playtest log contained no new GSC runtime errors before these changes.

## Portal asset reverse engineering

Decoded the complete 18,516-byte `vfx_rave_portal_02.iw7VFX` using x64-zt's
IW7 particle layouts and record serialization. Of its seven emitters, emitter
6 owns the PaP image: model `vfx_energy_rave_portal_paproom`, material
`el/vfx_zmb_paproom`. Its `m_offset` is zero, but its spawn-box min/max are
both -7.29 along local X; the model also has a nonzero local bounds center.
Emitter 0's box spans 11.15–13.15 along X, and emitters 1/2 span 8.1–16.2.
All three luminous ring emitters therefore share a 12.15-unit mean forward
offset, which the doorway placement compensates for. These are bounded reads
of the original 18,516-byte asset, with no changes to the effect itself.
The 1,040-byte model references
`mopw/vfx_zmb_paproom` and `vfx_energy_portal_b_lod010v0p3_0040` geometry.

Beast's dumped `cp_final.csv` confirms all ten material/light/geometry
dependencies already exist. The small `iwz_cargo_chaos` zone therefore packs
only the exact Rave effect and model, retaining references to those existing
dependencies. No guessed scriptable state or alternate portal image is used.
The visible image is centered at the authored FX spot plus 53 Z:
(1745, 1803, 73), facing +Y, inside the existing door frame.

Sources and zone manifest are in `assets/cargo_chaos`. Copy its `zonetool` and
`zone_source` contents to the game directory and build with ZoneTool:
`-no_common -no_code_post_gfx -buildzone iwz_cargo_chaos`. Deploy the resulting
fastfile to `iw7-mod/zone`. The client queues this zone and the shared red-jar
zone after `cp_final`, and logs missing assets explicitly.

## Script capacity and validation

The preceding Beast log used 4,016 of 4,095 canonical-name slots. Bounded
disassembly of just 0x140BFD340–0x140BFD4AB reconfirmed the 4,095-slot table,
its separate buffer at table+0x4000, and the different 0x1C000 buffer limit.
Changing the limits or just adding runtime guards would not address loading
unused names.

The loader now supports `survival-only` and `gns-arcade-only` discovery headers.
It handles Boolean, integer and UI-created string dvars. Ghosts N Skulls' shared
win-command listener moved unchanged into `ghosts_n_skulls_controls.gsc`;
the mode-specific launch/endgame implementation loads only when that mode is
selected. Ordinary map cabinets and the command retain their shared controls.
Cargo's shared survival libraries are not linked into standard Beast.

The first Cargo playtest linked 4,063 names, leaving 32 slots. The follow-up
uses existing stock fields for round budgets and PaP state; its compiler symbol
comparison is checked against that measured baseline.

The Release x64 client build passed with zero warnings and zero errors.
Validation includes production/developer GSC compilation and assembly, Lua
syntax checks, the UI lifecycle validator, and a temporary test exercising the
actual loader predicate with absent/Boolean/integer/string dvars. The built
4,272-byte fastfile decompresses to 21,327 bytes; its version, complete payload,
two portal assets and all ten references were verified. Temporary checks and research
artifacts remain outside the tracked source tree.

Manual playtesting is still required. `[IWZ][CargoChaos]` records spawn,
actual round enemy types and budgets, power/head state, door counts, wheel state and PaP
entry/return. Shared perk and Death Wish logs cover purchases, toggles and HUD
color. Confirm the laser button and centered portal, a double PaP purchase,
the first cryptid round's music/count/Max Ammo, both PaP exits, and no GSC
runtime errors during the next run. Co-op spawning and join-in-progress also
remain part of manual testing.

## Venom Z

Cargo's Magic Wheel now awards `iw7_venomx_zm_pap2+camo34` (Venom Z).
`interaction_magicwheel::_id_1010C` calls `level.nextwheelweaponfunc` before
its quest-gated Venom roll. Cargo supplies that same 4% roll through the callback
and disables the later stock Venom-X substitution. The stock ownership check
still prevents a player from receiving a second Venom weapon.

## Silent Entangler unlock

The stock Entangler activation sets quest bit 2. Beast's UI maps that bit to
`questArkGreenAlpha`, which both lights its inventory icon and triggers the
`questFullScreenSplashDLC4` piece-found animation. Cargo uses the recovered
splash constructor with only that notification subscription removed. The pickup,
inventory icon, manual inventory and other eight quest notifications keep their
stock behavior. Standard Beast keeps the original splash constructor.

The UI logs installation under `[IWZ][CargoChaos]`. Lua syntax, UI lifecycle and
an isolated constructor check passed, including the other notifications and
standard-map/frontend isolation. The client build passed; visual confirmation
still requires a manual match.
