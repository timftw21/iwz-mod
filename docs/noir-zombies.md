# Noir-based Zombies: initial design

Version 0.5 | September 10, 2026 | Playable south section

Manual checks passed: FTL movement restrictions, Eraser, respawning, Noir loading
and zombie spawning. The reported script errors are fixed; two consecutive
combat scenes passed on a local server. The user also confirmed the Zombies menu
transition, placement hints and EMC ammo purchases. Rendering defects remain open.

Map title: **TBA**. Base world: **Noir**. Display title and internal asset names
are separate; renaming the title does not change the world's loading requirements.

The browser placement tool is feasible. A complete Zombies conversion is
plausible, but depends on proving that Noir can load the required Zombies
systems and support their enemy navigation. Existing survival maps inherit
these systems from their parent Zombies maps; Noir needs that foundation added.

## Direction

Build round-based Zombies around Noir's nighttime Brooklyn setting and
three-lane layout
([Activision's description](https://blog.activision.com/call-of-duty/archives/announcing-the-first-dlc-map-pack-for-call-of-duty-infinite-warfare)).
Preserve landmarks; add machines, barricades, debris, effects, and a quest.
Exact locations follow geometry inspection.

The finished map launches from the **Zombies Survival map selection UI**, with
its own title, artwork, and normal lobby flow. The Multiplayer launch is only
the foundation test harness; it is not the intended way to play the finished map.

The player is **FTL with the Eraser payload**. Retain the Zombies movement profile:
sprinting, a normal jump, crouching, sliding, and mantling. Disable boost/double
jump, wallrunning, dodging, and FTL movement abilities. Check these restrictions
again after respawning and reviving. Include FTL's body, first-person arms, and
working animations.

Proposed Eraser behavior: combat-earned charge, temporary activation, limited
ammunition, disintegration, then restoration of normal weapons. Tune damage and
recharge for Zombies. Exclude other MP traits. Prototype solo; target 1–4 players.

## Gameplay requirements

| System | Initial direction |
| --- | --- |
| Scenes and economy | Escalating waves, points, drops, and between-scene respite. |
| Perks | Individual machines including Up 'N Atoms (Quick Revive); normal purchase limits, losses, and solo/co-op revive behavior. Final roster follows the asset audit. |
| Magic Wheel | Purchase, randomized weapons, collection timeout, and relocation between marked sites. |
| Wall buys and upgrades | Starter and stronger weapons, ammo refills, Pack-a-Punch, and a second upgrade. |
| Barricades and doors | Repairable entrances and traversal; purchased gates control player access and enemy routes together. |
| Power | Main switch activates linked machines and lighting. Spawn's revive option works before power. |
| Supporting systems | Zombies HUD, downs/revives, spectator/respawn flow, game over, equipment, traps, and Fate/Fortune support including refills. |

Start with revive and two wall buys. Purchased routes open two connected loops
leading to power and upgrades. Required routes must work without advanced
movement; zombies must reach every legal player position.

**Easter egg:** TBA.

## Browser placement tool

**Implemented:** [local geometry viewer](D:/iwz-mod/tools/map-viewer/README.md)
with surface picking, symbol palette, orbit/pan/zoom, top view, height clipping,
numeric positions/yaw, moving, duplication, deletion, undo, JSON import/export,
and **Save & install**. The initial layout contains four references, Quick Revive,
and an EMC wall buy. The user's south layout now has 13 markers, including a new
player start at `ref_south`; its original 12 placements are preserved. Player and
zombie spawns, power, solo Quick Revive, EMC, Wheel and barricades are active.
Save validates map identity, geometry fingerprint, IDs, coordinates and normals,
then generates the GSC used on the next match. Limit: 32 markers.

The broader editor design below remains the target. Linked rooms, purchased
gates and full window entrances remain pending; placed barricades now create
and remove navigation obstacles as their boards are repaired and destroyed.

Build a local browser app with geometry, marker palette, and properties panel.
Include orbit/fly controls, top view, and floor isolation for interiors.
Select **Quick Revive**, click a surface, adjust facing/height, and save.
Show its symbol, facing, footprint, and interaction area. Support moving,
duplicating, deleting, undoing, and importing layouts.

Use points for machines, weapons, player spawns, and quest objects; boxes for
zones/triggers; linked entry/exit points for barricades and traversal. Properties
include price, weapon/perk, power circuit, zone, and linked objects. Each marker
selects a preset supplying the actual model and behavior.

**Geometry acquisition:** first export untextured world triangles and essential
static props from the installed map using ZoneTool data or a small native
exporter, then convert to GLB. GSC/entity dumps lack the surface mesh. Include
relevant geometry chunks and prop transforms; report missing pieces. Show
collision separately and account for props/collision created by startup scripts.

Start with stripped geometry; simplify decoration if necessary while retaining
accurate surfaces for placement. Collision geometry is a fallback if visual
extraction stalls, subject to coverage checks.

**Coordinates and output:** keep the game's origin, units, and Z-up coordinates;
never silently recenter or resize the map. Record any display transform and its
inverse. Save versioned JSON with map/geometry fingerprint, stable object IDs,
game positions/angles, surface normals, presets, and properties. Presets handle
model pivots and surface offsets.

One converter validates this layout and produces placement GSC plus required
asset references. Game code creates the matching objects, interactions,
collision, and navigation obstacles. Reject mismatched maps, duplicate IDs,
missing links, and invalid coordinates. Start with export → game restart →
manual inspection.

The tool edits added gameplay objects. Moving an existing scripted prop needs
an explicit supported adapter; cutting walls or rebuilding baked collision,
lighting, and navigation is outside this first editor's scope.

## Foundation evidence and unresolved work

- A private headless run confirmed **Noir = `mp_prime`**. Its world, collision,
  and native navigation loaded in MP; the engine reported **10 agent slots**.
  Four authored spawn positions, including the opposite end and higher ground,
  returned navigation points. This verifies queries, not connected routes or
  zombie movement. Spawn-to-nav offsets ranged from 8.1 to 32.6 game units.
- The [native exporter](D:/iwz-mod/src/client/component/noir.cpp) produced a
  **22.3 MB GLB**, containing 14,353 static world surfaces / 779,525 triangles.
  [Khronos validation](https://github.com/KhronosGroup/glTF-Validator) reported
  zero errors/warnings and 209 degenerate source triangles as informational.
  The actual Three.js GLTF loader and triangle picker reproduced all six seed
  marker coordinates within 0.000001 game units. The engine created their
  anchors with **zero coordinate error**. Bullet-collision offsets at these
  surfaces were **0.001–0.006 units**, including the west ramp and lower floor.
  Visual alignment and facing still require a manual client check.
  The export explicitly omits 7,178 static props, brush models, dynamic/scripted
  objects, collision, and navigation. It is a usable world-mesh foundation,
  not complete placement coverage.
- **Asset obstacle resolved:** new IW7 animation-class and behavior-tree writers
  produce an isolated `iwz_noir_zombies.ff` bundle. The animation class and tree
  survived a dump/reload comparison unchanged. The bundle contains the stock
  zombie character, animation clips, effects and scripts, with separate network
  tables for its animation class and 67 character dependencies, including limbs
  and hair, plus seven south-section props. It adds no second world, collision
  or navigation map. Runtime: **MP**.
- **Client preload correction:** the first client test exhausted the stock
  15,616-image pool. Zombie assets now load synchronously at match startup,
  after leaving the lobby, instead of being appended to lobby map preloading.
  Noir starts through the full loading path, and the dependency uses its own
  gameplay flags rather than inheriting the map's already-preloaded flag.
  The current server loaded the expanded bundle with **312 image slots free** and registered
  its animation/model tables. The user now confirms Noir loads and zombies spawn.
  The renderer's fixed streaming tables prevent simply raising the image-pool
  count safely.
- **Combat evidence:** three stock zombies spawned, navigated a nearby route,
  dealt 45-damage melee hits, took ERAD and Eraser bullets, died, awarded points,
  and completed Scene 1 without script errors. A separate run verified death
  and respawn after a zombie attack. The shooting test used engine-generated
  bullets attributed to a test bot; manual weapon handling and rendering still
  need checking. The test helper has been removed from the installed game.
- **Runtime error fixed:** native `max()` changed the living-zombie counter to
  a float after a kill; the next increment failed and scenes advanced with live
  enemies. Both scene targets and decremented counters now retain integer types.
  Two consecutive scenes (three then five kills) passed with exact live counts,
  at most three living zombies, agent reuse, and no script runtime errors.
- **Placement purchase:** a local server verified EMC grants for 500 points,
  ammo refills for 250, and rejection without charging for insufficient funds,
  distance, a full inventory without a valid held replacement, and full ammo.
  The first UI entry assigns FTL/Eraser through the live class extension point;
  a server confirmed both fields without changing saved MP loadouts.
- **First Zombies UI integration:** Survival now includes **UNTITLED - NOIR
  PROTOTYPE**. Selection requests the MP foundation runtime, waits for it to be
  ready, then launches a solo Noir match with placement enabled. It deliberately
  avoids stock CP map-hover preloading. Lua dispatch and isolation checks pass;
  actual menu navigation and the CP-to-MP transition need the user's client test.
  This begins the UI migration; a full CP runtime, final artwork/title, and
  normal Zombies lobby/game-over flow remain future work.
- **Menu launch correction:** the client log showed the click reached native
  code but remained in CP until timeout. The native mode setter rejects a direct
  CP-to-MP request. The launcher now leaves the stock Zombies lobby, replaces
  its menu stack with MP's, waits for CP shutdown (`NONE`), then requests MP.
  Map startup also waits for the stock MP menu to finish initializing its dvars.
  Transition logs now include active mode, synchronization flags and menu readiness;
  repeated clicks are ignored. Native setter and Lua transition checks pass;
  the corrected full client transition awaits a manual check.
- **Remaining checks:** visuals, Eraser death effects, and full-map routes.
  The user's screenshot shows orange/camouflage-like zombie clothing, dark heads
  and hands, and apparent foot offsets. The rendering cause is not established;
  do not treat the successful server tests as visual validation.
  A long pursuit after a player respawn stalled
  near `(136, 1542, -56)`; nearby navigation success does not prove every route.
  Co-op and Zombies balance are not validated.
- [Shared perk code](D:/iwz-mod/data/cdata/custom_scripts/cp/survival_perks.gsc)
  and [survival work](D:/iwz-mod/docs/subway-shuffle.md) provide behavior to reuse
  once Zombies systems and assets are loaded.
- Both GSC dumps contain `allowdoublejump(0)`, `allowwallrun(0)`, and
  `allowdodge(0)` in `zombies_loadout.gsc`. The organized dump's
  `mp/battlerigtable.csv` and `mp/supertable.csv` identify FTL as
  `archetype_assassin`, Eraser as `super_atomizer`, and its weapon as
  `iw7_atomizer_mp+atomizerscope`. Eraser's base weapon was present in the Noir
  server. The user confirmed FTL movement restrictions, Eraser and respawning
  in the MP foundation. A Zombies player suit is not needed for this MP rig.
- [Aurora](https://docs.auroramod.dev/loading-usermaps) and
  [ZoneTool](https://github.com/Joelrau/x64-zt#supported-games) explicitly exclude
  IW7 custom-map support. The plan therefore uses an existing map with added
  gameplay. Asset dumping is not evidence that map rebuilding works.

## Current manual test

The south-section local server run had **zero script runtime errors** and verified:
initial and repeat south spawning, authored zombie spawn selection, power gating,
perk purchase guards, native lethal-hit last stand and revival, Wheel payment /
collection / expiry, and barricade navigation / repair / zombie damage.
One physical-collision ray check failed; the follow-up capsule check was stopped
at the user's request to begin manual testing. Barricade player collision remains
unverified. The test helper was removed. Machines and board alignment,
animations, held-weapon replacement and practical combat routes still need a
human visual check. Current barricades use the stock six-board model's individual
parts; stock window animations and entrance AI are pending.

Open the [viewer](http://127.0.0.1:8765), already running locally for this test.
For subsequent sessions, run `tools/map-viewer/start.ps1`.
Select `revive_south` or a reference and **Focus**. Lower the height slider to
see interiors. Place/move a symbol and choose **Save & install**.

Restart the installed game, then open **Zombies → Solo → Survival → UNTITLED -
NOIR PROTOTYPE**. This launches the current solo foundation with automatic
FTL/Eraser, unlimited time and placement enabled. Check that the new button is
reachable and that the runtime switch launches Noir successfully. Returning from
this prototype still uses the MP frontend; the finished Zombies flow is pending.

The existing manual MP path remains available: set `iwz_noir_foundation 1` and
`iwz_noir_placement 1`, then start/restart private **Free-for-All on Noir**. The
[combat script](D:/iwz-mod/data/cdata/custom_scripts/mp/maps/mp_prime/noir_zombies.gsc)
waits for the match countdown before spawning enemies.

Compare the four reference dots across the map and their facing: the small white
dot is 48 units forward and 4 units above the colored surface anchor. Captions
identify nearby markers. At `emc_south`, face the marker and press **Use** to buy
EMC (500 points) or ammo (250). With two normal guns, buying a new EMC replaces
the held gun; switch out of Eraser first. Check this replacement manually.
The player starts and respawns beside these machines at `ref_south`. Quick Revive
costs 500, works before power, and allows three purchases per match. A lethal
zombie hit uses native last stand, consumes the perk, and revives in place after
three seconds, followed by three seconds of protection. Full death clears the
perk and keeps the prototype's respawn behavior. Co-op revival is pending.

Use `power_1` to enable the Magic Wheel. It costs 950 and offers NV4, ERAD, Rack-9
or Mauler, avoiding owned guns where possible. The result appears after three
seconds; the buyer has 15 seconds to collect it. With two normal guns, collection
replaces the held gun; Eraser is protected. Check gun and machine alignment.

Hold Use at `barricade_1` to repair damaged boards, one per second. Repairs award
10 points, capped at six paid repairs per barricade per scene. Nearby zombies
break boards; the last board removes the navigation obstacle, and rebuilding
restores it. This is freestanding cover, not yet a stock vaulting window. Enemies
can navigate around its ends. The three authored south zombie markers drive the
waves; blocked or occupied points wait instead of falling back elsewhere.

Scene 1 has three zombies with 200 health, at most three alive together. Kills
award 50 points (100 for headshots), hits award 10, and the next scene is scheduled
after eight seconds. Eraser currently dealt 135 body damage in the server test;
balance is provisional. Check models/animations, pursuit around corners and
stairs, normal gunfire, Eraser, points, the next scene, and death/respawn.
Doors, Pack-a-Punch, remaining perks, full Zombies HUD and game-over flow remain
later milestones. A small status display now shows scene, points, power and revive.
The map still uses the MP runtime through its confirmed Zombies Survival button.

Results are under the game's `iw7-mod/map-data/mp_prime/` (`audit.json`,
`world.glb`), with `[IWZ][Noir]`, `[IWZ][NoirCombat]` and `[IWZ][MapLayout]`
entries in `logs/console.log`. Geometry export is now requested manually.
`iwz_noir_audit` repeats the asset check; `iwz_noir_export` repeats both checks
and export during the match. To stop the probe, set `iwz_noir_foundation 0`
and restart the match. It defaults off on a fresh game launch.

## Build order and acceptance

1. **Prove the foundation.** Confirm Noir's asset identity; audit geometry,
   collision, navigation, and Zombies/FTL dependencies. Use the MP runtime with
   stock zombie AI and the isolated dependency bundle.
   Pass when a zombie navigates corners/stairs, attacks, dies, awards points,
   and lets a scene finish. Check blocked/open gates and FTL/Eraser restrictions.
   Browser navigation data cannot substitute for the game's navigation format.
2. **Prove placement.** Export one representative area and place a revive
   marker. Compare at least four reference points spanning both horizontal
   axes and different heights, plus object facing. Target ≤1 game unit of
   coordinate error before model offsets. Verify the actual purchase in-game.
3. **Build a playable section.** Deliver spawn, waves, a barricade, purchased
   gate, power, perk, wall buy, Wheel, and Pack-a-Punch through the same layout.
   Add its normal Zombies Survival menu entry and lobby launch flow.
4. **Expand and finish.** Complete the map, quest, supporting systems, and
   co-op. Manually check unreachable spots, stuck enemies, revive/respawn
   behavior, reconnects, and progression before balancing.

Log export coverage, transforms, placements, missing assets, navigation failures,
and gameplay state under `[IWZ][Noir]` / `[IWZ][MapLayout]`. Review logs after
manual playtests. Resolve loading/navigation failures before expanding; update
this document with each milestone's evidence and decisions.
