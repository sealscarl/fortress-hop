class_name MatchState
extends Node
## The game clock and game modes (child of Game; the server decides, clients
## follow).
##
## Public play (sv_matchmode 0): a game clock of sv_timelimit minutes (0 = no
## limit). When it runs out the winner is shown, everyone is frozen for a
## moment, then scores and the map reset and a new game starts.
##
## Match mode (sv_matchmode 1, QWTF Live "quad" style):
##   PREMATCH   no clock. Fight freely, nothing counts, lasers harmless, flags
##              off. F3 (or "ready" in the console) to ready up.
##   COUNTDOWN  everyone ready: frozen, 10 s.
##   HALF1      everyone respawns, mp_halflength minutes. Blue attacks, Red defends.
##   HALFTIME   frozen 10 s (class changes apply when half 2 starts).
##   HALF2      everyone respawns, Red attacks, Blue defends.
##   POSTMATCH  frozen 30 s showing the winner, then back to PREMATCH.
## Changing map keeps match mode on: the new map starts in PREMATCH.

enum Phase { PUBLIC, PUBLIC_END, PREMATCH, COUNTDOWN, HALF1, HALFTIME, HALF2, POSTMATCH }

const COUNTDOWN_TIME := 10.0
const HALFTIME_TIME := 10.0
const POSTMATCH_TIME := 30.0
const PUBLIC_END_TIME := 15.0
const TICK_SOUND := preload("res://sounds/grenade_tick.wav")
const GO_SOUND := preload("res://sounds/grenade_tick_final.wav")

var phase := Phase.PUBLIC
var time_left := 0.0           ## Seconds on the clock (counts down). -1 = no clock.
var ready_peers: Array = []    ## Match mode: who has readied up.
var half_scores := [-1, -1]    ## Blue's score on offense (half 1), Red's (half 2).
var winner := -2               ## -1 = draw, 0 red, 1 blue, -2 = not decided.

var _matchmode_seen := -1.0
var _timelimit_seen := -1.0
var _public_elapsed := 0.0
var _sync_left := 0.0
var _beep: AudioStreamPlayer
var _last_beep_second := -1


func _ready() -> void:
	_beep = AudioStreamPlayer.new()
	_beep.volume_db = -4.0
	add_child(_beep)
	if multiplayer.is_server():
		_matchmode_seen = Console.sv("sv_matchmode")
		_timelimit_seen = Console.sv("sv_timelimit")
		if _matchmode_seen != 0.0:
			_enter(Phase.PREMATCH)
		else:
			_enter(Phase.PUBLIC)


# --- Questions the rest of the game asks --------------------------------------

## Nobody moves or shoots (countdowns and end screens).
func frozen() -> bool:
	return phase in [Phase.COUNTDOWN, Phase.HALFTIME, Phase.POSTMATCH, Phase.PUBLIC_END]


## Kills, deaths and scoreboard stats count.
func counting() -> bool:
	return phase in [Phase.PUBLIC, Phase.HALF1, Phase.HALF2]


## Security lasers and spawn protection kill.
func lasers_kill() -> bool:
	return phase != Phase.PREMATCH


## The attacking team in a match half, or -1 (both attack).
func offense() -> int:
	match phase:
		Phase.HALF1: return 1   # Blue
		Phase.HALF2: return 0   # Red
	return -1


## Whether this team may take (and capture) flags right now.
func can_take_flag(team: int) -> bool:
	if not counting():
		return false
	return offense() == -1 or offense() == team


func in_match_mode() -> bool:
	return phase not in [Phase.PUBLIC, Phase.PUBLIC_END]


# --- Server: running the phases -----------------------------------------------

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		if time_left > 0.0:
			time_left = maxf(time_left - delta, 0.0)
		_countdown_beeps()
		return
	# React to the host changing the mode or the time limit in the console.
	var mm := Console.sv("sv_matchmode")
	if mm != _matchmode_seen:
		_matchmode_seen = mm
		_say("Match mode %s." % ("ON: prematch, ready up with F3" if mm != 0.0 else "OFF"))
		_restart_round()
		_enter(Phase.PREMATCH if mm != 0.0 else Phase.PUBLIC)
		return
	var tl := Console.sv("sv_timelimit")
	if tl != _timelimit_seen:
		_timelimit_seen = tl
		if phase == Phase.PUBLIC:
			# A shorter limit than what's been played ends the game right away.
			time_left = maxf(tl * 60.0 - _public_elapsed, 0.001) if tl > 0.0 else -1.0
			_sync_now()

	if phase == Phase.PUBLIC:
		_public_elapsed += delta
	if time_left > 0.0:
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			_time_up()
	_countdown_beeps()
	if phase == Phase.PREMATCH:
		_check_all_ready()
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_now()


