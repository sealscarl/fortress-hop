# Weapons

All tuning values are on the Player's **Weapons** node in the Inspector (`weapons/weapon_manager.gd`). 1 m = 32 units.

## Controls (placeholders, rebind in Project Settings → Input Map)

| Action | Key |
| --- | --- |
| Fire | Mouse 1 |
| Reload | R |
| Rocket launcher / Shotgun | 1 / 2 |
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
| Self-damage | × 0.5 | Rocket jumps cost health |

Rockets fly straight with no gravity and explode on the first wall or player they touch. Damage and knockback fall off linearly to the edge of the radius.

## Shotgun

| Setting | Value |
| --- | --- |
| Clip / reserve | 8 / 40 |
| Fire interval | 0.5 s |
| Reload | 0.75 s first shell, 0.5 s each after |
| Pellets | 6 × 6 damage, 4° spread (first pellet dead center) |
| Range | 100 m |

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
