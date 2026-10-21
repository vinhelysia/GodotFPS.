// Offline editable graybox authoring: node design/town-500m/phase3/author-outer-pois.cjs [--check]
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../..');
const design = path.resolve(__dirname, '..');
const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const catalogue = read(path.join(design, 'building-catalogue.json'));
const buildingContract = read(path.join(root, 'Assets/TownConceptB/Buildings/building_contract.json'));
const zones = ['industry', 'bunker', 'hills', 'forest', 'farmland', 'lake'];
const structures = catalogue.structures.filter(s => zones.includes(s.zone_id));
const pending = structures.filter(s => !s.scene_ref);
const reused = structures.filter(s => s.scene_ref);
const outputs = new Map();
const num = n => Number(n.toFixed(9)).toString();
const vector = a => `Vector3(${a.map(num).join(', ')})`;
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const families = new Map();
assert.equal(structures.length, 44);
assert.equal(reused.length, 22);
assert.equal(pending.length, 22);
assert.equal(new Set(structures.map(s => s.id)).size, 44);
assert(structures.every(s => !['R01', 'R02', 'L03'].includes(s.source_ref)));

function grayboxScene(s) {
    const [width, depth] = s.footprint_m, height = s.height_m;
    const resources = ['[sub_resource type="StandardMaterial3D" id="graybox"]\nalbedo_color = Color(0.39, 0.41, 0.37, 1)\nroughness = 1.0'];
    const nodes = [`[node name="${s.kind}" type="Node3D"]\nmetadata/graybox = true\nmetadata/finished_art = false\nmetadata/footprint_m = Vector2(${num(width)}, ${num(depth)})\nmetadata/height_m = ${num(height)}\nmetadata/ground_access = ${s.access.ground}\nmetadata/upper_access = false\n\n[node name="Architecture" type="Node3D" parent="."]`];
    let closedShapes = 0;
    // Closed physics prevents top-down entry; primary removes sealed rooftop nav after baking.
    function box(name, size, position) {
        assert(size.every(n => n > 0));
        resources.push(`[sub_resource type="BoxMesh" id="${name}_mesh"]\nmaterial = SubResource("graybox")\nsize = ${vector(size)}`);
        resources.push(`[sub_resource type="BoxShape3D" id="${name}_shape"]\nsize = ${vector(size)}`);
        closedShapes++;
        nodes.push(`[node name="${name}" type="StaticBody3D" parent="Architecture"]\nposition = ${vector(position)}\ncollision_layer = 1\ncollision_mask = 0\n\n[node name="Mesh" type="MeshInstance3D" parent="Architecture/${name}"]\nmesh = SubResource("${name}_mesh")\n\n[node name="Collision" type="CollisionShape3D" parent="Architecture/${name}"]\nshape = SubResource("${name}_shape")`);
    }
    if (s.kind === 'bunker_entry') {
        assert.deepEqual([width, depth, height, s.yaw_deg], [8, 8, 3.6, 180]);
        const wall = 0.25, clearHeight = 3.2, doorWidth = 1.2, doorHeight = 2.4;
        const frontWidth = (width - doorWidth) / 2;
        box('GroundFloor', [width, 0.2, depth], [0, -0.1, 0]);
        box('WestWall', [wall, clearHeight, depth], [-width / 2 + wall / 2, clearHeight / 2, 0]);
        box('EastWall', [wall, clearHeight, depth], [width / 2 - wall / 2, clearHeight / 2, 0]);
        box('RearSeal', [width, clearHeight, wall], [0, clearHeight / 2, depth / 2 - wall / 2]);
        box('FrontLeft', [frontWidth, clearHeight, wall], [-(width + doorWidth) / 4, clearHeight / 2, -depth / 2 + wall / 2]);
        box('FrontRight', [frontWidth, clearHeight, wall], [(width + doorWidth) / 4, clearHeight / 2, -depth / 2 + wall / 2]);
        box('FrontLintel', [doorWidth, clearHeight - doorHeight, wall], [0, (doorHeight + clearHeight) / 2, -depth / 2 + wall / 2]);
        box('Roof', [width, 0.2, depth], [0, clearHeight + 0.1, 0]);
        assert(Math.abs(width - frontWidth * 2 - doorWidth) < 1e-9);
        assert(Math.abs(clearHeight - (clearHeight - doorHeight) - doorHeight) < 1e-9);
        assert(Math.abs(clearHeight + 0.2 + 0.2 - height) < 1e-9);
        nodes.push('[node name="Markers" type="Node3D" parent="."]\n\n[node name="GFEntry" type="Marker3D" parent="Markers"]\nposition = Vector3(0, 0, -5.2)\n\n[node name="GFInterior" type="Marker3D" parent="Markers"]\nposition = Vector3(0, 0, -2.8)\n\n[node name="DoorThreshold" type="Marker3D" parent="Markers"]\nposition = Vector3(0, 0, -4)\n\n[node name="DeepRearSealed" type="Marker3D" parent="Markers"]\nposition = Vector3(0, 0, 3.75)');
    } else {
        assert.equal(s.access.ground, false);
        assert.equal(s.access.upper, false);
        box('SolidShell', [width, height, depth], [0, height / 2 - 0.2, 0]);
    }
    assert.equal(closedShapes, s.kind === 'bunker_entry' ? 8 : 1);
    assert(resources.filter(r => r.startsWith('[sub_resource type="BoxShape3D"')).length === closedShapes);
    assert(!resources.some(r => r.includes('ConcavePolygonShape3D')));
    return `[gd_scene load_steps=${resources.length + 1} format=3]\n\n${resources.join('\n\n')}\n\n${nodes.join('\n\n')}\n`;
}

