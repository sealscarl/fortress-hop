# Multiplayer

Server-authoritative, QuakeWorld-style. ENet over UDP on **port 27500**.

## Playing

- **Host:** main menu → *Host game*. You play on the server. This is also offline practice.
- **Join:** type the host's IP address → *Join game*. `127.0.0.1` means "this PC".
- **Dedicated server:** run the game with `--server` (no player, no window needed with `--headless`).

### Two copies on one PC (for testing)

In Godot: **Debug → Customize Run Instances…**
1. Tick **Enable Multiple Instances**, set the count to **2**.
2. Instance 1 launch arguments: `--host`
3. Instance 2 launch arguments: `--join`
4. Press F5. One window hosts, the other joins it.

Only the focused window gets keyboard and mouse input.

### Playing with a friend over the internet

The host must forward **UDP port 27500** on their router to their PC, and allow Godot / the game through Windows Firewall. The friend joins using the host's public IP. On the same home network, use the host's local IP (e.g. `192.168.1.20`) and no forwarding is needed.

## How it works

1. Every tick (128/s) your client turns your input into a **command** (keys held, look direction, grenade taps), runs it on your player **immediately**, and sends it to the server. The last 4 commands are resent each tick, so a lost packet doesn't lose a grenade tap.
2. The server runs each player's commands, in order, through the **same movement code**. Grenades, damage, explosions and respawns happen **only on the server**.
3. 64 times a second the server sends a **snapshot**: everyone's position, plus, for you, the last command it ran and your exact state after it, your HP and your grenade counts and timer.
4. Your client checks the snapshot against what it predicted for that command. If they differ (you got hit by a conc, a packet was lost, you respawned), it snaps to the server's state and re-runs your newer commands on top, all within one tick.
5. Other players are drawn **125 ms in the past**, smoothly interpolated between snapshots.
6. Grenades: the server throws the real one; clients show a look-alike that flies with the same physics and is removed when the server says it exploded.

Files: `net/game.gd` (tick loop, prediction, snapshots), `net/player_cmd.gd` (the command), `net/network.gd` (host/join, autoload `Net`), `ui/main_menu.tscn`.

## Verified (headless, on one machine)

Dedicated server + two clients as separate processes:

| Check | Result |
| --- | --- |
| Client runs and strafe-jumps | Server and both clients agree on its final position exactly |
| Client primes a conc | Its HUD shows the timer and count from the server |
| Client holds it until it goes off | 301 ups straight up, matching single-player |
| Another player's conc hits a client | Launched at 954 ups, followed on the hit player's screen |
| Another player's frag 2 m away | 100 → 30 HP everywhere |
| Client throws a frag with the other key | Look-alike appears on the client, removed when the server's explodes |
| Movement speeds through the networked code | 320 ups run, 539 ups after 5 s strafe-jumping (unchanged) |

**Not yet tested:** real internet latency and packet loss. Over a real connection, explosions that hit **you** arrive one round-trip late, because only the server decides them.

## Known limits (v0.1)

- No player names, scoreboard, teams or chat yet.
- Players pass through each other.
- On the **host's** screen, remote players can look slightly jerky, because they move whenever their commands arrive. Clients see everyone smoothly interpolated.
- No anti-cheat beyond the server owning grenades and damage.
