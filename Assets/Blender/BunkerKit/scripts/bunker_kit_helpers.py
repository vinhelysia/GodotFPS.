"""Shared helpers for modular bunker structural kit (Vinh low-poly style)."""
import bpy
import bmesh
from mathutils import Vector
from math import radians, sin, cos, pi

BEVEL_W = 0.01

MAT_DEFS = {
    "MAT_Concrete_Dry": ((0.22, 0.21, 0.19, 1.0), 0.85, 0.0),
    "MAT_Concrete_Dark": ((0.12, 0.115, 0.11, 1.0), 0.88, 0.0),
    "MAT_Concrete_Inner": ((0.08, 0.07, 0.065, 1.0), 0.9, 0.0),
    "MAT_Concrete_Wet": ((0.09, 0.095, 0.1, 1.0), 0.45, 0.0),
    "MAT_Metal_Dark": ((0.03, 0.03, 0.032, 1.0), 0.7, 0.15),
    "MAT_Metal_Rusted": ((0.12, 0.055, 0.03, 1.0), 0.85, 0.1),
    "MAT_Metal_Painted": ((0.05, 0.08, 0.06, 1.0), 0.65, 0.05),
    "MAT_Rubber_Dark": ((0.015, 0.015, 0.015, 1.0), 0.95, 0.0),
}


def ensure_collections():
    scene = bpy.context.scene

    def ensure(name, parent=None):
        col = bpy.data.collections.get(name)
        if col is None:
            col = bpy.data.collections.new(name)
            if parent is None:
                if name not in [c.name for c in scene.collection.children]:
                    scene.collection.children.link(col)
            else:
                if name not in [c.name for c in parent.children]:
                    parent.children.link(col)
        return col

    kit = ensure("COL_BunkerKit")
    # link kit under scene if unlinked
    if kit.name not in [c.name for c in scene.collection.children]:
        try:
            scene.collection.children.link(kit)
        except RuntimeError:
            pass
    return {
        "kit": kit,
        "structures": ensure("COL_Structures", kit),
        "interactive": ensure("COL_Interactive", kit),
        "collision": ensure("COL_Collision", kit),
        "previews": ensure("COL_Previews", kit),
    }


def make_materials():
    created = []
    for name, (base, rough, metal) in MAT_DEFS.items():
        mat = bpy.data.materials.get(name)
        if mat is None:
            mat = bpy.data.materials.new(name)
            created.append(name)
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        links = mat.node_tree.links
        nodes.clear()
        out = nodes.new("ShaderNodeOutputMaterial")
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.inputs["Base Color"].default_value = base
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return created


def mat(name):
    return bpy.data.materials.get(name)


def link_obj(obj, col_name):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    col = bpy.data.collections.get(col_name)
    if col is None:
        col = bpy.data.collections.new(col_name)
        bpy.context.scene.collection.children.link(col)
    if obj.name not in col.objects:
        col.objects.link(obj)
    return obj


def remove_if_exists(name):
    obj = bpy.data.objects.get(name)
    if not obj:
        return
    mesh = obj.data if obj.type == "MESH" else None
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh is not None and mesh.users == 0:
        bpy.data.meshes.remove(mesh)


def flat_shade(obj):
    if obj is None or obj.type != "MESH":
        return
    for p in obj.data.polygons:
        p.use_smooth = False
    if hasattr(obj.data, "use_auto_smooth"):
        obj.data.use_auto_smooth = False


