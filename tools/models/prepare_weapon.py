"""Turns a generated weapon model (Meshy etc.) into a first-person weapon.

    python tools/models/prepare_weapon.py --src big.glb --out weapons/models/x.glb \
        --muzzle -x --length 0.85 [--tris 20000] [--kick 1.0]

Steps:
1. Reduce the mesh to --tris triangles (keeps the texture mapping) and
   shrink textures (color 2048, normal/roughness/metal 1024, JPEG).
2. Turn it so the muzzle points forward (--muzzle: which side of the source
   model the muzzle is on: +x -x +y -y +z -z, in glTF axes, Y up), scale it
   to --length meters long, and center it.
3. Add a one-bone rig and the animations the game plays (view_model.gd):
       draw   0.35 s  swings up into view
       idle   2 s     slow breathing sway (loops)
       fire   0.4 s   kick back and up (scaled by --kick)
Blender works Z-up with +Y forward; the exporter turns that into Godot's -Z
forward.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

FPS = 60


def arg(name, default=None, cast=str):
    if "--" + name in sys.argv:
        return cast(sys.argv[sys.argv.index("--" + name) + 1])
    return default


SRC = arg("src")
OUT = arg("out")
MUZZLE = arg("muzzle", "-x")
LENGTH = arg("length", 0.85, float)
TRIS = arg("tris", 20000, int)
KICK = arg("kick", 1.0, float)

# glTF axis -> Blender axis (Blender X = X, Y = -Z, Z = Y).
GLTF_TO_BLENDER = {"+x": Vector((1, 0, 0)), "-x": Vector((-1, 0, 0)), "+y": Vector((0, 0, 1)),
                   "-y": Vector((0, 0, -1)), "+z": Vector((0, -1, 0)), "-z": Vector((0, 1, 0))}


def load():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.ops.import_scene.gltf(filepath=SRC)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    o = bpy.context.active_object
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for x in list(bpy.data.objects):
        if x != o:
            bpy.data.objects.remove(x)
    o.name = "Weapon"
    return o


def reduce(o):
    o.data.calc_loop_triangles()
    tris = len(o.data.loop_triangles)
    if tris > TRIS:
        m = o.modifiers.new("Decimate", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = TRIS / tris
        m.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier="Decimate")
    o.data.calc_loop_triangles()
    print("triangles:", tris, "->", len(o.data.loop_triangles))
    for img in bpy.data.images:
        size = 2048 if img.colorspace_settings.name == "sRGB" else 1024
        if img.size[0] > size:
            img.scale(size, size)


def orient(o):
    muzzle = GLTF_TO_BLENDER[MUZZLE]
    rot = muzzle.rotation_difference(Vector((0, 1, 0))).to_matrix().to_4x4()
    o.data.transform(rot)
    o.data.update()
    vs = [v.co for v in o.data.vertices]   # Measure the real vertices, after turning.
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    s = LENGTH / (mx.y - mn.y)
    center = (mn + mx) / 2
    o.data.transform(Matrix.Scale(s, 4) @ Matrix.Translation(-center))
    o.data.update()
    print("scaled x%.3f to %.2f m long; size %s (x wide, y long, z tall)" % (s, LENGTH, tuple(round(v * s, 3) for v in (mx - mn))))


def rig(o):
    bpy.ops.object.armature_add(location=(0, 0, 0))
    arm = bpy.context.active_object
    arm.name = "WeaponRig"
    bpy.ops.object.mode_set(mode="EDIT")
    b = arm.data.edit_bones[0]
    b.name = "weapon"
    b.head = (0, 0, 0)
    b.tail = (0, 0.1, 0)
    b.roll = 0
    bpy.ops.object.mode_set(mode="OBJECT")
    vg = o.vertex_groups.new(name="weapon")
    vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
    o.parent = arm
    mod = o.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    return arm


def action(arm, name, keys):
    """keys: [(time_s, loc, rot_deg)] for the weapon bone (X right, Y fwd, Z up)."""
    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = act
    pb = arm.pose.bones["weapon"]
    pb.rotation_mode = "XYZ"
    for t, loc, rot in keys:
        pb.location = loc
        pb.rotation_euler = [math.radians(a) for a in rot]
        pb.keyframe_insert("location", frame=round(t * FPS))
        pb.keyframe_insert("rotation_euler", frame=round(t * FPS))
    act.use_fake_user = True
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, act)
    track.mute = True
    arm.animation_data.action = None


def animate(arm):
    Z = (0, 0, 0)
    k = KICK
    action(arm, "idle", [(0.0, Z, Z), (1.0, (0.0015, 0, 0.004), (0.6, 0, 0.3)), (2.0, Z, Z)])
    action(arm, "draw", [(0.0, (0.0, -0.08, -0.22), (-35, 0, 8)), (0.22, (0, 0.006, 0.006), (3, 0, -1)),
                         (0.35, Z, Z)])
    action(arm, "fire", [(0.0, Z, Z), (0.035, (0, -0.07 * k, 0.012 * k), (8 * k, 0, 1.2 * k)),
                         (0.16, (0, -0.012 * k, 0.002 * k), (1.5 * k, 0, 0)), (0.4, Z, Z)])


def export():
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True, export_yup=True,
                              export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_force_sampling=True, export_image_format="JPEG",
                              export_jpeg_quality=90)
    print("exported", OUT, os.path.getsize(OUT) // 1024, "KB")


if __name__ == "__main__":
    o = load()
    reduce(o)
    orient(o)
    animate(rig(o))
    export()
