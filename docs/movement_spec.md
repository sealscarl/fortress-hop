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

## Grenades

**Double-tap:** press once to prime (fuse starts, beeps begin), press either grenade key to throw it. Hold past the fuse and it goes off in your hand. Only one grenade can be primed at a time. The beeps and the HUD timer (left of the crosshair) keep running after you throw, so you can time drop concs.

Beeps: one per second, then four fast beeps in the final second. The HUD timer flashes red in the last second while the grenade is still in your hand.

| Setting | Value | Source |
| --- | --- | --- |
| `fuse_time` | 3.0 s | Our choice (TFC conc: 3.81 s) |
| `throw_speed` | 20.625 m/s | TFC/Momentum 660 ups |
| `throw_pitch_up_deg` | 18.5° | TFC/Momentum |
| `inherit_velocity` | 0 | TFC (thrown grenades don't carry your speed) |
| Grenade gravity / bounce | 0.8 × gravity / 0.6 | TFC/Momentum |
| Grenade rolling | Off (rotation locked; slides to a stop) | Our choice, for aim precision |
| `frag_damage` / `frag_radius` | 100 / 6.875 m | Radius from TFC (220 u) |
| `frag_knockback` | 0.25 m/s per damage point | Quake (8 ups per point) |
| `self_damage_scale` | 0.5 | Our choice |
| `hh_frag_push` | 31.25 m/s (1000 ups) | Our choice |
| `conc_radius` | 8.75 m | TFC (280 u) |
| `hh_lateral_power` / `hh_vertical_power` | 2.74 / 4.1 | TFC |
| `hh_min_up_speed` | 10 m/s (320 ups) | Fortress Forever-style assist, our value |
| `conc_max_horizontal_speed` | 43.75 m/s (1400 ups) | Our cap; TFC had none |

### Conc physics

**Thrown/drop conc (TFC formula):** the conc *sets* your velocity based on your offset from it. In meters, with `h` = horizontal offset, `z` = vertical offset, `d` = total distance:

- horizontal = h × (8.4 − 0.48 d)
- vertical = z × (12.6 − 0.72 d)

Push grows with distance, so the best launch is near the edge of the 8.75 m radius.

**Cap:** after any conc, horizontal speed is capped at 1400 ups so chained handhelds can't snowball (before the cap, two handhelds reached 3600+ ups).

**Handheld frag:** pushes you 1000 ups along the way you're already moving, plus 50 HP damage. Upward motion counts, so jump first for height; falling doesn't, so it never drives you into the floor. Standing still sends you straight up.

**Handheld conc (held past the fuse, or a thrown conc within 0.5 m):** multiplies the velocity you already have. Horizontal × 2.74, vertical × 4.1, and vertical is always at least 10 m/s / 320 ups (the FF-style assist). A handheld only moves the person holding it. The skill is jumping, and moving, at the instant it pops.

Verified in headless simulation:

| Case | Result |
| --- | --- |
| Handheld conc, standing still | 0 horizontal, about 300 ups up (assist hop) |
| Handheld conc at the moment you jump, bhopping at 480 ups | 1315 ups horizontal, 1107 ups up |
| Second handheld conc right after | 1400 ups horizontal (capped), 1107 ups up |
| Handheld conc mistimed near the top of a jump, moving 320 ups | 877 horizontal, 320 up |
| Drop conc 2 m away, 45° below | 337 horizontal / 505 up |
| Drop conc 8.7 m away (edge) | 832 horizontal / 1247 up |
| Handheld frag, standing still | 1000 ups straight up, 50 HP |
| Handheld frag, jumping forward at 320 ups | 1084 horizontal, 915 up |
| Handheld frag, running on the ground | 1320 horizontal, 0 up |

A green **resupply pad** right of spawn refills health and grenades. Dying also refills them.

## Controls

E/D/S/F move · Space jump · Mouse 4 crouch · Mouse 2 primes a frag · Q primes a conc · either key throws what you're holding · Mouse 1 fire · R reload · 1/2 or mouse wheel switch weapons (see docs/weapons.md) · Esc frees the mouse, click to recapture.
