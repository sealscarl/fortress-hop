"""Builds the first-person rocket launcher in Blender and exports it to glTF.

Run headless (Blender as a Python module, or `blender -b -P`):
    python tools/models/rocket_launcher.py  ->  weapons/models/rocket_launcher.glb

Everything is original and built from code. The model is one skinned mesh on
a small skeleton, so it imports into Godot (or Unreal) like any artist-made
weapon: a Skeleton3D plus an AnimationPlayer with these clips:

    idle            2 s loop, gentle breathing sway (hands on the grips)
    draw            0.35 s, comes up from below
    fire            0.4 s, recoil kick and trigger pull
    reload_start    0.12 s, swing the front end across, toward the middle
    reload_insert   0.8 s, left hand fetches a rocket and pushes it into the
                    muzzle, tail first (repeat per round)
    reload_end      0.25 s, close the hatch and level out

Blender axes: X right, Y forward (barrel), Z up, 1 unit = 1 m. The glTF
exporter turns Blender's +Y into Godot's -Z, so the barrel points forward.

Includes gloved hands and team-colored sleeves (material "Sleeve", which the
game can recolor per team).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

FPS = 60
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "weapons", "models", "rocket_launcher.glb")
OUT = os.path.normpath(sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else OUT)

TUBE_R = 0.056
HATCH_HINGE = Vector((-TUBE_R * 0.8, -0.12, TUBE_R * 0.55))   # Left side: the left hand loads it.
FOREGRIP = Vector((0, 0.14, -TUBE_R - 0.05))
GRIP = Vector((0, -0.065, -TUBE_R - 0.07))
ROCKET_REST = Vector((0, 0.25, 0))   # Rocket bone, inside the front of the tube.
GRIP_AXIS = Vector((0, math.sin(math.radians(14)), math.cos(math.radians(14))))


# --- Scene ------------------------------------------------------------------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.fps = FPS


def material(name, color, metallic=0.0, roughness=0.5, emission=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 3.0
    return m


MATS = {}


def mats():
    MATS["paint"] = material("OliveDrab", (0.17, 0.21, 0.12), 0.25, 0.55)
    MATS["paint_dark"] = material("OliveDark", (0.10, 0.12, 0.07), 0.25, 0.6)
    MATS["metal"] = material("Gunmetal", (0.09, 0.09, 0.1), 0.85, 0.32)
    MATS["steel"] = material("Steel", (0.55, 0.56, 0.58), 1.0, 0.22)
    MATS["brass"] = material("Brass", (0.78, 0.56, 0.24), 1.0, 0.28)
    MATS["rubber"] = material("Rubber", (0.035, 0.035, 0.035), 0.0, 0.9)
    MATS["hole"] = material("Bore", (0.005, 0.005, 0.005), 0.0, 1.0)
    MATS["hazard"] = material("Hazard", (0.85, 0.6, 0.06), 0.1, 0.45)
    MATS["lens"] = material("Lens", (0.4, 0.02, 0.02), 0.0, 0.1, emission=(1.0, 0.08, 0.05))
    MATS["rocket_body"] = material("RocketBody", (0.75, 0.74, 0.7), 0.3, 0.4)
    MATS["rocket_tip"] = material("RocketTip", (0.6, 0.08, 0.06), 0.2, 0.4)
    MATS["glove"] = material("Glove", (0.06, 0.06, 0.065), 0.0, 0.75)
    MATS["glove_pad"] = material("GlovePad", (0.16, 0.16, 0.17), 0.0, 0.6)
    MATS["cuff"] = material("Cuff", (0.11, 0.1, 0.09), 0.0, 0.85)
    MATS["sleeve"] = material("Sleeve", (0.5, 0.12, 0.1), 0.0, 0.8)


PARTS = []   # (object, bone)


def finish(obj, mat, bone="weapon", bevel=0.003, smooth=True):
    obj.data.materials.append(MATS[mat])
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(40)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier="Bevel")
    if smooth:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
        obj.select_set(False)
    PARTS.append((obj, bone))
    return obj


def cyl(r, length, y0, x=0.0, z=0.0, verts=48, r2=None):
    """Cylinder (or cone, with r2 at the front end) along +Y from y0."""
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=length,
                                            location=(x, y0 + length / 2, z), rotation=(-math.pi / 2, 0, 0))
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=length,
                                        location=(x, y0 + length / 2, z), rotation=(-math.pi / 2, 0, 0))
    return bpy.context.active_object


def box(size, loc, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return o


def torus(major, minor, y, x=0.0, z=0.0, rot=(math.pi / 2, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=48,
                                     minor_segments=12, location=(x, y, z), rotation=rot)
    return bpy.context.active_object


# --- The launcher -------------------------------------------------------------

def build():
    # Main tube and its hollow ends.
    finish(cyl(TUBE_R, 0.66, -0.27), "paint", bevel=0.004)
    finish(cyl(TUBE_R * 0.86, 0.004, 0.395), "hole", bevel=0, smooth=False)            # muzzle bore
    finish(cyl(TUBE_R + 0.014, 0.08, 0.33), "metal", bevel=0.004)                       # muzzle shroud
    finish(torus(TUBE_R + 0.014, 0.006, 0.41), "metal")                                 # muzzle lip
    finish(cyl(TUBE_R + 0.004, 0.026, 0.285), "hazard", bevel=0.002)                    # hazard band
    for i in range(4):                                                                  # black chevrons on it
        a = i * math.pi / 2 + math.pi / 4
        finish(box((0.012, 0.027, 0.004), (math.cos(a) * (TUBE_R + 0.006), 0.298, math.sin(a) * (TUBE_R + 0.006)),
                   (0, -a + math.pi / 2, 0)), "hole", bevel=0.001)
    # Rear venturi: a flared exhaust cone with a dark throat.
    finish(cyl(TUBE_R + 0.022, 0.11, -0.39, r2=TUBE_R + 0.002), "metal", bevel=0.003)
    finish(cyl(TUBE_R + 0.012, 0.004, -0.392), "hole", bevel=0, smooth=False)
    finish(torus(TUBE_R + 0.022, 0.006, -0.39), "steel")
    # Reinforcement rings and their bolts.
    for y in (-0.2, -0.02, 0.17):
        finish(cyl(TUBE_R + 0.007, 0.018, y), "metal", bevel=0.002)
        for a in (0.0, math.pi * 2 / 3, math.pi * 4 / 3):
            p = Vector((math.cos(a), 0, math.sin(a))) * (TUBE_R + 0.0085)
            bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=0.0042,
                                                 location=(p.x, y + 0.009, p.z))
            finish(bpy.context.active_object, "brass", bevel=0)
    # Top rail with a sight: rear block, front post, glowing dot.
    finish(box((0.026, 0.42, 0.012), (0, 0.02, TUBE_R + 0.012)), "metal")
    for i in range(10):
        finish(box((0.03, 0.012, 0.006), (0, -0.16 + i * 0.04, TUBE_R + 0.021)), "metal", bevel=0.001)
    finish(box((0.05, 0.05, 0.04), (0, -0.09, TUBE_R + 0.042)), "paint_dark", bevel=0.005)
    # Scope tube sticks out of the block at both ends (no faces sharing a
    # plane, which flickers), with a dark eyepiece at the back and the red
    # lens at the front, each straddling the tube's end.
    finish(cyl(0.017, 0.076, -0.128, z=TUBE_R + 0.05), "metal", bevel=0.002)
    finish(cyl(0.0115, 0.002, -0.1295, z=TUBE_R + 0.05), "hole", bevel=0, smooth=False)   # eyepiece
    finish(cyl(0.012, 0.002, -0.0525, z=TUBE_R + 0.05), "lens", bevel=0, smooth=False)    # red dot
    finish(box((0.008, 0.012, 0.03), (0, 0.24, TUBE_R + 0.035)), "metal", bevel=0.002)  # front post
    # Pistol grip, trigger guard, foregrip.
    finish(box((0.034, 0.07, 0.03), (0, -0.04, -TUBE_R - 0.008)), "metal", bevel=0.004)  # receiver block
    grip = box((0.03, 0.045, 0.12), (0, -0.065, -TUBE_R - 0.07), (math.radians(-14), 0, 0))
    finish(grip, "rubber", bevel=0.008)
    for i in range(5):   # grip ridges
        finish(box((0.033, 0.006, 0.004), (0, -0.05 - i * 0.005, -TUBE_R - 0.04 - i * 0.018),
                   (math.radians(-14), 0, 0)), "rubber", bevel=0)
    finish(torus(0.026, 0.004, -0.02, z=-TUBE_R - 0.034, rot=(0, math.pi / 2, 0)), "metal")
    trigger = box((0.008, 0.01, 0.028), (0, -0.018, -TUBE_R - 0.03), (math.radians(20), 0, 0))
    finish(trigger, "steel", bone="trigger", bevel=0.002)
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.018, depth=0.09,
                                        location=(0, 0.14, -TUBE_R - 0.05))   # foregrip (upright)
    finish(bpy.context.active_object, "rubber", bevel=0.004)
    # Loading hatch on the right side (opens for reloads) and its port.
    finish(box((0.006, 0.09, 0.05), (-TUBE_R - 0.001, -0.12, 0.0)), "hole", bevel=0)      # open port (dark)
    hatch = box((0.008, 0.096, 0.056), (-TUBE_R - 0.006, -0.12, 0.0))
    finish(hatch, "paint_dark", bone="hatch", bevel=0.003)
    finish(cyl(0.004, 0.1, -0.17, x=HATCH_HINGE.x - 0.004, z=HATCH_HINGE.z, verts=12), "steel", bone="hatch", bevel=0)
    # The rocket used in the reload (rests hidden inside the tube).
    # The rocket used in the reload: rests hidden inside the front of the
    # tube, tip forward. It's loaded through the muzzle, tail first.
    r0 = ROCKET_REST.y - 0.08
    finish(cyl(0.034, 0.16, r0), "rocket_body", bone="rocket", bevel=0.002)
    finish(cyl(0.034, 0.06, r0 + 0.16, r2=0.004), "rocket_tip", bone="rocket", bevel=0.001)
    for a in (0.0, math.pi / 2, math.pi, math.pi * 1.5):
        fin = box((0.004, 0.04, 0.022), (math.cos(a) * 0.04, r0 + 0.01, math.sin(a) * 0.04), (0, -a, 0))
        finish(fin, "metal", bone="rocket", bevel=0.001)
    hands()


# --- Hands ------------------------------------------------------------------------

def capsule(a, b, r, mat, bone, verts=16):
    """A rounded rod from a to b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=d.length, location=(a + b) / 2)
    o = bpy.context.active_object
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.normalized().to_track_quat("Z", "Y")
    bpy.ops.object.transform_apply(rotation=True)
    finish(o, mat, bone=bone, bevel=0)
    for p in (a, b):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=verts, ring_count=verts // 2, radius=r, location=p)
        finish(bpy.context.active_object, mat, bone=bone, bevel=0)