for (const s of pending) {
    const dimensions = [...s.footprint_m, s.height_m];
    if (families.has(s.kind)) assert.deepEqual(families.get(s.kind).dimensions_m, dimensions);
    else families.set(s.kind, {dimensions_m: dimensions, scene_ref: `res://Scene/World/Town500m/Graybox/${s.kind}.tscn`, ids: []});
    families.get(s.kind).ids.push(s.id);
}
assert.equal(families.size, 13);
for (const family of families.values()) {
    const sample = pending.find(s => s.id === family.ids[0]);
    outputs.set(family.scene_ref.slice(6), grayboxScene(sample));
}

const placements = [];
for (const zone of zones) {
    const members = structures.filter(s => s.zone_id === zone);
    const sceneRefs = [...new Set(members.map(s => s.scene_ref || families.get(s.kind).scene_ref))];
    const external = sceneRefs.map((ref, i) => `[ext_resource type="PackedScene" path="${ref}" id="${i + 1}"]`);
    const nodes = [`[node name="${zone}" type="Node3D"]\nmetadata/town500_zone = "${zone}"\nmetadata/phase = 3`];
    for (const s of members) {
        const ref = s.scene_ref || families.get(s.kind).scene_ref;
        const pad = s.pad_intent.surface_y_m, offset = s.pad_intent.root_above_pad_m;
        assert.equal(offset, 0.2);
        const position = [s.position_xz_m[0], pad + offset, s.position_xz_m[1]];
        const a = s.yaw_deg * Math.PI / 180, c = Math.cos(a), sin = Math.sin(a);
        for (const x of [-s.footprint_m[0] / 2, s.footprint_m[0] / 2]) {
            for (const z of [-s.footprint_m[1] / 2, s.footprint_m[1] / 2]) {
                assert(Math.abs(position[0] + c * x + sin * z) < 250);
                assert(Math.abs(position[2] - sin * x + c * z) < 250);
            }
        }
        let templateEvidence = null;
        if (s.scene_ref) {
            const contract = buildingContract.templates.find(t => t.scene === s.scene_ref);
            assert(contract, s.scene_ref);
            assert.deepEqual(contract.footprint_m, s.footprint_m);
            assert.equal(contract.height_m, s.height_m);
            const live = fs.readFileSync(path.join(root, ref.slice(6)), 'utf8');
            assert(live.includes('position = Vector3(0, -0.1, 0)'), 'Floor slab must extend to pad');
            assert(live.includes('size = Vector3(' + s.footprint_m[0] + ', 0.2, ' + s.footprint_m[1] + ')'));
            assert(live.includes('backface_collision = false'));
            if (s.access.ground) {
                assert(contract.markers.GFEntry);
                assert(live.includes('name="GFEntry" type="Marker3D"'));
            } else assert(!live.includes('name="GFEntry" type="Marker3D"'));
            templateEvidence = {sha256: hash(path.join(root, ref.slice(6))), floor_top_local_y_m: 0, floor_bottom_local_y_m: -0.2, approach_local_m: contract.markers.GFEntry || null};
        }
        nodes.push(`[node name="${s.id}" parent="." instance=ExtResource("${sceneRefs.indexOf(ref) + 1}")]\nposition = ${vector(position)}\nrotation = Vector3(0, ${num(a)}, 0)\nmetadata/town500_id = "${s.id}"\nmetadata/source_ref = "${s.source_ref}"\nmetadata/zone = "${zone}"\nmetadata/ground_access = ${s.access.ground}\nmetadata/upper_access = ${s.access.upper}\nmetadata/pad_surface_y_m = ${num(pad)}\nmetadata/graybox = ${!s.scene_ref}`);
        placements.push({id: s.id, source_ref: s.source_ref, zone, scene_ref: ref, reused_template: Boolean(s.scene_ref), position_m: position, yaw_deg: s.yaw_deg, scale: [1, 1, 1], footprint_m: s.footprint_m, height_m: s.height_m, pad_surface_y_m: pad, ground_contact_y_m: pad, access: s.access, template_evidence: templateEvidence});
    }
    outputs.set(`Scene/World/Town500m/POI/${zone}.tscn`, `[gd_scene load_steps=${sceneRefs.length + 1} format=3]\n\n${external.join('\n')}\n\n${nodes.join('\n\n')}\n`);
}

