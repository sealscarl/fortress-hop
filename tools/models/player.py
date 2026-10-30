"""Builds the player model in Blender and exports it to glTF.

    python tools/models/player.py  ->  weapons/models/player.glb   (see OUT)

One base body on one humanoid skeleton, shared by every class, plus a kit per
class that the game shows or hides:

    Body          stylized soldier, faceless (balaclava and visor). Uniform
                  in material "Team" / "TeamDark" (the game recolors them
                  red or blue), dark gear, gloves and boots.
    Kit_Scout     cap, headset with mic, light harness, hip pouch
    Kit_Soldier   helmet, shoulder armor, chest plate, rocket pack
    Kit_Medic     white panels with red crosses, medic backpack, headband
    Kit_Demoman   beanie with goggles, bandolier of pipe bombs, thigh pouch

Animations (shared by all classes; the game adds aiming and strafing on top
by turning the spine and hips):

    idle          2 s loop
    run           0.6 s loop at 320 ups (the game scales the speed)
    crouch        1 s loop, low enough to fit the 1.1 m crouch hull
    crouch_walk   0.8 s loop
    jump          held pose while in the air

Rest pose: weapon ready, right hand at about chest height (bone "hand_r",
where the game attaches the held weapon). 1.8 m tall, like the hitbox.
Blender: X right, Y forward, Z up; glTF/Godot: forward is -Z.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

FPS = 60
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "player", "models", "player.glb")
OUT = os.path.normpath(sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else OUT)

# --- Skeleton -----------------------------------------------------------------
# name: (head, tail, parent)
BONES = {
    "root": ((0, 0, 0), (0, 0.15, 0), None),
    "hips": ((0, 0, 0.95), (0, 0, 1.05), "root"),
    "spine": ((0, 0, 1.05), (0, 0, 1.25), "hips"),
    "chest": ((0, 0, 1.25), (0, 0, 1.48), "spine"),
    "neck": ((0, 0, 1.5), (0, 0, 1.6), "chest"),
    "head": ((0, 0, 1.6), (0, 0, 1.8), "neck"),
    "thigh_l": ((-0.11, 0, 0.93), (-0.11, 0.02, 0.52), "hips"),
    "shin_l": ((-0.11, 0.02, 0.52), (-0.11, 0, 0.1), "thigh_l"),
    "foot_l": ((-0.11, 0, 0.1), (-0.11, 0.16, 0.03), "shin_l"),
    "thigh_r": ((0.11, 0, 0.93), (0.11, 0.02, 0.52), "hips"),
    "shin_r": ((0.11, 0.02, 0.52), (0.11, 0, 0.1), "thigh_r"),
    "foot_r": ((0.11, 0, 0.1), (0.11, 0.16, 0.03), "shin_r"),
    "upperarm_r": ((0.21, 0, 1.43), (0.25, 0.12, 1.19), "chest"),
    "forearm_r": ((0.25, 0.12, 1.19), (0.14, 0.33, 1.16), "upperarm_r"),
    "hand_r": ((0.14, 0.33, 1.16), (0.12, 0.42, 1.16), "forearm_r"),
    "upperarm_l": ((-0.21, 0, 1.43), (-0.26, 0.18, 1.22), "chest"),
    "forearm_l": ((-0.26, 0.18, 1.22), (-0.08, 0.45, 1.22), "upperarm_l"),
    "hand_l": ((-0.08, 0.45, 1.22), (-0.03, 0.53, 1.22), "forearm_l"),
}


def J(bone, end="head"):
    """A joint position (bone head or tail)."""
    return Vector(BONES[bone][0 if end == "head" else 1])


# --- Scene and materials ------------------------------------------------------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS


MATS = {}


def material(key, name, color, metallic=0.0, roughness=0.6, emission=None, strength=1.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    MATS[key] = m


def mats():
    material("team", "Team", (0.55, 0.13, 0.1), 0.0, 0.7)
    material("team_dark", "TeamDark", (0.22, 0.06, 0.05), 0.0, 0.75)
    material("gear", "Gear", (0.13, 0.13, 0.12), 0.1, 0.65)
    material("gear_light", "GearLight", (0.3, 0.29, 0.26), 0.2, 0.55)
    material("glove", "Glove", (0.05, 0.05, 0.055), 0.0, 0.75)
    material("boot", "Boot", (0.07, 0.06, 0.05), 0.0, 0.7)
    material("visor", "Visor", (0.02, 0.03, 0.035), 0.7, 0.12, emission=(0.1, 0.35, 0.45), strength=0.6)
    material("metal", "Metal", (0.45, 0.46, 0.48), 1.0, 0.3)
    material("white", "White", (0.85, 0.85, 0.82), 0.0, 0.55)
    material("red", "RedCross", (0.75, 0.04, 0.04), 0.0, 0.5)
    material("pipe", "PipeBomb", (0.12, 0.3, 0.16), 0.3, 0.45)
    material("rocket", "RocketBody", (0.72, 0.71, 0.66), 0.3, 0.4)
    material("rocket_tip", "RocketTip", (0.6, 0.08, 0.06), 0.2, 0.4)


# --- Building blocks ----------------------------------------------------------
# Every piece is rigidly bound to one bone. Pieces are gathered per object
# (the body, or one class kit) and joined at the end.

PIECES = {}   # object name -> [(blender object, bone)]
CURRENT = ["Body"]


def _keep(o, mat, bone, smooth=True):
    o.data.materials.append(MATS[mat])
    if smooth:
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
        o.select_set(False)
    PIECES.setdefault(CURRENT[0], []).append((o, bone))
    return o


def sphere(c, r, mat, bone, scale=(1, 1, 1), segs=24):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=segs // 2, radius=r, location=c)
    o = bpy.context.active_object
    o.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return _keep(o, mat, bone)


def capsule(a, b, r, mat, bone, r2=None, segs=20):
    """A rounded limb from a to b (optionally tapering to r2)."""
    a, b = Vector(a), Vector(b)
    r2 = r if r2 is None else r2
    d = b - a
    bpy.ops.mesh.primitive_cone_add(vertices=segs, radius1=r, radius2=r2, depth=d.length, location=(a + b) / 2)
    o = bpy.context.active_object
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.normalized().to_track_quat("Z", "Y")
    bpy.ops.object.transform_apply(rotation=True)
    _keep(o, mat, bone)
    sphere(a, r, mat, bone, segs=segs)
    sphere(b, r2, mat, bone, segs=segs)


def blob(c, size, mat, bone, rot=(0, 0, 0), round_=0.03, segs=4):
    """A soft rounded box (torso, pads, packs)."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=c, rotation=[math.radians(a) for a in rot])
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    mod = o.modifiers.new("Bevel", "BEVEL")
    mod.width = min(round_, min(size) * 0.49)
    mod.segments = segs
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="Bevel")
    return _keep(o, mat, bone)