def blob(center, size, mat, bone, rot=None, bevel=0.012):
    """A soft rounded box (palms, backs of hands)."""
    o = box(size, center)
    if rot is not None:
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = rot
        bpy.ops.object.transform_apply(rotation=True)
    mod = o.modifiers.new("Bevel", "BEVEL")
    mod.width = bevel
    mod.segments = 4
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="Bevel")
    finish(o, mat, bone=bone, bevel=0)


def wrap_finger(center, axis, u, sweep_deg, grip_r, r, bone, start_deg=0.0, segs=3, curl=1.0):
    """A finger wrapped around a grip: knuckle segments along an arc around
    the grip's axis, starting at direction u. Fingertips taper a little."""
    axis, u = Vector(axis).normalized(), Vector(u).normalized()
    v = axis.cross(u)
    pts = []
    for i in range(segs + 1):
        ang = math.radians(start_deg + sweep_deg * i / segs)
        rad = grip_r + r * (1.0 - 0.15 * i / segs) * curl
        pts.append(Vector(center) + (u * math.cos(ang) + v * math.sin(ang)) * rad)
    for i in range(segs):
        capsule(pts[i], pts[i + 1], r * (1.0 - 0.12 * i), "glove", bone)
    # Knuckle pad on the first joint.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=r * 1.08, location=pts[0])
    finish(bpy.context.active_object, "glove_pad", bone=bone, bevel=0)


