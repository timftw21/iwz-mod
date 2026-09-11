# IW7 zombie asset repacking

Extensions for the GPL-3.0 [x64-zt](https://github.com/Joelrau/x64-zt) IW7 linker.
They repack loaded stock AnimationClass and BehaviorTree assets; the JSON dumps
are inspection output, not an animation editor/import format.

Install into a local x64-zt checkout, then build its Release/x64 `zonetool` target:

```powershell
python tools/zonetool-iw7/install.py D:/iwz-mod/.tmp/x64-zt
```

The installer also fixes optional physics-sound string relocation, enables the
existing native shader fallback for pixel/hull/domain shaders, and allows a
bounded serialization buffer through `ZONETOOL_ZONE_BUFFER_MB=256`.

Generate the Noir manifest using the installed game's extracted assets:

```powershell
python tools/zonetool-iw7/make-noir-bundle.py 'D:/Steam/steamapps/common/Call of Duty - Infinite Warfare'
```

Required inventories under the game's `dump/`: `cp_zmb`, `common_cp`, `mp_prime`,
`common_mp`, `techsets_common_core_mp`, `techsets_common_mp`, `techsets_mp_prime`.
The donor dumps must contain the models, surfaces, materials, images, physics,
effects, scriptables, scripts and rawfiles used by the bundle. Dump the zombie
animation class with this extension to obtain its normalized JSON. The manifest
loads the required stock donor zones in the offline tool.

Run `buildzone iwz_noir_zombies` in that tool with the game as working directory.
Deploy the resulting fastfile to `data/cdata/zone/` and the game's
`iw7-mod/zone/`. Only the isolated bundle is loaded alongside Noir in-game.

`noir-models.json` records the 67 non-reference models in the reloaded bundle's
inventory. They need network precaching because native scripted-character setup
attaches separate limbs and hair. If the character or effects change, review
this list against a fresh bundle inventory. Network tables use distinct asset
names so they extend Noir's tables without replacing them.

The manifest also adds the south section's seven machine/board models and their
network entries. These add 26 images; the gameplay load audit reports 15,304 of
15,616 image slots used (312 free). Use the locally built extended ZoneTool,
not an older copy of `zonetool.exe` installed with the game.

Validated with the stock zombie's 274 animation states and 17 behavior nodes:
normalized class/tree dumps matched after repacking, and the game completed a
three-zombie combat scene. Other classes, including aim-set-heavy classes, have
not been validated.
