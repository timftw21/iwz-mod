# Pack-a-Punch Timer Housing Handoff

## Goal

Restore the original black timer housing/backing behind the red countdown text in the shared Zombies Pack-a-Punch projection room. The red digits currently float against the wall on every film. Do not substitute newly drawn geometry or an unrelated UI material; the requested fix is the original asset/geometry.

Also retain the working `paproom` console command for quick testing.

## Paused state (2026-08-08)

The investigation is paused after deploying a geometry-export diagnostic build, but before running that build in game.

- Built and deployed executable SHA-256:
  - `0FEA590B8579FF45A31385DF27DA1A9B5FD2CE6518B9329779F0D115157FF829`
  - Repository build: `D:\iwz-mod\build\bin\x64\Release\iw7-mod.exe`
  - Deployed build: `D:\Steam\steamapps\common\Call of Duty - Infinite Warfare\iw7-mod.exe`
- The two hashes matched after deployment.
- The latest Release build completed with 0 warnings and 0 errors.
- The user intentionally paused before restarting the game and running the newest diagnostic.

## Current implementation

### `paproom` command

- `src/client/component/command.cpp`
  - Registers the cheat-protected server command `paproom`.
  - Notifies the level with `iwz_paproom` and the requesting player.
  - Logs with `[IWZ][PaPRoom]`.
  - The current diagnostic version also inspects candidate asset headers and exports timer-area geometry.
- `data/cdata/custom_scripts/cp/pap_room.gsc`
  - Starts from `post_load()` and listens for `iwz_paproom`.
  - Chooses the first available destination in this order:
    1. `hidden_room_spot`
    2. `pap_spawners[0]`
    3. `hidden_room_portal`
  - Teleports the player, applies destination angles, and sets `zombie_papTimer` to 30.
  - Logs through `custom_scripts\cp\gsc_diagnostics::emit`.
- The command is confirmed working on Rave. Use `sv_cheats 1` before invoking it.

### Latest untested geometry diagnostic

Running `paproom` with the currently deployed executable should export:

- `D:\Steam\steamapps\common\Call of Duty - Infinite Warfare\iw7-mod\dump\pap_timer\black_world_surface.obj`
  - Nearby BSP geometry using `w/plastic_fiberglass_black_01`.
- `D:\Steam\steamapps\common\Call of Duty - Infinite Warfare\iw7-mod\dump\pap_timer\zmb_pap_wire_01.obj`
  - The nearby original static model, transformed into world coordinates.
- `D:\Steam\steamapps\common\Call of Duty - Infinite Warfare\iw7-mod\dump\pap_timer\wdg_pnb_timer_background.dds`
  - This image is now known to be unrelated, but the current diagnostic still exports it.

Expected new log markers include:

- `black world surface index=... bounds=... vertices=... triangles=...`
- `black world geometry exported ...`
- `model geometry exported model=zmb_pap_wire_01 ...`

The OBJ exporter compiled successfully but has not yet been exercised. Validate its vertex/face indexing before relying on the rendered shape.

## Confirmed stock behavior

- Stock timer UI dump: `dumps/CODIW-Source/ui/ingame/cp/paptimer.lua`.
- The stock LUI widget creates only red `UIText` digits. It does not create a `UIImage` or black backing.
- Common-film world setup:
  - Position: `(-10142, 927, -1550)`
  - Yaw: `0`
  - World scale: `0.4`
- `cp_final` uses position `(5237.5, -5004.6, 364)`.
- The LUI root is approximately 491 by 189; the visible digit union is approximately local x `78.67..367.11`, y `-129.5..-89.5`.
- Therefore the missing black housing is shared room world geometry/static-model content, not part of the stock PAP timer Lua.

## Confirmed asset and geometry findings

### Healthy room content

- The timer-area BSP probe found 17 nearby material groups. None resolved to defaults.
- The likely black BSP material is healthy:
  - `w/plastic_fiberglass_black_01`
  - All three expected textures are loaded.
- Other nearby black/metal room materials are also healthy, including `w/metal_deck_painted_black_01`.
- Nearby static model:
  - Name: `zmb_pap_wire_01`
  - Origin: `(-10179.5, 928.0, -1568.0)`
  - World bounds midpoint: `(-10152.7, 884.0, -1599.4)`
  - Half-size: `(51.6, 44.1, 32.2)`
  - Six surfaces, flags `0x340`
  - Materials alternate between healthy `mopw/metal_bare_02` and `mopw/plastic_fiberglass_black_01`.