def cyl(c, r, h, mat, bone, axis=(0, 0, 1), segs=20, r2=None):
    axis = Vector(axis).normalized()
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=segs, radius=r, depth=h, location=c)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=segs, radius1=r, radius2=r2, depth=h, location=c)
    o = bpy.context.active_object
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = axis.to_track_quat("Z", "Y")
    bpy.ops.object.transform_apply(rotation=True)
    mod = o.modifiers.new("Bevel", "BEVEL")
    mod.width = min(r * 0.25, h * 0.2, 0.006)
    mod.segments = 2
    mod.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="Bevel")
    return _keep(o, mat, bone)


def torus(c, major, minor, mat, bone, axis=(0, 0, 1), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=32,
                                     minor_segments=10, location=c)
    o = bpy.context.active_object
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector(axis).normalized().to_track_quat("Z", "Y")
    o.scale = scale
    bpy.ops.object.transform_apply(rotation=True, scale=True)
    return _keep(o, mat, bone)


def cross(c, size, depth, mat, bone, facing=(0, 1, 0)):
    """A red cross plate facing a direction (front or back)."""
    f = Vector(facing)
    if abs(f.y) > 0.5:
        blob(c, (size * 0.3, depth, size), mat, bone, round_=0.004, segs=1)
        blob(c, (size, depth, size * 0.3), mat, bone, round_=0.004, segs=1)
    else:
        blob(c, (depth, size * 0.3, size), mat, bone, round_=0.004, segs=1)
        blob(c, (depth, size, size * 0.3), mat, bone, round_=0.004, segs=1)


