class_name BarrelModifier
extends SkeletonModifier3D
## Moving barrels on a weapon model (bones made by
## tools/models/prepare_weapon.py --barrels). Runs after the model's own
## animation, so the barrels move on top of the weapon's kick and sway.
##
## - Twin barrels (barrel_l, barrel_r: nailgun): each shot kicks one barrel
##   back, alternating, and it springs forward again. At 10 shots a second
##   both barrels are always moving, one going back as the other returns.
## - Spinning barrels (barrels: super nailgun): the cluster spins up while
##   firing (a quarter turn per shot, one barrel per nail) and winds down
##   when you stop.

const KICK := 0.05          ## How far a barrel kicks back (m, at model scale).
const KICK_RETURN := 0.14    ## Seconds for a kicked barrel to come back.
const SPIN_SPEED := TAU * 0.25 / 0.1   ## Quarter turn per shot at 10 shots/s.
const SPIN_HOLD := 0.15      ## Keeps full speed this long after the last shot.
const SPIN_SLOW := 18.0      ## Wind-down (rad/s per second).

var root: Node3D             ## The weapon model's root (forward = -Z).
var _twin: Array[int] = []   ## barrel_l, barrel_r
var _kick: Array[float] = [0.0, 0.0]
var _next := 0
var _spin := -1
var _angle := 0.0
var _speed := 0.0
var _since_shot := 99.0


## Adds a BarrelModifier to a weapon model if it has moving barrels.
static func attach(model: Node3D) -> BarrelModifier:
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	var sk := found[0] as Skeleton3D
	var spin := sk.find_bone("barrels")
	var l := sk.find_bone("barrel_l")
	var r := sk.find_bone("barrel_r")
	if spin == -1 and (l == -1 or r == -1):
		return null
	var m := BarrelModifier.new()
	m.root = model
	if spin != -1:
		m._spin = spin
	else:
		m._twin = [l, r]
	sk.add_child(m)
	return m


## A shot was fired.
func fire() -> void:
	if _twin.size() == 2:
		_kick[_next] = 1.0
		_next = 1 - _next
	_since_shot = 0.0
	if _spin != -1:
		_speed = SPIN_SPEED


## Which barrel fired last (for the muzzle flash): its bone, or -1.
func last_barrel() -> int:
	if _twin.size() == 2:
		return _twin[1 - _next]
	return _spin


func _process(delta: float) -> void:
	for i in 2:
		_kick[i] = move_toward(_kick[i], 0.0, delta / KICK_RETURN)
	_since_shot += delta
	if _spin != -1:
		if _since_shot > SPIN_HOLD:
			_speed = move_toward(_speed, 0.0, SPIN_SLOW * delta)
		_angle = fmod(_angle + _speed * delta, TAU)


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or not is_instance_valid(root):
		return
	if _twin.size() == 2:
		for i in 2:
			var bone := _twin[i]
			# KICK model meters straight back, in the parent bone's space.
			var back := _to_parent(sk, bone) * (root.global_basis.z * KICK)
			var k := _kick[i] * _kick[i]   # Snaps back, then eases forward.
			sk.set_bone_pose_position(bone, sk.get_bone_rest(bone).origin + back * k)
	if _spin != -1:
		var axis := (_to_parent(sk, _spin) * -root.global_basis.z).normalized()
		var rest := sk.get_bone_rest(_spin)
		sk.set_bone_pose_rotation(_spin, Quaternion(axis, _angle) * rest.basis.get_rotation_quaternion())


## Turns world vectors into the bone's parent space.
func _to_parent(sk: Skeleton3D, bone: int) -> Basis:
	var parent := sk.get_bone_parent(bone)
	var b := sk.global_basis
	if parent != -1:
		b = b * sk.get_bone_global_pose(parent).basis
	return b.inverse()
