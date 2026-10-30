# Console

Press **~** (the key left of 1) anywhere, in the menu or in game. **Tab** completes names, **↑/↓** recalls earlier commands, **~** or **Esc** closes. Several commands can go on one line separated by `;`.

Type a cvar's name to see its value, default and what it does. Type the name and a value to change it: `sv_gravity 600`.

Code: `console/console.gd` (autoload `Console`).

## Server cvars (movement and grenade tuning)

In Quake units, like QW. **Only the host can change them.** They're sent to everyone when they join and whenever they change, so every player's movement prediction stays exact. When you host or play offline, your own values are used; when you join someone, theirs are.

| Cvar | Default | What it does |
| --- | --- | --- |
| `sv_gravity` | 800 | Gravity |
| `sv_accelerate` | 10 | Ground acceleration |
| `sv_airaccelerate` | 10 | Air acceleration (strafing) |
| `sv_friction` | 6 | Ground friction (Quake: 4) |
| `sv_stopspeed` | 100 | Friction acts as if you're at least this fast |
| `pm_jumpspeed` | 270 | Jump upward speed |
| `pm_airwishspeed` | 30 | Max speed added per air tick toward your strafe (Quake's hard-coded 30) |
| `pm_bunnyspeedcap` | 0 | Max horizontal speed while hopping, in ups (0 = no cap) |
| `pm_stepheight` | 18 | Tallest step you walk up |
| `pm_airstep` | 1 | Step up stairs in the air too (bhop up stairs) |
| `sv_timelimit` | 30 | Game clock in minutes (0 = none) |
| `sv_matchmode` | 0 | 1 = match mode (see docs/game_modes.md) |
| `mp_halflength` | 10 | Match mode: minutes per half |
| `mp_friendlyfire` | 1 | Teammates hurt and push each other; a team kill costs a frag |
| `pm_stepdown` | 1 | Walking down stairs/slopes keeps you on the ground |
| `pm_slopeboost` | 0.5 | Downhill landings add forward speed (0 = none, 1 = full Quake) |
| `tf_conc_maxspeed` | 1000 | Horizontal speed cap after a conc (0 = no cap) |
| `tf_hhconc_hpower` / `tf_hhconc_vpower` | 2.74 / 4.1 | Handheld conc multipliers |
| `tf_hhconc_minup` | 320 | Handheld conc minimum upward speed |
| `tf_hhfrag_push` | 1000 | Handheld frag push |
| `tf_gren_primedelay` | 1 | Seconds after priming before the countdown starts |
| `tf_gren_fuse` | 3 | Countdown after that, seconds (total = both) |
| `tf_rocket_selfdamage` | 0.72 | Share of your own rocket's damage you take (4 rocket jumps, the 5th kills) |
| `tf_rocket_selfpush` | 0.8 | Share of your own rocket's push you get (rocket jump strength) |
| `tf_flagthrow_speed` / `tf_flagthrow_up` | 400 / 200 | Flag throw speed along your aim / extra upward speed |

Class run speeds stay per class (`player/classes.gd`).

## Client cvars (same as Options)

`sensitivity`, `m_invert`, `m_dpi`, `fov`, `cl_autohop`, `cl_showspeed`, `cl_showfps`, `cl_maxfps`, `vid_vsync`, `vid_mode` (0 windowed, 1 borderless, 2 exclusive), `volume` (0–1), `cl_hand` (weapon position: 0 center, 1 right, 2 left), `name`. Saved like the Options menu.

## Commands

| Command | |
| --- | --- |
| `help`, `cvarlist [text]` | List commands / cvars (`*` = changed) |
| `reset <cvar>`, `reset sv` | Back to default / all server cvars |
| `changed` | Show the server cvars you've changed **and copy them to the clipboard**, ready to paste to Claude |
| `writeconfig [file]` | Save changed server cvars to `user://tuning.cfg`; load again with `exec tuning` |
| `exec <file>` | Run a `.cfg` from your user folder |
| `connect <ip>`, `disconnect` | Join / leave |
| `map [name]` | Host a map (`map phantom`, `map hop`); no name lists maps |
| `status` | Connection, map, players |
| `team red\|blue\|auto`, `class <name>`, `kill` | In game |
| `ready`, `notready` | Match mode prematch (F3 toggles) |
| `bind <key> [action]`, `bindlist` | QW-style binds, e.g. `bind mouse3 +jump`. Keys: letters, `space`, `shift`, `ctrl`, `f1`, `mouse1`–`mouse5`, `mwheelup`/`mwheeldown`. Actions: `+forward +back +moveleft +moveright +jump +duck +attack +gren1 +gren2 reload detpipe slot1 slot2 slot3 invnext invprev +showscores changeclass changeteam`. A key already in use swaps, like the Options menu. |
| `echo`, `clear`, `quit` | |

## autoexec.cfg

If `autoexec.cfg` exists in your user folder it runs at startup. Put any commands in it, one per line (`//` comments are fine). Your user folder on Windows is `%APPDATA%\Godot\app_userdata\Fortress-Hop\` (`writeconfig` prints the exact path).

## Tuning workflow

1. Host (or `map hop`), open the console and try values: `sv_airaccelerate 12`, `pm_jumpspeed 290`...
2. When it feels right, type `changed`. The values are copied to your clipboard.
3. Paste them to Claude to make them the new defaults (or `writeconfig` to keep them as a file for now).
