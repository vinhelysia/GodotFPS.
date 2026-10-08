// Authoring only: Town instances the saved scene, never this script or proposal JSON.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../../..');
const layout = JSON.parse(fs.readFileSync(path.join(root, 'design/town-concept-b/town-layout.json'), 'utf8'));
const {heightAt} = require('../Terrain/author_terrain.cjs');
const resources = [], nodes = [];
const boxes = new Map();
const number = value => Number(value.toFixed(6));
const vector = values => `Vector3(${values.map(number).join(', ')})`;
const materials = {
  wire: 'albedo_texture = ExtResource("1_wire")\ntransparency = 2\nalpha_scissor_threshold = 0.45\ncull_mode = 2\nroughness = 0.9\nuv1_scale = Vector3(24, 12, 1)',
  metal: 'albedo_color = Color(0.23, 0.26, 0.23, 1)\nroughness = 0.9',
  wood: 'albedo_color = Color(0.32, 0.27, 0.19, 1)\nroughness = 1.0',
  wreck: 'albedo_color = Color(0.25, 0.29, 0.24, 1)\nroughness = 0.95',
  rubber: 'albedo_color = Color(0.08, 0.085, 0.08, 1)\nroughness = 1.0',
  marker: 'albedo_color = Color(0.5, 0.48, 0.38, 1)\nroughness = 1.0',
};
for (const [name, properties] of Object.entries(materials)) {
  resources.push(`[sub_resource type="StandardMaterial3D" id="Material_${name}"]\n${properties}\n`);
}
function group(name, parent = '.', properties = '') {
  nodes.push(`[node name="${name}" type="Node3D" parent="${parent}"]\n${properties}\n`);
}
function box(name, parent, position, size, material, rotation = [0, 0, 0], collides = true, transparent = false) {
  const key = material + JSON.stringify(size.map(number));
  if (!boxes.has(key)) {
    const id = `Box_${resources.length}`;
    resources.push(`[sub_resource type="BoxMesh" id="Mesh_${id}"]\nmaterial = SubResource("Material_${material}")\nsize = ${vector(size)}\n`);
    boxes.set(key, {id, hasShape:false});
  }
  const resource = boxes.get(key), id = resource.id;
  if (collides && !resource.hasShape) {
    resources.push(`[sub_resource type="BoxShape3D" id="Shape_${id}"]\nsize = ${vector(size)}\n`);
    resource.hasShape = true;
  }
  nodes.push(`[node name="${name}" type="${collides ? 'StaticBody3D' : 'Node3D'}" parent="${parent}"]\nposition = ${vector(position)}\nrotation = ${vector(rotation)}\n${transparent ? 'metadata/concept_b_los_transparent = true\n' : ''}`);
  nodes.push(`[node name="Mesh" type="MeshInstance3D" parent="${parent}/${name}"]\nmesh = SubResource("Mesh_${id}")\n`);
  if (collides) nodes.push(`[node name="CollisionShape3D" type="CollisionShape3D" parent="${parent}/${name}"]\nshape = SubResource("Shape_${id}")\n`);
}
function fence(name, parent, from, to, opaque = false, height = 2) {
  const dx = to[0] - from[0], dz = to[1] - from[1];
  const length = Math.hypot(dx, dz), yaw = -Math.atan2(dz, dx);
  const count = Math.ceil(length / (opaque ? 2 : 4));
  const samples = Array.from({length: count + 1}, (_, index) => {
    const x = from[0] + dx * index / count, z = from[1] + dz * index / count;
    return [x, heightAt(x, z), z];
  });
  const bounds = [Math.min(from[0], to[0]), Math.max(from[0], to[0]), Math.min(from[1], to[1]), Math.max(from[1], to[1])];
  group(name, parent, `metadata/concept_b_bounds_xz = PackedFloat32Array(${bounds.join(', ')})\nmetadata/concept_b_opaque = ${opaque}`);
  const target = `${parent}/${name}`;
  for (let index = 0; index < count; index++) {
    const a = samples[index], b = samples[index + 1];
    const panelLength = length / count, dy = b[1] - a[1];
    box(`Panel_${index}`, target, [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2 + height / 2, (a[2] + b[2]) / 2], [Math.hypot(panelLength, dy), height, opaque ? 0.14 : 0.06], opaque ? 'wood' : 'wire', [0, yaw, Math.atan2(dy, panelLength)], true, !opaque);
  }
  for (let index = 0; index < samples.length; index++) {
    const [x, y, z] = samples[index];
    box(`Post_${index}`, target, [x, y + height / 2, z], [0.09, height + 0.16, 0.09], opaque ? 'wood' : 'metal', [0, yaw, 0], true, !opaque);
  }
}
group('DepotFence');
// Gate endpoints are the inner clear span; posts sit outside it.
fence('NorthWest', 'DepotFence', [24,32], [39.75 - 0.045,32]);
fence('NorthEast', 'DepotFence', [46.25 + 0.045,32], [88,32]);
fence('WestNorth', 'DepotFence', [24,32], [24,40.75 - 0.045]);
fence('WestSouth', 'DepotFence', [24,47.25 + 0.045], [24,80]);
fence('East', 'DepotFence', [88,32], [88,80]);
fence('SouthWest', 'DepotFence', [24,80], [79.5 - 0.045,80]);
fence('SouthEast', 'DepotFence', [84.5 + 0.045,80], [88,80]);
for (const gate of layout.depot.gates) {
  const [x,z] = layout.nodes[gate.node];
  nodes.push(`[node name="${gate.node}" type="Marker3D" parent="DepotFence"]\nposition = ${vector([x,heightAt(x,z),z])}\nmetadata/clear_width_m = ${gate.width_m}\n`);
}
group('PrivacyScreens');
const plotStories = ['west cottage gardens','long-house rear gardens','north cooperative gardens','north apartment courtyard','east cottage garden line','east workshop service strip','south cottage west garden','south cottage east garden','village kitchen gardens','pump-house service boundary','depot allotment boundary','clinic rear garden','workshop east yard return'];
for (const [index, screen] of layout.occluders.entries()) {
  fence(screen.id, 'PrivacyScreens', screen.path[0], screen.path[1], true, screen.height_m);
  const rootNode = nodes.find(node => node.startsWith(`[node name="${screen.id}" type="Node3D" parent="PrivacyScreens"]`));
  nodes[nodes.indexOf(rootNode)] = rootNode + `metadata/concept_b_story_plot = "${plotStories[index]}"\n`;
}
group('BoundaryClosures');
// Approved S3 bus closure offset to Z97 preserves the Z92 culvert and S04 route.
for (const [name, x, z, yaw, length] of [['Truck_N0',-94,-48,-Math.atan2(12,39),6.8], ['Wreck_N4',94,-62,-Math.atan2(-10,24),5.8], ['Bus_South',16,97,Math.PI / 2,8.2]]) {
  const y = heightAt(x,z);
  group(name, 'BoundaryClosures', `position = ${vector([x,y,z])}\nrotation = ${vector([0,yaw,0])}`);
  const target = `BoundaryClosures/${name}`;
  box('Hull', target, [0,0.85,0], [2.5,1.2,length], 'wreck');
  box('Cabin', target, [0,1.7,-length * 0.25], [2.3,0.7,2], 'wreck');
  for (const side of [-1,1]) for (const axle of [-1,1]) box(`Wheel_${side}_${axle}`, target, [side * 1.12,0.36,axle * length * 0.3], [0.3,0.65,0.75], 'rubber', [0,0,0], false);
}
group('PlotMarkers');
// Broken low corner markers imply plots without forming another perimeter.
for (const screen of layout.occluders) {
  const [x,z] = screen.path[0];
  box(`Corner_${screen.id}`, 'PlotMarkers', [x,heightAt(x,z) + 0.16,z + 0.5], [0.24,0.32,0.24], 'marker', [0,0,0], false);
}
const scene = `[gd_scene load_steps=${resources.length + 2} format=3]\n\n[ext_resource type="Texture2D" path="res://Assets/TownConceptB/Dressing/fence_wire.svg" id="1_wire"]\n\n${resources.join('\n')}\n[node name="ConceptBDressing" type="Node3D"]\n\n${nodes.join('\n')}`;
fs.mkdirSync(path.join(root, 'Scene/World/TownConceptB'), {recursive:true});
fs.writeFileSync(path.join(root, 'Scene/World/TownConceptB/dressing.tscn'), scene);
console.log(`Saved dressing: ${layout.occluders.length} opaque privacy screens; 3 open depot gates; ${nodes.length} static nodes.`);
