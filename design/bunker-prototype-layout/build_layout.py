"""Build an editable, measured plan from the read-only Godot resource snapshot."""
from collections import defaultdict
from html import escape
import hashlib
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
SOURCE = PROJECT / "Scene/Hideout/bunker_prototype_16x20.tscn"
EXPECTED_HASH = "e3125ac5c52762ba6f1cfa3e9a85b753a65074e1203b5dcb5e72dc61a49955c3"
snapshot = json.loads((HERE / "scene-snapshot.json").read_text(encoding="utf-8"))
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == EXPECTED_HASH, "Source scene changed since task start"
assert not snapshot["warnings"], snapshot["warnings"]


def hull(points):
    points = sorted(set(tuple(round(v, 5) for v in p) for p in points))
    if len(points) < 3:
        return [list(p) for p in points]
    def cross(a, b, c):
        return (b[0]-a[0])*(c[1]-a[1]) - (b[1]-a[1])*(c[0]-a[0])
    halves = []
    for ordered in (points, points[::-1]):
        chain = []
        for p in ordered:
            while len(chain) > 1 and cross(chain[-2], chain[-1], p) <= 1e-9:
                chain.pop()
            chain.append(p)
        halves.append(chain[:-1])
    return [list(p) for p in halves[0]+halves[1]]


def loops(segments):
    """Trace closed triangle-plane sections, retaining real doorway gaps."""
    edges = set()
    adjacency = defaultdict(set)
    for a, b in segments:
        a, b = tuple(round(v, 5) for v in a), tuple(round(v, 5) for v in b)
        if a != b:
            edges.add(tuple(sorted((a, b))))
            adjacency[a].add(b)
            adjacency[b].add(a)
    assert all(len(v) == 2 for v in adjacency.values()), "Non-manifold section; do not invent a filled wall"
    polygons = []
    while edges:
        first = min(edges)
        edges.remove(first)
        start, current = first
        previous = start
        chain = [start, current]
        while current != start:
            nxt = next(p for p in adjacency[current] if p != previous)
            edge = tuple(sorted((current, nxt)))
            assert edge in edges, "Section loop did not close"
            edges.remove(edge)
            previous, current = current, nxt
            chain.append(current)
        polygons.append(hull(chain[:-1]))
        # These kit sections are convex rectangles; verify before convexifying.
        area = lambda p: abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(p,p[1:]+p[:1]))/2)
        assert abs(area(chain[:-1])-area(polygons[-1])) < 1e-5, "Non-convex section requires preserving its contour"
    return polygons


def bounds(rows):
    return {k: [round(f(r["world_bounds"][k][i] for r in rows), 5) for i in range(3)]
            for k, f in (("min", min), ("max", max))}


def plan_bounds(polygons):
    pts = [p for polygon in polygons for p in polygon]
    return [min(p[0] for p in pts), min(p[1] for p in pts), max(p[0] for p in pts), max(p[1] for p in pts)]


def belongs(row, path):
    return row["path"] == path or row["path"].startswith(path+"/")


def active(row):
    return not row["disabled"] and not row["removed_by_disabled_ancestor"] and bool(row["collision_layer"] & 1)


def measurement_id(path):
    return path.replace("/", "--").replace("@", "_")


floor = [r for r in snapshot["meshes"] if r["path"].startswith("Architecture/floor")]
wall_collisions = [r for r in snapshot["collisions"] if r["path"].startswith("Architecture/wall") and active(r)]
wall_visuals = [r for r in snapshot["meshes"] if r["path"].startswith("Architecture/wall")]
architecture = []
for row in snapshot["meshes"]:
    if row["path"].startswith(("Architecture/wall", "Architecture/column", "Architecture/door_frame")):
        if not row["world_bounds"]["min"][1] < 1.0 < row["world_bounds"]["max"][1]:
            continue
        sections = loops(row.get("section_y1_segments", []))
        assert sections, "Missing architectural section: "+row["path"]
        architecture.append({"id":measurement_id(row["path"]), "node_path":row["path"], "section_y_m":1.0, "polygons_xz_m":sections})

room_specs = [
    ("R1", "COMMON", "Terminal / khu chung", [-8,-4,0,0], [-8,-4,-.2,0], (-4,-2.4)),
    ("R2", "ARMORY", "Lockers / sáu stash", [-8,-12,0,-4], [-8,-12,-.2,-4.2], (-3.65,-8.5)),
    ("R3", "WORKSHOP", "Workbench / dụng cụ", [-8,-20,0,-12], [-8,-20,-.2,-12.2], (-3.6,-15.3)),
    ("R4", "MEDBAY", "Medical / storage", [4,-4,8,0], [4.2,-4,8,0], (6.0,-2.65)),
    ("R5", "PROVISIONS", "Shelf / food / pallet", [4,-12,8,-4], [4.2,-12,8,-4.2], (6.0,-5.45)),
    ("R6", "SERVICE", "Generator / filter", [4,-20,8,-12], [4.2,-20,8,-12.2], (6.25,-14.3)),
    ("R7", "CORRIDOR", "Trục kết nối phòng", [0,-20,4,0], [0,-20,4,0], (2,-10.5)),
]
rooms = [{"id":i,"name":name,"function":purpose,"grid_envelope_xz_m":grid,"clear_wall_envelope_xz_m":clear,
          "clear_wall_width_m":round(clear[2]-clear[0],3),"clear_wall_depth_m":round(clear[3]-clear[1],3),
          "excludes_columns_furniture_and_door_sweeps":True} for i,name,purpose,grid,clear,label in room_specs]