def arm(wrist, elbow, bone):
    """Glove cuff at the wrist, then a sleeved forearm back to the elbow."""
    wrist, elbow = Vector(wrist), Vector(elbow)
    d = (elbow - wrist).normalized()
    capsule(wrist, wrist + d * 0.05, 0.03, "cuff", bone)
    capsule(wrist + d * 0.05, elbow, 0.041, "sleeve", bone, verts=20)


def hands():
    # Right hand on the pistol grip: palm behind, three fingers wrapped round
    # the front, index finger on the trigger, thumb over the left side.
    gc = GRIP + GRIP_AXIS * 0.0
    fwd = Vector((0, 1, 0)) - GRIP_AXIS * GRIP_AXIS.y   # Grip "front", perpendicular to its axis.
    fwd.normalize()
    rot = Vector((0, 0, 1)).rotation_difference(GRIP_AXIS)
    blob(gc - fwd * 0.03 + Vector((0.012, 0, 0)), (0.05, 0.03, 0.085), "glove", "hand_r", rot)
    for k, (axial, r) in enumerate([(0.012, 0.0105), (-0.013, 0.0102), (-0.036, 0.0092)]):
        c = gc + GRIP_AXIS * axial
        wrap_finger(c, GRIP_AXIS, Vector((1, 0, 0)), 215, 0.021, r, "hand_r", start_deg=-25)
    # Index finger: from the knuckle forward onto the trigger and curled round it.
    k0 = gc + GRIP_AXIS * 0.04 + Vector((0.024, -0.008, 0))
    capsule(k0, (0.012, -0.03, -TUBE_R - 0.026), 0.0105, "glove", "hand_r")
    capsule((0.012, -0.03, -TUBE_R - 0.026), (0.004, -0.014, -TUBE_R - 0.034), 0.0095, "glove", "hand_r")
    capsule((0.004, -0.014, -TUBE_R - 0.034), (0.0, -0.02, -TUBE_R - 0.046), 0.009, "glove", "hand_r")
    # Thumb over the top-left.
    t0 = gc - fwd * 0.03 + GRIP_AXIS * 0.03 + Vector((0.02, 0, 0))
    capsule(t0, gc + GRIP_AXIS * 0.05 + Vector((-0.012, -0.02, 0)), 0.012, "glove", "hand_r")
    capsule(gc + GRIP_AXIS * 0.05 + Vector((-0.012, -0.02, 0)), gc + GRIP_AXIS * 0.055 + Vector((-0.026, 0.002, 0)),
            0.011, "glove", "hand_r")
    arm(gc - fwd * 0.04 - GRIP_AXIS * 0.05 + Vector((0.015, 0, 0)), (0.13, -0.5, -0.32), "hand_r")

    # Left hand on the foregrip: palm on the left, four fingers round the
    # front, thumb round the back.
    fc = FOREGRIP
    up = Vector((0, 0, 1))
    blob(fc + Vector((-0.029, -0.004, 0.0)), (0.028, 0.05, 0.08), "glove", "hand_l")
    for axial, r in [(0.03, 0.0102), (0.009, 0.0105), (-0.012, 0.0102), (-0.032, 0.0092)]:
        wrap_finger(fc + up * axial, up, Vector((-1, 0, 0)), -210, 0.018, r, "hand_l", start_deg=20)
    capsule(fc + Vector((-0.03, -0.02, 0.025)), fc + Vector((-0.008, -0.028, 0.04)), 0.012, "glove", "hand_l")
    capsule(fc + Vector((-0.008, -0.028, 0.04)), fc + Vector((0.016, -0.02, 0.04)), 0.011, "glove", "hand_l")
    arm(fc + Vector((-0.04, -0.01, -0.05)), (-0.32, -0.32, -0.42), "hand_l")


