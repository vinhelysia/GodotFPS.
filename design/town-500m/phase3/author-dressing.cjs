const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {applyProposal} = require('./check-phase3-los.cjs');
const {check, rectangle, edges, distance, segmentPolygon, polygonDistance} = require('../check-layout.cjs');
const terrain = require('../phase2/terrain-authoring.cjs');
const source = path.join(__dirname, '..');
const root = path.resolve(source, '..', '..');
const output = path.join(root, 'Scene/World/Town500m/Dressing');
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const num = n => Number(n.toFixed(6));
const v3 = values => `Vector3(${values.map(num).join(', ')})`;
const idFor = id => id.replace(/[^a-zA-Z0-9_]/g, '_');

function wallSegments(cover, ground, grid = false) {
    assert(cover.size_xyz_m.every(n => Number.isFinite(n) && n > 0), `Invalid wall dimensions ${cover.id}`);
    const major = cover.size_xyz_m[0] >= cover.size_xyz_m[2] ? 0 : 2;
    const minor = major === 0 ? 2 : 0;
    const maximumSpan = grid && !cover.solid ? .3 : 1;
    const length = cover.size_xyz_m[major], count = Math.ceil(length / maximumSpan), span = length / count;
    const rows = grid ? Math.ceil(cover.size_xyz_m[minor] / maximumSpan) : 1, depth = cover.size_xyz_m[minor] / rows;
    assert(span <= 1, `Wall segment exceeds 1m ${cover.id}`);
    const yaw = cover.yaw_deg * Math.PI / 180, segments = [];
    for (let index = 0; index < count * rows; index++) {
        const local = [0, 0, 0], size = [...cover.size_xyz_m];
        local[major] = -length / 2 + (index % count + .5) * span; size[major] = span;
        local[minor] = -cover.size_xyz_m[minor] / 2 + (Math.floor(index / count) + .5) * depth; size[minor] = depth;
        const center = [cover.position_xz_m[0] + local[0] * Math.cos(yaw) + local[2] * Math.sin(yaw), cover.position_xz_m[1] - local[0] * Math.sin(yaw) + local[2] * Math.cos(yaw)];
        const corners = rectangle(center, [size[0], size[2]], cover.yaw_deg);
        const samplePoints = [center, ...corners, ...edges([...corners, corners[0]]).map(([a, b]) => a.map((n, k) => (n + b[k]) / 2))];
        const samples = samplePoints.map(ground);
        assert(samples.every(Number.isFinite), `Invalid wall terrain sample ${cover.id}/${index}`);
        const base = Math.min(...samples) - .03, top = Math.max(...samples) + cover.size_xyz_m[1];
        size[1] = top - base;
        const exposed = base + size[1] - Math.max(...samples);
        assert(exposed >= Math.min(2, cover.size_xyz_m[1]) - 1e-6, `Insufficient wall exposure ${cover.id}/${index}`);
        segments.push({index, local_center: local, center_xz_m: center, size_xyz_m: size, base_y_m: base, ground_range_y_m: samples, sample_points_xz_m: samplePoints, minimum_exposed_height_m: exposed});
    }
    return segments;
}

