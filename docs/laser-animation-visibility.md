# Laser visibility during gestures

## September 4, 2026 correction

The previous fix treated `GestureWeaponSettings::useLeftIdleAkimbo` as an
exclusive hand selector. That setting controls an akimbo idle fallback. It
does not say whether a separate right-hand animation is playing, and it cannot
describe both hands using the gourd. The normal weapon model and its laser tag
can remain renderable while the animation moves the gun out of view.

`src/client/component/laser_visibility.cpp` now checks both client gesture slots
for the hand currently drawing its laser. A playing/in/out slot suppresses the
laser when its main weapon animation weight is below 1. The native -1 sentinel
means the slot is not contributing and does not suppress anything. An OFF slot
also does not suppress, respecting cancellation of the right-hand animation.

This applies to hand 0 for both single and akimbo weapons, and independently to
hand 1. It also covers directly scripted viewmodel gestures and client blend-out
after the server offhand flag clears. The previously tested left-akimbo idle
fallback remains through the offhand ending flag. Model/bone visibility checks
remain separate. There are no weapon names, map names, or fixed timers in the rule.

## Evidence

GSC dump: `dumps/iw7-gsc-dump/decompiled/scripts/cp/maps/cp_disco/kung_fu_mode.gsc`
calls `playgourdgesture`, which passes the gourd weapon to
`scripts/cp/utility::firegesturegrenade`. That helper calls `giveandfireoffhand`.
Other pickups and interactions use the same mechanism. GSC does not provide
the client animation's per-hand visibility state.

The September 4 console log resolves `ges_gourd` with `useLeftIdleAkimbo=1`
while hand 0 keeps reporting 10/11 visible gun surfaces. That explains why the
old hand selector and all-surfaces-hidden check both miss the supplied image.

Bounded disassembly of the IW7 runtime executable confirms:

| Address | Evidence |
| --- | --- |
| `0x140158570` | Client gesture-info getter; arguments are local client, slot, hand |
| `0x140159569` | Returns `cg + 0x59814 + (slot * 2 + hand) * 0x44` |
| `0x14015AF11` | Stores the gesture asset index at info `+0x40` |
| `0x14015FE40` | Updates per-hand animation state at info `+0x38` |
| `0x140160019` | Checks right-hand cancellation; clears only that hand's state |
| `0x140160123` | Retains client OUT state after the server slot clears |
| `0x14015ACBF` | Resets noncontributing slot weight at info `+0x34` to -1 |
| `0x140161C6F` | Main-tree update consumes the state and weight of each slot |

The related [OpenIW8 gesture code](https://github.com/0xLogic/OpenIW8/blob/main/workspace/iw8/code_source/src/cgame/cg_gesture.cpp)
helped identify the functions. All offsets and call signatures used by the fix
were checked against IW7, not copied from IW8. Runtime byte guards cover the
getter, its slot layout, and the native state/weight reads.

## Validation and logs

Focused checks using the implementation cover independent hands and local
clients, both slots, two-handed actions, OUT state, right-hand cancellation,
restored weapon weight, and noncontributing slots. Native patch bytes were
compared with the executable dump. These checks do not replace an in-game
visual test.

`[IWZ][LaserVisibility]` suppression entries include hand, gesture, slot,
animation state, and primary animation weight. Restoration is also logged.
The user should check the gourd with single/akimbo guns, a left-only pickup,
and cancellation by firing/reloading, including the return of each laser.

## Movement regression correction

The user confirmed the single/akimbo interaction fix, but reported missing
lasers during ordinary sliding. The log identifies `ges_default_slide` and
`ges_default_slide_akimbo`: both reduce the primary animation weight even
though the guns remain visible. A reduced weight alone is not a visibility rule.

The client-slot check now also requires an offhand shield, thrown weapon,
offhand script weapon, or script interaction priority, using IW7's
`GesturePriority` categories. Movement and demeanor categories are excluded;
no slide names or transient weapon-state numbers are hard-coded. Unknown or
unresolved categories are left to the existing model/bone visibility checks.

Filtering happens per slot. A movement slot does not prevent an interaction in
the other slot from suppressing its laser. The asset is resolved from the client
slot's saved index, so interaction blend-out still works after the offhand flags
clear. Suppression logs now include the asset priority.

## Visible primary gun during a left-hand action

The next screenshots show an available right-hand pistol during the radio and
pickup actions. Both slots can animate and reduce the primary tree weight
without putting that pistol away. The interaction-priority filter alone was
therefore still too broad.

The actual dumped definitions for `iw7_walkietalkie_zm`, `iw7_pickup_zm`, and
`iw7_powerlever_zm` set `gesturesDisablePrimary=false`. The native primary-weapon
processing predicate at `0x14071AFB7` reads this field at WeaponDef `+0xCE0`.
The fix now preserves hand 0 when its client gesture belongs to the current
offhand weapon and that definition permits the primary weapon. Hand 1 still
uses its own suppression rules. Definitions that disable the primary weapon
retain the existing animation timing checks.

The definition is resolved using the same weapon-map layout as IW7's offhand
lookup at `0x140716F73`: the handle at playerState `+0x860` selects the weapon
index at `weaponMap + 0xA + handle * 0x10`, then `bg_weaponDefs[index]` supplies
the definition. A compile-time offset check and a runtime instruction guard
cover the primary-disable field. Matching the exact gesture against the nine
offhand gesture fields avoids exempting an unrelated overlapping animation.
The lookup does not depend on active/ending flags, preserving the same policy
through client blend-out after those flags clear.

Model/bone hiding can still reject a preserved primary laser. Successful
preservation is logged once per transition as `preserved hand 0 laser` with the
gesture name and `gesturesDisablePrimary=0`.

Focused checks now also cover the radio/pickup settings, preservation across
all three animation phases, left-hand suppression, primary-disabling actions,
and simultaneous gestures that must not share the exemption. Visual checking
remains manual.