# IDs are editorial keys. Paths, poses, and footprints come from the scene snapshot.
prop_specs = [
    ("P01","Terminal","Props/Table/Terminal"), ("P02","Terminal table","Props/Table"),
    ("P03","Stove","Dressing/barrel_stove__001"),
    ("P04","Armory workbench","Dressing/workbench__002"),
    ("P05","Med worktop","Dressing/workbench__003"), ("P06","Med shelf","Dressing/shelf__001"),
    ("P07","Med steel storage","Dressing/compact_steel_container__001"),
    ("P08","Provisions shelf","Dressing/shelf__002"), ("P09","Wood chest","Dressing/reinforced_wood_chest__001"),
    ("P10","Pallet + stacked crates","Dressing/wood_pallet__001"),
    ("P11","Workshop workbench","Dressing/workbench__004"), ("P12","Anvil / stump","Dressing/anvil_stump__001"),
    ("P13","Jerrycan","Dressing/fuel_jerrycan__001"), ("P14","Handcart","Dressing/salvage_handcart__001"),
    ("P15","Steel + olive stack","Dressing/compact_steel_container__002"),
    ("P16","Service console (deco)","Dressing/control_console__001"),
    ("P17","Generator","Dressing/portable_generator__001"), ("P18","Water filter","Dressing/improvised_water_filter__001"),
    ("P19","Rubble","Dressing/rubble_cluster__001"),
]
for num, kind in enumerate(["gun_locker","mesh_gun_locker","simple_gun_locker","steel_locker"]):
    for instance in (1,2):
        prop_specs.append((f"L{num*2+instance:02}",kind.replace("_"," "),f"Dressing/{kind}__{instance:03}"))
for letter in "ABCDEF":
    prop_specs.append((f"S{letter}",f"Stash {letter}",f"StashCrate_{letter}"))

all_props = []
for pid, label, path in prop_specs:
    meshes = [r for r in snapshot["meshes"] if belongs(r,path) and r["visible"]]
    if path == "Props/Table":
        meshes = [r for r in meshes if not belongs(r,"Props/Table/Terminal")]
    collisions = [r for r in snapshot["collisions"] if belongs(r,path) and active(r)]
    if path == "Props/Table":
        collisions = [r for r in collisions if not belongs(r,"Props/Table/Terminal")]
    assert meshes, path
    polygons = [hull(r["projection_points"]) for r in meshes]
    collision_polygons = [hull(r["projection_points"]) for r in collisions]
    envelope = hull([p for polygon in polygons for p in polygon])
    bbox = plan_bounds(polygons)
    all_props.append({"id":pid,"label":label,"node_paths":[path],"visual_world_bounds_m":bounds(meshes),
        "visual_envelope_xz_m":envelope,"visual_parts_xz_m":polygons,
        "collision_parts_xz_m":collision_polygons,"visual_plan_bounds_xz_m":bbox,
        "plan_width_m":round(bbox[2]-bbox[0],5),"plan_depth_m":round(bbox[3]-bbox[1],5),
        "method":"transformed local mesh AABB corners; conservative visual projection; fitted/triangle collision point hulls"})

group_specs = [
    ("G1","Cases + 4 ammo types",[p["path"] for p in snapshot["placements"] if p["path"].startswith("Dressing/") and any(s in p["path"] for s in ["weapon_case__","pistol_case__","magazine_case__","ammo_"])]),
    ("G2","Medical box + water",["Dressing/medical_box__001","Dressing/water_bottle__001"]),
    ("G3","Food / drinks / salt",[p["path"] for p in snapshot["placements"] if p["path"].startswith("Dressing/") and any(s in p["path"] for s in ["canned_","coffee_","tea_","ration_","salt_","kalo_","water_bottle__00"]) and p["path"] != "Dressing/water_bottle__001"]),
    ("G4","Pallet cargo",["Dressing/wood_crate__007","Dressing/wood_crate__008"]),
    ("G5","Toolbox",["Dressing/metal_toolbox__001"]), ("G6","Olive upper box",["Dressing/olive_storage_box__001"]),
]
groups = []
for gid, label, paths in group_specs:
    rows = [r for r in snapshot["meshes"] if r["visible"] and any(belongs(r,p) for p in paths)]
    hidden_paths = [p for p in paths if not any(belongs(r,p) for r in rows)]
    groups.append({"id":gid,"label":label,"node_paths":paths,"member_count":len(paths),
        "visible_member_count":len(paths)-len(hidden_paths),"hidden_node_paths":hidden_paths,
        "visual_parts_xz_m":[hull(r["projection_points"]) for r in rows],"world_bounds_m":bounds(rows)})

