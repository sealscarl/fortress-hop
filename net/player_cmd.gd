class_name PlayerCmd
extends RefCounted
## One tick of player input. The client builds one every physics tick, runs
## it locally right away (prediction) and sends it to the server, which runs
## the exact same command. That's what keeps both sides in step.

const JUMP := 1
const CROUCH := 2
const GRENADE_1 := 4   ## Grenade 1 key went down this tick.
const GRENADE_2 := 8   ## Grenade 2 key went down this tick.
const AUTO_HOP := 16
const FIRE := 32         ## Fire held.
const RELOAD := 64       ## Reload key went down this tick.
const NEXT_WEAPON := 128
const PREV_WEAPON := 256
const DETONATE := 512    ## Detonate pipe bombs.
const THROW_FLAG := 1024 ## Throw the flag you carry (key went down this tick).

var seq := 0
var move := Vector2.ZERO   ## x = strafe (right +), y = forward/back (back +).
var flags := 0
var yaw := 0.0
var pitch := 0.0
var weapon_slot := 0     ## 1, 2... = switch to that slot this tick. 0 = no change.
## The server tick this client was drawing other players at, so the server
## can check hitscan shots against what the shooter actually saw.
var view_tick := 0


func has(flag: int) -> bool:
	return flags & flag != 0


func to_array() -> Array:
	return [seq, move.x, move.y, flags, yaw, pitch, weapon_slot, view_tick]


## Returns null for a malformed command (never trust the network).
static func from_array(a: Array) -> PlayerCmd:
	if a.size() != 8:
		return null
	for i in [0, 3, 6, 7]:
		if typeof(a[i]) != TYPE_INT: return null
	for i in [1, 2, 4, 5]:
		if typeof(a[i]) != TYPE_FLOAT: return null
	var c := PlayerCmd.new()
	c.seq = a[0]
	c.move = Vector2(clampf(a[1], -1, 1), clampf(a[2], -1, 1))
	c.flags = a[3]
	c.yaw = a[4]
	c.pitch = clampf(a[5], deg_to_rad(-89.0), deg_to_rad(89.0))
	c.weapon_slot = clampi(a[6], 0, 9)
	c.view_tick = a[7]
	return c
