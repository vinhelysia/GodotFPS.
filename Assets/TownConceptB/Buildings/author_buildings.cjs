// Offline graybox authoring only. Godot loads the saved PackedScenes, never this file.
// Run from project root: node Assets/TownConceptB/Buildings/author_buildings.cjs
// Use --check to validate the saved output without rewriting it.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const project = path.resolve(__dirname, '../../..');
const sceneDir = path.join(project, 'Scene/Props/TownKit/Buildings');
const layout = JSON.parse(fs.readFileSync(path.join(project, 'design/town-concept-b/town-layout.json')));
const checkOnly = process.argv.includes('--check');
const manifest = [];
const n = value => Number(value.toFixed(5)).toString();
const vec = values => `Vector3(${values.map(n).join(', ')})`;

function createScene(type, access, floors, filename) {
  const [width, depth] = type.footprint_m;
  const height = type.id === 'T08' ? 7 : type.id === 'T06' ? 4.5 : Math.max(1, floors) * 3.2;
  const resources = [];
  const nodes = [];
  const externals = new Map();
  const collisionBoxes = [];
  const markers = {};
  function external(file, kind = 'PackedScene') {
    if (!externals.has(file)) externals.set(file, { id: `ext_${externals.size}`, kind });
    return `ExtResource("${externals.get(file).id}")`;
  }
  function resource(kind, id, properties) {
    resources.push(`[sub_resource type="${kind}" id="${id}"]\n${properties}\n`);
    return `SubResource("${id}")`;
  }
  const wallFinish = resource('StandardMaterial3D', 'wall', 'albedo_color = Color(0.43, 0.44, 0.4, 1)\nroughness = 1.0');
  const floorFinish = resource('StandardMaterial3D', 'floor', 'albedo_color = Color(0.31, 0.32, 0.3, 1)\nroughness = 1.0');
  const roofFinish = resource('StandardMaterial3D', 'roof', 'albedo_color = Color(0.18, 0.23, 0.22, 1)\nroughness = 0.9');
  const trimFinish = resource('StandardMaterial3D', 'trim', 'albedo_color = Color(0.22, 0.31, 0.29, 1)\nroughness = 0.85');
  nodes.push(`[node name="${type.id}_${type.type}" type="Node3D"]\n`, '[node name="Architecture" type="Node3D" parent="."]\n');

  function box(name, size, position, material = wallFinish, collision = true) {
    const mesh = resource('BoxMesh', `${name}_mesh`, `material = ${material}\nsize = ${vec(size)}`);
    if (collision) {
      const shape = resource('BoxShape3D', `${name}_shape`, `size = ${vec(size)}`);
      nodes.push(`[node name="${name}" type="StaticBody3D" parent="Architecture"]\nposition = ${vec(position)}\ncollision_layer = 1\ncollision_mask = 0\n`,
        `[node name="Mesh" type="MeshInstance3D" parent="Architecture/${name}"]\nmesh = ${mesh}\n`,
        `[node name="Collision" type="CollisionShape3D" parent="Architecture/${name}"]\nshape = ${shape}\n`);
      collisionBoxes.push({ name, size, position });
    } else {
      nodes.push(`[node name="${name}" type="MeshInstance3D" parent="Architecture"]\nposition = ${vec(position)}\nmesh = ${mesh}\n`);
    }
  }
  function marker(name, position) {
    markers[name] = position;
    nodes.push(`[node name="${name}" type="Marker3D" parent="Markers"]\nposition = ${vec(position)}\n`);
  }
  function module(name, kind, position, yaw) {
    const instance = external(`res://Scene/Props/TownKit/${kind}_4m.tscn`);
    const finish = external('res://Assets/Blender/TownKit/materials/town_architecture_worn.tres', 'Material');
    const rootNames = { facade_solid: 'TownFacadeSolid', facade_window: 'TownFacadeWindow', facade_doorway: 'TownFacadeDoorway' };
    const meshNames = { facade_solid: 'FacadeSolid', facade_window: 'FacadeWindow', facade_doorway: 'FacadeDoorway' };
    nodes.push(`[node name="${name}" parent="Architecture" instance=${instance}]\nposition = ${vec(position)}\nrotation = Vector3(0, ${n(yaw)}, 0)\n`,
      `[node name="${meshNames[kind]}" parent="Architecture/${name}/${rootNames[kind]}" index="0"]\nsurface_material_override/0 = ${finish}\n`);
  }
  function ceiling(name, minX, maxX, minZ, maxZ, y) {
    // Godot concave front uses clockwise winding. Native rays found the previous
    // opposite order blocked from above, so both triangle faces are reversed here.
    const points = [minX,y,minZ, maxX,y,maxZ, maxX,y,minZ, minX,y,minZ, minX,y,maxZ, maxX,y,maxZ];
    for (const offset of [0, 9]) {
      const edgeA = [points[offset + 3] - points[offset], points[offset + 5] - points[offset + 2]];
      const edgeB = [points[offset + 6] - points[offset], points[offset + 8] - points[offset + 2]];
      const crossY = edgeA[1] * edgeB[0] - edgeA[0] * edgeB[1];
      assert(crossY > 0, `${filename}/${name}: Godot below-facing clockwise triangle order`);
    }
    const shape = resource('ConcavePolygonShape3D', `${name}_shape`, `data = PackedVector3Array(${points.map(n).join(', ')})\nbackface_collision = false`);
    nodes.push(`[node name="${name}" type="StaticBody3D" parent="Architecture"]\ncollision_layer = 1\ncollision_mask = 0\n`,
      `[node name="Collision" type="CollisionShape3D" parent="Architecture/${name}"]\nshape = ${shape}\n`);
  }

  box('GroundFloor', [width, 0.2, depth], [0, -0.1, 0], floorFinish);
  const modular = ['T02', 'T03', 'T07'].includes(type.id);
  const open = access === 'ground' || access === 'upper';
  const doorway = type.id === 'T06' ? [4, 3.2] : type.id === 'T08' ? [6, 4] : [1.2, 2.4];
  if (access === 'open') {
    // Bus shelter: open frontage and sides, opaque back with two slender supports.
    box('BackWall', [width, 2.6, 0.16], [0, 1.3, depth / 2 - 0.08], trimFinish);
    box('LeftPost', [0.12, 2.6, 0.12], [-width / 2 + 0.06, 1.3, -depth / 2 + 0.06], trimFinish);
    box('RightPost', [0.12, 2.6, 0.12], [width / 2 - 0.06, 1.3, -depth / 2 + 0.06], trimFinish);
    box('ShelterRoof', [width, 0.15, depth], [0, 2.675, 0], roofFinish, false);
    ceiling('ShelterCeiling', -width / 2, width / 2, -depth / 2, depth / 2, 2.6);
  } else if (modular) {
    for (let floor = 0; floor < floors; floor++) {
      const y = floor * 3.2;
      for (let i = 0; i < depth / 4; i++) {
        module(`West_${floor}_${i}`, i % 3 === 1 ? 'facade_window' : 'facade_solid', [-width / 2 + 0.25, y, -depth / 2 + i * 4], -Math.PI / 2);
        module(`East_${floor}_${i}`, i % 3 === 1 ? 'facade_window' : 'facade_solid', [width / 2 - 0.25, y, depth / 2 - i * 4], Math.PI / 2);
      }
      for (let i = 0; i < width / 4; i++) {
        module(`Rear_${floor}_${i}`, i % 2 === 0 ? 'facade_window' : 'facade_solid', [-width / 2 + i * 4, y, depth / 2 - 0.25], 0);
      }
      if (floor === 0 && open) {
        module('Entrance', 'facade_doorway', [2, 0, -depth / 2 + 0.25], Math.PI);
        const sideWidth = (width - 4) / 2;
        box('FrontLeftInfill', [sideWidth, 3.2, 0.25], [-(width + 4) / 4, 1.6, -depth / 2 + 0.125]);
        box('FrontRightInfill', [sideWidth, 3.2, 0.25], [(width + 4) / 4, 1.6, -depth / 2 + 0.125]);
      } else {
        for (let i = 0; i < width / 4; i++) module(`Front_${floor}_${i}`, i % 2 === 0 ? 'facade_window' : 'facade_solid', [width / 2 - i * 4, y, -depth / 2 + 0.25], Math.PI);
      }
    }
  } else {
    box('WestWall', [0.25, height, depth], [-width / 2 + 0.125, height / 2, 0]);
    if (type.id === 'T08') {
      // Original warehouse west breach becomes east after normalizing its +Z front to -Z.
      box('EastWallFront', [0.25, height, depth / 2 - 3], [width / 2 - 0.125, height / 2, (-depth / 2 - 3) / 2]);
      box('EastWallRear', [0.25, height, depth / 2 - 1], [width / 2 - 0.125, height / 2, (depth / 2 + 1) / 2]);
    } else box('EastWall', [0.25, height, depth], [width / 2 - 0.125, height / 2, 0]);
    box('RearWall', [width, height, 0.25], [0, height / 2, depth / 2 - 0.125]);
    const [doorWidth, doorHeight] = doorway;
    const flankWidth = (width - doorWidth) / 2;
    box('FrontLeft', [flankWidth, height, 0.25], [-(width + doorWidth) / 4, height / 2, -depth / 2 + 0.125]);
    box('FrontRight', [flankWidth, height, 0.25], [(width + doorWidth) / 4, height / 2, -depth / 2 + 0.125]);
    box('FrontLintel', [doorWidth, height - doorHeight, 0.25], [0, (height + doorHeight) / 2, -depth / 2 + 0.125]);
    if (!open) box('DoorSeal', [doorWidth, doorHeight, 0.25], [0, doorHeight / 2, -depth / 2 + 0.125], trimFinish);
    // Fitted doorway pieces replace the malformed independent Garage frame transforms.
    if (type.id === 'T06') {
      box('FrameLeft', [0.14, doorHeight, 0.12], [-doorWidth / 2 - 0.07, doorHeight / 2, -depth / 2 + 0.06], trimFinish);
      box('FrameRight', [0.14, doorHeight, 0.12], [doorWidth / 2 + 0.07, doorHeight / 2, -depth / 2 + 0.06], trimFinish);
      box('FrameLintel', [doorWidth + 0.28, 0.14, 0.12], [0, doorHeight + 0.07, -depth / 2 + 0.06], trimFinish);
    }
  }

  if (access === 'upper') {
    // Full opening above both flights and the turn; never reuse the sealed old C1-C4 slab.
    const slabY = 3.1;
    box('UpperFloorWest', [5, 0.2, depth], [-1.5, slabY, 0], floorFinish);
    box('UpperFloorEast', [0.4, 0.2, depth], [3.8, slabY, 0], floorFinish);
    box('UpperFloorFront', [2.6, 0.2, 8], [2.3, slabY, -4], floorFinish);
    box('UpperFloorRear', [2.6, 0.2, 4], [2.3, slabY, 6], floorFinish);
    for (let step = 0; step < 10; step++) {
      const lowerTop = (step + 1) * 0.16;
      box(`LowerStep_${step + 1}`, [1.2, lowerTop, 0.28], [1.6, lowerTop / 2, step * 0.28 + 0.14], floorFinish);
      const upperTop = 1.6 + (step + 1) * 0.16;
      box(`UpperStep_${step + 1}`, [1.2, upperTop - 1.6, 0.28], [3, (upperTop + 1.6) / 2, 2.8 - step * 0.28 - 0.14], floorFinish);
    }
    box('MidLanding', [2.6, 0.16, 1.2], [2.3, 1.52, 3.4], floorFinish);
    box('UpperGuardWest', [0.06, 1, 4], [0.97, 3.7, 2], trimFinish);
    box('UpperGuardEast', [0.06, 1, 4], [3.63, 3.7, 2], trimFinish);
    box('UpperGuardRear', [2.6, 1, 0.06], [2.3, 3.7, 4.03], trimFinish);
    box('UpperGuardFront', [1.2, 1, 0.06], [1.6, 3.7, -0.03], trimFinish);
  }

  if (access !== 'open') {
    if (type.id === 'T02' || type.id === 'T07') {
      const instance = external('res://Scene/Props/TownKit/metal_roof_8x8.tscn');
      const finish = external('res://Assets/Blender/TownKit/materials/town_roof_worn.tres', 'Material');
      for (let i = 0; i < 2; i++) nodes.push(`[node name="Roof_${i}" parent="Architecture" instance=${instance}]\nposition = ${vec([4, height, i * 8])}\nrotation = Vector3(0, 1.5707963, 0)\n`,
        `[node name="MetalRoof" parent="Architecture/Roof_${i}/TownMetalRoof" index="0"]\nsurface_material_override/0 = ${finish}\n`);
    } else {
      // Warehouse keeps the original 24x9m intact half and exposed opposite half.
      const roofDepth = type.id === 'T08' ? 9 : depth;
      const roofWidth = type.id === 'T08' ? 24 : width;
      const roofZ = type.id === 'T08' ? 4.5 : 0;
      box('RoofVisual', [roofWidth, 0.2, roofDepth], [0, height + 0.1, roofZ], roofFinish, false);
      if (type.id === 'T08') {
        box('ExposedTrussA', [24, 0.18, 0.18], [0, 7.05, -1.5], trimFinish, false);
        box('ExposedTrussB', [24, 0.18, 0.18], [0, 7.05, -6.5], trimFinish, false);
      }
    }
    const ceilingDepth = type.id === 'T08' ? 9 : depth;
    const ceilingWidth = type.id === 'T08' ? 24 : width;
    const ceilingZ = type.id === 'T08' ? 4.5 : 0;
    ceiling('CeilingUnderside', -ceilingWidth / 2, ceilingWidth / 2, ceilingZ - ceilingDepth / 2, ceilingZ + ceilingDepth / 2, height);
  }
  nodes.push('[node name="Markers" type="Node3D" parent="."]\n');
  if (open || access === 'open') {
    marker('GFEntry', [0, 0, -depth / 2 - 1.2]);
    marker('GFInterior', [0, 0, -depth / 2 + 1.2]);
  }
  if (access === 'upper') {
    marker('StairBottom', [1.6, 0, -0.8]);
    marker('FirstFlightTop', [1.6, 1.6, 3.35]);
    marker('MidLanding', [3, 1.6, 3.35]);
    marker('UpperLanding', [3, 3.2, -0.6]);
    marker('UpperInterior', [0, 3.2, -3]);
  }
  const extText = [...externals].map(([file, value]) => `[ext_resource type="${value.kind}" path="${file}" id="${value.id}"]\n`).join('\n');
  const output = `[gd_scene load_steps=${resources.length + externals.size + 1} format=3]\n\n${extText}\n${resources.join('\n')}\n${nodes.join('\n')}`;
  for (const file of externals.keys()) assert(fs.existsSync(path.join(project, file.slice(6))), file);
  for (const { name, size, position } of collisionBoxes) {
    assert(size.every(value => value > 0), `${filename}/${name}: positive size`);
    assert(Math.abs(position[0]) + size[0] / 2 <= width / 2 + 0.001, `${filename}/${name}: X bounds`);
    assert(Math.abs(position[2]) + size[2] / 2 <= depth / 2 + 0.001, `${filename}/${name}: Z bounds`);
  }
  function supportsPoint(point) {
    return collisionBoxes.some(box => Math.abs(box.position[1] + box.size[1] / 2 - point[1]) < 0.001 &&
      Math.abs(point[0] - box.position[0]) < box.size[0] / 2 && Math.abs(point[2] - box.position[2]) < box.size[2] / 2);
  }
  for (const [name, point] of Object.entries(markers)) {
    if (name !== 'GFEntry') assert(supportsPoint(point), `${filename}/${name}: floor support`);
  }
  if (access === 'upper') {
    const stairs = collisionBoxes.filter(box => box.name.startsWith('LowerStep_') || box.name.startsWith('UpperStep_'));
    assert.equal(stairs.length, 20);
    for (const step of stairs) {
      assert.equal(step.size[0], 1.2);
      const foot = [step.position[0], step.position[1] + step.size[1] / 2, step.position[2]];
      assert(supportsPoint(foot));
      // Standing 2.1m vertical clearance along each flight, including upper floor strips.
      for (const other of collisionBoxes) {
        if (Math.abs(foot[0] - other.position[0]) >= other.size[0] / 2 || Math.abs(foot[2] - other.position[2]) >= other.size[2] / 2) continue;
        const bottom = other.position[1] - other.size[1] / 2;
        assert(bottom >= foot[1] + 2.1 - 0.001 || other.position[1] + other.size[1] / 2 <= foot[1] + 0.001, `${filename}/${step.name}: headroom at ${other.name}`);
      }
      assert(height - foot[1] >= 2.1);
    }
  }
  if (open && !modular) {
    const [doorWidth, doorHeight] = doorway;
    assert(doorWidth >= 1.2 && doorHeight >= 2.4);
    assert(!collisionBoxes.some(box => Math.abs(box.position[0]) < box.size[0] / 2 - 0.001 &&
      Math.abs(-depth / 2 + 0.125 - box.position[2]) < box.size[2] / 2 &&
      box.position[1] - box.size[1] / 2 < 2.4 - 0.001 && box.position[1] + box.size[1] / 2 > 0.001), `${filename}: clear central doorway`);
  }
  if (checkOnly) assert.equal(fs.readFileSync(path.join(sceneDir, filename), 'utf8'), output, `${filename}: matches offline source`);
  else fs.writeFileSync(path.join(sceneDir, filename), output);
  manifest.push({ type: type.id, scene: `res://Scene/Props/TownKit/Buildings/${filename}`, footprint_m: [width, depth], access, floors, height_m: height, markers, collision: 'fitted walls/floors/steps layer1; visual roof has no collision; ceiling downward one-sided', native_verified: false });
}