- No XModel named specifically for a PAP timer/clock was found. Loaded shared PAP models include `zmb_pap_wire_01`, `zmb_pap_wire_02`, `zmb_pap_pipe_01`, `zmb_pap_pipe_02`, and the PAP machines.

### Definite but possibly unrelated broken material

- `eq/vfx_energy_digitalg_red` is the only probed material that resolves to the engine default:
  - Active zone: `0` / invalid/default
  - Technique: `2d`
  - Texture: engine `default`, 16 by 16
- Its intended image is loaded correctly from `cp_rave`:
  - `vfx_energy_digitalg_red`
  - 512 by 512, DXGI format 71
- Valid sibling materials from `techsets_cp_rave` are:
  - `eq/vfx_energy_digitalg`
  - `eq/vfx_energy_digitalg_01`
- Do not assume this broken red effect material is the black timer housing. It may warrant a sibling-material clone repair later, but current evidence does not connect it to the housing.

### VFX candidates ruled out

- `mopw/vfx_zmb_paproom` and `el/vfx_zmb_paproom` load correctly from `techsets_cp_rave`.
- Their images load correctly from `cp_rave`.
- Exported `vfx_zmb_paproom` is a blue PAP-room transition/vignette image, not the timer housing.
  - DDS: `D:\Steam\steamapps\common\Call of Duty - Infinite Warfare\iw7-mod\dump\pap_timer\vfx_zmb_paproom.dds`
  - Converted preview: `D:\iwz-mod\build\reverse\vfx_zmb_paproom.png`
- A multi-image GPU dump attempted to export five images in one renderer callback. Only the first completed; do not repeat the batch approach. Dump one resident image per callback/run if further texture inspection is required.

## False leads and reverted attempts

- A newly drawn solid black LUI rectangle appeared, but it was too large and then misaligned. It was not the original asset and was rejected.
- `hud_countdown_timer_background`, `hud_countdown_timer_separator`, and `hud_countdown_timer_end_cap` are unrelated campaign countdown-widget art. They were removed from the attempted fix.
- `wdg_pnb_timer_background` is used by `dumps/CODIW-Source/ui/frontend/mp/loadoutdrafttimer.lua`, not the PAP timer.
- The repository-side `data/cdata/ui_scripts/PaPTimer/__init__.lua` replacement was deleted.
- The deployed wrong replacement is disabled rather than active:
  - `D:\Steam\steamapps\common\Call of Duty - Infinite Warfare\iw7-mod\ui_scripts\PaPTimer\__init__.lua.disabled`
- Do not re-enable that Lua or recreate another approximate rectangle.

## Recommended resume path

1. Restart the game with the currently deployed executable.
2. Load any Zombies film, enable cheats, and run `paproom` once.
3. Exit or unfocus the game, then inspect the new `[IWZ][PaPRoom]` lines in:
   - `D:\Steam\steamapps\common\Call of Duty - Infinite Warfare\iw7-mod\logs\console.log`
4. Inspect/render `black_world_surface.obj` and `zmb_pap_wire_01.obj`.
5. Determine which case applies:
   - If the BSP export is the timer housing, investigate its DPVS visibility/draw state rather than replacing its material.
   - If `zmb_pap_wire_01` contains the housing, investigate its static-model LOD/culling/draw state.
   - If neither contains it, tighten the probe around the stock LUI digit world bounds and export the remaining nearby black/static geometry.
6. Once the original source is identified, implement the smallest restoration and retain concise `[IWZ][PaPTimer]` or `[IWZ][PaPRoom]` lifecycle logging.
7. Remove the large temporary asset/geometry diagnostics from `command.cpp` after the fix is verified. The current diagnostic work added hundreds of temporary lines and should not remain in the final implementation.

## Build and deploy

Build:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'build\iw7-mod.sln' /m /p:Configuration=Release /p:Platform=x64
```

Deploy:

- Copy `D:\iwz-mod\build\bin\x64\Release\iw7-mod.exe` to `D:\Steam\steamapps\common\Call of Duty - Infinite Warfare\iw7-mod.exe`.
- Copy `D:\iwz-mod\data\cdata\custom_scripts\cp\pap_room.gsc` to `D:\Steam\steamapps\common\Call of Duty - Infinite Warfare\iw7-mod\custom_scripts\cp\pap_room.gsc` if it changes.
- Verify build and deployed executable SHA-256 hashes match.

The worktree contains many unrelated modifications and untracked files from the broader iwz-mod session. Preserve them and do not use destructive Git cleanup.
