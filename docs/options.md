# Options

Main menu → **Options**, or in game press **Esc** → **Options**. Changes apply immediately and are saved to `user://settings.cfg` when you close the screen (on Windows: `%APPDATA%\Godot\app_userdata\Fortress-Hop\settings.cfg`). Code: `settings/settings.gd` (autoload `Settings`) and `ui/options_menu.gd`.

| Tab | Setting | Default | Notes |
| --- | --- | --- | --- |
| Mouse | Sensitivity | 4.5 | Quake/Source scale (0.022° per count × sens), so a TFC/QW/CS/TF2 sensitivity carries over 1:1. Shows degrees per count and cm/360. |
| Mouse | Mouse DPI | 800 | Only used for the cm/360 readout. |
| Mouse | Invert mouse Y | off | |
| Video | Field of view | 90 | Horizontal at 4:3, like Quake/TF2 `fov`. Widescreen adds view to the sides. |
| Video | Window | Windowed | Windowed, borderless fullscreen, or exclusive fullscreen. |
| Video | V-Sync | off | |
| Video | Max FPS | Unlimited | |
| Video | Show FPS | off | Top center, under the game clock. |
| Video | Weapon position | Center | Center, Right or Left (console `cl_hand` 0/1/2). Only changes how your own weapon is drawn: every weapon fires from the center of your view whatever you pick, and other players always see you right-handed. Left is a mirror image. |
| Game | Volume | 80 | |
| Game | Auto-hop | on | Hold jump to bunnyhop. |
| Game | Show speedometer | on | Horizontal speed in m/s |
| Controls | Every action | See below | Click a binding, press a key or mouse button. Esc cancels. If the key was already in use, the two actions swap. **Default keys** resets the bindings. |

Default keys: E/D/S/F move, Space jump, Mouse 4 crouch, Mouse 1 fire, Mouse 2 frag, Q conc, R reload, Mouse 5 detonate pipes, A throw flag, 1/2/3 weapons, wheel down/up next/previous weapon, Tab scoreboard, F1 class, F2 team, F3 ready up (match mode). Esc is reserved for menus.

Only bindings you change are saved, so later changes to the defaults still reach you.

## Esc menu (in game)

Resume · Options · Change team · Change class · Leave game · Quit to desktop. Esc also closes the team/class menus. The game keeps running behind it (it's multiplayer).
