// Offline apartment excavation; canonical terrain/roads and their authoring sources stay untouched.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const geometry = require('../phase2/terrain-authoring.cjs');

const root = path.resolve(__dirname, '../../..');
const sourceDir = path.join(root, 'Scene/World/Town500m/Terrain');
const outputRelative = 'Scene/World/Town500m/Art/ApartmentSite';
const outputDir = path.join(root, outputRelative);
const checkOnly = process.argv.includes('--check');
const epsilon = 1e-7;
const number = value => Number(value.toFixed(7)).toString();
const hash = text => crypto.createHash('sha256').update(text).digest('hex');
const center = polygon => [0, 1].map(axis => polygon.reduce((sum, point) => sum + point[axis], 0) / polygon.length);
const cross = (a, b, point) => (b[0] - a[0]) * (point[1] - a[1]) - (b[1] - a[1]) * (point[0] - a[0]);
const area = geometry.area;
const bounds = geometry.bounds;
const overlap = geometry.overlap;
const projection = face => face.map(point => [point[0], point[2]]);

function partition(polygon, clip) {
    let remaining = polygon;
    const outside = [];
    for (let edge = 0; edge < clip.length && remaining.length; edge++) {
        const a = clip[edge], b = clip[(edge + 1) % clip.length];
        const pieces = geometry.splitPolygon(remaining, a, b);
        remaining = [];
        for (const piece of pieces) {
            if (cross(a, b, center(piece)) >= -epsilon) remaining = piece;
            else outside.push(piece);
        }
    }
    return {outside, inside: remaining};
}

function fan(polygon, originalFace, heightOffset = 0) {
    const vertices = polygon.map(([x, z]) => {
        const y = geometry.triangleHeight(x, z, originalFace);
        assert(y !== null && Number.isFinite(y), 'Clipped point left its original terrain plane');
        return [x, y + heightOffset, z];
    });
    const result = [];
    for (let index = 1; index + 1 < vertices.length; index++) {
        const face = [vertices[0], vertices[index], vertices[index + 1]];
        if (area(projection(face)) > epsilon) result.push(face);
    }
    return result;
}

function readOBJ(file) {
    const vertices = [], faces = [];
    const text = fs.readFileSync(file, 'utf8');
    for (const line of text.split(/\r?\n/)) {
        if (line.startsWith('v ')) vertices.push(line.slice(2).split(/\s+/).map(Number));
        if (line.startsWith('f ')) {
            const indices = line.slice(2).split(/\s+/).map(value => Number(value.split('/')[0]) - 1);
            assert(indices.length === 3, 'Canonical terrain must contain triangles');
            faces.push(indices.map(index => vertices[index]));
        }
    }
    assert(faces.length && faces.every(face => face.every(point => point.length === 3 && point.every(Number.isFinite))));
    return {faces, sha256: hash(text)};
}

function obj(faces, description) {
    const lines = [`# ${description}; world metres; identity root.`];
    for (const face of faces) for (const point of face) lines.push(`v ${point.map(number).join(' ')}`);
    for (let index = 0; index < faces.length; index++) lines.push(`f ${index * 3 + 1} ${index * 3 + 2} ${index * 3 + 3}`);
    return lines.join('\n') + '\n';
}

function write(relative, text) {
    const file = path.join(outputDir, relative);
    if (checkOnly) assert.equal(fs.readFileSync(file, 'utf8'), text, `Stale apartment terrain output: ${relative}`);
    else {
        fs.mkdirSync(path.dirname(file), {recursive: true});
        fs.writeFileSync(file, text);
    }
    return {res_path: `res://${outputRelative}/${relative}`, sha256: hash(text), bytes: Buffer.byteLength(text)};
}