func _time_up() -> void:
	match phase:
		Phase.PUBLIC:
			_decide_winner()
			_say(_winner_text())
			_enter(Phase.PUBLIC_END)
		Phase.PUBLIC_END:
			_restart_round()
			_enter(Phase.PUBLIC)
			_say("New game!")
		Phase.COUNTDOWN:
			_restart_round()
			_enter(Phase.HALF1)
			_say("HALF 1: Blue attacks, Red defends!")
		Phase.HALF1:
			half_scores[0] = _team_score(1)
			_say("Halftime! Blue scored %d on offense." % half_scores[0])
			_enter(Phase.HALFTIME)
		Phase.HALFTIME:
			_reset_objectives(true)   # Flags home, security up; scores carry over.
			_respawn_all()
			_enter(Phase.HALF2)
			_say("HALF 2: Red attacks, Blue defends!")
		Phase.HALF2:
			half_scores[1] = _team_score(0)
			_decide_winner()
			_say("Match over! %s" % _winner_text())
			_enter(Phase.POSTMATCH)
		Phase.POSTMATCH:
			_restart_round()
			_enter(Phase.PREMATCH)
			_say("Prematch: press F3 to ready up.")


func _enter(p: Phase) -> void:
	phase = p
	match p:
		Phase.PUBLIC:
			_public_elapsed = 0.0
			var tl := Console.sv("sv_timelimit")
			time_left = tl * 60.0 if tl > 0.0 else -1.0
			winner = -2
		Phase.PUBLIC_END:
			time_left = PUBLIC_END_TIME
		Phase.PREMATCH:
			time_left = -1.0
			ready_peers.clear()
			half_scores = [-1, -1]
			winner = -2
		Phase.COUNTDOWN:
			time_left = COUNTDOWN_TIME
		Phase.HALF1, Phase.HALF2:
			time_left = Console.sv("mp_halflength") * 60.0
		Phase.HALFTIME:
			time_left = HALFTIME_TIME
		Phase.POSTMATCH:
			time_left = POSTMATCH_TIME
	_last_beep_second = -1
	_sync_now()


## Fresh round: scores, map objectives, everyone back at spawn.
func _restart_round() -> void:
	var g := Game.instance
	if g:
		g.reset_stats()
	_reset_objectives()
	_respawn_all()


func _reset_objectives(keep_scores := false) -> void:
	if MapLogic.instance:
		MapLogic.instance.reset_objectives(keep_scores)


func _respawn_all() -> void:
	var g := Game.instance
	if g == null:
		return
	for p: Player in g.players_root.get_children():
		if p.class_id == -1 and p.pending_class == -1:
			continue   # Still picking a class.
		if p.pending_class != -1:
			p.apply_class(p.pending_class)
			p.pending_class = -1
		p.grenades.cancel_held()
		p.respawn()


func _team_score(team: int) -> int:
	return MapLogic.instance.team_scores[team] if MapLogic.instance else 0


func _decide_winner() -> void:
	var red := _team_score(0)
	var blue := _team_score(1)
	winner = -1 if red == blue else (0 if red > blue else 1)


func _winner_text() -> String:
	var score := "%d – %d" % [maxi(_team_score(0), _team_score(1)), mini(_team_score(0), _team_score(1))]
	if winner == -1:
		return "It's a draw, %d – %d." % [_team_score(0), _team_score(1)]
	return "%s wins %s!" % [PlayerClasses.TEAM_NAMES[winner], score]


# --- Ready up -------------------------------------------------------------------

## Server: a player pressed F3 / typed ready.
func set_ready(peer: int, value: bool) -> void:
	if phase != Phase.PREMATCH:
		return
	if value and not peer in ready_peers:
		ready_peers.append(peer)
	elif not value:
		ready_peers.erase(peer)
	_sync_now()


