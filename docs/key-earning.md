# Key earning: recovered client contract

IWZ-MOD now awards match keys using **approximation v1**, authorized on September
4, 2026. These rates are explicit design choices, not the recovered vanilla
Demonware equation. The previous emulator returned an empty Currencies array
on match completion. The existing daily-login grant remains separate.

## Approximation v1

Balances use hundredths of a key (100 units = 1 key).

| Mode | Base award | Example |
| --- | --- | --- |
| Zombies | 0.8 keys per completed Scene, up to 125 keys per match | Ending on Scene 31 gives 24 keys |
| Multiplayer loss/draw | 1 key per 300 seconds played | 150 seconds gives 0.50 keys |
| Multiplayer win | Same time award with a 25% bonus | 300 seconds gives 1.25 keys |

The ending Scene is the Scene reached: Scene 1 completes none; Scene 2 completes
one. Zombies requires positive survival time, but time alone does not earn keys.
The Zombies cap applies before the double-key multiplier, allowing 250 keys
with double keys enabled. Multiplayer uses the stock reported 0/1 result;
the mod does not reinterpret the game's win/draw classification.

`online_double_keys` doubles the computed award in either mode. IWZ-MOD's
Double XP setting (`iwz_double_xp`) also enables double keys for Zombies.
Both enable the same 2x bonus; they never stack to 4x. The setting is evaluated
when EndMission arrives, using its mission type even if the player has left
the Zombies menu. Other XP multipliers do not affect keys. Multiplayer calculations
multiply before dividing and truncate only sub-hundredth values. The wallet
retains hundredths across matches and restarts (two 0.8-key awards total 1.6).
Unknown mission types, invalid results, and nonpositive durations award zero.

No extra timer grants keys. Awards occur when the existing native EndMission
request arrives, using its reported Scene/result and time. A quit or crash that
does not submit that request has no additional payout fallback. Existing stock
special-mode reporting is preserved; the service does not infer new results.

## Persistence and duplicate handling

StartMission reserves a persistent, increasing ID in the existing `loot.json`
under `KeyRewards`, recording its mission type. Finishing it credits currency
11 and consumes that ID in the same file replacement. A repeated end request,
including after restarting, cannot credit the same ID twice. ResetMissions
does not recycle reward IDs or remove another local controller's pending start.
Only the newest 64 pending starts are retained, bounding abandoned lobby visits.

Wallet saves write a sibling temporary file, check the write and close, then
replace the live file. Failed key-reward saves restore the in-memory state and
return a service error, allowing retry. The signed stock-UI balance limit is
respected without wrapping or reducing an already larger legacy balance.

The response contains an absolute balance and echoes ClientTx, so the native
handler supplies the usual commerce refresh and after-action reward display.

## GSC and Lua

- `scripts/cp/cp_gamelogic::get_time_survived` returns
  `int((gettime() - level.starttime) / 1000)` unless the map overrides it.
  Endgame publishes this through `zm_time_survived`.
- `ui/postgamemanager.lua::FinalizeCPGame` checks online Zombies, client match
  data, and its finalization guard. For each local controller it calls
  `Rewards.EndZombies(controller, waveNumber, timeSurvived)`.
- `ui/utils/mp/missiondirector.lua` defines multiplayer mission 0 and Zombies
  mission 1. Private and public Zombies menus call `Rewards.StartZombies`.
- Multiplayer passes round time and a win/loss result to `Rewards.EndMission`.
  Zombies Scene must therefore not be interpreted as a multiplayer win flag.

The three UI files were decompiled individually into `.tmp/key-earning-re`.

## Native reverse engineering

Evidence source: the existing unpacked runtime image in
`.tmp/ammo-re/iw7_ship.runtime.bin`, image base 0x140000000. Analysis used
bounded strings, the Lua registration table, and small function ranges.

- Lua registration table: 0x141497230–0x1414973C0.
- `Rewards.StartZombies`: 0x140530FE0. Records the supplied mission ID and
  formats the StartMission JSON at 0x1414975B0; MatchId is 0.
- `Rewards.EndZombies`: 0x140531110–0x140531349. Converts the Lua numeric
  arguments to integers and formats the EndMission JSON at 0x141497790:
  Action, MatchId, MissionId, MissionInstanceId, MissionResult, TimePlayed,
  ClientTx. Scene and seconds are forwarded; this code does not compute keys.
- Reward reporting dispatch: 0x140533490, called by both of those wrappers.
- EndMissionResponse handler: 0x140533B4F. Calls 0x140532F80 to find the key
  balance difference, stores it for the after-action rewards screen, handles
  items, then refreshes commerce through 0x140515FE0.
- 0x140532F80 reads the current currency 11 balance, reads the returned
  Currencies array's Balance, and subtracts the current value. The wire reply
  must carry an absolute balance, not merely the earned amount.
- Existing loot storage and daily login use 100 currency units per key, so
  hundredths can persist across matches without discarding fractional progress.

The match payout is an original Demonware server responsibility. Neither the
examined GSC/Lua nor these native request/response paths contains that equation.
The legacy service tasks incrementTime/claimRewardRoll are also stubs, but the
traced Zombies route is task 4's EndMission event, not those legacy tasks.

## Diagnostics

`[IWZ][Keys]` records mission starts and ends without requiring the
`demonware_debug` launch flag. It includes mode, mission instance, result,
survival seconds, approximation version, double-key state, earned hundredths,
and old/new balances. Completion logs distinguish a saved payout from a
duplicate/unknown instance. Save and request failures are logged as errors.

For exact calibration, vanilla observations need before/after key balances
(including progress if visible), ending Scene, elapsed gameplay seconds,
mode, and whether a double-key event was active. The mod's local emulator cannot
supply the original server's balances by itself.

## Validation

The payout calculator and the actual wallet functions were exercised in an
isolated temporary C++ harness. Checks covered rates, cap and multiplier,
fractional accumulation, invalid inputs, large values, duplicate and mismatched
instances, restart/reload, failed-save rollback and retry, balance saturation,
and bounded abandoned starts. No real player wallet was changed by these checks.
Release x64 and the build's UI lifecycle checks pass. In-game reward presentation
and live request delivery still require a manual playtest.
