# Zombie Collision and Clown Spawn Handoff

## Goal

Reduce player bouncing/flinging when colliding with traversing zombies and provide a reliable `spawnClown` test command for the Spaceland overlap case.

## Current implementation (2026-08-06)

- `data/cdata/custom_scripts/cp/zombie_collision.gsc`
  - Disables `scr_zombie_traversal_push` and `bg_playerEjection`.
  - Reduces zombie movement capsule radius from 15 to 12.
  - Keeps traversing zombies solid. It disables the separate stock traversal-player redirect and engine overlap-ejection pass while retaining the reduced physical capsule.
  - Watches `agent_spawned` and logs the stock `traverse_begin` / `traverse_end` notifications without changing solidity.
  - Wraps the map-selected `level.callbackplayerdamage` and adds IW7's stock `idflags_no_knockback` flag only to zombie melee hits. The stock generic zombie melee script reports these as `MOD_IMPACT`; `MOD_MELEE` is retained for variants using the same damage callback.
  - Listens for `iwz_spawn_clown` and attempts to create `zombie_clown` at the player through the dump-derived spawning functions.
  - Uses `post_load()` so the patch is started after IW7's stock `Scr_LoadLevel` work.
- `data/cdata/custom_scripts/cp/gsc_diagnostics.gsc`
  - Provides a shared `emit(channel, message)` helper controlled by `iwz_gsc_diagnostics`.
  - Sends formatted messages through `level notify("iwz_gsc_log", message)`.
- `data/cdata/custom_scripts/cp/patches.gsc`
  - Contains only the interaction-point and door-price patches now.
  - Avoids the throwing `getfunction` door hook; instead waits for the dump-confirmed `level.post_nondeterministic_func` value before replacing it.
- `src/client/component/command.cpp`
  - Registers `spawnClown` and sends `iwz_spawn_clown` to the level with the requesting player.
- `src/client/component/scripting.cpp`
  - Logs generic `iwz_gsc_log` VM notifications and retains `iwz_collision_log` compatibility.
  - Logs delivery and argument count for `iwz_spawn_clown` VM notifications.
- `src/client/component/gsc/script_loading.cpp`
  - Reports the exact filesystem/asset source used for every compiled custom GSC.
  - Preserves the working pre-load timing for existing `main` and `init` handles.
  - Executes optional `post_load` handles after IW7's original `Scr_LoadLevel`.
- `src/client/component/gsc/script_extension.cpp`
  - Enables `developer_script` by default so GSC runtime errors are visible.

## Confirmed findings

- Aurora's AppData search path currently contains an old `custom_scripts/cp/patches.gsc`. Because it sorts before the game directory, it shadows the repository/game copy. That old file has no collision patch or collision logging. This is the direct cause of the previously absent behavior and logs.
- Collision was moved to the unique `zombie_collision.gsc` name so it cannot be lost behind that unrelated stale patch. Loader source-path diagnostics make future shadowing visible.
- Native `spawnClown` dispatch works. The VM hook records `iwz_spawn_clown owner=593 args=1`.
- A previous loader position executed `patches::main` synchronously and exposed the old fatal `getfunction: function not found` error. That lookup has been removed.
- `zombies_cast.gsc` proves the existing pre-load `main` stage can keep long-running child threads. Moving every custom script after `Scr_LoadLevel` would unnecessarily risk the working character-selection lifecycle, so collision alone uses `post_load`.
- `sysprint`, stock `println`, and a unique custom print builtin did not produce dependable persisted GSC logs. Do not repeat those approaches; the VM-notify logging path is the intended diagnostic route.
- Dump confirmation:
  - `mp_agent.gsc::spawn_scripted_agent` passes `level.agent_definition[type]["radius"]` directly to `giveplaceable`, so editing radius before spawn changes the physical scripted-agent capsule.
  - Generic zombie setup reads `scr_zombie_traversal_push` for each spawn and only starts the stock push thread when it is `1`.
  - The stock push thread listens to `traverse_begin` and ends its inner loop on `traverse_end`; the collision patch now follows the same signals rather than polling `is_traversing` every frame.
  - `_callbacksetup.gsc` defines `level.idflags_no_knockback = 4`, and `zombie_damage.gsc::finishplayerdamagewrapper` forwards the damage flags directly to the engine's `finishplayerdamage` builtin. Every Zombies film selects its own `level.callbackplayerdamage`, so wrapping that function field preserves the film-specific damage implementation.

## Expected evidence

1. Loader: `Loaded custom gsc 'custom_scripts/cp/zombie_collision.gsc' from '<exact path>'`.
2. Native lifecycle: `executed 'custom_scripts/cp/zombie_collision::post_load' stage=post-load ...`.
3. GSC lifecycle: `[IWZ][Collision] ... post-load entry ...` and `runtime threads survived first frame`.
4. `installed zombie melee knockback patch flag=4`.
5. Zombie `monitor attached` entries, then `traversal began with solid collision retained` / `traversal ended`.
6. Successful zombie melee hits produce `suppressed melee knockback ... mod=MOD_IMPACT dflags=4` (or a `dflags` value containing bit 4).
7. After `spawnClown`, a GSC `clown request ...` entry followed by the exact failure reason or `clown spawned`.

## Build, deploy, and test

Build:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'build\iw7-mod.sln' /m:1 /nodeReuse:false /p:Configuration=Release /p:Platform=x64 /v:minimal
```

Deploy:

- `build/bin/x64/Release/iw7-mod.exe` to `D:\Steam\steamapps\common\Call of Duty - Infinite Warfare\iw7-mod.exe`
- `data/cdata/custom_scripts/cp/patches.gsc` to `D:\Steam\steamapps\common\Call of Duty - Infinite Warfare\iw7-mod\custom_scripts\cp\patches.gsc`
- `data/cdata/custom_scripts/cp/gsc_diagnostics.gsc` and `zombie_collision.gsc` to the same custom-script directory

Test on Spaceland: exercise climbing/falling zombies, run `spawnClown`, exit the client, then inspect:

`D:\Steam\steamapps\common\Call of Duty - Infinite Warfare\iw7-mod\logs\console.log`

Preserve unrelated dirty-worktree changes.
