"""Turns a rigged, generated player model (Meshy / Mixamo skeleton) into the
game's player model.

    python tools/models/prepare_player.py --src red_soldier_rigged.glb --out player/models/soldier.glb

Steps:
1. Keeps the skinned character and its skeleton; drops stray objects.
2. Arms: a two-handed weapon hold (weapon in front at chest height, right
   hand on the grip, left hand forward), on every animation, including the
   ones the model came with (Running, Walking), whose free arm swing would
   look odd with a weapon.
3. Adds the animations the game needs (Mixamo bone names, "mixamorig:..."):
       idle         2 s loop, breathing
       run          the model's own Running (arms in the hold)
       walk         the model's own Walking (arms in the hold)
       crouch       1 s loop, low enough for the 1.1 m crouch hull
       crouch_walk  0.8 s loop
       jump         held pose in the air
The model faces Blender -Y (glTF +Z); the game turns it around.
Textures are made red: the game recolors red to blue for the Blue team
(player/team_swap.gdshader).
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector


def arg(name, default=None):
    return sys.argv[sys.argv.index("--" + name) + 1] if "--" + name in sys.argv else default


SRC = arg("src")
OUT = arg("out")
P = "mixamorig:"
X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))

# Where the hands go for the weapon hold, in meters on the model (facing -Y).
HOLD_RIGHT = Vector((-0.13, -0.3, 1.13))   # On the grip, near the chest.
HOLD_LEFT = Vector((0.06, -0.52, 1.24))    # Forward, under the barrel.


def load():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o.parent != arm and not any(m.type == "ARMATURE" for m in o.modifiers):
            print("removing stray object", o.name)
            bpy.data.objects.remove(o)
    for img in bpy.data.images:   # Color stays 2K; normal/roughness maps 1K.
        if img.colorspace_settings.name != "sRGB" and img.size[0] > 1024:
            img.scale(1024, 1024)
    if arm.animation_data:   # The importer's own tracks would export the clips twice.
        for t in list(arm.animation_data.nla_tracks):
            arm.animation_data.nla_tracks.remove(t)
    fps = bpy.context.scene.render.fps
    print("scene fps", fps, "actions", [(a.name, tuple(a.frame_range)) for a in bpy.data.actions])
    return arm


# --- Pose maths ------------------------------------------------------------------
# Poses are rotations in armature (world) space, applied in each bone's rest
# frame: local = rest^-1 * W * rest. A child given W_child = R_parent^-1 *
# R_extra * R_parent ends up with R_extra on top of its parent's rotation.

def W_arm(arm):
    return arm.matrix_world.to_3x3().normalized()


def rest_dir(arm, bone):
    b = arm.data.bones[P + bone]
    return (W_arm(arm) @ (b.tail_local - b.head_local)).normalized()


def rest_head(arm, bone):
    return arm.matrix_world @ arm.data.bones[P + bone].head_local


def local_q(arm, bone, world_rot: Matrix) -> Quaternion:
    rest = W_arm(arm) @ arm.data.bones[P + bone].matrix_local.to_3x3().normalized()
    return (rest.inverted() @ world_rot @ rest).to_quaternion()


def two_bone(shoulder, a, b, target, pole):
    """Elbow position for an arm of segment lengths a, b reaching target."""
    d = target - shoulder
    dist = min(d.length, a + b - 1e-4)
    d = d.normalized()
    cos_a = (a * a + dist * dist - b * b) / (2 * a * dist)
    ang = math.acos(max(-1.0, min(1.0, cos_a)))
    side = (pole - d * pole.dot(d)).normalized()
    return shoulder + d * math.cos(ang) * a + side * math.sin(ang) * a


def arm_hold(arm, side, target, pole):
    """World rotations for <side>Arm and <side>ForeArm reaching target."""
    up, fore, hand = side + "Arm", side + "ForeArm", side + "Hand"
    s, e, h = rest_head(arm, up), rest_head(arm, fore), rest_head(arm, hand)
    a, b = (e - s).length, (h - e).length
    elbow = two_bone(s, a, b, target, pole)
    r_up = rest_dir(arm, up).rotation_difference((elbow - s).normalized()).to_matrix()
    fore_now = r_up @ rest_dir(arm, fore)
    r_extra = fore_now.rotation_difference((target - elbow).normalized()).to_matrix()
    return {up: r_up, fore: r_up.inverted() @ r_extra @ r_up}


def hold_pose(arm):
    p = {}
    p.update(arm_hold(arm, "Right", HOLD_RIGHT, Vector((-0.6, 0.3, -1))))
    p.update(arm_hold(arm, "Left", HOLD_LEFT, Vector((0.7, 0.1, -1))))
    return p


def rot(axis, deg):
    return Matrix.Rotation(math.radians(deg), 3, axis)


def key_pose(arm, frame, pose, hips_loc=Vector()):
    """pose: {bone: world rotation 3x3}; everything else at rest."""
    for pb in arm.pose.bones:
        name = pb.name[len(P):] if pb.name.startswith(P) else pb.name
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = local_q(arm, name, pose[name]) if name in pose else Quaternion()
        pb.location = (0, 0, 0)
        if name == "Hips":
            rest = W_arm(arm) @ arm.data.bones[P + "Hips"].matrix_local.to_3x3().normalized()
            scale = arm.matrix_world.to_scale().x
            pb.location = rest.inverted() @ (hips_loc / scale)
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)


def new_action(arm, name, keys, fps):
    """keys: [(time_s, pose, hips_loc)]."""
    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = act
    for t, pose, loc in keys:
        key_pose(arm, round(t * fps), pose, loc)
    push(arm, act)


def push(arm, act):
    act.use_fake_user = True
    track = arm.animation_data.nla_tracks.new()
    track.name = act.name
    track.strips.new(act.name, int(act.frame_range[0]), act)
    track.mute = True
    arm.animation_data.action = None


def fcurves(act):
    if hasattr(act, "fcurves") and len(act.fcurves):
        return act.fcurves, None
    for layer in act.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                return bag.fcurves, bag
    return [], None


def override_arms(arm, act, new_name, hold):
    """The model's own animation, with the arms swapped for the weapon hold."""
    act.name = new_name
    fcs, _ = fcurves(act)
    bones = [P + b for b in hold]
    for fc in list(fcs):
        if any('pose.bones["%s"]' % b in fc.data_path for b in bones):
            fcs.remove(fc)
    arm.animation_data_create()
    arm.animation_data.action = act
    f0, f1 = act.frame_range
    for f in (f0, f1):
        for name, r in hold.items():
            pb = arm.pose.bones[P + name]
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = local_q(arm, name, r)
            pb.keyframe_insert("rotation_quaternion", frame=int(f))
    push(arm, act)


