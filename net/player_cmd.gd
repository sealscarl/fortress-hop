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

var seq := 0
var move := Vector2.ZERO   ## x = strafe (right +), y = forward/back (back +).
var flags := 0
var yaw := 0.0
var pitch := 0.0


func has(flag: int) -> bool:
	return flags & flag != 0


func to_array() -> Array:
	return [seq, move.x, move.y, flags, yaw, pitch]


static func from_array(a: Array) -> PlayerCmd:
	var c := PlayerCmd.new()
	c.seq = a[0]
	c.move = Vector2(clampf(a[1], -1, 1), clampf(a[2], -1, 1))
	c.flags = a[3]
	c.yaw = a[4]
	c.pitch = clampf(a[5], deg_to_rad(-89.0), deg_to_rad(89.0))
	return c
