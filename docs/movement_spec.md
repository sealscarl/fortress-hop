# Movement spec

Source of truth for movement feel. When a playtest value feels right, record it here.
All values live as `@export` variables on `player/player_movement.gd` (select **Player** in the scene tree, look in the Inspector).

Units: 1 m = 32 Quake units, so 10 m/s = 320 ups. The speedometer shows both.

## Current values (v0.1, classic QuakeWorld/TFC baseline)

| Setting | Value | Quake equivalent |
| --- | --- | --- |
| `auto_hop` | on | hold jump to keep hopping |
| `jump_velocity` | 8.4375 m/s | 270 ups |
| `gravity` | 25 m/s² | sv_gravity 800 |
| `max_speed` | 10 m/s | 320 ups |
| `ground_accelerate` | 10 | sv_accelerate 10 |
| `friction` | 4 | sv_friction 4 |
| `stop_speed` | 3.125 m/s | sv_stopspeed 100 |
| `air_accelerate` | 10 | sv_airaccelerate 10 |
| `air_wish_speed_cap` | 0.9375 m/s | 30 ups |
| `max_bhop_speed` | 0 (uncapped) | TFC capped near 1.7 × max_speed |
| `crouch_speed_scale` | 0.333 | TFC duck speed |
| `stand_height` / `crouch_height` | 1.8 / 1.1 m | |

## How bhopping works here

- **Jump fires before friction.** If jump is held (auto-hop) or just pressed (classic) on the tick you land, you leave the ground again with zero friction, so you keep your speed.
- **Air strafing adds speed.** In the air you can only add up to `air_wish_speed_cap` along your wish direction. Holding a strafe key while turning the mouse smoothly keeps that direction nearly perpendicular to your velocity, so each tick adds a little speed.
- **Holding forward alone never gains speed.** That's intentional and classic.
- **Crouch in the air lifts your feet** by 0.7 m, so crouch-jumps clear higher ledges.

## Verified in headless simulation (128 tick)

| Test | Result |
| --- | --- |
| Run forward 3 s | 320 ups |
| Auto-hop, forward only, 5 s | 320 ups (no gain, as expected) |
| Strafe-jump (right + turn right), 5 s | 539 ups |
| Auto-hop off, jump held | 1 jump only |
| Crouch / uncrouch | hull 1.1 m / 1.8 m |

## Test map (`maps/test_hop.tscn`)

Spawn faces north (−Z) down a long open runway. Grid lines every 1 m, orange every 4 m.

- **West:** 20° ramp to a 3 m deck, and a 50° wall that is too steep to stand on (surf test).
- **East:** gap jumps at 3–8 m between 2 m platforms. 3–6 m from a standing run; 7–8 m need bhop speed.
- **Far east:** ledges at 1.2 m (plain jump) and 1.9 m (crouch-jump only).
- **North-west:** a 1.3 m tunnel you must crouch through.
- Fall off the world and you respawn at the start.

## Controls

E/D/S/F move · Space jump · Mouse 4 crouch · Esc frees the mouse, click to recapture.