def legs(lt, ls, rt, rs):
    """Thigh and knee angles in degrees (+ = forward / knee bent back); feet flat.
    The model faces -Y, so 'forward' is a negative rotation about X."""
    return {
        "LeftUpLeg": rot(X, -lt), "LeftLeg": rot(X, ls), "LeftFoot": rot(X, lt - ls),
        "RightUpLeg": rot(X, -rt), "RightLeg": rot(X, rs), "RightFoot": rot(X, rt - rs),
    }


def animate(arm):
    fps = bpy.context.scene.render.fps
    hold = hold_pose(arm)
    for act in list(bpy.data.actions):
        n = act.name.lower()
        if "run" in n:
            override_arms(arm, act, "run", hold)
        elif "walk" in n:
            override_arms(arm, act, "walk", hold)

    def with_hold(p):
        out = dict(hold)
        out.update(p)
        return out

    # Spine leans: the model faces -Y, so leaning forward is +X.
    new_action(arm, "idle", [
        (0.0, with_hold({}), Vector()),
        (1.0, with_hold({"Spine1": rot(X, -1.2), "Head": rot(X, 0.8)}), Vector((0, 0, -0.006))),
        (2.0, with_hold({}), Vector()),
    ], fps)

    def crouch(lt, ls, rt, rs, drop=0.47):
        return with_hold({**legs(lt, ls, rt, rs), "Spine": rot(X, 22), "Spine1": rot(X, 10), "Spine2": rot(X, 6),
                          "Neck": rot(X, -14), "Head": rot(X, -20)}), Vector((0, 0.03, -drop))
    c = (92, 132, 88, 128)
    new_action(arm, "crouch", [(0.0, *crouch(*c)), (0.5, *crouch(*c, drop=0.475)), (1.0, *crouch(*c))], fps)
    new_action(arm, "crouch_walk", [
        (0.0, *crouch(102, 140, 78, 118)), (0.2, *crouch(90, 136, 92, 136, drop=0.46)),
        (0.4, *crouch(78, 118, 102, 140)), (0.6, *crouch(92, 136, 90, 136, drop=0.46)),
        (0.8, *crouch(102, 140, 78, 118)),
    ], fps)
    jump = with_hold({**legs(48, 80, 24, 44), "Spine": rot(X, 6), "Head": rot(X, -5)})
    new_action(arm, "jump", [(0.0, jump, Vector()), (0.5, jump, Vector())], fps)


def export():
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=False,
                              export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_force_sampling=True, export_image_format="JPEG", export_jpeg_quality=92)
    print("exported", OUT, os.path.getsize(OUT) // 1024, "KB")


if __name__ == "__main__":
    a = load()
    animate(a)
    export()