function pathQuads(points, width) {
    const normals = points.slice(1).map((point, index) => {
        const dx = point[0] - points[index][0], dz = point[1] - points[index][1];
        const length = Math.hypot(dx, dz);
        assert(length > epsilon);
        return [-dz / length, dx / length];
    });
    const offsets = points.map((point, index) => {
        const before = normals[Math.max(0, index - 1)], after = normals[Math.min(index, normals.length - 1)];
        const denominator = 1 + before[0] * after[0] + before[1] * after[1];
        assert(denominator > .5, 'Spur corner needs a wider authored turn');
        return [(before[0] + after[0]) * width / (2 * denominator), (before[1] + after[1]) * width / (2 * denominator)];
    });
    const left = points.map((point, index) => point.map((value, axis) => value + offsets[index][axis]));
    const right = points.map((point, index) => point.map((value, axis) => value - offsets[index][axis]));
    return points.slice(1).map((point, index) => {
        const quad = [left[index], right[index], right[index + 1], left[index + 1]];
        return geometry.signedArea(quad) > 0 ? quad : quad.reverse();
    });
}

function distanceToSegment(point, a, b) {
    const dx = b[0] - a[0], dz = b[1] - a[1];
    const along = Math.max(0, Math.min(1, ((point[0] - a[0]) * dx + (point[1] - a[1]) * dz) / (dx * dx + dz * dz)));
    return Math.hypot(point[0] - a[0] - along * dx, point[1] - a[1] - along * dz);
}

function selfCheck() {
    const square = [[0, 0], [2, 0], [2, 2], [0, 2]];
    const face = [[-1, 4, 1], [3, 8, 1], [1, 6, 3]];
    const result = partition(projection(face), square);
    assert(Math.abs(area(result.inside) + result.outside.reduce((sum, polygon) => sum + area(polygon), 0) - area(projection(face))) < epsilon);
    assert(fan(result.inside, face).flat().every(point => Math.abs(point[1] - (point[0] + 5)) < epsilon));
    assert.equal(partition([[3, 3], [4, 3], [3, 4]], square).inside.length, 0);
    assert.equal(partition([[.2, .2], [.8, .2], [.2, .8]], square).outside.length, 0);
    const quads = pathQuads([[0, 0], [3, 0], [5, 2], [8, 2]], 1.8);
    for (let index = 0; index + 1 < quads.length; index++) assert(area(partition(quads[index], quads[index + 1]).inside) < epsilon);
}

