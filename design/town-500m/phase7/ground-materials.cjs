// Offline visual masks and inherited material overrides; never changes walking geometry.
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..');
const out = 'Scene/World/Town500m/Art/GroundArt/';
const check = process.argv.includes('--check');
const size = 2048, worldSize = 500, pixel = worldSize / size, count = size * size;
const signedRange = 6;
const hashes = {};
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
function read(file) {
    const bytes = fs.readFileSync(path.join(root, file));
    hashes[file] = digest(bytes);
    return bytes.toString('utf8');
}
const json = file => JSON.parse(read(file));
const outputs = [];
function write(file, bytes) {
    if (typeof bytes === 'string') bytes = Buffer.from(bytes);
    const destination = path.join(root, file);
    if (check) assert(fs.readFileSync(destination).equals(bytes), `Stale ${file}`);
    else { fs.mkdirSync(path.dirname(destination), {recursive: true}); fs.writeFileSync(destination, bytes); }
    outputs.push({path: file, bytes: bytes.length, sha256: digest(bytes)});
}
function triangles(file) {
    const vertices = [], faces = [];
    for (const line of read(file).split(/\r?\n/)) {
        if (line.startsWith('v ')) vertices.push(line.slice(2).trim().split(/\s+/).map(Number));
        if (line.startsWith('f ')) {
            const face = line.slice(2).trim().split(/\s+/).map(v => vertices[Number(v.split('/')[0]) - 1]);
            assert.equal(face.length, 3, `Only source triangles expected ${file}`);
            faces.push(face);
        }
    }
    return faces;
}
function rasterize(face, apply) {
    const p = face.map(v => [(v[0] + 250) / pixel - 0.5, (v[2] + 250) / pixel - 0.5]);
    const den = (p[1][1] - p[2][1]) * (p[0][0] - p[2][0]) + (p[2][0] - p[1][0]) * (p[0][1] - p[2][1]);
    if (Math.abs(den) < 1e-9) return;
    const minX = clamp(Math.ceil(Math.min(...p.map(v => v[0]))), 0, size - 1);
    const maxX = clamp(Math.floor(Math.max(...p.map(v => v[0]))), 0, size - 1);
    const minZ = clamp(Math.ceil(Math.min(...p.map(v => v[1]))), 0, size - 1);
    const maxZ = clamp(Math.floor(Math.max(...p.map(v => v[1]))), 0, size - 1);
    for (let z = minZ; z <= maxZ; z++) for (let x = minX; x <= maxX; x++) {
        const a = ((p[1][1] - p[2][1]) * (x - p[2][0]) + (p[2][0] - p[1][0]) * (z - p[2][1])) / den;
        const b = ((p[2][1] - p[0][1]) * (x - p[2][0]) + (p[0][0] - p[2][0]) * (z - p[2][1])) / den;
        if (a >= -1e-7 && b >= -1e-7 && a + b <= 1 + 1e-7) apply(z * size + x, a * face[0][1] + b * face[1][1] + (1 - a - b) * face[2][1]);
    }
}
// Exact squared Euclidean distance transform, separable into rows and columns.
function lineDistance(input, length, output, sites, limits) {
    let k = 0;
    sites[0] = 0; limits[0] = -Infinity; limits[1] = Infinity;
    for (let q = 1; q < length; q++) {
        let s;
        do {
            const v = sites[k];
            s = ((input[q] + q * q) - (input[v] + v * v)) / (2 * (q - v));
            if (s <= limits[k]) k--;
            else break;
        } while (k >= 0);
        k++; sites[k] = q; limits[k] = s; limits[k + 1] = Infinity;
    }
    k = 0;
    for (let q = 0; q < length; q++) {
        while (limits[k + 1] < q) k++;
        const distance = q - sites[k];
        output[q] = distance * distance + input[sites[k]];
    }
}
function distances(mask, target) {
    const grid = new Float32Array(count), input = new Float64Array(size), line = new Float64Array(size);
    const sites = new Int32Array(size), limits = new Float64Array(size + 1), far = 1e12;
    for (let z = 0; z < size; z++) {
        for (let x = 0; x < size; x++) input[x] = mask[z * size + x] === target ? 0 : far;
        lineDistance(input, size, line, sites, limits);
        for (let x = 0; x < size; x++) grid[z * size + x] = line[x];
    }
    for (let x = 0; x < size; x++) {
        for (let z = 0; z < size; z++) input[z] = grid[z * size + x];
        lineDistance(input, size, line, sites, limits);
        for (let z = 0; z < size; z++) grid[z * size + x] = line[z];
    }
    return grid;
}
function selfCheckDistance() {
    const input = new Float64Array([100, 100, 0, 100, 100]);
    const actual = new Float64Array(5);
    lineDistance(input, 5, actual, new Int32Array(5), new Float64Array(6));
    assert.deepEqual([...actual], [4, 1, 0, 1, 4]);
    const joinedRoad = new Float64Array([0, 0, 1e12, 1e12, 1e12, 1e12, 1e12, 0, 0]);
    const joinedDistance = new Float64Array(9);
    lineDistance(joinedRoad, 9, joinedDistance, new Int32Array(9), new Float64Array(10));
    assert.deepEqual([...joinedDistance].slice(4, 6), [9, 4], 'Joined asphalt/gravel seam stays inside the road union, not at an outer edge');
}
selfCheckDistance();
const roads = Buffer.alloc(count * 4), context = Buffer.alloc(count * 4), labels = new Uint8Array(count);
const roadCounts = {};
for (const [kind, label] of [['asphalt', 1], ['gravel', 2], ['trail', 3]]) {
    const faces = triangles(`Scene/World/Town500m/Circulation/${kind}.obj`);
    roadCounts[kind] = faces.length;
    for (const face of faces) rasterize(face, index => { labels[index] = label; });
}
// The Phase6 spur is also visual-only and must suppress grass at the entrance.
for (const face of triangles('Scene/World/Town500m/Art/ApartmentSite/entry_spur.obj')) rasterize(face, index => { if (!labels[index]) labels[index] = 3; });
const mask = new Uint8Array(count);
function encodeDistance(mask, bytes, channel) {
    const inside = distances(mask, 0), outside = distances(mask, 1);
    for (let i = 0; i < count; i++) {
        const signed = (Math.sqrt(mask[i] ? inside[i] : outside[i]) - 0.5) * pixel * (mask[i] ? -1 : 1);
        bytes[i * 4 + channel] = Math.round((clamp(signed, -signedRange, signedRange) / signedRange * 0.5 + 0.5) * 255);
    }
}
for (let channel = 0; channel < 3; channel++) {
    for (let i = 0; i < count; i++) mask[i] = labels[i] === channel + 1 ? 1 : 0;
    encodeDistance(mask, roads, channel);
}
// Material boundaries inside a junction must not become shoulder edges.
for (let i = 0; i < count; i++) mask[i] = labels[i] ? 1 : 0;
encodeDistance(mask, context, 3);
// A shared semantic map keeps damp banks, foundation aprons and tree falloff coherent.
const contract = json('design/town-500m/terrain-contract.json');
const water = [contract.hydrology.river.actual_water_polygon_xz_m, contract.hydrology.lake.actual_water_polygon_xz_m];
function pointInPolygon(x, z, polygon) {
    let inside = false;
    for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
        const a = polygon[i], b = polygon[j];
        if ((a[1] > z) !== (b[1] > z) && x < (b[0] - a[0]) * (z - a[1]) / (b[1] - a[1]) + a[0]) inside = !inside;
    }
    return inside;
}
for (let z = 0; z < size; z++) for (let x = 0; x < size; x++) mask[z * size + x] = water.some(poly => pointInPolygon((x + 0.5) * pixel - 250, (z + 0.5) * pixel - 250, poly)) ? 1 : 0;
const waterDistance = distances(mask, 1);
for (let i = 0; i < count; i++) context[i * 4] = Math.round((1 - smooth(0.5, 9.0, Math.sqrt(waterDistance[i]) * pixel)) * 255);
function paintBounds(bounds, apply) {
    const x0 = clamp(Math.floor((bounds[0] + 250) / pixel), 0, size - 1), x1 = clamp(Math.ceil((bounds[2] + 250) / pixel), 0, size - 1);
    const z0 = clamp(Math.floor((bounds[1] + 250) / pixel), 0, size - 1), z1 = clamp(Math.ceil((bounds[3] + 250) / pixel), 0, size - 1);
    for (let z = z0; z <= z1; z++) for (let x = x0; x <= x1; x++) apply(z * size + x, (x + 0.5) * pixel - 250, (z + 0.5) * pixel - 250);
}
const catalogue = json('design/town-500m/building-catalogue.json');
const foundations = catalogue.structures.map(s => ({center: s.position_xz_m, size: s.footprint_m, yaw: s.yaw_deg}));
foundations.push({center: [-165, 60], size: [16.2, 40.5], yaw: 0});
for (const building of foundations) {
    const radius = Math.hypot(...building.size) * 0.5 + 4;
    const angle = building.yaw * Math.PI / 180, c = Math.cos(angle), s = Math.sin(angle), [cx, cz] = building.center;
    paintBounds([cx - radius, cz - radius, cx + radius, cz + radius], (index, x, z) => {
        const dx = x - cx, dz = z - cz;
        const a = Math.abs(c * dx - s * dz) - building.size[0] * 0.5;
        const b = Math.abs(s * dx + c * dz) - building.size[1] * 0.5;
        const distance = Math.hypot(Math.max(a, 0), Math.max(b, 0)) + Math.min(Math.max(a, b), 0);
        context[index * 4 + 1] = Math.max(context[index * 4 + 1], Math.round((1 - smooth(0.2, 2.2, distance)) * 255));
    });
}
const plan = json('design/town-500m/phase5/placement-plan.json');
const trees = plan.placements.filter(p => /^forest_(birch|pine|spruce)_tree$/.test(p.catalog_id)).map(p => ({at: [p.position_m[0], p.position_m[2]], birch: p.catalog_id === 'forest_birch_tree'}));
trees.push(...[[-179.5, 77], [-178.5, 42.5], [-151, 81]].map(at => ({at, birch: true})));
for (const tree of trees) {
    const [cx, cz] = tree.at, radius = tree.birch ? 5.0 : 4.0;
    paintBounds([cx - radius, cz - radius, cx + radius, cz + radius], (index, x, z) => {
        const weight = 1 - smooth(0.4, radius, Math.hypot(x - cx, z - cz));
        context[index * 4 + 2] = Math.max(context[index * 4 + 2], Math.round(weight * 255));
        if (tree.birch) roads[index * 4 + 3] = Math.max(roads[index * 4 + 3], Math.round(weight * 255));
    });
}
const terrainFiles = fs.readdirSync(path.join(root, 'Scene/World/Town500m/Terrain')).filter(f => /^chunk_.*\.obj$/.test(f)).sort();
for (const file of terrainFiles) read('Scene/World/Town500m/Terrain/' + file);
// RGBA PNG, filter0 rows and zlib: no image-authoring dependency.
const crcTable = Uint32Array.from({length: 256}, (_, value) => {
    for (let bit = 0; bit < 8; bit++) value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    return value >>> 0;
});
function chunk(type, bytes) {
    const name = Buffer.from(type), data = Buffer.concat([name, bytes]);
    let crc = 0xffffffff;
    for (const value of data) crc = crcTable[(crc ^ value) & 255] ^ (crc >>> 8);
    const head = Buffer.alloc(4), tail = Buffer.alloc(4);
    head.writeUInt32BE(bytes.length); tail.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
    return Buffer.concat([head, data, tail]);
}
function png(bytes) {
    const header = Buffer.alloc(13); header.writeUInt32BE(size, 0); header.writeUInt32BE(size, 4); header[8] = 8; header[9] = 6;
    const stride = size * 4, rows = Buffer.alloc((stride + 1) * size);
    for (let y = 0; y < size; y++) bytes.copy(rows, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', zlib.deflateSync(rows, {level: 9})), chunk('IEND', Buffer.alloc(0))]);
}
write(out + 'mask_roads_leaves.png', png(roads));
write(out + 'mask_ground_context.png', png(context));
const palette = {town: [.42, .39, .33], industry: [.35, .40, .43], bunker: [.40, .42, .35], hills: [.51, .48, .40], forest: [.30, .40, .30], farmland: [.49, .43, .30], shore: [.48, .44, .36], asphalt: [.16, .17, .17], gravel: [.37, .35, .30], trail: [.40, .33, .25], retaining: [.30, .27, .23]};
const resource = (type, file, id) => `[ext_resource type="${type}" path="res://${file}" id="${id}"]`;
for (const [name, color] of Object.entries(palette)) {
    const role = ['asphalt', 'gravel', 'trail'].includes(name) ? 1 : 0;
    const body = `[gd_resource type="ShaderMaterial" load_steps=11 format=3]\n\n${[
        resource('Shader', out + 'ground_surface.gdshader', 'shader'), resource('Texture2D', out + 'mask_roads_leaves.png', 'roads'), resource('Texture2D', out + 'mask_ground_context.png', 'context'), resource('Texture2D', out + 'mask_variation.png', 'variation'), resource('Texture2D', out + 'v2_ground_detail.png', 'v2ground'), resource('Texture2D', out + 'v2_road_detail.png', 'v2road'), resource('Texture2D', out + 'v2_detail_normal.png', 'v2normal'),
        resource('Texture2D', 'Assets/Textures/Grass/Grass_001_COLOR.jpg', 'detail'), resource('Texture2D', 'Assets/Textures/Grass/Grass_001_NORM.jpg', 'normal'), resource('Texture2D', 'Assets/Textures/Grass/Grass_001_ROUGH.jpg', 'rough')
    ].join('\n')}\n\n[resource]\nresource_name = "Town ${name} ground art"\nshader = ExtResource("shader")\nshader_parameter/road_leaf_mask = ExtResource("roads")\nshader_parameter/ground_context_mask = ExtResource("context")\nshader_parameter/variation_mask = ExtResource("variation")\nshader_parameter/v2_ground_detail = ExtResource("v2ground")\nshader_parameter/v2_road_detail = ExtResource("v2road")\nshader_parameter/v2_detail_normal = ExtResource("v2normal")\nshader_parameter/detail_albedo = ExtResource("detail")\nshader_parameter/detail_normal = ExtResource("normal")\nshader_parameter/detail_roughness = ExtResource("rough")\nshader_parameter/original_color = Color(${color.join(', ')}, 1)\nshader_parameter/surface_is_road = ${role === 1 ? 'true' : 'false'}\nshader_parameter/global_coverage = true\n${name === 'retaining' ? 'shader_parameter/detail_normal_strength = 0.0\n' : ''}`;
    write(out + name + '.tres', body);
}
const drySource = read('Scene/World/Town500m/Terrain/dry_terrain.tscn');
const names = [...drySource.matchAll(/\[node name="(chunk_[^"]+)" type="MeshInstance3D" parent="\."\]/g)].map(match => match[1]);
assert.equal(names.length, 60);
const zones = Object.keys(palette).slice(0, 7);
const ext = [resource('PackedScene', 'Scene/World/Town500m/Art/ApartmentSite/ground_finish.tscn', 'base'), ...zones.map(z => resource('Material', out + z + '.tres', z)), resource('Material', out + 'trail.tres', 'trail'), resource('Material', out + 'retaining.tres', 'retaining')];
const nodes = names.map(name => `[node name="${name}" parent="."]\nmaterial_override = ExtResource("${name.split('_').at(-1)}")`);
for (const name of ['chunk_0_2_farmland_cut', 'chunk_0_2_shore_cut', 'chunk_0_2_town_cut', 'chunk_0_3_farmland_cut', 'chunk_0_3_shore_cut', 'chunk_0_3_town_cut']) nodes.push(`[node name="${name}" parent="ApartmentExcavation"]\nmaterial_override = ExtResource("${name.split('_').at(-2)}")`);
nodes.push('[node name="entry_spur" parent="ApartmentExcavation"]\nmaterial_override = ExtResource("trail")', '[node name="pit_retaining" parent="ApartmentExcavation"]\nmaterial_override = ExtResource("retaining")');
write(out + 'dry_terrain.tscn', `[gd_scene load_steps=${ext.length + 1} format=3]\n\n${ext.join('\n\n')}\n\n[node name="Town500mDryTerrain" instance=ExtResource("base")]\n\n${nodes.join('\n\n')}\n`);
write(out + 'circulation.tscn', `[gd_scene load_steps=5 format=3]\n\n${[resource('PackedScene', 'Scene/World/Town500m/Circulation/circulation.tscn', 'base'), ...['asphalt', 'gravel', 'trail'].map(z => resource('Material', out + z + '.tres', z))].join('\n\n')}\n\n[node name="Circulation" instance=ExtResource("base")]\n\n${['asphalt', 'gravel', 'trail'].map(z => `[node name="${z}" parent="."]\nmaterial_override = ExtResource("${z}")`).join('\n\n')}\n`);
assert(read('Scene/World/Town500m/Water/water.tscn').includes('[node name="BankFaces"'), 'Existing bank mesh is retained');
write(out + 'water.tscn', `[gd_scene load_steps=3 format=3]\n\n${resource('PackedScene', 'Scene/World/Town500m/Water/water.tscn', 'base')}\n\n${resource('Material', out + 'retaining.tres', 'bank')}\n\n[node name="Water" instance=ExtResource("base")]\n\n[node name="BankFaces" parent="."]\nmaterial_override = ExtResource("bank")\n`);
const at = (x, z) => clamp(Math.floor((z + 250) / pixel), 0, size - 1) * size + clamp(Math.floor((x + 250) / pixel), 0, size - 1);
assert(roads[at(-190, 19) * 4] < 128, 'Known main road centre must be asphalt');
assert(context[at(-174, 60) * 4 + 1] > 20, 'Apartment edge must get foundation apron');
assert(roads[at(-179.5, 77) * 4 + 3] > 200, 'Existing plot birch must get leaf falloff');
const report = {status: 'OFFLINE_VISUAL_MASKS_CHECKED_NATIVE_PENDING', dimensions: [size, size], metres_per_texel: pixel, mapping: 'UV=(worldXZ+250)/500; row0=north; texture data is linear, not source_color', road_channels: {r: 'asphalt signed union edge distance -6..6m', g: 'gravel signed union edge distance -6..6m', b: 'trail/spur signed union edge distance -6..6m', a: 'localized birch leaf falloff'}, context_channels: {r: 'wet bank distance0.5..9m from actual wet polygons', g: 'rotated foundation footprints plus0.2..2.2m apron', b: 'existing native tree shade/root context', a: 'all-road union signed edge distance -6..6m; dryness uses actual world Y in shader'}, road_source_faces: roadCounts, original_terrain_obj_count: terrainFiles.length, foundation_count: foundations.length, tree_context_count: trees.length, pilot_bounds_xz_m: [-198, 5, -130, 90], global_coverage_default: true, collision_or_mesh_vertex_edits: 0, source_sha256: hashes, outputs, mask_distance_method: 'Exact separable squared Euclidean transform over rasterized actual exported class unions; halftexel correction, +/-6m saturation. No fragment segment loops.', limitations: ['Visual masks sample500m at0.244140625m; finite raster detail is not collision data.', 'Roads remain opaque at existing+0.012m offset; source geometry and navigation unchanged.', 'Normal/roughness/color textures reused from project; native shader/render/performance validation belongs to primary.', 'Full coverage enabled after pilot and Town preview; native acceptance recorded separately.']};
write('design/town-500m/phase7/ground-mask-report.json', JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({mode: check ? 'check' : 'write', masks: [size, size], road_faces: roadCounts, output_files: outputs.length, collision_edits: 0}));
