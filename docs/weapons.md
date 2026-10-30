# Weapons

All weapon numbers live in `weapons/weapon_stats.gd`; which class carries what is in `player/classes.gd` (see `docs/classes.md`). 1 m = 32 units.

## Controls (placeholders, rebind in Project Settings → Input Map)

| Action | Key |
| --- | --- |
| Fire | Mouse 1 |
| Reload | R |
| Weapon slots | 1 / 2 / 3 |
| Detonate pipe bombs | Mouse 5 |
| Next / previous weapon | Mouse wheel down / up |

## Reload rules (every weapon with a clip, TFC/FF/TF2-style)

- Reloads **one round at a time**: the first round takes `reload_first`, each one after that `reload_each`.
- Starts **automatically when the clip is empty** (after the last shot's cooldown), or press **R** to top up early.
- **Fire cancels a reload** as soon as at least one round is loaded, and fires it. The partly-loaded round is lost.
- **Switching weapons cancels a reload.** Each weapon keeps whatever it had loaded.
- Out of both clip and reserve: fire just clicks.
- Respawning and the resupply pad refill every clip and reserve.

## Rocket launcher

| Setting | Value | Notes |
| --- | --- | --- |
| Clip / reserve | 4 / 20 | TFC/TF2 clip |
| Fire interval | 0.8 s | |
| Reload | 0.92 s first rocket, 0.8 s each after | TF2 |
| Rocket speed | 31.25 m/s (1000 ups) | Our choice (TFC: 900) |
| Damage / radius | 100 / 5 m (160 u) | Quake radius = damage + 40 units |
| Knockback | 0.25 m/s per damage point | Quake (8 ups per point) |
| Self-damage | × 0.72 (`tf_rocket_selfdamage`) | A rocket jump costs ~54 HP: a 250 HP Soldier gets 4, the 5th kills |
| Self-push | × 0.8 (`tf_rocket_selfpush`) | Rocket jump: ~720 ups up, ~10 m high |

Rockets fly straight with no gravity and explode on the first wall or player they touch. Damage and knockback fall off linearly to the edge of the radius.

## Shotgun

| Setting | Value |
| --- | --- |
| Clip / reserve | 8 / 40 |
| Fire interval | 0.5 s |
| Reload | 0.75 s first shell, 0.5 s each after |
| Pellets | 6 × 6 damage, 4° spread (first pellet dead center) |
| Range | 100 m |

## Nailgun (Scout) and super nailgun (Medic)

| Setting | Nailgun | Super nailgun |
| --- | --- | --- |
| Damage per nail | 9 | 12 |
| Fire interval | 0.1 s | 0.1 s |
| Ammo | 200, no reload | 150, no reload |
| Nail speed | 31.25 m/s (1000 ups) | same |

Nails are straight-flying projectiles, like small rockets that don't explode.

## Grenade launcher and pipe bombs (Demoman)

| Setting | Grenade launcher | Pipe bombs |
| --- | --- | --- |
| Clip / reserve | 6 / 30 | 6 / 30 |
| Fire interval | 0.6 s | 0.6 s |
| Reload | 1.0 s first, 0.6 s each | same |
| Damage / radius | 100 / 5 m | 90 / 5 m |
| Goes off | After 2.5 s, or on touching an enemy before its first bounce | Only on Mouse 5, once armed (0.25 s after firing; armed pipes glow) |
| Max out at once | — | 8 (the oldest goes off) |

Both bounce like hand grenades. Self-damage: grenade launcher × 0.5; pipe bombs × 0.66, so a pipe jump costs ~48 HP: a 200 HP Demoman gets 4 pipe jumps (6 HP left) and the 5th kills him. Each pipe jump launches ~845 ups up.

## Medkit (Medic)

Melee, 1.8 m reach, 0.4 s per swing. Heals a teammate 25 (up to their max health) or hits an enemy for 9. Lag-compensated like the shotgun.

## Multiplayer

- The server owns firing, ammo, reloads, rockets and damage. Your HUD and view model follow the server's snapshots.
- **Rockets** are real projectiles on the server, mirrored as look-alikes on clients. They are not lag-compensated, as in classic TF: you lead your shots.
- **Shotgun** pellets are **lag-compensated**: the server checks them against where other players were on *your* screen (up to 1 s back). Walls are checked as they are now.

## Verified (headless)

| Test | Result |
| --- | --- |
| Hold fire with a full clip | 4 rockets 0.8 s apart, then auto-reload to 4/4 in 4.12 s (as calculated) |
| Fire while reloading with 2 loaded | Reload cancels, rocket fires: 2/4 → 1/4 |
| Switch to shotgun mid-reload | Reload cancels; rocket launcher keeps its 2 rockets |
| Shotgun: R at 5/8, wait 1.25 s | 7/8 (0.75 + 0.5 s) |
| Rocket jump (look down, jump + fire) | 827 ups upward (plain jump 270), 37 HP self-damage |
| Shotgun vs a player strafing over the network | 30–36 damage per hit, target killed twice |
| Rocket vs that player | 88 damage (kill); shooter took 19 splash damage from 4 m |

## Placeholders

The view model is a simple tube (rocket launcher) or barrel (shotgun) that dips while reloading or switching and kicks when firing. Other players don't show a weapon yet. Firing sounds and effects come from the server, so over a real connection they lag by one round trip.

## First-person weapons (`weapons/view_model.gd`)

- Drawn by a second camera on render layer 20, overlaid on the world: the weapon never pokes through walls, and it always uses fov 90 (73.74° vertical) whatever your FOV setting, so it doesn't stretch at fov 120. Same 3D world, so map lights light it.
- Weapons with a model play its animations, driven by the real weapon state: `draw` on switch, `idle` loop, `fire` on every shot, and `reload_start` → `reload_insert` (once per round, as each round lands) → `reload_end`. Firing mid-reload cuts straight to `fire`.
- Sleeves (material named `Sleeve`) take your team color.
- Weapon position (Options / `cl_hand`): right, centered, or left (a mirror image). Placement per weapon in `PLACE_MODEL`.
- Models so far: **rocket launcher** (`weapons/models/rocket_launcher.glb`, built by `tools/models/rocket_launcher.py` in Blender: gloved hands, muzzle-loading reload). Other weapons still use placeholder cylinders.

### Rebuilding a model

1. Install Blender (or `pip install bpy`), then run `python tools/models/rocket_launcher.py` (or `blender -b -P tools/models/rocket_launcher.py`). It writes `weapons/models/rocket_launcher.glb`.
2. Godot re-imports it automatically. Animation names must stay the same.
