# Noir placement workshop

From the repository, run `tools/map-viewer/start.ps1`, then open
<http://127.0.0.1:8765>. The server runs locally; it does not upload the map.
Node/npm and Python are required. The launcher installs the pinned Three.js
dependency if needed. Stop the server with Ctrl+C.

1. Select a reference marker and choose **Focus**, or use **Fit map** / **Top view**.
   Drag to orbit, right-drag to pan, scroll to zoom. Lower **Hide geometry above
   game Z** to expose interiors. Clipped surfaces cannot receive markers.
2. Choose **Quick Revive**, **EMC**, or another symbol, then click geometry.
   Adjust the numeric game coordinates and yaw, or use **Move on surface**.
   The dot is the exact anchor. The line shows facing; a machine's ring is its
   96-unit interaction radius. Duplicate starts a move; Undo restores edits.
3. **Save & install** validates the layout, writes `data/layouts/mp_prime.json`,
   generates `noir_layout.gsc` in the repository and installed game, and logs
   the result. **Restart the match** to load it. Import affects the working copy
   until saved; Export downloads that copy. Up to 32 markers are supported.
4. In the game, open **Zombies → Solo → Survival → UNTITLED - NOIR PROTOTYPE**.
   This first UI integration launches a solo MP foundation match with FTL,
   Eraser, zombie combat and placement enabled. The final title remains TBA.
   It does not yet provide the full CP/Zombies runtime or finished lobby flow.
   The transition briefly passes through the Multiplayer menu while Zombies
   shuts down; Noir starts automatically once that menu has initialized.
   From a private MP match, the equivalent setup is `set iwz_noir_foundation 1`
   and `set iwz_noir_placement 1`, then restart Noir in Free-for-All.
5. Compare the reference dots at both ends, the lower area and the west ramp.
   The colored dot is the anchor; the small white dot is 48 units along its yaw
   and 4 units higher. A nearby caption identifies the marker. At `emc_south`,
   face the marker and press **Use** to buy EMC for 500 points (ammo: 250).
   With two normal guns, a new purchase replaces the held gun. Eraser is protected.
   Quick Revive costs 500 and works before power: three purchases per match,
   one automatic revive per purchase. Power unlocks the 950-point Magic Wheel.
   Collect its gun within 15 seconds. Hold Use near damaged boards to repair them.

The installed south layout has 13 markers. `player_spawn_south` starts and
respawns the player at `ref_south`, facing north. Move this new Player start
marker to change that position; one is supported in this solo prototype.
The user's original 12 markers remain at their saved coordinates. All three
Zombie spawn markers now drive the waves. An occupied spawn waits; it does not
silently spawn enemies elsewhere. Spawn points must have nearby ground navigation.

Barricades are freestanding six-board obstacles, with navigation blocking while
any boards remain. Nearby zombies break a board every 1.5 seconds. Repairs restore
one per second and award 10 points, capped at six paid repairs per barricade per
scene. Place barricades across an actual passage: zombies can go around exposed
ends. These are not yet stock window entrances with vault animations.
Machine models and boards need manual alignment checks against the unexported
props. No doors, room boundaries or Pack-a-Punch have been added to this layout.

The viewer reads the game's `iw7-mod/map-data/mp_prime/world.glb`: 779,525 static
world triangles. It omits 7,178 props, brush models, dynamic objects, collision and
navigation. A surface may differ from the collision players actually stand on.
Both the whole-export SHA-256 and world checksum identify the layout; mismatches
are rejected. The runtime checks the world checksum before spawning anchors.

Coordinates retain the game's original origin and units. Game `(x,y,z)` maps to
viewer `(x,z,-y)`; the inverse is `(x,-z,y)`. The GLB root already applies that
rotation. The viewer never rotates the model a second time, recenters or rescales
it. Yaw is the game's yaw, with zero facing +X and 90 facing +Y. For a wall,
initial facing follows the clicked surface normal; for a floor it defaults to zero.

Inspect `[IWZ][MapLayout]` entries in the game's `iw7-mod/logs/console.log` for
world identity, exact spawned coordinates, facing, collision offsets and purchases.
`coordinateError` compares the JSON origin to the engine entity. `collisionOffset`
measures visual-surface vs bullet-collision separation and is a different check.
Visual alignment and controller/menu behavior still require a manual playtest.

To use another installation: `python tools/map-viewer/server.py --game "D:\path\to\game"`.
To refresh geometry, run `iwz_noir_export` during a Noir foundation match, stop
the viewer, and restart it. Existing layouts are deliberately rejected if that
changes the geometry fingerprint; preserve the old export/layout before migrating.
