# Maps

Maps are Quake/QWTF `.map` files, built in TrenchBroom and converted to Godot scenes with [func_godot](https://github.com/func-godot/func_godot_plugin) (in `addons/func_godot`, MIT license). Scale is Quake's: **32 units = 1 m**, the same as our movement code, so jumps, gaps and ramps feel the way they did in QWTF.

| File | What it is |
| --- | --- |
| `maps/source/<name>.map` | The source map. Edit this in TrenchBroom. |
| `maps/<name>/<name>_geometry.scn` | Built geometry + entity markers (generated; don't edit). |
| `maps/<name>/<name>.tscn` | The playable scene: geometry, lighting, `MapLogic`, players, `Game`. |
| `maps/<name>/textures.md` | Every texture name the map uses (generated). |
| `maps/map_logic.gd` | Turns QWTF entities into gameplay (below). |
| `tools/map_builder.gd` | The converter. |

## Current maps

| Map | Mode | Credit |
| --- | --- | --- |
| **ff-phantom** | CTF with security | "Phantom" by =High= Uliboh, Quake port by klown (2019), from the map's own credits. **For development and private testing only.** A public release needs the authors' permission or a replacement map. |
| test_hop | Movement testing | Ours (generated grey-box). |

## Dev textures

All textures are drawn as the world-space grid (1 m lines, orange every 4 m), tinted red toward Red's spawns and blue toward Blue's. The original texture names stay in the `.map`, so each can get a new texture later by adding `maps/materials/<name>.tres`. The original `.wad` files are never used or committed.

| Texture | Becomes |
| --- | --- |
| `SKIP` | Not drawn |
| `clip` | Invisible wall |
| `sky*` | Sky color |
| `*water` and other `*` liquids | See-through, **not solid** |
| `~light…` | Glowing |
| `+…button…` | Glowing yellow (buttons) |

## Rebuilding after editing in TrenchBroom

1. Edit and save `maps/source/<name>.map` in TrenchBroom.
2. In Godot, open `tools/build_maps.gd` in the Script editor and choose **File → Run** (Ctrl+Shift+X). It rebuilds every map in `maps/source/` (about a second each).
3. Commit the `.map` and the regenerated `_geometry.scn` and `textures.md`.

A new map also needs a playable scene: copy `maps/ff-phantom/ff-phantom.tscn`, point it at the new `_geometry.scn`, and add it to `MAPS` in `net/network.gd`.

### Setting up TrenchBroom

1. Install [TrenchBroom](https://trenchbroom.github.io/).
2. Use game **Quake**, map format **Standard** (what Phantom uses). The map's own entity definitions (`Quoth2.fgd`) are fine: TrenchBroom keeps the TF entities and all their settings even though it doesn't know them.
3. If you still have the original `.wad` files, add them under *Map → Properties → Texture Collections* to see real textures while editing. That's local to your PC; the game never uses them.

## QWTF entities we understand

TF teams: `team_no 1` = Blue, `2` = Red (ours: Red = 0, Blue = 1). Goal boxes use `goal_min`/`goal_max`, or TF's default 32×32×56 units.

| Entity | Becomes |
| --- | --- |
| `info_player_teamspawn` (`team_no`, `angle`) | Team spawn points |
| `item_tfgoal` with `owned_by` | A **flag**: `team_no` may take it, returns home after `pausetime` s when dropped, `message` shown to the taker |

| `info_tfgoal` with `items_allowed` | A **capture point** for the flag with that `goal_no`; `increase_team1/2` points; `target` = refill on capture |
| `func_button` → `targetname` goal with `remove_group_no` + `activate_goal_no` → goal with `delay_time`, `restore_group_no`, `netname` | A **security system**: the button (pressable by its `team_no`) takes the laser group offline for `delay_time` s; HUD shows "NETNAME: online / OFFLINE n" |
| `info_tfgoal` with a `*laser*` model, `group_no`, kill effect | **Security lasers**: kill the `team_no` team while online |
| `info_tfgoal` with a `*laser*` model and no group, and `netname "kill"` goals | **Spawn protection**: kills the `team_no` team |
| `info_tfgoal` with a `*backpack*` model | **Supply pack** for `team_no`: full resupply (`999` ammo), ammo (half your reserve), or grenades; respawns after `wait` s |
| `func_plat` | A **lift**: rests at the bottom, rises `height` units when stood on at `speed` (150 u/s), waits, comes down |
| `light` | A light (`light` value = range in units, `_color`) |

Not yet: doors (`func_door`), trains, teleporters, `trigger_push`, ladders, swimming, TF's more exotic goal effects. They'll be added as maps need them.

## Throwing the flag

Carrying a flag, press **A** (Throw flag; rebindable, console `throwflag`) to toss it along your aim: 400 ups forward plus 200 ups up (`tf_flagthrow_speed`, `tf_flagthrow_up`), about 7 m on flat ground. It stops against walls and lands on the floor, then waits like a dropped flag (back home after `pausetime`). You can't grab your own throw for 1 s; teammates can catch it, so you can pass. A flag dropped on death now falls to the floor instead of floating.

## Rules on Phantom (verified headless)

| Check | Result |
| --- | --- |
| Contents | 12 + 12 spawns, 2 flags, 2 capture points, 8 security lasers, 2 security systems, 12 spawn-protection zones, 16 packs, 2 lifts |
| Spawns | All 24 have floor under them |
| Capture | Blue takes the Red flag, carries it to Blue's capture point → Blue 10, flag goes home |
| Drop | Carrier dies → flag drops there, back home after 45 s (map's `pausetime`) |
| Security | Online lasers kill Blue; Blue presses Red's button → offline 30 s, lasers off, safe to pass; online again after 30 s |
| Spawn protection | Blue entering Red's spawn exit dies |
| Pack | 40 → 175 HP on a full pack; respawns after 1 s |
| Lift | Rises 8 m with the player on it |
| Multiplayer (server + 2 clients) | Both clients load Phantom from the server; see the carried flag, Blue's capture (B10), the security countdown and the lift; messages per team |
| Stress test (host + 2 clients, 25 s) | 0 errors |