# --- Skeleton and skinning ------------------------------------------------------

BONES = {
    # name: (head, parent)
    "weapon": ((0, 0, 0), None),
    "trigger": ((0, -0.018, -TUBE_R - 0.018), "weapon"),
    "hatch": (tuple(HATCH_HINGE), "weapon"),
    "hand_r": (tuple(GRIP), "weapon"),
    "hand_l": (tuple(FOREGRIP), "weapon"),
    "rocket": (tuple(ROCKET_REST), "hand_l"),   # Carried by the left hand while reloading.
}


def rig():
    bpy.ops.object.armature_add(location=(0, 0, 0))
    arm = bpy.context.active_object
    arm.name = "RocketLauncherRig"
    arm.data.name = "RocketLauncherRig"
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    eb.remove(eb[0])
    for name, (head, parent) in BONES.items():
        b = eb.new(name)
        b.head = head
        b.tail = (head[0], head[1] + 0.05, head[2])   # Every bone points forward, roll 0: local axes = world axes.
        b.roll = 0
        if parent:
            b.parent = eb[parent]
    bpy.ops.object.mode_set(mode="OBJECT")

    # One mesh, each part rigidly weighted to its bone.
    for obj, bone in PARTS:
        vg = obj.vertex_groups.new(name=bone)
        vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    bpy.ops.object.select_all(action="DESELECT")
    for obj, _ in PARTS:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = PARTS[0][0]
    bpy.ops.object.join()
    mesh = bpy.context.active_object
    mesh.name = "RocketLauncher"
    mesh.parent = arm
    mod = mesh.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    return arm


