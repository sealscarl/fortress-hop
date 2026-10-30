# Game clock and game modes

Code: `net/match_state.gd` (a child of `Game`; the server runs it and sends it to everyone). The HUD shows it at top center.

## Public play (`sv_matchmode 0`, default)

- The game clock runs for **`sv_timelimit` minutes (default 30; 0 = no limit)**, shown top center. It turns red in the last minute.
- When it runs out: the winner is announced, everyone is frozen for 15 s ("GAME OVER · new game in 15"), then scores, flags and security reset, everyone respawns, and a new game starts.
- Changing `sv_timelimit` mid-game applies to the game in progress. A limit shorter than the time already played ends it right away.

## Match mode (`sv_matchmode 1`), QWTF Live "quad" style

Type `sv_matchmode 1` in the console as host. The map restarts into prematch. It stays on across map changes (each new map starts in prematch) until `sv_matchmode 0`.

| Phase | Clock | What happens |
| --- | --- | --- |
| **Prematch** | none | Fight freely with your full loadout, but **nothing counts** (kills, deaths, damage, touches, carry, caps). Security lasers and spawn protection are visible but **harmless**. **Flags can't be taken or captured.** A prompt shows "Press F3 to READY UP", how many are ready and who you're waiting for. **F3** toggles ready; console `ready` / `notready`. |
| **Countdown** | 10 s | Everyone is ready: frozen in place (you can look around), ticks for the last 5 s. |
| **Half 1** | `mp_halflength` (10 min) | Everyone respawns; scores and the map reset. **Blue attacks, Red defends**: only Blue can take and capture flags. |
| **Halftime** | 10 s | Blue's score is logged. Frozen. Pick a new class (F1); it applies when half 2 starts. |
| **Half 2** | `mp_halflength` (10 min) | Everyone respawns (new classes applied), flags home, security back up; scores carry over. **Red attacks, Blue defends.** |
| **Postmatch** | 30 s | The team with the higher score wins (or a draw). Frozen. Then back to **Prematch** with everything reset. |

Players who join during a match play normally; anyone who leaves during prematch is dropped from the ready check.

## Settings (server cvars, host only)

| Cvar | Default | |
| --- | --- | --- |
| `sv_timelimit` | 30 | Public game clock, minutes. 0 = no limit |
| `sv_matchmode` | 0 | 1 = match mode |
| `mp_halflength` | 10 | Match mode: minutes per half |

## Verified (host + client, half length 6 s)

Public clock ran out → GAME OVER for 15 s → fresh 30:00 game. Match mode: prematch kill didn't count, flag couldn't be taken, lasers harmless; both readied (F3 / console) → 10 s countdown, holding forward moved 0 m; Half 1 Blue took and capped (10), Red couldn't take; halftime logged Blue 10; Half 2 Red could take, Blue couldn't; postmatch "BLUE WINS" on both screens; 30 s later back to prematch with scores 0 and nobody ready.