function build() {
    selfCheck();
    const importPath = path.join(__dirname, 'apartment-import-report.json');
    const imported = JSON.parse(fs.readFileSync(importPath, 'utf8'));
    const site = imported.site_a;
    assert.deepEqual(site.root_position_m, [-165, 2, 60]);
    assert.equal(site.yaw_deg, -90);
    assert.deepEqual(site.scale, [1, 1, 1]);
    assert.deepEqual(imported.native_local.basement_cut_xz_m, [-20.25, -8.1, 20.25, 8.1]);
    const [west, north, east, south] = site.basement_body_world_xz_m;
    const cut = [[west, north], [east, north], [east, south], [west, south]];
    const cutBounds = bounds(cut), floorY = site.basement_bottom_world_y - .05;
    // Measured GLB shell is .405m thick; bury lining 15mm behind its outside face.
    const liningInset = .015, measuredWallThickness = .405;
    assert(liningInset > 0 && liningInset < measuredWallThickness / 2);
    const sourceFiles = fs.readdirSync(sourceDir).filter(file => /^chunk_\d_\d_\w+\.obj$/.test(file)).sort();
    const sourceHashes = {}, allFaces = [], replacements = [], boundaryPoints = cut.map(point => [...point]);
    let oldArea = 0, removedArea = 0, preservedArea = 0, unchangedFaces = 0, modifiedFaces = 0, removedFaces = 0, maximumPlaneError = 0;

    for (const file of sourceFiles) {
        const original = readOBJ(path.join(sourceDir, file));
        sourceHashes[`Scene/World/Town500m/Terrain/${file}`] = original.sha256;
        const output = [];
        let changed = false;
        for (const face of original.faces) {
            allFaces.push(face);
            const polygon = projection(face), originalArea = area(polygon);
            oldArea += originalArea;
            const result = overlap(bounds(polygon), cutBounds) ? partition(polygon, cut) : {inside: [], outside: []};
            if (result.inside.length < 3 || area(result.inside) < epsilon) {
                output.push(face);
                unchangedFaces++;
                preservedArea += originalArea;
                continue;
            }
            changed = true;
            const removed = area(result.inside);
            removedArea += removed;
            modifiedFaces++;
            if (!result.outside.length) removedFaces++;
            for (const point of result.inside) {
                if (cut.some((a, index) => Math.abs(cross(a, cut[(index + 1) % cut.length], point)) < epsilon)) boundaryPoints.push(point);
            }
            let outsideArea = 0;
            for (const polygon of result.outside) {
                const faces = fan(polygon, face);
                output.push(...faces);
                outsideArea += faces.reduce((sum, piece) => sum + area(projection(piece)), 0);
                for (const piece of faces) for (const point of piece) {
                    maximumPlaneError = Math.max(maximumPlaneError, Math.abs(point[1] - geometry.triangleHeight(point[0], point[2], face)));
                }
            }
            assert(Math.abs(outsideArea + removed - originalArea) < 1e-5, `Triangle area changed outside excavation in ${file}`);
            preservedArea += outsideArea;
        }
        if (changed) replacements.push({name: file.slice(0, -4), sourceFaces: original.faces.length, faces: output});
    }
    assert(Math.abs(removedArea - area(cut)) < 1e-5, 'Excavation does not cover exactly the measured basement body');
    assert(Math.abs(preservedArea + removedArea - oldArea) < 1e-5, 'Dry terrain area changed outside the excavation');
    assert(maximumPlaneError < epsilon);
    assert(replacements.length > 0);
    for (const replacement of replacements) for (const face of replacement.faces) {
        const polygon = projection(face);
        if (overlap(bounds(polygon), cutBounds)) assert(area(partition(polygon, cut).inside) < 1e-5, `Uncut terrain remains in ${replacement.name}`);
    }

    const pitFaces = [];
    let pitWallSegments = 0;
    for (let edge = 0; edge < cut.length; edge++) {
        const a = cut[edge], b = cut[(edge + 1) % cut.length];
        const onEdge = boundaryPoints.filter(point => Math.abs(cross(a, b, point)) < epsilon);
        const length2 = (b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2;
        const along = point => ((point[0] - a[0]) * (b[0] - a[0]) + (point[1] - a[1]) * (b[1] - a[1])) / length2;
        const ordered = [...new Map(onEdge.map(point => [point.map(number).join(','), point])).values()].sort((p, q) => along(p) - along(q));
        for (let index = 0; index + 1 < ordered.length; index++) {
            const p = ordered[index], q = ordered[index + 1];
            if (Math.hypot(p[0] - q[0], p[1] - q[1]) < epsilon) continue;
            const heights = [p, q].map(point => {
                const containing = allFaces.find(face => geometry.triangleHeight(...point, face) !== null);
                assert(containing, 'Pit rim has no canonical terrain floor');
                const y = geometry.triangleHeight(...point, containing);
                assert(Math.abs(y - site.root_position_m[1]) < 1e-5, 'Site A no longer has a flat pad');
                return y;
            });
            const inset = point => [Math.max(west + liningInset, Math.min(east - liningInset, point[0])), Math.max(north + liningInset, Math.min(south - liningInset, point[1]))];
            const innerP = inset(p), innerQ = inset(q);
            const topA = [innerP[0], heights[0], innerP[1]], topB = [innerQ[0], heights[1], innerQ[1]];
            const lowA = [innerP[0], floorY, innerP[1]], lowB = [innerQ[0], floorY, innerQ[1]];
            pitFaces.push([topA, lowB, lowA], [topA, topB, lowB]);
            pitWallSegments++;
        }
    }
    const floor = cut.map(([x, z]) => [x, floorY, z]);
    pitFaces.push([floor[0], floor[2], floor[1]], [floor[0], floor[3], floor[2]]);
    const liningBounds = bounds(pitFaces.slice(0, -2).flat().map(point => [point[0], point[2]]));
    assert(liningBounds.every((value, index) => Math.abs(value - [west + liningInset, north + liningInset, east - liningInset, south - liningInset][index]) < epsilon));
    assert.deepEqual(pitFaces.slice(-2), [[floor[0], floor[2], floor[1]], [floor[0], floor[3], floor[2]]]);

    // Start at GR_G03's east edge, so the new opaque path never overlaps its visual floor.
    const spurPoints = [[-188.75, 63.5], [-180, 63.5], [-175.4, 60], [-174.909, 60]];
    const spurWidth = 1.8, spurQuads = pathQuads(spurPoints, spurWidth), spurFaces = [];
    const spurBounds = bounds(spurQuads.flat());
    for (const face of allFaces) {
        const polygon = projection(face);
        if (!overlap(bounds(polygon), spurBounds)) continue;
        for (const quad of spurQuads) {
            if (!overlap(bounds(polygon), bounds(quad))) continue;
            const intersection = partition(polygon, quad).inside;
            if (intersection.length >= 3 && area(intersection) > epsilon) spurFaces.push(...fan(intersection, face, .012));
        }
    }
    const spurArea = spurFaces.reduce((sum, face) => sum + area(projection(face)), 0);
    assert(Math.abs(spurArea - spurQuads.reduce((sum, quad) => sum + area(quad), 0)) < 1e-5, 'Spur mesh leaves a hole or duplicates area');
    assert(!overlap(spurBounds, cutBounds), 'Spur must stay outside the basement excavation');
    const tree = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../layout.json'), 'utf8')).dressing.vegetation.find(row => row.id === 'A010');
    assert(tree);
    const trunkClearance = Math.min(...spurPoints.slice(1).map((point, index) => distanceToSegment(tree.position_xz_m, spurPoints[index], point))) - tree.trunk_diameter_m / 2 - spurWidth / 2;
    assert(trunkClearance >= 1, 'Entry spur is too close to the preserved A010 trunk');

    const ext = ['[ext_resource type="PackedScene" path="res://Scene/World/Town500m/Art/TerrainPilot/dry_terrain.tscn" id="base"]', '[ext_resource type="Material" path="res://Scene/World/Town500m/Art/TerrainPilot/ground_blend.tres" id="pilot"]'];
    const resources = [], nodes = ['[node name="Town500mDryTerrain" instance=ExtResource("base")]'];
    const files = [];
    const colors = {town: [.42, .39, .33], farmland: [.49, .43, .3], shore: [.48, .44, .36], pit: [.30, .27, .23], spur: [.4, .33, .25]};
    for (const [name, color] of Object.entries(colors)) resources.push(`[sub_resource type="StandardMaterial3D" id="${name}"]\nalbedo_color = Color(${color.join(', ')}, 1)\nroughness = 1\ncull_mode = 2`);
    for (const replacement of replacements) {
        nodes.push(`[node name="${replacement.name}" parent="."]\nvisible = false`, `[node name="DryTerrainBody" parent="${replacement.name}"]\ncollision_layer = 0`, `[node name="CollisionShape3D" parent="${replacement.name}/DryTerrainBody"]\ndisabled = true`);
    }
    nodes.push('[node name="ApartmentExcavation" type="Node3D" parent="."]\nmetadata/authoring_source = "design/town-500m/phase6/apartment-terrain.cjs"');
    function addMesh(name, faces, material, collision) {
        files.push(write(`${name}.obj`, obj(faces, name === 'entry_spur' ? 'Conformed visual-only apartment entry spur' : 'Apartment basement excavation replacement')));
        ext.push(`[ext_resource type="ArrayMesh" path="res://${outputRelative}/${name}.obj" id="${name}"]`);
        nodes.push(`[node name="${name}" type="MeshInstance3D" parent="ApartmentExcavation"]\nmesh = ExtResource("${name}")\nmaterial_override = ${material}`);
        if (collision) {
            // Godot collision/nav uses clockwise faces; imported OBJ visuals use the opposite winding.
            const collisionFaces = faces.map(face => [face[0], face[2], face[1]]);
            if (name !== 'pit_retaining') for (const face of collisionFaces) {
                const a = face[0], b = face[1], c = face[2];
                assert((b[2] - a[2]) * (c[0] - a[0]) - (b[0] - a[0]) * (c[2] - a[2]) < -epsilon, 'Terrain collision winding must match canonical upward Godot faces');
            }
            resources.push(`[sub_resource type="ConcavePolygonShape3D" id="shape_${name}"]\ndata = PackedVector3Array(${collisionFaces.flat(2).map(number).join(', ')})\nbackface_collision = true`);
            nodes.push(`[node name="DryTerrainBody" type="StaticBody3D" parent="ApartmentExcavation/${name}"]\ncollision_layer = 1\ncollision_mask = 0`, `[node name="CollisionShape3D" type="CollisionShape3D" parent="ApartmentExcavation/${name}/DryTerrainBody"]\nshape = SubResource("shape_${name}")`);
        }
    }
    for (const replacement of replacements) {
        const zone = replacement.name.split('_').slice(3).join('_');
        assert(colors[zone], `Unexpected excavation zone: ${zone}`);
        const material = replacement.name === 'chunk_0_2_town' ? 'ExtResource("pilot")' : `SubResource("${zone}")`;
        addMesh(`${replacement.name}_cut`, replacement.faces, material, true);
    }
    addMesh('pit_retaining', pitFaces, 'SubResource("pit")', true);
    addMesh('entry_spur', spurFaces, 'SubResource("spur")', false);
    files.push(write('dry_terrain.tscn', `[gd_scene load_steps=${ext.length + resources.length + 1} format=3]\n\n${[...ext, ...resources, ...nodes].join('\n\n')}\n`));

    for (const [relative, expected] of Object.entries(sourceHashes)) assert.equal(hash(fs.readFileSync(path.join(root, relative))), expected, `Concurrent source edit: ${relative}`);
    const protectedSources = ['Scene/World/Town500m/Terrain/dry_terrain.tscn', 'Scene/World/Town500m/Art/TerrainPilot/dry_terrain.tscn', 'Scene/World/Town500m/Circulation/circulation.tscn', 'design/town-500m/phase2/terrain-authoring.cjs', 'design/town-500m/layout.json', 'design/town-500m/terrain-contract.json', 'design/town-500m/phase5/placement-plan.json'];
    for (const relative of protectedSources) sourceHashes[relative] = hash(fs.readFileSync(path.join(root, relative)));
    const report = {
        schema_version: 1,
        status: 'OFFLINE_EXCAVATION_AND_SPUR_CHECKED_NATIVE_PENDING',
        source_import_report: 'design/town-500m/phase6/apartment-import-report.json',
        source_geometry_sha256: hash(JSON.stringify({native_local: imported.native_local, site_a: site})),
        source_sha256: sourceHashes,
        output_files: files,
        scene_ref: `res://${outputRelative}/dry_terrain.tscn`,
        inherited_base: 'res://Scene/World/Town500m/Art/TerrainPilot/dry_terrain.tscn',
        cut: {world_bounds_xz_m: cutBounds, area_m2: area(cut), root_position_m: site.root_position_m, basement_floor_world_y_m: site.basement_floor_world_y, basement_slab_bottom_world_y_m: site.basement_bottom_world_y, pit_floor_world_y_m: floorY, pit_floor_clearance_below_slab_m: .05, retaining_wall_segments: pitWallSegments, retaining_triangles: pitFaces.length, lining_inset_inside_basement_outer_face_m: liningInset, lining_world_bounds_xz_m: liningBounds, measured_basement_wall_thickness_m: measuredWallThickness, lining_reason: 'Avoid duplicate coplanar collision with the apartment shell; native basement_enclosed ray must hit the original building first', wall_thickness_evidence: {source_glb_sha256: imported.source_glb.sha256, part: 'L0_wall12_0_0', local_z_bounds_m: [7.694999694824219, 8.100000381469727], local_y_bounds_m: [-2.5799999237060547, .23999999463558197]}, purpose: 'Exact measured basement body only; no balcony/canopy AABB excavation'},
        terrain: {source_chunks: sourceFiles.length, replaced_chunks: replacements.map(row => ({name: row.name, original_triangles: row.sourceFaces, replacement_triangles: row.faces.length, old_mesh_path: row.name, old_shape_disabled: `${row.name}/DryTerrainBody/CollisionShape3D`, new_mesh_path: `ApartmentExcavation/${row.name}_cut`, new_shape_path: `ApartmentExcavation/${row.name}_cut/DryTerrainBody/CollisionShape3D`})), unchanged_original_triangles: unchangedFaces, intersected_original_triangles: modifiedFaces, fully_removed_triangles: removedFaces, dry_area_before_m2: oldArea, dry_area_preserved_m2: preservedArea, removed_area_m2: removedArea, area_conservation_error_m2: Math.abs(preservedArea + removedArea - oldArea), maximum_outside_plane_height_error_m: maximumPlaneError, imported_obj_precision_m: 1e-7, generated_collision: 'Exact replacement triangle mesh; old affected body layer0 and shape disabled; all other old colliders inherited unchanged', pit_mesh_path: 'ApartmentExcavation/pit_retaining'},
        entry_spur: {width_m: spurWidth, route_controller_start_xz_m: [-190, 63.5], visual_centerline_xz_m: spurPoints, visual_offset_above_original_floor_m: .012, area_m2: spurArea, triangles: spurFaces.length, collision: 'None; unchanged canonical dry terrain owns walking floor', endpoint: 'Touches the outside of imported bottom entry step at worldX=-174.909', preserved_tree_id: tree.id, canonical_trunk_edge_clearance_m: trunkClearance},
        checks: ['Convex split area conservation including sloped-plane interpolation and outside/inside controls', 'Every old terrain face wholly outside cut retained verbatim as coordinates', 'Clipped outside faces stay exactly on their original triangle planes', 'Removed area equals measured 656.1m2 basement body; no retained surface intersects its interior', 'Retaining lining has measured15mm inset inside .405m apartment shell; all rim subdivisions retained and pit floor unchanged below imported slab', 'Spur miter quads share edges without area overlap; conformed triangles cover exactly their footprint', 'Spur does not intersect excavation or existing GR_G03 visual floor; A010 preserved with >1m trunk clearance', 'Canonical OBJ bytes unchanged at end of build'],
        limits: ['Primary must link this inherited scene in terrain_payload; this generator does not edit Town or payload', 'Godot import/materials/controller entry, basement rooms/stairwell and old-collider removal require MCP verification', 'No navigation bake, AI, save/load, rooftop LOS or performance verification', 'Other conversation owns unit-scale props; placement-plan hash is a point-in-time conflict marker, never overwritten here']
    };
    if (!checkOnly) fs.writeFileSync(path.join(__dirname, 'apartment-terrain-report.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify({mode: checkOnly ? 'check' : 'write', replaced_chunks: replacements.length, cut_area_m2: removedArea, outside_plane_error_m: maximumPlaneError, spur_triangles: spurFaces.length, trunk_clearance_m: trunkClearance, scene: report.scene_ref}));
    return report;
}

if (require.main === module) build();
module.exports = {build, partition, pathQuads};