func _check_all_ready() -> void:
	var g := Game.instance
	if g == null:
		return
	var ids := _player_ids()
	if ids.is_empty():
		return
	ready_peers = ready_peers.filter(func(id): return id in ids)   # Drop anyone who left.
	for id in ids:
		if not id in ready_peers:
			return
	_say("Everyone's ready! The match starts in %d." % COUNTDOWN_TIME)
	_enter(Phase.COUNTDOWN)


func _player_ids() -> Array:
	var ids := []
	for p: Player in Game.instance.players_root.get_children():
		ids.append(p.peer_id)
	return ids


## Names of players who aren't ready yet (for the prompt).
func not_ready_names() -> Array:
	var out := []
	var g := Game.instance
	if g == null:
		return out
	for p: Player in g.players_root.get_children():
		if not p.peer_id in ready_peers:
			out.append(g.scores.get(p.peer_id, {}).get("name", "?"))
	return out


# --- Sync -----------------------------------------------------------------------

func _sync_now() -> void:
	_sync_left = 1.0
	if Game.instance:
		Game.instance.send_all(self, "_state", [_state_array()], false)


func _state_array() -> Array:
	return [phase, time_left, ready_peers, half_scores, winner]


## Server: a client finished loading.
func send_state_to(peer: int) -> void:
	_state.rpc_id(peer, _state_array())


@rpc("authority", "call_remote", "reliable")
func _state(s: Array) -> void:
	phase = s[0]
	time_left = s[1]
	ready_peers = s[2]
	half_scores = s[3]
	winner = s[4]


func _say(text: String) -> void:
	if Game.instance:
		Game.instance.send_all(self, "_message", [text])


@rpc("authority", "call_remote", "reliable")
func _message(text: String) -> void:
	if Game.instance and Game.instance.ui:
		Game.instance.ui.show_message(text)
	Console.print_line("[color=#ffcc66]%s[/color]" % text)


## Ticks for the last 5 seconds of a countdown, and a final beep at zero.
func _countdown_beeps() -> void:
	if not phase in [Phase.COUNTDOWN, Phase.HALFTIME, Phase.POSTMATCH] or DisplayServer.get_name() == "headless":
		return
	var sec := ceili(time_left)
	if sec != _last_beep_second and sec <= 5:
		_last_beep_second = sec
		_beep.stream = GO_SOUND if sec <= 0 else TICK_SOUND
		_beep.play()


# --- HUD text -------------------------------------------------------------------

static func clock_text(seconds: float) -> String:
	var s := maxi(ceili(seconds), 0)
	return "%d:%02d" % [floori(s / 60.0), s % 60]


## Top-center line: the clock and what's going on.
func hud_line() -> String:
	match phase:
		Phase.PUBLIC:
			return clock_text(time_left) if time_left >= 0.0 else ""
		Phase.PUBLIC_END:
			return "GAME OVER  ·  new game in %d" % ceili(time_left)
		Phase.PREMATCH:
			return "PREMATCH"
		Phase.COUNTDOWN:
			return "MATCH STARTS IN %d" % ceili(time_left)
		Phase.HALF1:
			return "HALF 1  ·  %s  ·  BLUE ATTACKS" % clock_text(time_left)
		Phase.HALFTIME:
			return "HALFTIME  ·  half 2 in %d" % ceili(time_left)
		Phase.HALF2:
			return "HALF 2  ·  %s  ·  RED ATTACKS" % clock_text(time_left)
		Phase.POSTMATCH:
			var w := "DRAW" if winner == -1 else "%s WINS" % PlayerClasses.TEAM_NAMES[maxi(winner, 0)].to_upper()
			return "MATCH OVER  ·  %s  ·  prematch in %d" % [w, ceili(time_left)]
	return ""


## Center prompt during prematch, for the local player.
func ready_prompt(my_peer: int) -> String:
	if phase != Phase.PREMATCH:
		return ""
	var total := Game.instance.players_root.get_child_count() if Game.instance else 0
	var line1 := "You're READY  (F3 to cancel)" if my_peer in ready_peers else "Press F3 to READY UP"
	var waiting := not_ready_names()
	var line2 := "%d / %d ready" % [ready_peers.size(), total]
	if waiting.size() and waiting.size() <= 6:
		line2 += "  ·  waiting for " + ", ".join(waiting)
	return line1 + "\n" + line2
