// Offline static authoring, following Assets/TownConceptB/Buildings/author_buildings.cjs.
// Godot loads the saved instances. --check compares every output without writing.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const project = path.resolve(__dirname, '../../..');
const design = path.resolve(__dirname, '..');
const catalogue = JSON.parse(fs.readFileSync(path.join(design, 'building-catalogue.json')));
const layout = JSON.parse(fs.readFileSync(path.join(design, 'layout.json')));
const check = process.argv.includes('--check');
const sceneRef = 'res://Scene/World/Town500m/POI/town_core.tscn';
const local = ref => path.join(project, ref.replace(/^res:\/\//, ''));
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const fileHash = file => hash(fs.readFileSync(file));
const n = value => Number(value.toFixed(9)).toString();
const vec = values => `Vector3(${values.map(n).join(', ')})`;
const rows = catalogue.structures.filter(row => row.zone_id === 'town');
const templates = [...new Set(rows.map(row => row.scene_ref))];
assert.equal(rows.length, 32);
assert.equal(new Set(rows.map(row => row.id)).size, 32);
assert.equal(catalogue.plots.length, 12);
assert.equal(rows.filter(row => row.access.ground).length, 15);
assert.equal(rows.filter(row => row.access.upper).length, 4);
assert.equal(templates.length, 14);
for (const contract of layout.provenance.contracts) {
  assert.equal(fileHash(path.join(design, contract.path)), contract.sha256, `Stale canonical hash: ${contract.path}`);
}
assert.deepEqual(rows, layout.structures.filter(row => row.zone_id === 'town'));

// This deliberately reads the known text-scene blocks, not a general Godot parser.
function blocks(text, kind) {
  return [...text.matchAll(new RegExp(`^\\[${kind} ([^\\n]+)\\]\\r?\\n([^]*?)(?=^\\[|$(?![^]))`, 'gm'))]
    .map(match => ({header: match[1], body: match[2]}));
}
function property(block, name) {
  const line = block.body.split(/\r?\n/).find(line => line.startsWith(`${name} = `));
  return line ? line.slice(name.length + 3) : null;
}
function position(block) {
  const value = property(block, 'position');
  return value ? value.match(/Vector3\(([^)]+)\)/)[1].split(',').map(Number) : [0, 0, 0];
}
const roofRef = 'res://Assets/Blender/TownKit/assets/metal_roof_8x8.glb';
const roofBuffer = fs.readFileSync(local(roofRef));
assert.equal(roofBuffer.toString('ascii', 0, 4), 'glTF');
const roofGltf = JSON.parse(roofBuffer.subarray(20, 20 + roofBuffer.readUInt32LE(12)).toString());
assert(roofGltf.nodes.every(node => !node.matrix && !node.translation && !node.rotation && !node.scale));
const roofY = roofGltf.meshes.flatMap(mesh => mesh.primitives.map(primitive => roofGltf.accessors[primitive.attributes.POSITION]));
const roofMinY = Math.min(...roofY.map(bounds => bounds.min[1]));
const roofMaxY = Math.max(...roofY.map(bounds => bounds.max[1]));
const inspections = templates.map(ref => {
  assert(ref?.startsWith('res://Scene/Props/TownKit/Buildings/'));
  const text = fs.readFileSync(local(ref), 'utf8');
  const nodes = blocks(text, 'node'), resources = blocks(text, 'sub_resource');
  const node = name => nodes.find(item => item.header.startsWith(`name="${name}" `));
  const resource = id => resources.find(item => item.header.includes(`id="${id}"`));
  const floor = node('GroundFloor');
  const floorSize = property(resource('GroundFloor_shape'), 'size').match(/Vector3\(([^)]+)\)/)[1].split(',').map(Number);
  const floorTop = position(floor)[1] + floorSize[1] / 2;
  assert.equal(floorTop, 0, `${ref}: unsupported floor origin`);
  assert(!/^(?:scale|transform) = /m.test(nodes[0].body), `${ref}: nonidentity template root`);
  const declared = catalogue.templates.find(template => template.scene_ref === ref);
  assert.deepEqual([floorSize[0], floorSize[2]], declared.footprint_m);
  for (const dependency of text.matchAll(/^\[ext_resource [^\n]*path="(res:\/\/[^"\n]+)"/gm)) {
    assert(fs.existsSync(local(dependency[1])), `Missing template dependency: ${dependency[1]}`);
  }
  const markers = Object.fromEntries(nodes.filter(item => item.header.includes('type="Marker3D"'))
    .map(item => [item.header.match(/^name="([^"]+)"/)[1], position(item)]));
  const roofs = nodes.filter(item => /^name="(?:RoofVisual|ShelterRoof|Roof_\d+)" /.test(item.header)).map(item => {
    const origin = position(item), meshId = property(item, 'mesh')?.match(/SubResource\("([^"]+)"\)/)?.[1];
    const size = meshId ? property(resource(meshId), 'size').match(/Vector3\(([^)]+)\)/)[1].split(',').map(Number) : null;
    return {node: item.header.match(/^name="([^"]+)"/)[1], position_local_m: origin,
      visual_bottom_local_y_m: origin[1] + (size ? -size[1] / 2 : roofMinY),
      visual_top_local_y_m: origin[1] + (size ? size[1] / 2 : roofMaxY),
      imported_module: size ? null : roofRef};
  });
  assert(roofs.length > 0, `${ref}: roof inspection missing`);
  const ceilings = resources.filter(item => /id="(?:CeilingUnderside|ShelterCeiling)_shape"/.test(item.header));
  const ceilingY = [...new Set(ceilings.flatMap(item => property(item, 'data').match(/PackedVector3Array\(([^)]+)\)/)[1]
    .split(',').map(Number).filter((value, index) => index % 3 === 1)))];
  assert.deepEqual(ceilingY, [ref.endsWith('t12_bus_shelter.tscn') ? 2.6 : declared.height_m], `${ref}: unexpected ceiling height`);
  const roofTop = Math.max(...roofs.map(roof => roof.visual_top_local_y_m));
  return {scene_ref: ref, sha256: hash(text), footprint_m: declared.footprint_m,
    ground_floor_bottom_local_y_m: position(floor)[1] - floorSize[1] / 2,
    ground_floor_top_local_y_m: floorTop, ceiling_local_y_m: ceilingY[0],
    nominal_height_m: declared.height_m, roof_visual_top_local_y_m: roofTop,
    roof_above_nominal_height_m: roofTop - declared.height_m, roofs, markers_local_m: markers};
});

