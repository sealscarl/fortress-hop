# Teams and classes

No armor: every class has a flat health pool, so damage numbers are exactly what comes off. Numbers live in `player/classes.gd` (classes) and `weapons/weapon_stats.gd` (weapons). Edit them there to rebalance.

## Classes

| Class | Health | Speed | Weapons (1 / 2 / 3) | Grenades (Mouse 2 / Q) |
| --- | --- | --- | --- | --- |
| Scout | 125 | 400 ups | Nailgun, shotgun | — / 4 concs |
| Soldier | 250 | 240 ups | Rocket launcher, shotgun | 4 frags / — |
| Medic | 175 | 320 ups | Super nailgun, shotgun, medkit | 4 frags / 4 concs |
| Demoman | 200 | 280 ups | Grenade launcher, pipe bombs, shotgun | 4 frags / — |

Health is TFC's health + armor turned into one number, then pulled a bit closer together (TFC's effective ~107 / 300 / 190 / 210 for Scout / Soldier / Medic / Demoman). Speeds are TFC's.

## Teams

- **Red** spawns at the south end of the test map, **Blue** at the north end. Each base has a green resupply pad.
- **Friendly fire is on by default** (`mp_friendlyfire 1`). Teammates' pellets, nails, rockets, grenades and pipes hurt and push you. Killing a teammate shows TEAMKILL in the kill feed and costs the killer a kill. With `mp_friendlyfire 0`, teammates are neither hurt nor pushed and pellets pass through them. The Medic's medkit always heals teammates.
- **Your own explosions** still hurt you (half damage) and push you, so rocket, pipe and grenade jumps work.
- **Concs push everyone in range, teammates included** (as in TFC), and never do damage.

## Joining, changing team and class

- On joining you pick a team (**Red / Blue / Auto**), then a class, then you spawn.
- **F1** class menu (number keys 1–4 also pick). Your first class spawns you right away. After that, a new class takes effect the next time you respawn (TFC rules). The HUD shows "next: …" until then.
- **F2** team menu. Switching team respawns you on the new side straight away, without counting a death.
- **Esc** closes a menu.

## Scoreboard, kill feed, damage numbers

- **Hold Tab** for the scoreboard: both teams, each player's class, kills and deaths, team kill totals.
- **Kill feed** top right, in team colors.
- **Damage numbers:** when you hurt an enemy, a yellow **-N** floats up over them. Only you see it. Hits in the same tick are added together, so a shotgun blast shows one total. Medic heals show a green **+N**.
- Names come from the **Your name** box on the main menu (saved between sessions).

## Verified (headless; dedicated server + 3 clients)

| Test | Result |
| --- | --- |
| Pick Soldier / Scout / Demoman / Medic | 250 / 125 / 200 / 175 HP, correct weapons and grenades |
| Run speed | Soldier 240, Scout 400, Medic 320 ups |
| Ask for Scout while alive as Soldier | Stays Soldier until death, then respawns as Scout |
| Scout nailgun, 1 s | 10 nails, no reload |
| Demoman grenade launcher | Grenade explodes after 2.5 s |
| Pipes | 6 out; Mouse 5 detonates all; one pipe under you = 34 self-damage + 321 ups up |
| Soldier rockets a teammate's feet (friendly fire on) | Teammate 175 → 95 HP and pushed; with `mp_friendlyfire 0`, untouched |
| Soldier kills an enemy Scout with 2 rockets | Shooter sees **-86** and **-85**; all 3 clients agree on the scoreboard |
| Medic medkits a hurt teammate | Medic sees **+25 +25**; teammate's health goes up |
| Medic movement and handheld conc | Unchanged (320 run, 539 strafe-jump, conc lift) |

## Kill feed

Top right: **Killer [weapon icon] Victim**, names in team colors. Icons (drawn in code): rocket, shotgun, nailgun, super nailgun, grenade launcher, pipe bomb, frag, medkit, lightning bolt for security lasers, skull for suicides (`kill`) and the world. Suicides show just the icon and the victim. Entries that involve you have a light background and stay 8 s instead of 6. Team kills are marked TEAMKILL.

## Player models

Other players are drawn with `player/player_model.gd` using models made in
Meshy, rigged on the Mixamo skeleton, and prepared with
`tools/models/prepare_player.py`:

```
python tools/models/prepare_player.py --src red_soldier_rigged.glb --out player/models/soldier.glb
```

- **Team colors:** models are made red; Blue is made by recoloring the red
  parts in `player/team_swap.gdshader` (skin and gear are left alone).
- **Animations:** idle, run (sped up, slowed or reversed to match movement),
  crouch, crouch_walk and jump. Arms are always in a two-handed weapon hold.
- **Aim and strafe:** `player/aim_modifier.gd` bends the spine up and down to
  where the player looks, and turns the legs toward a sideways run while the
  chest keeps facing forward.
- **Weapon:** the class's main weapon in the right hand (the rocket launcher
  model, or a placeholder for weapons without a model yet).
- In Godot the bones are named `mixamorig_Hips` etc. (the `:` becomes `_`).

- Models: Scout, Soldier, Medic, Demoman (`player/models/<class>.glb`). The hand hold and crouch depth are scaled to each model's arms and legs, so all four share the same animations.
- A class without a model uses the Soldier.