function checkWallSegments() {
    for (const size of [[3.4, 2.6, .3], [.3, 1.4, 3.4]]) for (const yaw of [0, 37, 90]) {
        const cover = {id: 'self_check', size_xyz_m: size, position_xz_m: [12, -8], yaw_deg: yaw};
        const segments = wallSegments(cover, ([x, z]) => x * .2 - z * .3);
        assert.equal(segments.length, 4);
        const major = size[0] >= size[2] ? 0 : 2;
        assert(Math.abs(segments.reduce((n, s) => n + s.size_xyz_m[major], 0) - size[major]) < 1e-6);
        for (const segment of segments) {
            assert(segment.base_y_m < Math.min(...segment.ground_range_y_m));
            assert(segment.minimum_exposed_height_m >= size[1] - 1e-6);
        }
    }
    const gridCover = {id: 'grid_check', solid: true, size_xyz_m: [3, 2.3, 2.4], position_xz_m: [12, -8], yaw_deg: 37};
    const cells = wallSegments(gridCover, ([x, z]) => x * .2 - z * .3, true);
    assert.equal(cells.length, 9);
    assert(Math.abs(cells.reduce((area, cell) => area + cell.size_xyz_m[0] * cell.size_xyz_m[2], 0) - 7.2) < 1e-6);
    for (const cell of cells) {
        assert(Math.max(cell.size_xyz_m[0], cell.size_xyz_m[2]) <= 1);
        assert(cell.minimum_exposed_height_m >= 2.3 - 1e-6);
    }
    assert.throws(() => wallSegments({id: 'invalid', size_xyz_m: [2, 2, .3], position_xz_m: [0, 0], yaw_deg: 0}, () => NaN), /Invalid wall terrain sample/);
}

function visualConformanceObj(cover, segments, base) {
    const vertices = [], faces = [], yaw = cover.yaw_deg * Math.PI / 180;
    for (const segment of segments) {
        const offset = vertices.length, perimeter = [1, 5, 2, 6, 3, 7, 4, 8];
        const vertex = (index, y) => {
            const point = segment.sample_points_xz_m[index], x = point[0] - cover.position_xz_m[0], z = point[1] - cover.position_xz_m[1];
            return [x * Math.cos(yaw) - z * Math.sin(yaw), y - base, x * Math.sin(yaw) + z * Math.cos(yaw)];
        };
        vertices.push(...perimeter.map(index => vertex(index, segment.base_y_m)));
        vertices.push(...perimeter.map(index => vertex(index, segment.ground_range_y_m[index] + cover.size_xyz_m[1])));
        vertices.push(vertex(0, segment.ground_range_y_m[0] + cover.size_xyz_m[1]));
        const face = (...indices) => faces.push(indices.map(index => offset + index + 1));
        for (let i = 0; i < 8; i++) {
            const next = (i + 1) % 8;
            face(16, next + 8, i + 8);
            face(i, i + 8, next + 8); face(i, next + 8, next);
        }
        for (let i = 1; i < 7; i++) face(0, i, i + 1);
        for (let i = 0; i < 8; i++) assert(Math.abs(vertices[offset + i + 8][1] + base - segment.ground_range_y_m[perimeter[i]] - cover.size_xyz_m[1]) < 1e-6);
    }
    const edgeCounts = new Map();
    for (const face of faces) {
        assert(face.every(index => index > 0 && index <= vertices.length));
        for (const [a, b] of edges([...face, face[0]])) {const key = [a, b].sort((x, y) => x - y).join(':'); edgeCounts.set(key, (edgeCounts.get(key) || 0) + 1);}
    }
    assert([...edgeCounts.values()].every(count => count === 2), `Open visual cell ${cover.id}`);
    return `o ${idFor(cover.id)}\n${vertices.map(vertex => `v ${vertex.map(num).join(' ')}`).join('\n')}\n${faces.map(face => `f ${face.join(' ')}`).join('\n')}\n`;
}