fs.mkdirSync(sceneDir, { recursive: true });
for (const type of layout.types) {
  const access = type.id === 'T02' ? 'upper' : ['T03','T10','T11','T13'].includes(type.id) ? 'shell' : type.id === 'T12' ? 'open' : 'ground';
  createScene(type, access, type.floors, `${type.id.toLowerCase()}_${type.type}.tscn`);
  if (['T01','T07','T09'].includes(type.id)) createScene(type, 'shell', type.floors, `${type.id.toLowerCase()}_${type.type}_shell.tscn`);
  if (type.id === 'T02') createScene(type, 'ground', 1, 't02_long_house_ground.tscn');
}
assert.equal(new Set(manifest.map(item => item.type)).size, 14);
assert.equal(manifest.length, 18);
const assigned = layout.buildings.map(building => {
  const template = manifest.find(item => item.type === building.type && item.access === building.access && item.floors === building.floors);
  assert(template, `${building.id}: access/floor variant exists`);
  return { id: building.id, scene: template.scene };
});
assert.equal(assigned.length, 33);
assert.equal(layout.buildings.filter(item => ['ground', 'upper'].includes(item.access)).length, 17);
assert.equal(layout.buildings.filter(item => item.access === 'upper').length, 4);
const report = JSON.stringify({ coordinates: 'metres; floor-centred origin; front -Z; GF0; upper3.2; root world pad+.2', templates: manifest, instances: assigned, stair_contract: { opening_xz: [1, 3.6, 0, 4], width_m: 1.2, landing_m: 1.2, riser_m: 0.16, tread_m: 0.28, risers: 20, upper_y: 3.2, minimum_clear_headroom_m: 3.2, native_controller_check: 'pending primary; existing Cogito stair stepping; no hidden ramps' } }, null, 2) + '\n';
const manifestPath = path.join(__dirname, 'building_contract.json');
if (checkOnly) assert.equal(fs.readFileSync(manifestPath, 'utf8'), report);
else fs.writeFileSync(manifestPath, report);
console.log(`PASS static contracts: 14 types / 18 scenes / 33 mappings / 17 ground / 4 upper. Native load, nav and physical traversal pending.`);
