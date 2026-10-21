// Offline static payload authoring; no runtime generator or new dependency.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const terrain = require('./terrain-authoring.cjs');
const root = path.resolve(__dirname, '../../..');
const contract = require('../terrain-contract.json');
const layout = require('../layout.json');
const out = path.join(root, 'Scene/World/Town500m');
const check = process.argv.includes('--check');
const n = v => Number(v.toFixed(7)).toString();
const vec = p => `Vector3(${p.map(n).join(', ')})`;
const cross = (a, b, p) => (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]);
const center = tri => [tri.reduce((s, v) => s + v[0], 0) / 3, tri.reduce((s, v) => s + v[2], 0) / 3];
const inConvex = (p, poly, tolerance = 1e-7) => poly.every((a, i) => {
    const b = poly[(i + 1) % poly.length];
    return cross(a, b, p) >= -tolerance * Math.hypot(b[0] - a[0], b[1] - a[1]);
});
function write(relative, text) {
    const file = path.join(out, relative);
    if (check) assert.equal(fs.readFileSync(file, 'utf8'), text, `Stale ${relative}`);
    else {fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, text);}
}
function obj(faces) {
    const lines = ['# World metres; visual only. Walking floors are terrain/decks.'];
    for (const t of faces) for (const p of [t[0], t[2], t[1]]) lines.push(`v ${p.map(n).join(' ')}`);
    for (let i = 0; i < faces.length; i++) lines.push(`f ${i * 3 + 1} ${i * 3 + 2} ${i * 3 + 3}`);
    return lines.join('\n') + '\n';
}
// Ear clipping is only for the two small water outlines, not general terrain.
function triangulate(poly) {
    const p = terrain.signedArea(poly) > 0 ? [...poly] : [...poly].reverse();
    const triangles = [];
    while (p.length > 3) {
        const ear = p.findIndex((b, i) => {
            const a = p[(i + p.length - 1) % p.length], c = p[(i + 1) % p.length];
            return cross(a, b, c) > 1e-8 && !p.some(v => v !== a && v !== b && v !== c && inConvex(v, [a, b, c]));
        });
        assert(ear >= 0, 'Water outline cannot be triangulated');
        triangles.push([p[(ear + p.length - 1) % p.length], p[ear], p[(ear + 1) % p.length]]);
        p.splice(ear, 1);
    }
    triangles.push(p);
    assert(Math.abs(triangles.reduce((sum, t) => sum + terrain.area(t), 0) - terrain.area(poly)) < 1e-5);
    return triangles;
}
function material(id, rgb) {
    return `[sub_resource type="StandardMaterial3D" id="${id}"]\nalbedo_color = Color(${rgb.join(', ')}, 1)\nroughness = 0.9\ncull_mode = 2`;
}
function scene(ext, resources, nodes, connections = []) {
    return `[gd_scene load_steps=${1 + ext.length + resources.length} format=3]\n\n${[...ext, ...resources, ...nodes, ...connections].join('\n\n')}\n`;
}
function box(parts, id, parent, size, position, materialId, collision = true, extra = '') {
    parts.resources.push(`[sub_resource type="BoxMesh" id="mesh_${id}"]\nsize = ${vec(size)}`);
    if (collision) parts.resources.push(`[sub_resource type="BoxShape3D" id="shape_${id}"]\nsize = ${vec(size)}`);
    parts.nodes.push(`[node name="${id}" type="${collision ? 'StaticBody3D' : 'Node3D'}" parent="${parent}"]\nposition = ${vec(position)}${collision ? '\ncollision_layer = 1\ncollision_mask = 0' : ''}${extra}`);
    parts.nodes.push(`[node name="Visual" type="MeshInstance3D" parent="${parent === '.' ? '' : parent + '/'}${id}"]\nmesh = SubResource("mesh_${id}")\nmaterial_override = SubResource("${materialId}")`);
    if (collision) parts.nodes.push(`[node name="Collision" type="CollisionShape3D" parent="${parent === '.' ? '' : parent + '/'}${id}"]\nshape = SubResource("shape_${id}")`);
}