const report = {
    status: 'OFFLINE_AUTHORING_PASS_NATIVE_PENDING',
    source_sha256: {'building-catalogue.json': hash(path.join(design, 'building-catalogue.json')), 'terrain-contract.json': hash(path.join(design, 'terrain-contract.json'))},
    totals: {instances: 44, reused_templates: 22, pending_graybox_instances: 22, graybox_families: 13, zone_scenes: 6},
    floor_convention: 'Unit root = canonical pad + 0.2m. Reused room floor localY=-0.2..0; new primitive overall bounds localY=-0.2..height-0.2, exact physical overall height, bottom touches pad.',
    bunker_entry: {id: 'B04-ENTRY', dimensions_m: [8, 8, 3.6], clear_room_xz_m: [7.5, 7.5], clear_ceiling_m: 3.2, door_clear_m: [1.2, 2.4], local_front: '-Z', world_front: 'south', floor_y_m: 10.2, ceiling_collision: 'closed BoxShape3D roof slab; top and underside solid', deep_rear: 'full solid wall; no transition'},
    closed_collision: 'Every pending solid uses a closed BoxShape3D matching its BoxMesh. Entry uses eight closed boxes for floor, walls, lintel and roof, leaving only its actual south doorway. This prevents top-down entry into hollow proxies, including the low F04 crate.',
    navigation_gate: 'Closed boxes can produce rooftop navigation polygons. Primary must inspect the native bake and remove any sealed rooftop polygons using catalogue footprints and physical ceiling bounds; physics closure is not sacrificed to suppress navigation.',
    finished_reuse_audit: {
        files: ['C:/Stuff/Blender/TownKit/asset_manifest.json', 'C:/Stuff/Blender/BunkerKit/asset_manifest.json'],
        finding: 'Inspected live manifests before authoring. TownKit release covers architecture/circulation/booth/barrier/lamp; BunkerKit wood_crate is1x0.91x0.99m, incompatible with approved F04 1.2x0.8x0.75m. No exact pending-family match; retained dimensioned grayboxes, no scaled finished art or whole-kit copy.'
    },
    families: Object.fromEntries(families),
    placements,
    limits: ['Native import/physics/rays/navigation/player traversal and visual review owned by primary and not run by this authoring worker.', 'Sealed roofs can generate rooftop nav; primary native bake inspection/filter and F04 jump/step checks remain required.', 'Primitives are dimensioned graybox cover silhouettes, not finished assets or approved art triangle budgets.', 'Reusable template height is its existing wall-height contract; roof/trim native bounds and new placement acceptance remain primary checks.', 'No terrain-owned R01/R02/dock, gameplay, teleport, scripts, Town merge, settings, shared templates or canonical data were edited.'],
    output_sha256: Object.fromEntries([...outputs].map(([file, data]) => [file, crypto.createHash('sha256').update(data).digest('hex')]))
};
outputs.set('design/town-500m/phase3/outer-placement-report.json', JSON.stringify(report, null, 2) + '\n');
outputs.set('design/town-500m/phase3/outer-handoff.txt', `Town500m Phase3 outer POI handoff\nOFFLINE AUTHORING PASS; NATIVE PENDING\n\nSix entry payloads: res://Scene/World/Town500m/POI/{industry,bunker,hills,forest,farmland,lake}.tscn\nExact44 non-town catalogue placements:22 existing templates +22 dimensioned pending graybox instances in13 shared native primitive scenes. Identity payload roots; unit instance scales; canonical XZ/yaw and pad+.2m roots.\n\nB04-ENTRY is8x8x3.6m physical outer bounds,7.5x7.5m clear room,3.2m clear ceiling; south-facing1.2x2.4m door (local-Z), floor surfaceY10.2m, rear fully sealed. GFEntry=(0,0,-5.2), GFInterior=(0,0,-2.8), actual threshold=(0,0,-4). No teleport, underground or gameplay.\nPending grayboxes use closed BoxShape3D volumes matching the visual primitives. B04 floor, walls, lintel and roof are closed boxes; its south doorway is the only passage. Top-down capsule entry cannot enter hollow proxy interiors. Tall landmarks have no authored stairs or ladders. Closed tops may generate rooftop nav polygons; primary must inspect/filter native bake polygons using catalogue footprints and physical ceiling bounds. Physics closure is retained. Exact overall height includes the.2m below-root base; contact at pad. Reused templates preserve their own floor/roof contract.\n\nChecks: node design/town-500m/phase3/author-outer-pois.cjs --check\nAsserts44/22/22 counts,13 families, template dimensions/height/floor/markers, unit pad offsets, world footprint bounds, no R01/R02/L03 duplicate, closed BoxShape3D for every pending body (eight entry boxes, one other-family box), no concave pending shell and exact entry doorway. Deterministic outputs are byte checked.\nReport: design/town-500m/phase3/outer-placement-report.json (all placements, template hashes, dimensions and output hashes).\n\nInspected live TownKit/BunkerKit finished manifests: no exact pending family match. BunkerKit wood_crate dimensions differ from F04; no unauthorized rescale/import. Primitive art is intentionally temporary.\nPrimary must merge into existing Town, import/inspect native scenes, bake navigation, ray-test sides/top/underside and rear seal, jump/step-test F04, remove any sealed rooftop nav polygons after native bake, walk entry/ground structures and check actual art bounds. This worker did not call Godot MCP or launch Godot. No Town/shared-template/terrain/settings/canonical-data edits, commit or push.\n`);

for (const [file, contents] of outputs) {
    const absolute = path.join(root, file);
    if (process.argv.includes('--check')) assert.equal(fs.readFileSync(absolute, 'utf8'), contents, `Stale output: ${file}`);
    else {
        fs.mkdirSync(path.dirname(absolute), {recursive: true});
        fs.writeFileSync(absolute, contents);
    }
}
console.log(`Outer POI ${process.argv.includes('--check') ? 'CHECK' : 'AUTHOR'} PASS:44 instances,22 reuse,22 pending,13 primitive families,6 zones; native pending.`);