doors = []
for anim in snapshot["door_animations"]:
    if anim["name"] != "door_open":
        continue
    root_path = anim["player_path"].split("/Model/")[0]
    hermetic = "hermetic" in root_path
    number = 7 if hermetic else int(root_path[-3:])
    mesh = next(r for r in snapshot["meshes"] if belongs(r,root_path) and r["path"].endswith("/HermeticLeaf" if hermetic else "/door_leaf"))
    pivot_track = next(t for t in anim["tracks"] if t["path"].endswith("/LeafPivot"))
    q = pivot_track["keys"][-1]["value"]
    angle = 2*math.atan2(q[1],q[3])
    origin, basis = mesh["origin"], mesh["basis"]
    local_min, local_max = mesh["local_aabb"]["min"], mesh["local_aabb"]["max"]
    def rotate_point(x, yaw):
        return [origin[i]+basis[0][i]*x*math.cos(yaw)-basis[2][i]*x*math.sin(yaw) for i in (0,2)]
    ends = (local_min[0],local_max[0]) if hermetic else (local_max[0],)
    arcs = [[rotate_point(x,angle*n/40) for n in range(41)] for x in ends]
    leaf_ends = (local_min[0],local_max[0]) if hermetic else (0,local_max[0])
    closed = [rotate_point(x,0) for x in leaf_ends]
    opened = [rotate_point(x,angle) for x in leaf_ends]
    frame_path = root_path if hermetic else f"Architecture/door_frame__{number:03}"
    frame_rows = [r for r in snapshot["collisions"] if belongs(r,frame_path) and active(r) and "/LeafPivot/" not in r["path"]]
    frame_parts = []
    for row in frame_rows:
        frame_parts += loops(row.get("section_y1_segments",[]))
    assert len(frame_parts) == 2, (root_path,"Expected two frame jamb sections",len(frame_parts))
    axis = 0 if hermetic else 1
    ranges = sorted((min(p[axis] for p in poly),max(p[axis] for p in poly)) for poly in frame_parts)
    clear_width = ranges[1][0]-ranges[0][1]
    rough_path = "Architecture/wall_doorway_4m__001" if hermetic else f"Architecture/wall_doorway_4m__{number+1:03}"
    rough_parts = loops(next(r for r in wall_collisions if belongs(r,rough_path))["section_y1_segments"])
    rough_ranges = sorted((min(p[axis] for p in poly),max(p[axis] for p in poly)) for poly in rough_parts)
    rough_width = rough_ranges[1][0]-rough_ranges[0][1]
    doors.append({"id":f"D{number:02}","node_path":root_path,"authored_pose":"closed",
        "pivot_xz_m":[origin[0],origin[2]],"pivot_type":"central" if hermetic else "edge hinge",
        "angle_local_y_degrees":round(math.degrees(angle),3),"animation_length_seconds":anim["length"],
        "animation_path":anim["player_path"],"track_path":pivot_track["path"],"closed_line_xz_m":closed,
        "open_line_xz_m":opened,"sweep_arcs_xz_m":arcs,"frame_clear_width_at_y1_m":round(clear_width,5),
        "wall_rough_opening_width_at_y1_m":round(rough_width,5),
        "closed_visual_parts_xz_m":[hull(r["projection_points"]) for r in snapshot["meshes"] if belongs(r,root_path)],
        "closed_collision_parts_xz_m":[hull(r["projection_points"]) for r in snapshot["collisions"] if belongs(r,root_path) and active(r)]})
doors.sort(key=lambda d:d["id"])

lookup = {p["id"]:p for p in all_props}
measurements = [
    {"id":"M1","label":"Floor rectangle","width_m":16.0,"depth_m":20.0,"basis":"measured native floor bounds"},
    {"id":"M2","label":"Outer shell","width_m":16.4,"depth_m":20.4,"basis":"wall collision and visual bounds, rounding to mm"},
    {"id":"M3","label":"Corridor clear width","value_m":4.0,"basis":"inner faces X=0 and X=4; no player-radius deduction"},
]
wood_bounds, steel_bounds = lookup["SA"]["visual_plan_bounds_xz_m"],lookup["SB"]["visual_plan_bounds_xz_m"]
row_a = lookup["SB"]["visual_plan_bounds_xz_m"]
row_b = lookup["SE"]["visual_plan_bounds_xz_m"]
stash_gap = row_a[1]-row_b[3]
locker_east = max(p["visual_plan_bounds_xz_m"][2] for p in all_props if p["id"].startswith("L"))
west_aisle = wood_bounds[0]-locker_east
measurements += [{"id":"M4","label":"Stash row gap (steel visual extremes)","value_m":round(stash_gap,5),"basis":"visual projection, excludes player radius"},
                 {"id":"M5","label":"West locker/stash gap","value_m":round(west_aisle,5),"basis":"most easterly locker visual extent to first wood stash western edge"}]