// Terrain is already partitioned by every corridor edge. Keep one visual material per face.
terrain.generate();
const classes = {asphalt: [.16, .17, .17], gravel: [.37, .35, .30], trail: [.40, .33, .25]};
const groups = Object.fromEntries(Object.keys(classes).map(k => [k, []]));
const route = new Map(layout.corridors.map(r => [r.id, r]));
const priority = s => s.id === 'P01' ? 0 : s.id === 'P04' ? 1 : ['P02', 'P03'].includes(s.id) ? 2 : 3;
const segments = terrain.segments.map(s => ({...s, bb: terrain.bounds(s.poly)})).sort((a, b) => priority(a) - priority(b));
let roadFaces = 0;
for (const tri of terrain.triangles) {
    const p = center(tri);
    const seg = segments.find(s => p[0] >= s.bb[0] && p[0] <= s.bb[2] && p[1] >= s.bb[1] && p[1] <= s.bb[3] && inConvex(p, s.poly));
    if (!seg) continue;
    assert(tri.every(v => inConvex([v[0], v[2]], seg.poly, 1e-4)), `Road face spans unpartitioned corridor ${seg.id}`);
    const type = route.get(seg.id)?.surface;
    const kind = type === 'asphalt' ? 'asphalt' : type === 'gravel' || priority(seg) < 3 ? 'gravel' : 'trail';
    groups[kind].push(tri.map(([x, y, z]) => [x, y + .012, z])); roadFaces++;
}
const roadExt = [], roadNodes = ['[node name="Circulation" type="Node3D"]'];
for (const [kind, faces] of Object.entries(groups)) {
    write(`Circulation/${kind}.obj`, obj(faces));
    roadExt.push(`[ext_resource type="ArrayMesh" path="res://Scene/World/Town500m/Circulation/${kind}.obj" id="${kind}"]`);
    roadNodes.push(`[node name="${kind}" type="MeshInstance3D" parent="."]\nmesh = ExtResource("${kind}")\nmaterial_override = SubResource("${kind}")`);
}
write('Circulation/circulation.tscn', scene(roadExt, Object.entries(classes).map(([id, c]) => material(id, c)), roadNodes));

// Raised bridge pads end above water; close their exposed banks without adding a wet floor.
const terrainEdges = new Map();
const vertexKey = p => `${Math.round(p[0] * 1e5)},${Math.round(p[2] * 1e5)}`;
for (const tri of terrain.triangles) for (let i = 0; i < 3; i++) {
    const a = tri[i], b = tri[(i + 1) % 3], key = [vertexKey(a), vertexKey(b)].sort().join('|');
    const edge = terrainEdges.get(key) || {a, b, count: 0};
    edge.count++; terrainEdges.set(key, edge);
}
const bankFaces = [];
for (const {a, b, count} of terrainEdges.values()) {
    if (count !== 1) continue;
    const outer = [0, 2].some(axis => [-250, 250].some(edge => Math.abs(a[axis] - edge) < 1e-5 && Math.abs(b[axis] - edge) < 1e-5));
    if (outer) continue;
    assert(a[1] >= -.350001 && b[1] >= -.350001, 'Bank top below canonical wet boundary');
    const lowA = [a[0], -4, a[2]], lowB = [b[0], -4, b[2]];
    bankFaces.push([a, b, lowB], [a, lowB, lowA]);
}
assert(bankFaces.length > 0 && bankFaces.every(tri => Math.abs(terrain.signedArea(tri.map(v => [v[0], v[2]]))) < 1e-8), 'Bank faces must be vertical, visual only');
write('Terrain/bank_faces.obj', obj(bankFaces));
const water = {resources: [material('water', [.12, .29, .35]), material('bed', [.22, .21, .16]), material('bank', [.39, .33, .22])], nodes: ['[node name="Water" type="Node3D"]']};
const waterFaces = [contract.hydrology.river.actual_water_polygon_xz_m, contract.hydrology.lake.actual_water_polygon_xz_m].flatMap(triangulate);
for (const [name, y] of [['surface', 0], ['bed', -4]]) {
    write(`Water/${name}.obj`, obj(waterFaces.map(t => t.map(([x, z]) => [x, y, z]))));
    water.nodes.push(`[node name="${name}" type="MeshInstance3D" parent="."]\nmesh = ExtResource("${name}")\nmaterial_override = SubResource("${name === 'surface' ? 'water' : 'bed'}")`);
}
water.nodes.push('[node name="BankFaces" type="MeshInstance3D" parent="."]\nmesh = ExtResource("banks")\nmaterial_override = SubResource("bank")');
water.nodes.push('[node name="DeepWater" type="Area3D" parent="."]\ncollision_layer = 0\ncollision_mask = 16\nmonitorable = false\nscript = ExtResource("hazard")');
waterFaces.forEach((tri, i) => {
    const points = [-50, contract.hydrology.deep_water_threshold_y_m].flatMap(y => tri.flatMap(([x, z]) => [x, y, z]));
    water.resources.push(`[sub_resource type="ConvexPolygonShape3D" id="wet_${i}"]\npoints = PackedVector3Array(${points.map(n).join(', ')})`);
    water.nodes.push(`[node name="Wet_${i}" type="CollisionShape3D" parent="DeepWater"]\nshape = SubResource("wet_${i}")`);
});
write('Water/water.tscn', scene([
    '[ext_resource type="Script" path="res://Scripts/World/deep_water_zone.gd" id="hazard"]',
    '[ext_resource type="ArrayMesh" path="res://Scene/World/Town500m/Terrain/bank_faces.obj" id="banks"]',
    ...['surface', 'bed'].map(s => `[ext_resource type="ArrayMesh" path="res://Scene/World/Town500m/Water/${s}.obj" id="${s}"]`)
], water.resources, water.nodes, ['[connection signal="body_entered" from="DeepWater" to="DeepWater" method="_on_body_entered"]']));

