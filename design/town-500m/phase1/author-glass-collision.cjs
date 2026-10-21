'use strict';
// Offline authoring only; preserves imported visual paths and fitted source bounds.
const fs = require('fs');
const path = require('path');
const assert = require('assert/strict');
const project = path.resolve(__dirname, '../../..');
const check = process.argv.includes('--check');
const vector = values => `Vector3(${values.map(value => Number(value.toFixed(6))).join(', ')})`;
const box = (name, min, max) => ({name, size: max.map((value, i) => value - min[i]), centre: min.map((value, i) => (value + max[i]) / 2)});
const fitted = (name, centre, size) => ({name, centre, size});

function scene(asset, root, mesh, opaque, panes, ceiling = '') {
  const resources = [];
  const nodes = [];
  function shapes(body, boxes) {
    for (const item of boxes) {
      assert(item.size.every(value => Number.isFinite(value) && value > 0));
      assert(item.centre.every(Number.isFinite));
      const id = `${body}_${item.name}`;
      resources.push(`[sub_resource type="BoxShape3D" id="${id}"]\nsize = ${vector(item.size)}`);
      nodes.push(`[node name="${item.name}" type="CollisionShape3D" parent="${body}"]\nposition = ${vector(item.centre)}\nshape = SubResource("${id}")`);
    }
  }
  nodes.push('[node name="OpaqueCollision" type="StaticBody3D" parent="."]\nprocess_mode = 3\ncollision_layer = 1\ncollision_mask = 0');
  shapes('OpaqueCollision', opaque);
  if (ceiling) {
    resources.push(`[sub_resource type="ConcavePolygonShape3D" id="ceiling"]\ndata = PackedVector3Array(${ceiling})\nbackface_collision = false`);
    nodes.push('[node name="Ceiling" type="CollisionShape3D" parent="OpaqueCollision"]\nshape = SubResource("ceiling")');
  }
  for (const pane of panes) {
    nodes.push(`[node name="${pane.name}" type="StaticBody3D" parent="." groups=["ai_vision_transparent"]]\nprocess_mode = 3\ncollision_layer = 1\ncollision_mask = 0`);
    shapes(pane.name, [{...pane, name: 'Shape'}]);
  }
  return `[gd_scene load_steps=${resources.length + 3} format=3]\n\n` +
    `[ext_resource type="PackedScene" path="res://Assets/Blender/TownKit/assets/${asset}.glb" id="1_model"]\n` +
    '[ext_resource type="Material" path="res://Assets/Blender/TownKit/materials/town_architecture_clean.tres" id="2_finish"]\n\n' +
    resources.join('\n\n') + '\n\n' +
    // Imported combined helpers have unstable generated names. Disabled visuals remove
    // their physics, while explicit ALWAYS bodies below retain only the fitted shapes.
    `[node name="${root}" instance=ExtResource("1_model")]\nprocess_mode = 4\n\n` +
    `[node name="${mesh}" parent="${root}" index="0"]\nsurface_material_override/0 = ExtResource("2_finish")\n\n` +
    nodes.join('\n\n') + '\n';
}

const windowOpaque = [
  box('WestWall', [0,0,0], [1.2,3.2,.244]), box('EastWall', [2.8,0,0], [4,3.2,.244]),
  box('SillWall', [1.2,0,0], [2.8,1.05,.244]), box('LintelWall', [1.2,2.4,0], [2.8,3.2,.244]),
  fitted('LeftFrame', [1.235,1.725,.155], [.07,1.35,.13]), fitted('RightFrame', [2.765,1.725,.155], [.07,1.35,.13]),
  fitted('LowerFrame', [2,1.085,.155], [1.46,.07,.13]), fitted('UpperFrame', [2,2.365,.155], [1.46,.07,.13]),
  fitted('Mullion', [2,1.725,.155], [.045,1.21,.115]),
];
const boothOpaque = [
  box('Floor', [-.15,0,-2.85], [2.85,.08,.15]),
  box('FrontWest', [-.15,.08,0], [.75,3.04,.15]), box('FrontEast', [1.95,.08,0], [2.85,3.04,.15]), box('FrontLintel', [.75,2.48,0], [1.95,3.04,.15]),
  box('LeftFront', [-.15,.08,-.55], [0,3.04,0]), box('LeftSill', [-.15,.08,-2.15], [0,1.05,-.55]),
  box('LeftLintel', [-.15,2.45,-2.15], [0,3.04,-.55]), box('LeftRear', [-.15,.08,-2.7], [0,3.04,-2.15]),
  box('RightFront', [2.7,.08,-.55], [2.85,3.04,0]), box('RightSill', [2.7,.08,-2.15], [2.85,1.05,-.55]),
  box('RightLintel', [2.7,2.45,-2.15], [2.85,3.04,-.55]), box('RightRear', [2.7,.08,-2.7], [2.85,3.04,-2.15]),
  box('RearWest', [0,.08,-2.85], [.55,3.04,-2.7]), box('RearSill', [.55,.08,-2.85], [2.15,1.05,-2.7]),
  box('RearLintel', [.55,2.45,-2.85], [2.15,3.04,-2.7]), box('RearEast', [2.15,.08,-2.85], [2.7,3.04,-2.7]),
];
for (const [name, centre, size] of [
  ['LeftFrame',[.585,1.75,.07],[.07,1.4,.12]], ['RightFrame',[2.115,1.75,.07],[.07,1.4,.12]],
  ['LowerFrame',[1.35,1.085,.07],[1.46,.07,.12]], ['UpperFrame',[1.35,2.415,.07],[1.46,.07,.12]], ['Mullion',[1.35,1.75,.06],[.04,1.26,.10]],
]) {
  const [x,y,z] = centre;
  boothOpaque.push(fitted(`Left_${name}`, [-z,y,-x], [size[2],size[1],size[0]]));
  boothOpaque.push(fitted(`Right_${name}`, [2.7+z,y,-x], [size[2],size[1],size[0]]));
  boothOpaque.push(fitted(`Rear_${name}`, [x,y,-2.7-z], size));
}
const outputs = {
  facade_window_4m: scene('facade_window_4m', 'TownFacadeWindow', 'FacadeWindow', windowOpaque,
    [box('GlassPane', [1.278,1.123,.105], [2.722,2.327,.117])]),
  guard_booth_3m: scene('guard_booth_3m', 'TownGuardBooth', 'GuardBooth', boothOpaque, [
    box('GlassLeft', [-.027,1.0875,-2.0775], [-.015,2.4125,-.6225]),
    box('GlassRight', [2.715,1.0875,-2.0775], [2.727,2.4125,-.6225]),
    box('GlassRear', [.6225,1.0875,-2.727], [2.0775,2.4125,-2.715]),
  ], '0,3.04,-2.7, 2.7,3.04,0, 2.7,3.04,-2.7, 0,3.04,-2.7, 0,3.04,0, 2.7,3.04,0'),
};
assert.equal(windowOpaque.length, 9);
assert.equal(boothOpaque.length, 31);
for (const [name, content] of Object.entries(outputs)) {
  const target = path.join(project, 'Scene/Props/TownKit', `${name}.tscn`);
  if (check) assert.equal(fs.readFileSync(target, 'utf8').replace(/\r\n/g, '\n'), content, `${name}: authored collider scene differs`);
  else fs.writeFileSync(target, content);
}
console.log(`Glass wrapper ${check ? 'check' : 'author'}: PASS (two modules; one/three separate panes; opaque frames)`);