# --- The base body --------------------------------------------------------------

def body():
    CURRENT[0] = "Body"
    # Hips and belt.
    blob((0, 0, 0.94), (0.33, 0.21, 0.2), "team", "hips", round_=0.06)
    blob((0, 0, 1.03), (0.35, 0.235, 0.065), "gear", "hips", round_=0.02)
    blob((0, 0.12, 1.03), (0.07, 0.015, 0.05), "metal", "hips", round_=0.006)          # buckle
    for x in (-0.15, 0.15):
        blob((x, 0.06, 1.0), (0.05, 0.07, 0.07), "gear", "hips", round_=0.015)         # belt pouches
    # Torso: belly, then a broad chest with shoulders.
    blob((0, 0, 1.15), (0.3, 0.19, 0.2), "team", "spine", round_=0.07)
    blob((0, -0.005, 1.35), (0.43, 0.25, 0.27), "team", "chest", round_=0.09)
    for x in (-0.205, 0.205):
        sphere((x, 0, 1.43), 0.08, "team", "chest")
    blob((0, 0.11, 1.42), (0.2, 0.04, 0.06), "team_dark", "chest", round_=0.02)          # collar
    # Neck and head: balaclava, visor, a little brow.
    capsule((0, 0, 1.48), (0, 0, 1.57), 0.058, "team_dark", "neck")
    sphere((0, 0, 1.685), 0.118, "team_dark", "head", scale=(0.92, 1.0, 1.08))
    blob((0, 0.088, 1.695), (0.17, 0.05, 0.065), "visor", "head", round_=0.022)
    blob((0, 0.07, 1.74), (0.16, 0.05, 0.02), "gear", "head", round_=0.008)              # visor brow
    blob((0, 0.095, 1.63), (0.08, 0.04, 0.045), "gear", "head", round_=0.015)            # breather
    # Arms: sleeves in team color, elbow pads, gloves.
    for side in ("r", "l"):
        sh, el, wr = J("upperarm_" + side), J("forearm_" + side), J("hand_" + side)
        capsule(sh, el, 0.058, "team", "upperarm_" + side, r2=0.052)
        sphere(el, 0.06, "gear", "forearm_" + side)
        capsule(el, wr, 0.05, "team", "forearm_" + side, r2=0.043)
        cyl(wr + (el - wr).normalized() * 0.02, 0.047, 0.05, "glove", "forearm_" + side, axis=el - wr)   # cuff
        d = (J("hand_" + side, "tail") - wr).normalized()
        blob(wr + d * 0.045, (0.07, 0.1, 0.06), "glove", "hand_" + side, round_=0.025)
    # Legs: thighs, knee pads, shins, boots.
    for side in ("l", "r"):
        hip, knee, ankle = J("thigh_" + side), J("shin_" + side), J("foot_" + side)
        capsule(hip, knee, 0.08, "team", "thigh_" + side, r2=0.066)
        sphere(knee + Vector((0, 0.035, 0)), 0.064, "gear", "shin_" + side, scale=(1, 0.8, 1.1))
        capsule(knee, ankle + Vector((0, 0, 0.06)), 0.062, "team", "shin_" + side, r2=0.05)
        blob((ankle.x, 0.035, 0.065), (0.115, 0.26, 0.13), "boot", "foot_" + side, round_=0.04)
        blob((ankle.x, 0.04, 0.012), (0.12, 0.27, 0.025), "gear", "foot_" + side, round_=0.008)  # sole