def select_only(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_tf(obj):
    select_only(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def tri_count(obj):
    if obj is None or obj.type != "MESH":
        return 0
    me = obj.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def add_bevel(obj, width=BEVEL_W, segments=1, angle=30):
    for m in list(obj.modifiers):
        if m.name.startswith("VinhBevel"):
            obj.modifiers.remove(m)
    bev = obj.modifiers.new("VinhBevel", "BEVEL")
    bev.width = width
    bev.segments = segments
    bev.limit_method = "ANGLE"
    bev.angle_limit = radians(angle)
    bev.miter_outer = "MITER_SHARP"
    return bev


def apply_modifiers(obj):
    select_only(obj)
    for m in list(obj.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except Exception as e:
            print("modifier apply fail", m.name, e)


def box_from_corners(name, xmin, ymin, zmin, xmax, ymax, zmax, mat_name, col_name="COL_Structures"):
    remove_if_exists(name)
    sx = max(xmax - xmin, 1e-6)
    sy = max(ymax - ymin, 1e-6)
    sz = max(zmax - zmin, 1e-6)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    obj = bpy.data.objects.new(name, mesh)
    link_obj(obj, col_name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector((sx, sy, sz)), verts=bm.verts)
    bmesh.ops.translate(
        bm,
        vec=Vector((xmin + sx * 0.5, ymin + sy * 0.5, zmin + sz * 0.5)),
        verts=bm.verts,
    )
    bm.to_mesh(mesh)
    bm.free()
    m = mat(mat_name)
    if m:
        mesh.materials.append(m)
    flat_shade(obj)
    return obj


def cylinder_n(
    name,
    radius,
    depth,
    sides,
    location,
    rotation_euler,
    mat_name,
    col_name="COL_Structures",
):
    remove_if_exists(name)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    obj = bpy.data.objects.new(name, mesh)
    link_obj(obj, col_name)
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=sides,
        radius1=radius,
        radius2=radius,
        depth=depth,
    )
    bm.to_mesh(mesh)
    bm.free()
    obj.location = location
    obj.rotation_euler = rotation_euler
    m = mat(mat_name)
    if m:
        mesh.materials.append(m)
    flat_shade(obj)
    select_only(obj)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    flat_shade(obj)
    return obj


def join_parts(final_name, part_names, origin_world=(0, 0, 0), col_name="COL_Structures", bevel=True, bevel_w=BEVEL_W):
    objs = [bpy.data.objects.get(n) for n in part_names]
    objs = [o for o in objs if o is not None]
    if not objs:
        return None
    # apply transforms on each
    for o in objs:
        select_only(o)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = final_name
    if joined.data:
        joined.data.name = final_name + "_Mesh"
    select_only(joined)
    bpy.context.scene.cursor.location = Vector(origin_world)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    joined.location = (0.0, 0.0, 0.0)
    joined.rotation_euler = (0.0, 0.0, 0.0)
    joined.scale = (1.0, 1.0, 1.0)
    link_obj(joined, col_name)
    if bevel:
        add_bevel(joined, width=bevel_w)
        apply_modifiers(joined)
    flat_shade(joined)
    apply_tf(joined)
    flat_shade(joined)
    return joined


def set_origin_zero(obj, origin_world=(0, 0, 0)):
    select_only(obj)
    bpy.context.scene.cursor.location = Vector(origin_world)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    obj.location = (0, 0, 0)
    obj.rotation_euler = (0, 0, 0)
    obj.scale = (1, 1, 1)
    apply_tf(obj)
    flat_shade(obj)


def make_collision_box(name, size, location_offset=(0, 0, 0), origin=(0, 0, 0)):
    """size = (sx,sy,sz), geometry centered on location_offset then origin set."""
    remove_if_exists(name)
    sx, sy, sz = size
    ox, oy, oz = location_offset
    xmin, xmax = ox - sx * 0.5, ox + sx * 0.5
    ymin, ymax = oy - sy * 0.5, oy + sy * 0.5
    zmin, zmax = oz - sz * 0.5, oz + sz * 0.5
    obj = box_from_corners(name, xmin, ymin, zmin, xmax, ymax, zmax, "MAT_Concrete_Dark", "COL_Collision")
    obj.display_type = "WIRE"
    obj.hide_render = True
    set_origin_zero(obj, origin)
    return obj


def make_collision_from_bounds(name, xmin, ymin, zmin, xmax, ymax, zmax, origin=(0, 0, 0)):
    remove_if_exists(name)
    obj = box_from_corners(name, xmin, ymin, zmin, xmax, ymax, zmax, "MAT_Concrete_Dark", "COL_Collision")
    obj.display_type = "WIRE"
    obj.hide_render = True
    set_origin_zero(obj, origin)
    return obj


def bolt(name, x, y, z, r=0.025, h=0.03, mat_name="MAT_Metal_Dark", sides=8, col="COL_Structures"):
    return cylinder_n(name, r, h, sides, (x, y, z), (radians(90), 0, 0), mat_name, col)


def dims(obj):
    if not obj:
        return None
    return [round(v, 4) for v in obj.dimensions]