for (const b of contract.bridges) {
    const parts = {resources: [material('concrete', [.45, .45, .40]), material('metal', [.22, .25, .23])], nodes: [`[node name="${b.id}" type="Node3D" groups=["town500_bridge"]]\nposition = ${vec([b.anchor_xz_m[0], 0, b.anchor_xz_m[1]])}\nrotation = Vector3(0, ${n(b.yaw_deg * Math.PI / 180)}, 0)`]};
    box(parts, 'Deck', '.', [b.deck_length_m, b.deck_thickness_m, b.deck_clear_width_m], [0, b.deck_surface_y_m - b.deck_thickness_m / 2, 0], 'concrete');
    for (const sign of [-1, 1]) box(parts, sign < 0 ? 'RailNorth' : 'RailSouth', '.', [b.deck_length_m, 1.1, .12], [0, b.deck_surface_y_m + .55, sign * (b.deck_clear_width_m / 2 + .06)], 'metal');
    parts.nodes.push(`[node name="WestPort" type="Marker3D" parent="."]\nposition = ${vec([-b.deck_length_m / 2, b.deck_surface_y_m, 0])}`);
    parts.nodes.push(`[node name="EastPort" type="Marker3D" parent="."]\nposition = ${vec([b.deck_length_m / 2, b.deck_surface_y_m, 0])}`);
    write(`Circulation/${b.id.toLowerCase()}_bridge.tscn`, scene([], parts.resources, parts.nodes));
}
const d = contract.dock;
const dock = {resources: [material('wood', [.34, .26, .17])], nodes: ['[node name="DockL03" type="Node3D"]']};
box(dock, 'Deck', '.', [d.deck_size_m[0], .35, d.deck_size_m[1]], [d.deck_center_xz_m[0], d.deck_surface_y_m - .175, d.deck_center_xz_m[1]], 'wood');
box(dock, 'Gangway', '.', [d.gangway_clear_width_m, .35, d.gangway_length_m], [175, d.deck_surface_y_m - .175, 157], 'wood');
write('Circulation/dock_l03.tscn', scene([], dock.resources, dock.nodes));

const boundary = {resources: [material('earth', [.36, .31, .25])], nodes: ['[node name="RoadCollapses" type="Node3D"]']};
const termini = [
    {id: 'CountyWest', size: [6, 5, 20], at: [-247, 2, 15]},
    {id: 'CountyEast', size: [6, 5, 20], at: [247, 2, 0]},
    {id: 'RailNorth', size: [18, 5, 6], at: [214.77, 2, -247]},
    {id: 'RailEast', size: [6, 5, 18], at: [247, 2, 121.59]},
    {id: 'FarmSouth', size: [16, 5, 6], at: [10.23, 1.5, 247]}
];
for (const b of termini) box(boundary, b.id, '.', b.size, [b.at[0], b.at[1] + b.size[1] / 2, b.at[2]], 'earth');
write('Terrain/road_collapses.tscn', scene([], boundary.resources, boundary.nodes));
const childScenes = ['Terrain/dry_terrain.tscn', 'Terrain/road_collapses.tscn', 'Circulation/circulation.tscn', 'Water/water.tscn', 'Circulation/r01_bridge.tscn', 'Circulation/r02_bridge.tscn', 'Circulation/dock_l03.tscn'];
const names = ['DryTerrain', 'RoadCollapses', 'Circulation', 'Water', 'R01', 'R02', 'DockL03'];
write('terrain_payload.tscn', scene(childScenes.map((s, i) => `[ext_resource type="PackedScene" path="res://Scene/World/Town500m/${s}" id="s${i}"]`), [], ['[node name="Town500TerrainPayload" type="Node3D"]', ...names.map((name, i) => `[node name="${name}" parent="." instance=ExtResource("s${i}")]`)]));
const report = {status: 'OFFLINE CHECKED; NATIVE PENDING', road_visual_faces: roadFaces, road_collision: 'none; dry terrain is sole road floor', bank_visual_faces: bankFaces.length, bank_collision: false, bridge_count: 2, water_triangular_prisms: waterFaces.length, wet_top_y_m: -.35, wet_bottom_y_m: -50, water_or_bed_floor_collision: false, road_collapses: termini, integration: 'Static child payload for Town Phase3; production Town unchanged in Phase2'};
if (!check) fs.writeFileSync(path.join(__dirname, 'circulation-authoring.report.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({mode: check ? 'check' : 'write', ...report}));
