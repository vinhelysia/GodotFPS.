// Import one approved complete WORN building. No Town/terrain edits or source rebuilds.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {readGlb, geometryFacts} = require('../phase5/import-assets.cjs');

const project = path.resolve(__dirname, '../../..');
const source = 'C:/Stuff/Blender/Buildings/soviet_apartment_block_01_overgrown';
const receiptFile = path.join(source, 'delivery_receipt.json');
const contractFile = path.join(source, 'verification/final_checks.json');
const configFile = path.join(source, 'planning/visual_correction_config.json');
const glbPath = 'Assets/Blender/Buildings/SovietApartmentWorn/soviet_apartment_block_01_overgrown.glb';
const wrapperPath = 'Scene/Props/Buildings/soviet_apartment_worn.tscn';
const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const hash = data => crypto.createHash('sha256').update(data).digest('hex');
const rounded = value => Number(value.toFixed(6));
const blenderToGodot = ([x, y, z]) => [x, z, -y];
const sitePoint = ([x, y, z]) => [-165 - z, 2 + y, 60 + x].map(rounded);
const bounds = points => [0, 1].map(side => [0, 1, 2].map(axis => (side ? Math.max : Math.min)(...points.map(point => point[axis]))).map(rounded));

function worldBox(box) {
    const corners = [];
    for (const x of [box[0][0], box[1][0]]) for (const y of [box[0][1], box[1][1]]) for (const z of [box[0][2], box[1][2]]) corners.push(sitePoint([x, y, z]));
    return bounds(corners);
}

function accessorValues(glb, index) {
    const accessor = glb.json.accessors[index], view = glb.json.bufferViews[accessor.bufferView];
    assert(!accessor.sparse && view.buffer === 0, 'Unsupported external/sparse accessor');
    const methods = {5126: ['readFloatLE', 4], 5125: ['readUInt32LE', 4], 5123: ['readUInt16LE', 2], 5121: ['readUInt8', 1]};
    const [method, size] = methods[accessor.componentType] || [];
    const count = {SCALAR: 1, VEC3: 3}[accessor.type];
    assert(method && count, 'Unsupported geometry accessor');
    const offset = (view.byteOffset || 0) + (accessor.byteOffset || 0), stride = view.byteStride || size * count;
    assert(offset + (accessor.count - 1) * stride + size * count <= glb.binary.length, 'Truncated geometry accessor');
    return Array.from({length: accessor.count}, (_, vertex) => {
        const values = Array.from({length: count}, (_, axis) => glb.binary[method](offset + vertex * stride + axis * size));
        assert(values.every(Number.isFinite), 'Non-finite source geometry');
        return count === 1 ? values[0] : values;
    });
}

function collisionParts(glb) {
    const node = glb.json.nodes.find(node => node.name === 'Building-colonly');
    assert(node, 'Missing canonical collision-only helper');
    const primitive = glb.json.meshes[node.mesh].primitives;
    assert.equal(primitive.length, 1, 'Unexpected collision surfaces');
    const positions = accessorValues(glb, primitive[0].attributes.POSITION), indices = accessorValues(glb, primitive[0].indices);
    assert(indices.every(index => index < positions.length), 'Collision index out of range');
    const parts = JSON.parse(node.extras.assembly_parts), measured = [];
    let cursor = 0;
    for (const part of parts) {
        // Source parts are closed genus-zero islands; triangulated faces = 2V - 4.
        const count = (2 * part.vertex_count - 4) * 3, vertices = indices.slice(cursor, cursor + count).map(index => positions[index]);
        assert.equal(new Set(vertices.map(point => point.map(value => value.toFixed(5)).join(','))).size, part.vertex_count, `Source part order changed: ${part.role}`);
        measured.push({role: part.role, bounds_godot_m: bounds(vertices), triangle_count: count / 3});
        cursor += count;
    }
    assert.equal(cursor, indices.length, 'Unmapped collision triangles');
    return {node: node.name, triangles: indices.length / 3, parts: measured, positions};
}

