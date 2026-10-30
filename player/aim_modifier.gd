class_name AimModifier
extends SkeletonModifier3D
## Runs after the player model's animation each frame:
## - Aim: the spine bends so the upper body (and the weapon) points where the
##   player is looking, up or down.
## - Strafe: the hips turn toward the way the player is moving, and the spine
##   turns back, so the legs run sideways while the chest keeps facing forward.
## Rotations are in skeleton space; the model faces +Z there, so looking up
## is a rotation about -X.

var pitch := 0.0   ## Radians, + = looking up.
var hips_yaw := 0.0   ## Radians the legs turn toward the move direction.

const SPINE := [["mixamorig_Spine", 0.3], ["mixamorig_Spine1", 0.3], ["mixamorig_Spine2", 0.4]]
var _hips := -1
var _spine: Array = []


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _hips == -1:
		_hips = sk.find_bone("mixamorig_Hips")
		for s in SPINE:
			_spine.append([sk.find_bone(s[0]), s[1]])
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


## Rotates a bone about its own position, in skeleton space.
func _turn(sk: Skeleton3D, bone: int, r: Basis) -> void:
	var g := sk.get_bone_global_pose(bone)
	g.basis = r * g.basis
	sk.set_bone_global_pose(bone, g)