# --- Class kits -----------------------------------------------------------------

def kit_scout():
    CURRENT[0] = "Kit_Scout"
    # Cap with a bill, worn over the balaclava.
    sphere((0, -0.005, 1.72), 0.125, "team", "head", scale=(0.98, 1.02, 0.62))
    blob((0, 0.13, 1.735), (0.17, 0.12, 0.016), "team_dark", "head", rot=(-8, 0, 0), round_=0.007)
    # Headset: ear cups, band, mic boom.
    for x in (-0.112, 0.112):
        cyl((x, -0.005, 1.68), 0.04, 0.03, "gear", "head", axis=(1, 0, 0))
    capsule((0.115, 0.01, 1.66), (0.06, 0.11, 1.63), 0.006, "gear", "head")
    sphere((0.055, 0.115, 1.63), 0.013, "gear", "head")
    # Light chest harness and a hip pouch.
    for x in (-0.1, 0.1):
        capsule((x, 0.125, 1.46), (x * 0.8, 0.135, 1.08), 0.014, "gear", "chest")
        capsule((x, -0.13, 1.46), (x * 0.8, -0.13, 1.08), 0.014, "gear", "chest")
    blob((0, 0.135, 1.25), (0.2, 0.025, 0.035), "gear", "chest", round_=0.01)
    blob((0.17, -0.06, 0.95), (0.06, 0.12, 0.1), "gear", "hips", round_=0.02)


def kit_soldier():
    CURRENT[0] = "Kit_Soldier"
    # Helmet: dome and rim.
    sphere((0, -0.005, 1.725), 0.14, "gear_light", "head", scale=(1.0, 1.05, 0.72))
    torus((0, -0.005, 1.7), 0.14, 0.012, "gear_light", "head", scale=(1.0, 1.06, 1.0))
    capsule((-0.1, 0.06, 1.66), (0.1, 0.06, 1.66), 0.006, "gear", "head")                 # chin strap
    # Shoulder armor.
    for x, tilt in ((0.235, -22), (-0.235, 22)):
        blob((x, 0, 1.47), (0.15, 0.17, 0.07), "gear_light", "chest", rot=(0, tilt, 0), round_=0.03)
    # Chest plate with pouches.
    blob((0, 0.125, 1.33), (0.38, 0.05, 0.3), "gear_light", "chest", round_=0.025)
    for x in (-0.11, 0, 0.11):
        blob((x, 0.16, 1.24), (0.085, 0.04, 0.09), "gear", "chest", round_=0.015)
    # Rocket pack on the back: frame and two spare rockets.
    blob((0, -0.17, 1.31), (0.3, 0.09, 0.32), "gear", "chest", round_=0.025)
    for x in (-0.08, 0.08):
        cyl((x, -0.245, 1.33), 0.036, 0.28, "rocket", "chest")
        cyl((x, -0.245, 1.51), 0.036, 0.08, "rocket_tip", "chest", r2=0.004)


def kit_medic():
    CURRENT[0] = "Kit_Medic"
    # White panels front and back, red crosses.
    blob((0, 0.125, 1.33), (0.34, 0.04, 0.3), "white", "chest", round_=0.02)
    cross((0, 0.148, 1.35), 0.12, 0.012, "red", "chest")
    blob((0, -0.15, 1.32), (0.3, 0.12, 0.3), "white", "chest", round_=0.03)               # medic pack
    cross((0, -0.213, 1.33), 0.14, 0.012, "red", "chest")
    # Armbands with crosses, and a headband.
    for side in ("r", "l"):
        sh, el = J("upperarm_" + side), J("forearm_" + side)
        mid = sh.lerp(el, 0.45)
        cyl(mid, 0.064, 0.05, "white", "upperarm_" + side, axis=el - sh)
    torus((0, 0, 1.715), 0.112, 0.016, "white", "head", scale=(0.95, 1.05, 1.0))
    cross((0, 0.106, 1.72), 0.035, 0.008, "red", "head")