resource_paths = sorted(set([snapshot["source"]]+[p["resource"] for p in snapshot["placements"]]+[r["source"] for r in snapshot["meshes"]+snapshot["collisions"]]))
hashes = {p:hashlib.sha256((PROJECT/p.removeprefix("res://")).read_bytes()).hexdigest() for p in resource_paths}
data = {"source_scene":snapshot["source"],"source_sha256_before":EXPECTED_HASH,"source_sha256_after":hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    "created_local_date":"2026-10-08","coordinates":{"units":"metres","north":"-Z","east":"+X","south":"+Z","world_origin_xz_m":[0,0]},
    "extraction_method":snapshot["method"]+"; CACHE_MODE_IGNORE_DEEP; no open/save/play/stop/reimport/bake/settings operations",
    "floor_bounds_m":bounds(floor),"wall_collision_bounds_m":bounds(wall_collisions),"wall_visual_bounds_m":bounds(wall_visuals),
    "architectural_section_height_m":1.0,"rooms":rooms,"architecture":architecture,"props":all_props,"small_prop_groups":groups,"doors":doors,"measurements":measurements,
    "resource_sha256":hashes,"placements":snapshot["placements"],
    "uncertainties":["Furniture uses transformed mesh AABB projection, not exact silhouette or standing-height walkability.",
        "Collision polygons are resource projections; no runtime physics, navmesh, traversal, interaction or saved door state was tested.",
        "Room function labels follow documented zones; clear wall envelopes do not subtract columns or furniture.",
        "Historical Common bench is absent from current scene resource geometry; no bench was added.",
        "Ceilings, overhead beams/ducts/cable trays/lights and player mesh are hidden in the plan for legibility; raw resource geometry remains in scene-snapshot.json."]}