function newOrIdentical(relative, bytes) {
    const target = path.resolve(project, relative), allowed = path.relative(project, target);
    assert(allowed && !allowed.startsWith('..') && !path.isAbsolute(allowed), 'Target escapes active project');
    if (fs.existsSync(target)) assert.equal(hash(fs.readFileSync(target)), hash(bytes), `Refusing overwrite of different target: ${relative}`);
    else {fs.mkdirSync(path.dirname(target), {recursive: true}); fs.writeFileSync(target, bytes);}
    assert.equal(hash(fs.readFileSync(target)), hash(bytes), `Copied bytes differ: ${relative}`);
    return {res_path: `res://${relative}`, sha256: hash(bytes), bytes: bytes.length};
}

function run(checkOnly = false) {
    const receipt = readJson(receiptFile), profile = receipt.profiles.find(profile => profile.name === 'worn');
    assert.equal(receipt.asset, 'soviet_apartment_block_01_overgrown');
    assert.equal(receipt.revision, 'v5_visual_correction', 'Review new delivery explicitly before import');
    assert.equal(receipt.status, 'verified_isolated_delivery');
    assert.equal(path.resolve(profile.glb), path.resolve(source, 'godot/assets/soviet_apartment_block_01_overgrown.glb'));
    const glb = readGlb(profile.glb), facts = geometryFacts(glb.json, glb.binary), collision = collisionParts(glb);
    assert.equal(hash(glb.bytes), profile.glb_sha256, 'Canonical WORN GLB changed since delivery');
    assert.equal(hash(fs.readFileSync(profile.source)), profile.source_sha256, 'Canonical WORN source changed since delivery');
    assert.equal(facts.visual_triangles, profile.visual_triangles);
    assert.equal(collision.triangles, profile.collision_triangles);
    assert.equal(facts.visual_meshes.length, 5);
    assert.deepEqual(facts.collision_nodes, ['Building-colonly']);
    assert.equal(glb.json.animations?.length || 0, 0);
    assert.equal(glb.json.skins?.length || 0, 0);
    assert(glb.json.nodes.every(node => !node.matrix && !node.translation && !node.rotation && !node.scale), 'Unexpected node transforms: measure full transform chain before importing');
    assert((glb.json.buffers || []).every(buffer => !buffer.uri) && (glb.json.images || []).every(image => !image.uri && image.bufferView !== undefined), 'Expected fully embedded payload; review dependencies before copy');

    const sourceContract = readJson(contractFile), config = readJson(configFile);
    assert.equal(sourceContract.visual_triangles, facts.visual_triangles, 'Contract belongs to another profile');
    assert.equal(sourceContract.physics_probes.length, profile.native_probes);
    const floor = collision.parts.find(part => part.role === 'level0_slab');
    assert(floor && Math.abs(floor.bounds_godot_m[0][0] + 20.25) < 1e-5 && Math.abs(floor.bounds_godot_m[1][2] - 8.1) < 1e-5, 'Basement geometry changed');
    const selectedParts = collision.parts.filter(part => /^(level0_slab|level1_slab\d+|L0_up|L0_return|L0_midlanding|entry_landing|entry_step\d+)$/.test(part.role)).map(part => ({...part, bounds_site_a_world_m: worldBox(part.bounds_godot_m)}));
    const entrance = sourceContract.openings.find(opening => opening.role === 'L1_door25');
    assert(entrance && entrance.orientation === 'h' && entrance.constant < 0, 'Entrance contract changed');
    const entryPoint = blenderToGodot(entrance.centre);
    const wrapper = Buffer.from(`[gd_scene load_steps=2 format=3]\n\n[ext_resource type="PackedScene" path="res://${glbPath}" id="1_model"]\n\n[node name="SovietApartmentWorn" type="Node3D"]\nmetadata/source_revision = "v5_visual_correction"\nmetadata/appearance_profile = "worn"\nmetadata/source_glb_sha256 = "${profile.glb_sha256}"\nmetadata/import_contract = "Metres; root/model unit transform; embedded materials; preserve Building-colonly as static concave collision"\n\n[node name="Model" parent="." instance=ExtResource("1_model")]\n`);
    const files = [
        {relative: glbPath, bytes: glb.bytes},
        {relative: wrapperPath, bytes: wrapper},
    ];
    // Preflight every destination before the first copy.
    for (const file of files) {
        const target = path.join(project, file.relative);
        if (fs.existsSync(target)) assert.equal(hash(fs.readFileSync(target)), hash(file.bytes), `Refusing overwrite: ${file.relative}`);
    }
    const report = {
        schema_version: 1, status: 'OFFLINE_PAYLOAD_VERIFIED_NATIVE_PENDING', asset: receipt.asset, delivery_revision: receipt.revision,
        source_configuration_revision: config.revision, profile: 'worn', unit_scale: [1, 1, 1],
        source_receipt: {path: receiptFile, sha256: hash(fs.readFileSync(receiptFile))},
        source_glb: {path: profile.glb, sha256: profile.glb_sha256},
        wrapper_res_path: `res://${wrapperPath}`, root_name: 'SovietApartmentWorn', model_node_path: 'Model',
        files: files.map(file => ({res_path: `res://${file.relative}`, sha256: hash(file.bytes), bytes: file.bytes.length})),
        embedded_dependencies: {images: glb.json.images.length, buffers: glb.json.buffers.length, external_uris: 0, external_maps_or_materials_copied: 0},
        ...facts,
        collision: {helper: collision.node, triangle_count: collision.triangles, closed_source_parts: collision.parts.length, all_parts_mapped_and_vertex_counts_checked: true, bounds_godot_m: bounds(collision.positions), below_ground_bounds_godot_m: bounds(collision.positions.filter(point => point[1] < -.001)), selected_parts: selectedParts, import_semantics: 'Keep name suffix processing: Building-colonly becomes one StaticBody3D/ConcavePolygonShape3D; wrapper does not remove/disable/replace helpers'},
        materials: glb.json.materials.map(material => ({name: material.name, alpha_mode: material.alphaMode || 'OPAQUE', base_color_alpha: material.pbrMetallicRoughness?.baseColorFactor?.[3] ?? 1})),
        source_contract: {source_file: contractFile, sha256: hash(fs.readFileSync(contractFile)), coordinates: 'Original arrays are Blender XYZ; convert to Godot local [x,z,-y]', stairs: sourceContract.stairs, levels: sourceContract.levels, openings: sourceContract.openings, rooms: sourceContract.rooms, physics_probes: sourceContract.physics_probes, minimum_sampled_stair_headroom_m: sourceContract.minimum_sampled_stair_headroom_m},
        native_local: {front_direction: [0, 0, 1], ground_root_y: 0, ground_floor_y: .42, basement_floor_y: -2.58, basement_bottom_y: -2.78, roof_floor_y: 18.42, bulkhead_top_y: 21.02, entrance: {source_role: entrance.role, opening_center_godot_m: entryPoint, clear_width_m: entrance.width, clear_height_m: entrance.height, outer_approach_godot_m: [0, 0, 10.4]}, basement_cut_xz_m: [-20.25, -8.1, 20.25, 8.1], basement_cut_note: 'Remove dry terrain only inside basement body; visual balcony/vegetation envelope is not the cut polygon'},
        site_a: {root_position_m: [-165, 2, 60], yaw_deg: -90, scale: [1, 1, 1], bounds_world_m: worldBox(facts.visual_bounds_godot_m), basement_body_world_xz_m: [-173.1, 39.75, -156.9, 80.25], entrance_world_m: sitePoint(entryPoint), outer_approach_world_m: sitePoint([0, 0, 10.4]), basement_floor_world_y: -.58, basement_bottom_world_y: -.78},
        import_settings_required_for_exact_qa: {name_suffix_processing: true, force_disable_mesh_compression: true, generated_lods: false},
        verification_limits: ['No Town insertion or terrain changes in this importer', 'No Godot importer/runtime/player/navigation/FPS rerun by import worker', 'Source physics probes do not prove Cogito capsule stair traversal', 'No authoring of animations, LODs or additional profiles'],
    };
    if (!checkOnly) {
        files.forEach(file => newOrIdentical(file.relative, file.bytes));
        fs.writeFileSync(path.join(__dirname, 'apartment-import-report.json'), JSON.stringify(report, null, 2) + '\n');
    }
    console.log(JSON.stringify({mode: checkOnly ? 'check' : 'import', visual_triangles: facts.visual_triangles, collision_triangles: collision.triangles, collision_parts: collision.parts.length, files: report.files, dimensions_godot_m: facts.dimensions_godot_m, basement_cut_world_xz_m: report.site_a.basement_body_world_xz_m, native: 'pending'}));
    return report;
}

if (require.main === module) run(process.argv.includes('--check'));
module.exports = {run};