def kit_demoman():
    CURRENT[0] = "Kit_Demoman"
    # Beanie with a rolled brim, goggles pushed up on it.
    sphere((0, -0.005, 1.74), 0.13, "team_dark", "head", scale=(0.96, 1.0, 0.85))
    torus((0, -0.005, 1.715), 0.122, 0.022, "team_dark", "head", scale=(0.95, 1.05, 1.0))
    for x in (-0.045, 0.045):
        cyl((x, 0.105, 1.76), 0.032, 0.03, "gear", "head", axis=(0, 1, 0))
        cyl((x, 0.121, 1.76), 0.024, 0.004, "visor", "head", axis=(0, 1, 0))
    torus((0, 0, 1.76), 0.13, 0.008, "gear", "head", scale=(0.95, 1.0, 1.0))
    # Bandolier of pipe bombs across the chest, and a thigh pouch.
    a, b = Vector((0.17, 0.125, 1.46)), Vector((-0.16, 0.13, 1.02))
    capsule(a, b, 0.018, "gear", "chest")
    for i in range(5):
        p = a.lerp(b, 0.12 + i * 0.18) + Vector((0, 0.025, 0))
        cyl(p, 0.022, 0.07, "pipe", "chest", axis=(0.55, 0, 0.83))
        cyl(p + Vector((0.55, 0, 0.83)) * 0.038, 0.016, 0.012, "metal", "chest", axis=(0.55, 0, 0.83))
    blob((0.18, 0.03, 0.74), (0.07, 0.13, 0.13), "gear", "thigh_r", round_=0.025)


# --- Rig and skinning --------------------------------------------------------------

def rig():
    bpy.ops.object.armature_add(location=(0, 0, 0))
    arm = bpy.context.active_object
    arm.name = "PlayerRig"
    arm.data.name = "PlayerRig"
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    eb.remove(eb[0])
    for name, (head, tail, parent) in BONES.items():
        b = eb.new(name)
        b.head = head
        b.tail = tail
        b.roll = 0
        if parent:
            b.parent = eb[parent]
            b.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for obj_name, pieces in PIECES.items():
        for o, bone in pieces:
            vg = o.vertex_groups.new(name=bone)
            vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
        bpy.ops.object.select_all(action="DESELECT")
        for o, _ in pieces:
            o.select_set(True)
        bpy.context.view_layer.objects.active = pieces[0][0]
        bpy.ops.object.join()
        joined = bpy.context.active_object
        joined.name = obj_name
        joined.data.name = obj_name
        joined.parent = arm
        mod = joined.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
    return arm


# --- Animation ---------------------------------------------------------------------
# Poses are given as rotations about world axes (X = pitch forward/back for
# legs and spine, Z = yaw, Y = roll), applied in each bone's rest frame, so
# chains like thigh + shin simply add up.

def _local_rot(bone, axis, deg):
    rest = bone.matrix_local.to_3x3()
    world = Matrix.Rotation(math.radians(deg), 3, axis)
    return (rest.inverted() @ world @ rest).to_quaternion()


def pose_key(arm, frame, bone_name, rots=(), loc=(0, 0, 0)):
    pb = arm.pose.bones[bone_name]
    pb.rotation_mode = "QUATERNION"
    q = Quaternion()
    for axis, deg in rots:
        q = _local_rot(pb.bone, axis, deg) @ q
    pb.rotation_quaternion = q
    pb.location = pb.bone.matrix_local.to_3x3().inverted() @ Vector(loc)
    pb.keyframe_insert("rotation_quaternion", frame=frame)
    pb.keyframe_insert("location", frame=frame)


def action(arm, name, poses, length):
    """poses: [(time_s, {bone: (rots, loc)}), ...]. Unlisted bones stay at rest."""
    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = act
    for t, pose in poses:
        f = round(t * FPS)
        for b in BONES:
            rots, loc = pose.get(b, ((), (0, 0, 0)))
            pose_key(arm, f, b, rots, loc)
    act.use_fake_user = True
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, act)
    track.mute = True
    arm.animation_data.action = None