# Editable SVG uses native polygons, lines and text; 62 drawing pixels per metre.
W,H,S,OX,OZ = 1860,1850,62,656,1540
INK = "#24333d"
svg = [f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" width="{W}" height="{H}" viewBox="0 0 {W} {H}">']
svg += ['<title>Bunker prototype — measured top-down layout</title>', '<desc>Read-only scene-resource snapshot. North is -Z; dimensions in metres. All text and vector objects are editable.</desc>',
        '<defs><pattern id="metre-grid" width="62" height="62" patternUnits="userSpaceOnUse" x="160" y="300"><path d="M62 0H0V62" fill="none" stroke="#ccd7dd" stroke-width=".7"/></pattern><marker id="arrow" markerWidth="6" markerHeight="6" refX="5" refY="3" orient="auto"><path d="M0 0L6 3L0 6" fill="none" stroke="#af7549" stroke-width="1"/></marker></defs>',
        '<style>text{font-family:Arial,sans-serif;fill:#24333d} .small{font-size:17px} .muted{fill:#60737f} .id{font-size:15px;font-weight:bold} .room{font-size:25px;font-weight:bold;letter-spacing:1px} .dim{font-size:17px;fill:#526873} .prop{fill:#c5d4d8;stroke:#7f969f;stroke-width:1.1} .collision{fill:none;stroke:#4393a5;stroke-width:1.2;stroke-dasharray:4 3} .sweep{fill:none;stroke:#af7549;stroke-width:1.4;stroke-dasharray:5 4} .leader{fill:none;stroke:#70838d;stroke-width:1}</style>',f'<rect width="{W}" height="{H}" fill="#f7f9f9"/>']
labels = []


def xy(x,z): return (OX+x*S,OZ+z*S)
def points(poly): return " ".join(f"{xy(x,z)[0]:.3f},{xy(x,z)[1]:.3f}" for x,z in poly)
def text_px(x,y,value,size=17,anchor="start",fill=INK,weight="normal",extra=""):
    svg.append(f'<text x="{x:.3f}" y="{y:.3f}" font-size="{size}" text-anchor="{anchor}" fill="{fill}" font-weight="{weight}" {extra}>{escape(value)}</text>')
def text_world(x,z,value,**kw): text_px(*xy(x,z),value,**kw)
def layer(name): svg.append(f'<g inkscape:groupmode="layer" inkscape:label="{name}" id="{name.replace(" ","-")}">')
def polygon(poly,cls="",fill=None,stroke=None,extra=""):
    if len(poly) >= 3:
        svg.append(f'<polygon points="{points(poly)}" class="{cls}" {f"fill={chr(34)}{fill}{chr(34)}" if fill else ""} {f"stroke={chr(34)}{stroke}{chr(34)}" if stroke else ""} {extra}/>')
def line(a,b,stroke="#70838d",width=1,extra=""):
    x1,y1=xy(*a);x2,y2=xy(*b)
    svg.append(f'<line x1="{x1:.3f}" y1="{y1:.3f}" x2="{x2:.3f}" y2="{y2:.3f}" stroke="{stroke}" stroke-width="{width}" {extra}/>')
def dim(a,b,label,offset=0,vertical=False):
    if vertical:
        aa,bb=(a[0]+offset,a[1]),(b[0]+offset,b[1])
    else:
        aa,bb=(a[0],a[1]+offset),(b[0],b[1]+offset)
    line(a,aa,"#a5b4bc",.8);line(b,bb,"#a5b4bc",.8);line(aa,bb,"#758c99",1)
    for p in (aa,bb): line((p[0]-.06,p[1]-.06),(p[0]+.06,p[1]+.06),"#758c99",1.2)
    mid=((aa[0]+bb[0])/2,(aa[1]+bb[1])/2)
    px,py=xy(*mid)
    if vertical and abs(a[1]-b[1]) > 2:
        px += -13 if offset <= 0 else 19
        text_px(px,py,label,17,"middle",fill="#526873",extra=f'transform="rotate(-90 {px} {py})"')
    elif vertical:
        text_px(px-7,py-7,label,17,"end",fill="#526873")
    else:
        text_px(px,py-7,label,17,"middle",fill="#526873")
def badge(pid,x,z):
    px,py=xy(x,z)
    bw=31 if len(pid)==2 else 38
    svg.append(f'<rect x="{px-bw/2:.2f}" y="{py-11:.2f}" width="{bw}" height="22" rx="4" fill="#f7f9f9" fill-opacity=".93" stroke="#bac8cf" stroke-width=".7"/>')
    text_px(px,py+5,pid,14,"middle",weight="bold")
    labels.append({"id":pid,"bbox_px":[px-bw/2,py-11,px+bw/2,py+11]})

layer("Header")
text_px(80,76,"BUNKER PROTOTYPE",37,weight="bold")
text_px(80,113,"Top-down từ scene hiện tại · north = −Z · dimensions = metres · 08.10.2026",20,fill="#60737f")
text_px(80,147,"res://Scene/Hideout/bunker_prototype_16x20.tscn",17,fill="#60737f")
text_px(1770,79,"RESOURCE SNAPSHOT",18,"end",fill="#60737f",weight="bold")
text_px(1770,112,"SVG editable / geometry read-only",17,"end",fill="#60737f")
svg.append('</g>')

layer("Floor and grid")
for row in floor:
    polygon(hull(row["projection_points"]),fill="#edf2f3",stroke="none")
for i,name,purpose,grid,clear,label in room_specs:
    color="#e6eff1" if i=="R7" else "#f0f4f4"
    a,b,c,d=grid
    polygon([[a,b],[c,b],[c,d],[a,d]],fill=color,stroke="none")
svg.append('<rect x="160" y="300" width="992" height="1240" fill="url(#metre-grid)"/>')
for x in range(-8,9,2): text_world(x,-20.65,f"X {x}",size=15,anchor="middle",fill="#6b818d")
for z in range(-20,1,2): text_world(-8.8,z+.08,f"Z {z}",size=15,anchor="end",fill="#6b818d")
svg.append('</g>')

layer("Architectural cut Y1m")
for item in architecture:
    svg.append(f'<g id="{escape(item["id"])}"><title>{escape(item["node_path"])}</title>')
    for poly in item["polygons_xz_m"]:
        polygon(poly,fill="#34424a" if "/door_frame" not in item["node_path"] else "#8b7867",stroke="#34424a",extra='stroke-width=".6"')
    svg.append('</g>')
svg.append('</g>')

layer("Furniture visual projection")
for prop in sorted(all_props,key=lambda p:p["id"] == "P01"):
    svg.append(f'<g id="{prop["id"]}"><title>{escape(prop["label"])} | {escape(prop["node_paths"][0])} | visual AABB projection</title>')
    polygon(prop["visual_envelope_xz_m"],"prop",fill="#b8cbc8" if prop["id"].startswith("S") else "#c5d4d8")
    for poly in prop["visual_parts_xz_m"]:
        polygon(poly,fill="none",stroke="#9ab0b6",extra='stroke-width=".45"')
    svg.append('</g>')
svg.append('</g>')

layer("Small props grouped")
for group in groups:
    svg.append(f'<g id="{group["id"]}"><title>{escape(group["label"])} | {escape("; ".join(group["node_paths"]))}</title>')
    for poly in group["visual_parts_xz_m"]:
        polygon(poly,fill="#bcc5bd",stroke="#8d9f94",extra='stroke-width=".55" fill-opacity=".78"')
    svg.append('</g>')
svg.append('</g>')

layer("Collision projection")
for prop in all_props:
    svg.append(f'<g id="collision-{prop["id"]}"><title>{prop["id"]}: collision resource projection, not runtime walkability</title>')
    for poly in prop["collision_parts_xz_m"]: polygon(poly,"collision")
    svg.append('</g>')
svg.append('</g>')

layer("Closed doors and authored sweeps")
for door in doors:
    svg.append(f'<g id="{door["id"]}"><title>{escape(door["node_path"])} | {door["angle_local_y_degrees"]} degrees local Y | {door["pivot_type"]} | closed authored pose</title>')
    for poly in door["closed_visual_parts_xz_m"]:
        polygon(poly,fill="#bd9470",stroke="#936c49",extra='stroke-width=".7"')
    for poly in door["closed_collision_parts_xz_m"]:
        polygon(poly,"collision")
    line(*door["closed_line_xz_m"],"#8d6241",2.4)
    line(*door["open_line_xz_m"],"#af7549",1.3,extra='stroke-dasharray="5 4"')
    for arc in door["sweep_arcs_xz_m"]:
        svg.append(f'<polyline points="{points(arc)}" class="sweep" marker-end="url(#arrow)"/>')
    px,py=xy(*door["pivot_xz_m"])
    svg.append(f'<circle cx="{px:.3f}" cy="{py:.3f}" r="3.4" fill="#8d6241"/>')
    n=int(door["id"][-2:])
    if n<7:
        text_world(.65 if n<4 else 3.35,door["pivot_xz_m"][1]-.03,door["id"],size=16,anchor="middle",weight="bold",fill="#936c49")
    else: text_world(2,1.12,"D07 · center pivot",size=16,anchor="middle",fill="#936c49")
    svg.append('</g>')
svg.append('</g>')

layer("Room labels and keys")
for i,name,purpose,grid,clear,position in room_specs:
    x,z=position
    if i=="R7":
        text_world(x,z,"R7",size=17,anchor="middle",fill="#718a94")
        text_world(x,z+.48,"CORRIDOR",size=21,anchor="middle",weight="bold")
        text_world(x,z+.9,"4,00 m clear",size=17,anchor="middle",fill="#60737f")
        continue
    text_world(x,z,i,size=16,anchor="middle",fill="#718a94")
    text_world(x,z+.44,name,size=25 if i not in ["R4","R5"] else 22,anchor="middle",weight="bold")
    text_world(x,z+.82,f'{clear[2]-clear[0]:.2f} × {clear[3]-clear[1]:.2f} m',size=17,anchor="middle",fill="#60737f")
positions={"P01":(-5,-.55),"P02":(-3.94,-.58),"P03":(-7.25,-3.15),"P04":(-4.8,-10.75),"P05":(6,-.7),"P06":(7.45,-3.05),"P07":(5.7,-3.35),"P08":(7.45,-8.2),"P09":(5.6,-7.25),"P10":(5.45,-10.5),"P11":(-7.15,-17.15),"P12":(-4.8,-16.4),"P13":(-7.4,-18.25),"P14":(-2,-18.1),"P15":(-5.1,-19.15),"P16":(7.65,-16.1),"P17":(4.69867,-19.62126),"P18":(7.68,-12.6),"P19":(7,-19.1)}
for prop in all_props:
    pid=prop["id"]
    b=prop["visual_plan_bounds_xz_m"]
    if pid.startswith(("L","S")): position=((b[0]+b[2])/2,(b[1]+b[3])/2)
    else: position=positions[pid]
    badge(pid,*position)
for gid,x,z in [("G1",-4.8,-9.65),("G2",6,-1.35),("G3",7.0,-6.05),("G4",5.45,-9.65),("G5",-6.35,-16.6),("G6",-5.1,-18.5)]:
    badge(gid,x,z)
svg.append('</g>')

layer("Dimensions axes and scale")
dim((-8,-20),(8,-20),"16,00 m · floor",-.85)
dim((-8.2,-20.2),(8.2,-20.2),"16,40 m · outer shell",-1.6)
dim((-8,-20),(-8,0),"20,00 m",-1.7,True)
dim((8,-20),(8,0),"20,40 m shell",.93,True)
dim((-8,0),(0,0),"8,00 m grid",1.8)
dim((0,0),(4,0),"4,00 m",1.8)
dim((4,0),(8,0),"4,00 m grid",1.8)
dim((0,-18.8),(4,-18.8),"4,00 m clear")
dim((locker_east,-5.65),(wood_bounds[0],-5.65),f"{west_aisle:.2f} m",-.25)
dim((-2.03,row_b[3]),(-2.03,row_a[1]),f"{stash_gap:.3f} m",0,True)
text_world(0,.42,"O (0,0)",size=15,anchor="middle",fill="#627884")
px,py=xy(0,0)
svg.append(f'<circle cx="{px}" cy="{py}" r="4" fill="#406e80"/>')
line((0,0),(.7,0),"#406e80",1.4);line((0,0),(0,.7),"#406e80",1.4)
text_world(.84,.1,"+X",size=14,fill="#406e80")
text_world(.12,.78,"+Z",size=14,fill="#406e80")
text_px(1188,254,"N",20,"middle",weight="bold")
svg.append('<path d="M1188 265 L1181 286 L1188 282 L1195 286 Z" fill="#24333d"/>')
text_px(1188,307,"−Z",15,"middle",fill="#60737f")
for n in range(5):
    svg.append(f'<rect x="{160+n*62}" y="1710" width="62" height="9" fill="{INK if n%2==0 else "#e5edef"}" stroke="{INK}" stroke-width=".7"/>')
for n in (0,1,2,5): text_px(160+n*62,1744,str(n)+(" m" if n==5 else ""),16,"middle")
text_px(160,1689,"GRID 1 m · 62 px/m trong SVG",17,fill="#60737f")
svg.append('</g>')

layer("Legend and node key")
PX=1260
text_px(PX,215,"CÁCH ĐỌC BẢN VẼ",24,weight="bold")
legend=[("#34424a","Tường / cột: mặt cắt Y = 1 m"),("#c5d4d8","Furniture: visual AABB projection"),("#b8cbc8","SA–SF: sáu stash tương tác"),("#bd9470","Cửa đặc: authored closed pose")]
for n,(color,label) in enumerate(legend):
    y=252+n*31
    svg.append(f'<rect x="{PX}" y="{y-15}" width="22" height="16" fill="{color}"/>')
    text_px(PX+35,y,label,17)
svg.append(f'<path d="M{PX} 379h23" stroke="#4393a5" stroke-width="1.8" stroke-dasharray="4 3"/>')
text_px(PX+35,384,"Nét cyan: collision resource projection",17)
svg.append(f'<path d="M{PX} 410h23" stroke="#af7549" stroke-width="1.8" stroke-dasharray="5 4"/>')
text_px(PX+35,415,"Cung nâu: swing từ animation clip",17)
text_px(PX,457,"ĐO TỪ HIỆN TRẠNG",22,weight="bold")
for n,value in enumerate(["Floor: 16,00 × 20,00 m", "Outer wall shell: 16,40 × 20,40 m", "Corridor: 4,00 m giữa mặt tường", "Doorways: rough 1,40 / frame clear 1,20 m", "D01–D06: +100° local Y / pivot mép", "D07: −100° local Y / pivot giữa lá", f"Giữa hai hàng stash: {stash_gap:.3f} m", f"Lockers → stash phía tây: {west_aisle:.3f} m"]):
    text_px(PX,490+n*29,value,17)
text_px(PX,759,"PROP KEY · paths đầy đủ trong JSON",22,weight="bold")
for n,prop in enumerate(all_props[:19]):
    text_px(PX,790+n*24,prop["id"],16,weight="bold",fill="#526d76")
    text_px(PX+53,790+n*24,prop["label"],16)
text_px(PX,1268,"L01–02 gun / L03–04 mesh lockers",16)
text_px(PX,1294,"L05–06 simple / L07–08 steel lockers",16)
text_px(PX,1320,"SA, SD wood · SB, SE steel · SC, SF olive",16)
text_px(PX,1366,"SMALL PROP GROUPS",21,weight="bold")
for n,g in enumerate(groups):
    count = f"{g['visible_member_count']}/{g['member_count']} visible" if g["hidden_node_paths"] else str(g["member_count"])
    text_px(PX,1397+n*24,g["id"]+"  "+g["label"]+f" ({count})",16)
svg.append('</g>')

layer("Limits and provenance")
svg.append('<path d="M80 1773H1780" stroke="#b9c7cd" stroke-width="1"/>')
text_px(80,1803,"Room sizes là envelope giữa tường; chưa trừ cột/props. Visual bounds bảo thủ; chưa test runtime traversal / navmesh.",17,fill="#60737f")
text_px(80,1828,"D07 giữ đúng center pivot hiện tại. Bench lịch sử không có trong scene snapshot. Scene SHA256 trước/sau không đổi.",17,fill="#60737f")
svg.append('</g></svg>')
svg_text="\n".join(svg)
(HERE/"layout.svg").write_text(svg_text,encoding="utf-8")
ET.fromstring(svg_text)
data["svg"]={"file":"layout.svg","drawing_pixels_per_metre":S,"canvas_px":[W,H],"origin_px":[OX,OZ],"label_badges":labels}
(HERE/"layout-data.json").write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

assert len(doors)==7 and len([p for p in all_props if p["id"].startswith("S")])==6
assert len([p for p in all_props if p["id"].startswith("L")])==8
assert bounds(floor)["min"][::2]==[-8,-20] and bounds(floor)["max"][::2]==[8,0]
assert all(abs(d["frame_clear_width_at_y1_m"]-1.2)<.0001 for d in doors)
assert all(abs(d["wall_rough_opening_width_at_y1_m"]-1.4)<.0001 for d in doors)
assert all(abs(abs(d["angle_local_y_degrees"])-100)<.001 for d in doors)
for a_i,a in enumerate(labels):
    for b in labels[a_i+1:]:
        x0,y0,x1,y1=a["bbox_px"]; xx0,yy0,xx1,yy1=b["bbox_px"]
        assert min(x1,xx1)<=max(x0,xx0) or min(y1,yy1)<=max(y0,yy0), f"Overlapping ID labels: {a['id']} / {b['id']}"
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==EXPECTED_HASH

brief = f"""BUNKER PROTOTYPE — MEASURED TOP-DOWN LAYOUT (2026-10-08, Asia/Saigon)

Nguồn: {snapshot['source']}
Godot MCP xác nhận nested Cogito project / Godot 4.7 / Forward Plus.
Extraction: SceneState + mesh/Shape3D/Animation resources, CACHE_MODE_IGNORE_DEEP.
Không instantiate Node, open/save scene, play/stop, reimport, bake, settings hay thay editor resource.

SHA256 scene trước và sau: {EXPECTED_HASH}
Floor bounds X -8..8; Y -0.18..0.008; Z -20..0; actual floor 16 x 20 m.
Wall visual/collision shell X -8.2..8.2; Z -20.200001..0.2; rounded 16.400 x 20.400 m.
World origin (X,Z)=(0,0), north=-Z, east=+X, south=+Z. Grid 1 m.
SVG scale 62 drawing px/m; resize-to-fit changes screen scale, not metre labels.

Architecture: native mesh horizontal section at Y=1 m; actual gaps preserved.
Room envelopes được lấy giữa mặt tường: west width 7.8 m / east 3.8 m; common/med 4 m,
armory/workshop/provisions/service 7.8 m. Chưa trừ cột, furniture hoặc swing.
Corridor inner faces X=0..4: 4.00 m. Rough doorway 1.40 m; fixed frame clear 1.20 m at Y1.
D01 common, D02 armory, D03 workshop, D04 medbay, D05 provisions, D06 service, D07 entry.
D01–06 imported clip +100deg local Y, edge pivot, swing vào phòng.
D07 imported clip -100deg local Y, CENTRAL pivot at (2,0); hai đầu lá quét vào/ra shell.
Solid doors show default authored CLOSED poses. Dashed arcs are mathematical clip sweeps,
not a live open-door state or a proposed hinge correction.
Stash steel row visual gap {stash_gap:.5f}m; west locker-to-wood-stash gap {west_aisle:.5f}m.

Visual projection: transformed LOCAL mesh AABB corners, preserving full nested transforms,
rotation and scale. Conservative hull per assembly; not exact triangle silhouette.
Cyan outlines: resource collider projections; disabled imported stash helpers excluded.
Collision projection can differ from visible hardware. Projections do NOT prove walkable
clearance: tabletop supports/overhead parts project into the same plan. No player radius subtracted.
Props small grouped G1–G6. Every furniture/door ID includes exact node paths in layout-data.json
and SVG title elements. Architectural groups retain full node paths. Eight lockers and six
stash models remain at their actual positions. No historical Common bench exists in current
scene geometry; none was invented. Ceilings, beams/ducts/trays/lights and player omitted
visually for readability; raw geometry included in scene-snapshot.json.
Authored hidden coffee_jar__002 mesh is excluded from the visual plan; G3 records 23/24 visible.

Verification: native extraction warnings0; SVG XML/JSON parse; floor bounds;7doors;
6stash;8lockers; section loops close and stay convex; doorway widths; +/-100deg tracks;
ID badge overlap self-check; source SHA256 unchanged. PNG must be visually inspected
after rendering; final receipt records that inspection separately.
No runtime physics/navmesh/traversal/interaction/save-state test performed; main chat owns runtime.

Files: layout.svg (editable), layout.png (preview), layout-data.json (measured data),
scene-snapshot.json (raw resources), read_scene_snapshot.gd (read-only MCP body),
build_layout.py (offline vectors/self-checks), render_layout.cjs (existing sharp),
validation.json (final QA receipt). .gdignore prevents design artifacts entering Godot imports.
"""
(HERE/"brief.txt").write_text(brief,encoding="utf-8")
print(json.dumps({"svg":"layout.svg","props":len(all_props),"groups":len(groups),"doors":len(doors),"architecture_parts":len(architecture),"floor_bounds":data["floor_bounds_m"],"stash_gap_m":stash_gap,"west_aisle_m":west_aisle,"checks":"PASS"},ensure_ascii=False))
