class_name AimModifier
extends SkeletonModifier3D
## Runs after the player model's animation each frame:
## - Aim: the spine bends so the upper body (and the weapon) points where the
##   player is looking, up or down.
## - Strafe: the hips turn toward the way the player is moving, and the spine
##   turns back, so the legs run sideways while the chest keeps facing forward.
## - Weapon: placed in front of the chest along the aim, then both arms are
##   bent (two-bone IK) so the hands hold it whatever the pose and aim.
## Rotations are in skeleton space; the model faces +Z there, so looking up
## is a rotation about -X.

var pitch := 0.0   ## Radians, + = looking up.
var hips_yaw := 0.0   ## Radians the legs turn toward the move direction.
## Held weapon (set by PlayerModel). Placed in front of the chest, pointing
## along aim_basis (world); both hands then reach for their spots on it.
var weapon: Node3D
var aim_basis := Basis()
var grip := Vector3.ZERO      ## Right hand spot, in the weapon's space (-Z = muzzle).
var support := Vector3.ZERO   ## Left hand spot, in the weapon's space.

## Weapon center from the middle of the shoulders, in aim space (x right,
## -z forward), for an arm 0.5 m long; scaled to each model's arms.
const HOLD := Vector3(0.05, -0.2, -0.22)
const REF_ARM := 0.5
const PALM := 0.075           ## Wrist to middle of the palm (m).
## Which way the fingers point, in the weapon's space.
const FINGERS_R := Vector3(-0.2, -0.45, -0.9)   # Round the grip, forward and down.
const FINGERS_L := Vector3(0.45, 0.1, -0.9)     # Under the weapon, forward.

const SPINE := [["mixamorig_Spine", 0.3], ["mixamorig_Spine1", 0.3], ["mixamorig_Spine2", 0.4]]
var _hips := -1
var _spine: Array = []
var _arms := {}   ## "Left"/"Right" -> [arm, forearm, hand] bone ids.


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _hips == -1:
		_hips = sk.find_bone("mixamorig_Hips")
		for s in SPINE:
			_spine.append([sk.find_bone(s[0]), s[1]])
		for side in ["Left", "Right"]:
			var ids := [sk.find_bone("mixamorig_%sArm" % side), sk.find_bone("mixamorig_%sForeArm" % side), sk.find_bone("mixamorig_%sHand" % side)]
			if not ids.has(-1):
				_arms[side] = ids
	if _hips == -1:
		return
	if absf(hips_yaw) > 0.001:
		_turn(sk, _hips, Basis(Vector3.UP, hips_yaw))
	for s in _spine:
		if s[0] == -1:
			continue
		var r := Basis(Vector3.RIGHT, -pitch * s[1])
		if absf(hips_yaw) > 0.001:
			r = Basis(Vector3.UP, -hips_yaw * s[1]) * r
		_turn(sk, s[0], r)
	if is_instance_valid(weapon) and _arms.size() == 2:
		_hold_weapon(sk)


func _hold_weapon(sk: Skeleton3D) -> void:
	var to_world := sk.global_transform
	var to_skel := to_world.affine_inverse()
	var sc := to_world.basis.get_scale().x
	var l: Array = _arms["Left"]
	var r: Array = _arms["Right"]
	var ls := sk.get_bone_global_pose(l[0]).origin
	var rs := sk.get_bone_global_pose(r[0]).origin
	var reach := ((sk.get_bone_global_pose(l[1]).origin - ls).length()
		+ (sk.get_bone_global_pose(l[2]).origin - sk.get_bone_global_pose(l[1]).origin).length()) * sc
	var mid := to_world * ((ls + rs) * 0.5)
	var w := Transform3D(aim_basis, mid + aim_basis * (HOLD * (reach / REF_ARM)))
	weapon.global_transform = w
	var palm_len := PALM / sc
	for hand in [[r, grip, FINGERS_R], [l, support, FINGERS_L]]:
		var fingers := (to_skel.basis * (w.basis * (hand[2] as Vector3))).normalized()
		var wrist := to_skel * (w * (hand[1] as Vector3)) - fingers * palm_len
		_reach(sk, hand[0], wrist, fingers)


## Two-bone IK: bends arm and forearm so the hand's wrist is at `target`
## (skeleton space), keeping the elbow on the side the animation put it, then
## turns the hand so the fingers point along `fingers`.
func _reach(sk: Skeleton3D, bones: Array, target: Vector3, fingers: Vector3) -> void:
	var s := sk.get_bone_global_pose(bones[0]).origin
	var e := sk.get_bone_global_pose(bones[1]).origin
	var h := sk.get_bone_global_pose(bones[2]).origin
	var a := (e - s).length()
	var b := (h - e).length()
	var d := target - s
	var dist := clampf(d.length(), absf(a - b) + 0.001, a + b - 0.001)
	var dir := d.normalized()
	var side := (e - s) - dir * (e - s).dot(dir)
	if side.length_squared() < 1e-8:
		side = Vector3.DOWN
	side = side.normalized()
	var ang := acos(clampf((a * a + dist * dist - b * b) / (2.0 * a * dist), -1.0, 1.0))
	var elbow := s + dir * cos(ang) * a + side * sin(ang) * a
	_aim_bone(sk, bones[0], e - s, elbow - s)
	var e2 := sk.get_bone_global_pose(bones[1]).origin
	_aim_bone(sk, bones[1], sk.get_bone_global_pose(bones[2]).origin - e2, target - e2)
	_aim_bone(sk, bones[2], sk.get_bone_global_pose(bones[2]).basis.y, fingers)


## Turns a bone (about its own position) so the direction `from` points along `to`.
func _aim_bone(sk: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> void:
	if from.length_squared() < 1e-10 or to.length_squared() < 1e-10:
		return
	var f := from.normalized()
	var t := to.normalized()
	var axis := f.cross(t)
	if axis.length_squared() < 1e-10:
		return
	_turn(sk, bone, Basis(axis.normalized(), f.signed_angle_to(t, axis.normalized())))


## Rotates a bone about its own position, in skeleton space.
func _turn(sk: Skeleton3D, bone: int, r: Basis) -> void:
	var g := sk.get_bone_global_pose(bone)
	g.basis = r * g.basis
	sk.set_bone_global_pose(bone, g)