X, Y, Z = "X", "Y", "Z"


def legs(l_thigh, l_shin, r_thigh, r_shin, foot_fix=True):
    """Leg pose by thigh and knee angles (degrees, + = forward); feet kept flat."""
    p = {
        "thigh_l": (((X, l_thigh),), (0, 0, 0)), "shin_l": (((X, l_shin),), (0, 0, 0)),
        "thigh_r": (((X, r_thigh),), (0, 0, 0)), "shin_r": (((X, r_shin),), (0, 0, 0)),
    }
    if foot_fix:
        p["foot_l"] = (((X, -(l_thigh + l_shin)),), (0, 0, 0))
        p["foot_r"] = (((X, -(r_thigh + r_shin)),), (0, 0, 0))
    return p


def merge(*dicts):
    out = {}
    for d in dicts:
        out.update(d)
    return out


def animate(arm):
    # Idle: slow breathing and a slight weight shift.
    action(arm, "idle", [
        (0.0, {}),
        (1.0, {"chest": (((X, -1.5),), (0, 0, 0)), "hips": ((), (0, 0, -0.006)),
               "head": (((X, 1.0),), (0, 0, 0))}),
        (2.0, {}),
    ], 2.0)

    # Run: a 0.6 s stride. Contact, passing, contact (other leg), passing.
    def run_pose(phase_legs, bob, twist):
        return merge(phase_legs, {
            "hips": (((Z, twist),), (0, 0, bob)),
            "spine": (((X, 8), (Z, -twist * 1.4)), (0, 0, 0)),
            "chest": (((X, 4),), (0, 0, 0)),
            "head": (((X, -10),), (0, 0, 0)),
        })
    a = legs(34, -12, -30, -28)
    b = legs(4, -18, 18, -88)
    c = legs(-30, -28, 34, -12)
    d = legs(18, -88, 4, -18)
    action(arm, "run", [
        (0.0, run_pose(a, -0.035, 6)), (0.15, run_pose(b, 0.02, 0)),
        (0.3, run_pose(c, -0.035, -6)), (0.45, run_pose(d, 0.02, 0)), (0.6, run_pose(a, -0.035, 6)),
    ], 0.6)

    # Crouch: deep squat that fits the 1.1 m hull; lean in, keep the head up.
    def crouch_pose(lt, ls, rt, rs, drop=-0.55):
        return merge(legs(lt, ls, rt, rs), {
            "hips": ((), (0, -0.02, drop)),
            "spine": (((X, 20),), (0, 0, 0)),
            "chest": (((X, 14),), (0, 0, 0)),
            "neck": (((X, -12),), (0, 0, 0)),
            "head": (((X, -18),), (0, 0, 0)),
        })
    base = (88, -132, 82, -128)
    action(arm, "crouch", [(0.0, crouch_pose(*base)), (0.5, crouch_pose(*base, drop=-0.56)),
                           (1.0, crouch_pose(*base))], 1.0)
    action(arm, "crouch_walk", [
        (0.0, crouch_pose(98, -138, 72, -118)), (0.2, crouch_pose(85, -140, 88, -138, drop=-0.54)),
        (0.4, crouch_pose(72, -118, 98, -138)), (0.6, crouch_pose(88, -138, 85, -140, drop=-0.54)),
        (0.8, crouch_pose(98, -138, 72, -118)),
    ], 0.8)

    # Jump: legs tucked, one higher than the other.
    jump = merge(legs(48, -78, 22, -42), {"spine": (((X, 6),), (0, 0, 0)), "head": (((X, -6),), (0, 0, 0))})
    action(arm, "jump", [(0.0, jump), (0.5, jump)], 0.5)


def export():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True,
                              export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_force_sampling=True, export_yup=True)
    print("exported", OUT)


if __name__ == "__main__":
    reset()
    mats()
    body()
    kit_scout()
    kit_soldier()
    kit_medic()
    kit_demoman()
    arm = rig()
    animate(arm)
    export()