function build(checkOnly = false) {
    checkWallSegments();
    const original = JSON.parse(fs.readFileSync(path.join(source, 'layout.json')));
    const proposal = JSON.parse(fs.readFileSync(path.join(__dirname, 'dressing-proposal.json')));
    const layout = applyProposal(original, proposal);
    const spatial = check(layout);
    assert.equal(spatial.status, 'PASS', spatial.errors.join('\n'));
    const canonical = original.dressing.cover.filter(c => /^C\d{2}-\d{2}$/.test(c.id));
    assert.equal(canonical.length, 64, 'Canonical cover count changed');
    assert.equal(original.dressing.vegetation.length, 93, 'Canonical vegetation count changed');
    assert.equal(new Set(layout.dressing.cover.map(c => c.id)).size, layout.dressing.cover.length);
    const canonicalIds = new Set(canonical.map(c => c.id));
    assert.deepEqual(layout.dressing.cover.filter(c => canonicalIds.has(c.id)), canonical, 'Canonical cover changed');
    assert.deepEqual(layout.dressing.vegetation, original.dressing.vegetation, 'Canonical vegetation changed');
    for (const cover of layout.dressing.cover.filter(c => !canonicalIds.has(c.id))) {
        if (cover.allow_rail_overlap === true) continue;
        const shape = rectangle(cover.position_xz_m, [cover.size_xyz_m[0], cover.size_xyz_m[2]], cover.yaw_deg);
        for (const rail of layout.corridors.filter(c => c.type === 'rail')) assert(Math.min(...edges(rail.points_xz_m).map(([a, b]) => segmentPolygon(a, b, shape))) - rail.width_m / 2 >= .5 - 1e-6, `${cover.id} blocks rail reservation`);
    }
    const ground = ([x, z]) => {const y = terrain.heightAt(x, z); assert(Number.isFinite(y), `No dry terrain at ${x},${z}`); return y;};
    const materials = {
        concrete: [.39, .4, .36, 1], wood: [.38, .28, .18, 1], vehicle: [.26, .3, .27, 1],
        rock: [.36, .36, .32, 1], sandbag: [.48, .43, .29, 1], hay: [.52, .45, .26, 1],
        trunk: [.24, .19, .14, 1], pine: [.2, .28, .2, 1], orchard: [.34, .3, .2, 1], wire: [.42, .45, .4, .2]
    };
    const resources = Object.entries(materials).map(([id, colour]) => `[sub_resource type="StandardMaterial3D" id="mat_${id}"]\nalbedo_color = Color(${colour.join(', ')})\nroughness = 1${id === 'wire' ? '\ntransparency = 1\ncull_mode = 2' : ''}`);
    const nodes = [], heights = [], fences = [], visualFiles = [];
    const externalResources = ['[ext_resource type="PackedScene" path="res://Scene/Props/BunkerKit/wood_pallet.tscn" id="pallet"]'];
    if (!checkOnly) fs.mkdirSync(output, {recursive: true});
    let resourceCount = resources.length;
    const addResource = (type, id, properties) => {resources.push(`[sub_resource type="${type}" id="${id}"]\n${properties}`); resourceCount++;};
    const box = (name, parent, size, position, material, collision = true) => {
        const id = idFor(`${parent}_${name}`), mesh = `mesh_${id}`, shape = `shape_${id}`;
        addResource('BoxMesh', mesh, `size = ${v3(size)}\nmaterial = SubResource("mat_${material}")`);
        nodes.push(`[node name="${name}" type="MeshInstance3D" parent="${parent}"]\nposition = ${v3(position)}\nmesh = SubResource("${mesh}")`);
        if (collision) {
            addResource('BoxShape3D', shape, `size = ${v3(size)}`);
            const transparent = material === 'wire';
            nodes.push(`[node name="Body" type="StaticBody3D" parent="${parent}/${name}"${transparent ? ' groups=["ai_vision_transparent"]' : ''}]\ncollision_layer = 1\ncollision_mask = 0${transparent ? '\nmetadata/concept_b_los_transparent = true\nmetadata/town500_los_transparent = true' : ''}\n\n[node name="Shape" type="CollisionShape3D" parent="${parent}/${name}/Body"]\nshape = SubResource("${shape}")`);
        }
    };
    nodes.push('[node name="HardCover" type="Node3D" parent="."]');
    for (const cover of layout.dressing.cover) {
        const name = idFor(cover.id), parent = `HardCover/${name}`;
        const footprint = rectangle(cover.position_xz_m, [cover.size_xyz_m[0], cover.size_xyz_m[2]], cover.yaw_deg);
        const samples = [cover.position_xz_m, ...footprint].map(ground), base = Math.min(...samples) - .03;
        const originalExposure = base + cover.size_xyz_m[1] - Math.max(...samples);
        const correctBuried = !cover.grounding && originalExposure < 0;
        const conforming = cover.grounding === 'terrain_conforming_wall' || correctBuried;
        const segments = conforming ? wallSegments(cover, ground, correctBuried) : [];
        heights.push({id: cover.id, grounding: cover.grounding || (correctBuried ? 'terrain_conforming_cover' : 'lowest_footprint_sample'), solid: cover.solid === true, base_y_m: num(base), ground_range_y_m: samples.map(num), minimum_exposed_height_m: num(conforming ? Math.min(...segments.map(s => s.minimum_exposed_height_m)) : originalExposure), ...(correctBuried ? {original_minimum_exposed_height_m: num(originalExposure), requested_visible_height_m: cover.size_xyz_m[1], visual_top_follows_terrain: !cover.solid} : {}), ...(conforming ? {segments: segments.map(s => ({index: s.index, center_xz_m: s.center_xz_m.map(num), size_xyz_m: s.size_xyz_m.map(num), base_y_m: num(s.base_y_m), ground_range_y_m: s.ground_range_y_m.map(num), minimum_exposed_height_m: num(s.minimum_exposed_height_m)}))} : {})});
        nodes.push(`[node name="${name}" type="Node3D" parent="HardCover"]\nposition = ${v3([cover.position_xz_m[0], base, cover.position_xz_m[1]])}\nrotation = Vector3(0, ${num(cover.yaw_deg * Math.PI / 180)}, 0)\nmetadata/source_id = "${cover.id}"\nmetadata/finished_art = false\nmetadata/opaque_2d_proxy = ${cover.opaque_proxy ? 'true' : 'false'}`);
        const material = cover.kind.includes('rock') || cover.kind === 'boulders' ? 'rock' : cover.kind === 'sandbags' ? 'sandbag' : cover.kind === 'hay_bales' ? 'hay' : cover.kind === 'pallets' ? 'wood' : cover.kind.includes('car') || cover.kind.includes('trailer') || cover.kind.includes('freight') ? 'vehicle' : 'concrete';
        if (correctBuried && !cover.solid) {
            const filename = `${name.toLowerCase()}_grounded.obj`, file = path.join(output, filename), content = visualConformanceObj(cover, segments, base);
            if (checkOnly) assert.equal(fs.readFileSync(file, 'utf8'), content, `Stale concealment mesh ${cover.id}`); else fs.writeFileSync(file, content);
            visualFiles.push(file);
            externalResources.push(`[ext_resource type="Mesh" path="res://Scene/World/Town500m/Dressing/${filename}" id="visual_${name}"]`);
            nodes.push(`[node name="ConformingVisual" type="MeshInstance3D" parent="${parent}"]\nmesh = ExtResource("visual_${name}")\nmaterial_override = SubResource("mat_${material}")\nmetadata/collision = "none"\nmetadata/requested_visible_height_m = ${cover.size_xyz_m[1]}`);
        } else if (conforming) {
            for (const segment of segments) box(`GroundPanel${segment.index}`, parent, segment.size_xyz_m, [segment.local_center[0], segment.base_y_m - base + segment.size_xyz_m[1] / 2, segment.local_center[2]], material, cover.solid === true);
        } else if (cover.kind === 'pallets') {
            // Reuse only the imported visual; native dimensioned body owns the stack collision.
            for (let layer = 0; layer < 5; layer++) nodes.push(`[node name="Pallet${layer}" parent="${parent}" instance=ExtResource("pallet")]\nprocess_mode = 4\nposition = ${v3([0, layer * cover.size_xyz_m[1] / 5, 0])}\nscale = ${v3([cover.size_xyz_m[0] / 1.1, cover.size_xyz_m[1] / 5 / .21, cover.size_xyz_m[2] / .94])}`);
            const shape = `shape_${name}`;
            addResource('BoxShape3D', shape, `size = ${v3(cover.size_xyz_m)}`);
            nodes.push(`[node name="Body" type="StaticBody3D" parent="${parent}"]\nposition = Vector3(0, ${num(cover.size_xyz_m[1] / 2)}, 0)\ncollision_layer = 1\ncollision_mask = 0\n\n[node name="Shape" type="CollisionShape3D" parent="${parent}/Body"]\nshape = SubResource("${shape}")`);
        } else box('Graybox', parent, cover.size_xyz_m, [0, cover.size_xyz_m[1] / 2, 0], material, cover.solid === true);
        if (cover.kind === 'wrecked_cars' || cover.kind.includes('trailer') || cover.kind.includes('freight')) {
            box('WindowHint', parent, [cover.size_xyz_m[0] * .72, .25, cover.size_xyz_m[2] * .4], [0, cover.size_xyz_m[1] + .125, 0], 'wire', false);
        }
    }
    nodes.push('[node name="Concealment" type="Node3D" parent="."]');
    for (const tree of layout.dressing.vegetation) {
        const name = idFor(tree.id), parent = `Concealment/${name}`, y = ground(tree.position_xz_m);
        const trunkHeight = tree.height_m * .6, crownHeight = tree.height_m * .72;
        nodes.push(`[node name="${name}" type="Node3D" parent="Concealment"]\nposition = ${v3([tree.position_xz_m[0], y, tree.position_xz_m[1]])}\nmetadata/source_id = "${tree.id}"\nmetadata/species = "${tree.kind}"\nmetadata/finished_art = false\nmetadata/los_role = "concealment only; trunk collision never certifies a whole crown"`);
        addResource('CylinderMesh', `trunk_${name}`, `top_radius = ${tree.trunk_diameter_m / 2}\nbottom_radius = ${tree.trunk_diameter_m / 2}\nheight = ${num(trunkHeight)}\nradial_segments = 6\nrings = 1\nmaterial = SubResource("mat_trunk")`);
        addResource('CylinderShape3D', `trunk_shape_${name}`, `radius = ${tree.trunk_diameter_m / 2}\nheight = ${num(trunkHeight)}`);
        nodes.push(`[node name="Trunk" type="MeshInstance3D" parent="${parent}"]\nposition = Vector3(0, ${num(trunkHeight / 2)}, 0)\nmesh = SubResource("trunk_${name}")\n\n[node name="TrunkBody" type="StaticBody3D" parent="${parent}"]\nposition = Vector3(0, ${num(trunkHeight / 2)}, 0)\ncollision_layer = 1\ncollision_mask = 0\n\n[node name="Shape" type="CollisionShape3D" parent="${parent}/TrunkBody"]\nshape = SubResource("trunk_shape_${name}")`);
        const pine = tree.kind === 'pine';
        addResource('CylinderMesh', `crown_${name}`, `top_radius = ${pine ? 0 : num(tree.crown_radius_m * .6)}\nbottom_radius = ${tree.crown_radius_m}\nheight = ${num(crownHeight)}\nradial_segments = 7\nrings = 1\nmaterial = SubResource("mat_${pine ? 'pine' : 'orchard'}")`);
        nodes.push(`[node name="CrownSilhouette" type="MeshInstance3D" parent="${parent}"]\nposition = Vector3(0, ${num(tree.height_m - crownHeight / 2)}, 0)\nmesh = SubResource("crown_${name}")\nmetadata/collision = "none"`);
    }
    nodes.push('[node name="Fences" type="Node3D" parent="."]');
    const bunker = layout.boundaries.bunker_fence;
    const fenceDefinitions = [{id: 'BUNKER', kind: 'wire', height_m: bunker.height_m, thickness_m: bunker.thickness_m, segments_xz_m: bunker.segments_xz_m}, ...proposal.fences];
    for (const fence of fenceDefinitions) for (const [index, [a, b]] of fence.segments_xz_m.entries()) {
        const length = distance(a, b), yaw = Math.atan2(a[1] - b[1], b[0] - a[0]) * 180 / Math.PI;
        const shape = rectangle(a.map((n, i) => (n + b[i]) / 2), [length, fence.thickness_m], yaw);
        const errors = [];
        for (const c of layout.corridors) if (Math.min(...edges(c.points_xz_m).map(([u, v]) => segmentPolygon(u, v, shape))) - c.width_m / 2 < .5 - 1e-6) errors.push(`route ${c.id}`);
        for (const s of layout.structures) if (polygonDistance(shape, rectangle(s.position_xz_m, s.footprint_m, s.yaw_deg)) < .5 - 1e-6) errors.push(`structure ${s.id}`);
        for (const s of layout.structures.filter(s => s.access?.ground)) if (segmentPolygon(s.door_apron.from_xz_m, s.door_apron.to_xz_m, shape) - s.door_apron.width_m / 2 < .5 - 1e-6) errors.push(`door ${s.id}`);
        for (const c of layout.dressing.cover) if (polygonDistance(shape, rectangle(c.position_xz_m, [c.size_xyz_m[0], c.size_xyz_m[2]], c.yaw_deg)) < .5 - 1e-6) errors.push(`cover ${c.id}`);
        for (const t of layout.dressing.vegetation) if (polygonDistance(shape, rectangle(t.position_xz_m, [t.trunk_diameter_m, t.trunk_diameter_m])) < 2 - 1e-6) errors.push(`trunk ${t.id}`);
        for (const m of layout.markers) if (polygonDistance(shape, rectangle(m.position_xz_m, m.pad_size_xz_m)) < .5 - 1e-6) errors.push(`pad ${m.id}`);
        for (const water of [layout.terrain.hydrology.river.actual_water_polygon_xz_m, layout.terrain.hydrology.lake.actual_water_polygon_xz_m]) if (polygonDistance(shape, water) < .5 - 1e-6) errors.push('wet reservation');
        for (const actor of layout.gameplay.encounters.actors) if (Math.min(...edges([...actor.patrol_points_xz_m, actor.patrol_points_xz_m[0]]).map(([a, b]) => segmentPolygon(a, b, shape))) < 1.5 - 1e-6) errors.push(`patrol ${actor.node_path}`);
        assert.equal(errors.length, 0, `${fence.id}/${index}: ${errors.join(', ')}`);
        const count = Math.ceil(length / 4);
        for (let i = 0; i < count; i++) {
            const from = a.map((v, k) => v + (b[k] - v) * i / count), to = a.map((v, k) => v + (b[k] - v) * (i + 1) / count);
            const midpoint = from.map((v, k) => (v + to[k]) / 2), yy = [ground(from), ground(to), ground(midpoint)], base = Math.min(...yy) - .04, height = fence.height_m + Math.max(...yy) - base;
            const name = `${fence.id}_${index}_${i}`, parent = `Fences/${name}`, span = length / count;
            nodes.push(`[node name="${name}" type="Node3D" parent="Fences"]\nposition = ${v3([midpoint[0], base, midpoint[1]])}\nrotation = Vector3(0, ${num(yaw * Math.PI / 180)}, 0)\nmetadata/los_role = "wire concealment; body uses ai_vision_transparent; native ray acceptance pending"`);
            box('WireGraybox', parent, [span, height, fence.thickness_m], [0, height / 2, 0], 'wire');
            box('Post', parent, [.1, height, .1], [-span / 2, height / 2, 0], 'vehicle', false);
            box('Rail', parent, [span, .05, .05], [0, height * .75, 0], 'vehicle', false);
        }
        fences.push({id: fence.id, index, from_xz_m: a, to_xz_m: b, panels: count, kind: fence.kind, opaque_proxy: false});
    }
    const resourceIds = resources.map(r => r.match(/id="([^"]+)"/)[1]);
    assert.equal(new Set(resourceIds).size, resourceIds.length, 'Duplicate native resource ID');
    const scene = `[gd_scene load_steps=${resourceCount + externalResources.length + 1} format=3]\n\n${externalResources.join('\n\n')}\n\n${resources.join('\n\n')}\n\n[node name="Town500mDressing" type="Node3D"]\nmetadata/authoring_source = "design/town-500m/phase3/author-dressing.cjs"\nmetadata/status = "static graybox; finished art and native acceptance pending"\n\n${nodes.join('\n\n')}\n`;
    assert(!/\b(?:NaN|Infinity)\b/.test(scene), 'Invalid native numeric value');
    assert.equal((scene.match(/groups=\["ai_vision_transparent"\]/g) || []).length, fences.reduce((n, fence) => n + fence.panels, 0), 'Every wire body must join the native transparent-vision group');
    assert.equal((scene.match(/metadata\/concept_b_los_transparent = true/g) || []).length, fences.reduce((n, fence) => n + fence.panels, 0), 'Every wire body must declare fixture LOS transparency');
    for (const reference of scene.matchAll(/SubResource\("([^"]+)"\)/g)) assert(resourceIds.includes(reference[1]), `Missing resource ${reference[1]}`);
    const entry = path.join(output, 'dressing.tscn');
    if (checkOnly) assert.equal(fs.readFileSync(entry, 'utf8'), scene, 'Stale dressing scene'); else {fs.mkdirSync(output, {recursive: true}); fs.writeFileSync(entry, scene);}
    const sourceFiles = ['layout.json', 'building-catalogue.json', 'terrain-contract.json', 'phase2/terrain-authoring.cjs', 'phase3/dressing-proposal.json', 'phase3/author-dressing.cjs', 'phase3/check-phase3-los.cjs', 'phase3/los-proposal-report.json'];
    const los = JSON.parse(fs.readFileSync(path.join(__dirname, 'los-proposal-report.json')));
    assert.equal(los.source_sha256['layout.json'], hash(path.join(source, 'layout.json')), 'LOS report layout is stale');
    assert.equal(los.source_sha256['dressing-proposal.json'], hash(path.join(__dirname, 'dressing-proposal.json')), 'LOS report proposal is stale');
    const conformingWalls = heights.filter(cover => cover.grounding === 'terrain_conforming_wall');
    const correctedCovers = heights.filter(cover => cover.grounding === 'terrain_conforming_cover');
    const coverBodies = nodes.filter(node => node.includes('type="StaticBody3D"') && node.includes('parent="HardCover/'));
    assert.equal(coverBodies.length, heights.filter(cover => cover.solid).reduce((count, cover) => count + (cover.segments?.length || 1), 0));
    for (const cover of heights.filter(cover => !cover.solid)) assert(!coverBodies.some(body => body.includes(`parent="HardCover/${idFor(cover.id)}/`)), `Concealment has gameplay collision ${cover.id}`);
    const report = {
        status: `OFFLINE STATIC CHECK PASS; ${los.status === '2D PROXY PASS; NATIVE PENDING' ? los.status : 'LOS HOLD; NATIVE PENDING'}`, native_verified: false, los_proxy_status: los.status,
        source_sha256: Object.fromEntries(sourceFiles.map(file => [file, hash(path.join(source, file))])),
        output_sha256: Object.fromEntries([entry, ...visualFiles].map(file => [path.relative(root, file).replaceAll('\\', '/'), hash(file)])),
        counts: {canonical_cover: canonical.length, additional_cover: layout.dressing.cover.length - canonical.length, authored_cover: layout.dressing.cover.length, collidable_cover: heights.filter(cover => cover.solid).length, concealment_only_cover: heights.filter(cover => !cover.solid).length, native_cover_bodies: coverBodies.length, vegetation_seeds: 93, imported_pallet_stacks: layout.dressing.cover.filter(c => c.kind === 'pallets').length, fence_segments: fences.length, fence_panels: fences.reduce((n, f) => n + f.panels, 0), terrain_conforming_walls: conformingWalls.length, terrain_conforming_panels: conformingWalls.reduce((n, cover) => n + cover.segments.length, 0), corrected_buried_cover: correctedCovers.length, corrected_buried_panels: correctedCovers.reduce((count, cover) => count + cover.segments.length, 0), terrain_following_visual_meshes: visualFiles.length, terrain_following_visual_cells: correctedCovers.filter(cover => !cover.solid).reduce((count, cover) => count + cover.segments.length, 0)},
        spatial: {status: spatial.status, errors: spatial.errors, scope: spatial.scope, counts: spatial.counts},
        declared_rail_overlap_cover: layout.dressing.cover.filter(cover => cover.allow_rail_overlap === true).map(cover => cover.id),
        grounding: {method: 'Offline phase2 terrain.heightAt: regular cover samples centre/four footprint corners and embeds3cm beneath lowest; terrain_conforming_wall uses closed BoxMesh/BoxShape panels<=1m along long axis; buried solid cover uses closed box cells<=1m in both XZ axes, base3cm below minimum and top=requested height above maximum of centre/four corners/four edge midpoints. Buried non-solid cover uses closed static OBJ cells<=0.3m, top vertices exactly0.9m above those9 terrain samples, bottom3cm below cell minimum and no collider; trees root at exact centre height; fences subdivided<=4m', minimum_conforming_wall_exposure_m: conformingWalls.length ? num(Math.min(...conformingWalls.map(cover => cover.minimum_exposed_height_m))) : null, corrected_buried_cover: correctedCovers.map(cover => ({id: cover.id, solid: cover.solid, geometry: cover.solid ? 'closed native collider boxes' : 'closed static visual mesh; no collider', panels: cover.segments.length, original_minimum_exposed_height_m: cover.original_minimum_exposed_height_m, minimum_exposed_height_m: cover.minimum_exposed_height_m, maximum_sample_exposed_height_m: cover.solid ? num(Math.max(...cover.segments.map(segment => segment.base_y_m + segment.size_xyz_m[1] - Math.min(...segment.ground_range_y_m)))) : cover.requested_visible_height_m, requested_visible_height_m: cover.requested_visible_height_m})), minimum_authored_cover_exposure_m: num(Math.min(...heights.map(cover => cover.minimum_exposed_height_m))), minimum_solid_cover_exposure_m: num(Math.min(...heights.filter(cover => cover.solid).map(cover => cover.minimum_exposed_height_m))), sample_limit: 'Exposure is guaranteed at recorded analytical terrain samples only; native generated terrain and standing/ADS/lean/upstairs/high-ground rays remain required', cover: heights},
        fences, gate: bunker.gate, resources_reused: ['res://Scene/Props/BunkerKit/wood_pallet.tscn'],
        cover_vs_concealment: '71 solid cover records own untagged native layer1 boxes/stack bodies;12 non-solid cover records have no gameplay collider and never certify hard LOS. Trunks alone have layer1 collision; crowns have none and never certify whole-crown hard LOS. Every wire CollisionObject body joins ai_vision_transparent and declares concept_b_los_transparent/town500_los_transparent; player/weapon collision remains layer1.',
        pending: proposal.native_required.concat(['Regular unsegmented cover may expose less than2m on slopes; conforming-wall sample exposure is recorded separately; native3D terrain/window/camera rays required', 'ScavPerception skips at most4 tagged StaticBody RIDs and fails closed at the fifth; stacked wire-panel/glass rays need native acceptance', 'Imported pallet visual process_mode disabled; primary must verify only native stack collider participates', 'No finished art/modeling/performance/nav/raid claim; no Godot CLI/editor was launched'])
    };
    const reportText = JSON.stringify(report, null, 2) + '\n', reportPath = path.join(__dirname, 'dressing-report.json');
    if (checkOnly) assert.equal(fs.readFileSync(reportPath, 'utf8'), reportText, 'Stale dressing report'); else fs.writeFileSync(reportPath, reportText);
    console.log(JSON.stringify({mode: checkOnly ? 'check' : 'write', status: report.status, counts: report.counts}));
    return report;
}
if (require.main === module) build(process.argv.includes('--check'));
module.exports = {build};
