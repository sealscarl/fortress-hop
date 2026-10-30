"""Turns a generated grenade model (Meshy etc.) into the game's grenade.

    python tools/models/prepare_grenade.py --src hand_grenade.glb --out grenades/models/frag.glb \
        [--radius 0.12] [--tris 4000]

The game's grenade collision is always a sphere (grenades/grenade.gd), so the
model is fitted to it: the round body is centered on the sphere and scaled to
its radius. A pin, spoon or other part that sticks out is ignored when
fitting, and only shows (it never changes how the grenade bounces).

The body is measured as the widest horizontal extent of the model (the pin
and spoon stick out up top, so they don't widen it); its center is that
width's middle sideways, and half a width up from the bottom.
Reduces the mesh to --tris triangles and textures to 1K (JPEG).
"""
import os
import sys

import bpy
from mathutils import Matrix, Vector


def arg(name, default=None, cast=str):
    if "--" + name in sys.argv:
        return cast(sys.argv[sys.argv.index("--" + name) + 1])
    return default


SRC = arg("src")
OUT = arg("out")
RADIUS = arg("radius", 0.12, float)
TRIS = arg("tris", 4000, int)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
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
    o.name = "Grenade"

    o.data.calc_loop_triangles()
    tris = len(o.data.loop_triangles)
    if tris > TRIS:
        m = o.modifiers.new("Decimate", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = TRIS / tris
        m.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier="Decimate")
    o.data.calc_loop_triangles()
    print("triangles:", tris, "->", len(o.data.loop_triangles))
    for img in bpy.data.images:
        if img.size[0] > 1024:
            img.scale(1024, 1024)

    vs = [v.co for v in o.data.vertices]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    # Body: the lower, round part. Its width is measured in the bottom half
    # (above that, a spoon or pin may stick out sideways).
    low = [v for v in vs if v.z < mn.z + (mx.z - mn.z) * 0.5]
    lx = (min(v.x for v in low), max(v.x for v in low))
    ly = (min(v.y for v in low), max(v.y for v in low))
    width = max(lx[1] - lx[0], ly[1] - ly[0])
    center = Vector(((lx[0] + lx[1]) / 2, (ly[0] + ly[1]) / 2, mn.z + width / 2))
    s = RADIUS / (width / 2)
    o.data.transform(Matrix.Scale(s, 4) @ Matrix.Translation(-center))
    o.data.update()
    print("body %.3f wide, centered at %s; scaled x%.3f; overall %s m" % (
        width, tuple(round(c, 3) for c in center), s, tuple(round(c * s, 3) for c in (mx - mn))))

    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True,
                              export_image_format="JPEG", export_jpeg_quality=90)
    print("exported", OUT, os.path.getsize(OUT) // 1024, "KB")


if __name__ == "__main__":
    main()