# --- Animation --------------------------------------------------------------------

def key(arm, frame, bone, loc=(0, 0, 0), rot_deg=(0, 0, 0), scale=1.0):
    pb = arm.pose.bones[bone]
    pb.rotation_mode = "XYZ"
    pb.location = loc
    pb.rotation_euler = [math.radians(a) for a in rot_deg]
    pb.scale = (scale, scale, scale)
    pb.keyframe_insert("location", frame=frame)
    pb.keyframe_insert("rotation_euler", frame=frame)
    pb.keyframe_insert("scale", frame=frame)


def action(arm, name, keys, loop=False):
    """keys: {bone: [(time_s, loc, rot_deg), ...]}. Bones not listed hold rest."""
    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = act
    for bone in BONES:
        frames = keys.get(bone, [(0.0, (0, 0, 0), (0, 0, 0))])
        for f in frames:
            key(arm, round(f[0] * FPS), bone, *f[1:])
    # Smooth, slightly snappy curves.
    for fc in _fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.easing = "AUTO"
    act.use_fake_user = True
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, act)
    track.mute = True
    arm.animation_data.action = None
    return act


def _fcurves(act):
    if hasattr(act, "fcurves") and act.fcurves:
        return list(act.fcurves)
    out = []   # Blender 4.4+ layered actions
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                out.extend(bag.fcurves)
    return out


def animate(arm):
    Z = (0, 0, 0)
    # Idle: slow breathing, a few millimetres.
    action(arm, "idle", {"weapon": [
        (0.0, Z, Z), (1.0, (0.0015, 0, 0.004), (0.6, 0, 0.3)), (2.0, Z, Z)]}, loop=True)
    # Draw: swings up from below and settles.
    action(arm, "draw", {"weapon": [
        (0.0, (0.02, -0.08, -0.22), (-35, 0, 12)),
        (0.22, (0, 0.006, 0.006), (3, 0, -1)),
        (0.35, Z, Z)]})
    # Fire: hard kick back and up, trigger snaps, settles.
    action(arm, "fire", {
        "weapon": [(0.0, Z, Z), (0.035, (0, -0.075, 0.012), (9, 0, 1.5)),
                   (0.16, (0, -0.012, 0.002), (1.5, 0, 0)), (0.4, Z, Z)],
        "trigger": [(0.0, Z, Z), (0.03, (0, -0.005, 0), (-25, 0, 0)), (0.15, Z, Z)],
    })
    # Reload through the muzzle: swing the launcher across the body so the
    # front end comes in close to the middle of the screen; the left hand fetches a rocket from below, lines it up in
    # front of the muzzle (tip forward) and pushes it in, then back to the grip.
    tilt = ((0.02, 0.06, -0.06), (-4, 14, 62))
    held = (0.0, -0.14, -0.046)      # Rocket bone offset that puts it in the left palm.
    low = (-0.16, -0.26, -0.3)       # Hand down at the belt, off screen.
    front = (0.0, 0.39, 0.046)       # Rocket lined up just in front of the muzzle.
    push = (0.0, 0.3, 0.05)          # Hand follows it in a little.
    action(arm, "reload_start", {
        "weapon": [(0.0, Z, Z), (0.12, *tilt)],
    })
    action(arm, "reload_insert", {
        "weapon": [(0.0, *tilt), (0.5, *tilt), (0.57, (0.03, 0.05, -0.062), (-5, 14, 61)), (0.8, *tilt)],
        "hand_l": [(0.0, Z, Z), (0.15, low, (-30, 0, 20)), (0.36, front, (0, 0, 0)),
                   (0.46, front, (0, 0, 0)), (0.57, push, (0, 0, 0)), (0.8, Z, Z)],
        "rocket": [(0.0, held, Z, 0.0), (0.14, held, Z, 0.0), (0.15, held, Z, 1.0), (0.46, held, Z, 1.0),
                   (0.57, Z, Z, 1.0), (0.8, Z, Z, 1.0)],
    })
    action(arm, "reload_end", {
        "weapon": [(0.0, *tilt), (0.25, Z, Z)],
    })


def export():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True,
                              export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_force_sampling=True, export_yup=True)
    print("exported", OUT)


if __name__ == "__main__":
    reset()
    mats()
    build()
    arm = rig()
    animate(arm)
    export()