const ext = templates.map((ref, index) => `[ext_resource type="PackedScene" path="${ref}" id="building_${index}"]`);
const nodes = ['[node name="TownCore" type="Node3D"]'];
const placements = [];
for (const plot of catalogue.plots) {
  const members = rows.filter(row => row.source_ref === plot.id);
  assert(members.length >= 2 && members.length <= 3, `${plot.id}: member count`);
  nodes.push(`[node name="${plot.id}" type="Node3D" parent="."]`);
  for (const row of members) {
    const template = inspections.find(item => item.scene_ref === row.scene_ref);
    assert.deepEqual(row.footprint_m, template.footprint_m);
    assert.equal(row.pad_intent.root_above_pad_m, .2);
    const [x, z] = row.position_xz_m, y = row.pad_intent.surface_y_m + .2;
    const yaw = row.yaw_deg * Math.PI / 180;
    assert([x, y, z, yaw].every(Number.isFinite));
    assert(Math.abs(row.front_xz[0] + Math.sin(yaw)) < 1e-8 && Math.abs(row.front_xz[1] + Math.cos(yaw)) < 1e-8);
    if (row.access.ground) assert(template.markers_local_m.GFEntry && template.markers_local_m.GFInterior);
    if (row.access.upper) assert.equal(template.markers_local_m.UpperInterior?.[1], 3.2);
    const name = row.id.replaceAll('-', '_'), nodePath = `TownCore/${plot.id}/${name}`;
    nodes.push(`[node name="${name}" parent="${plot.id}" instance=ExtResource("building_${templates.indexOf(row.scene_ref)}")]\nposition = ${vec([x, y, z])}\nrotation = ${vec([0, yaw, 0])}\nmetadata/town500_id = "${row.id}"\nmetadata/source_ref = "${row.source_ref}"\nmetadata/zone = "town"`);
    const markers = Object.fromEntries(Object.entries(template.markers_local_m).map(([marker, p]) => [marker,
      [x + Math.cos(yaw) * p[0] + Math.sin(yaw) * p[2], y + p[1], z - Math.sin(yaw) * p[0] + Math.cos(yaw) * p[2]].map(value => Number(n(value)))]));
    placements.push({id: row.id, node_path: nodePath, source_ref: row.source_ref, zone: row.zone_id,
      scene_ref: row.scene_ref, position_m: [x, y, z], yaw_deg: row.yaw_deg, scale: [1, 1, 1],
      pad_surface_y_m: row.pad_intent.surface_y_m, ground_floor_y_m: y,
      roof_visual_top_world_y_m: y + template.roof_visual_top_local_y_m,
      access: row.access, markers_world_m: markers});
  }
}
assert.equal(placements.length, 32);
const scene = `[gd_scene load_steps=${templates.length + 1} format=3]\n\n${[...ext, ...nodes].join('\n\n')}\n`;
assert.equal((scene.match(/\[node .*instance=ExtResource/g) || []).length, 32);
assert(!scene.includes('[sub_resource') && !scene.includes('script =') && !scene.includes('scale ='));
const report = {
  status: 'STATIC_PAYLOAD_PASS_NATIVE_PENDING', scene_ref: sceneRef,
  authoring: 'node design/town-500m/phase3/author-town-core.cjs [--check]',
  counts: {plots: 12, structures: 32, reusable_scenes: 14, ground_interiors: 15, upper_interiors: 4},
  ownership: 'Identity TownCore and 12 identity plot parents; 32 unit-scale editable template instances. No plot geometry, runtime script, terrain or duplicate marker nodes.',
  source_hashes: Object.fromEntries(['building-catalogue.json', 'layout.json', 'terrain-contract.json'].map(file => [file, fileHash(path.join(design, file))])),
  output_sha256: hash(scene), imported_roof_sha256: fileHash(local(roofRef)),
  incompatibilities: [
    'Catalogue height is ceiling/eave height for all enclosed templates, not visual roof maximum: slabs extend .2m and imported roof ridge .859000027179718m above it. No scale correction applied.',
    'T07-C bus shelter catalogue height3.2m differs from native ceiling2.6m/visual top2.75m; no scale correction applied.',
    'T07-C bus shelter keeps native GFEntry/GFInterior, but catalogue access.ground=false intentionally excludes this open shelter from the 15 enclosed ground interiors.',
    'Ground floor spans padY..padY+.2; 0.2m threshold rise is intentional. Native door/roof/stair/navigation acceptance remains primary-owned.'
  ],
  template_inspections: inspections, placements,
  not_verified: ['Godot native scene import/load', 'terrain-pad physics alignment and real door/stair traversal', 'navigation and 8 spawn/extract routes', 'standing/ADS/lean/upstairs LOS', 'finished art/performance/export']
};
const handoff = `Town500m Phase3 Town core — static payload only\n\nEntry: ${sceneRef}\nAttach at identity under Town NavigationRegion3D/Level.\nTownCore/T01..T12 remain identity; instance node names replace '-' with '_'.\n32 catalogue structures / 12 plots / 14 reusable scenes / 15 ground / 4 upper.\nEvery root = exact catalogue XZ, pad surface + .2m (currently all Y2.2),\nauthored yaw, unit scale. Metadata: town500_id, source_ref, zone.\nNative Markers/GFEntry/GFInterior/stair/upper marker nodes stay in templates.\nNo plot-sized geometry, runtime parser, script, settings or template changes.\n\nReproduce: node design/town-500m/phase3/author-town-core.cjs\nCheck: node design/town-500m/phase3/author-town-core.cjs --check\nChecks assert canonical provenance hashes/data, exact counts, scene/dependency\nexistence, floor footprints/origins, marker access, front/yaw and byte outputs.\ncore-placement-report.json records 32 exact poses/world markers and hashes.\n\nTemplate compatibility: floor localY[-.2,0], enclosed ceiling/eave=nominal.\nEnclosed slab roof top=nominal+.2; imported roof ridge\n=nominal+.859000027179718 (T02 local7.259000027; T07 local4.059000027).\nThese extend beyond catalogue nominal height: preserve full geometry,\ncompute native bake Y bounds from actual colliders, inspect high-ground LOS.\nT07-C bus shelter catalogue height3.2 differs from native ceiling2.6/roof2.75.\nIt keeps open-shelter GF markers but is not counted as an enclosed interior.\nNo incompatible footprint or floor origin was found in the 14 live templates.\n\nNative Godot import/load, terrain alignment/traversal, nav/routes and LOS are\nNOT verified here; primary owns all editor/runtime operations and integration.\nNo commit/push. No gameplay/settings/Town/terrain/canonical JSON edits.\n`;
for (const [file, content] of [[local(sceneRef), scene], [path.join(__dirname, 'core-placement-report.json'), JSON.stringify(report, null, 2) + '\n'], [path.join(__dirname, 'core-handoff.txt'), handoff]]) {
  if (check) assert.equal(fs.readFileSync(file, 'utf8'), content, `Stale output: ${path.relative(project, file)}`);
  else { fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, content); }
}
console.log('PASS Town core static payload: 32 instances / 12 plots / 15 ground / 4 upper; native pending.');
