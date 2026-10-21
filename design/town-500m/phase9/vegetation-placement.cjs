// Offline pilot only: node design/town-500m/phase9/vegetation-placement.cjs [--check]
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const terrain = require('../phase2/terrain-authoring.cjs');
const root = path.resolve(__dirname, '../../..');
const check = process.argv.includes('--check');
const seed = 20261023;
const sources = {};
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
function read(file) {
    const bytes = fs.readFileSync(path.join(root, file));
    sources[file] = hash(bytes);
    return bytes.toString('utf8');
}
const json = file => JSON.parse(read(file));
const previous = json('design/town-500m/phase8/vegetation-plan.json');
const catalogue = json('design/town-500m/building-catalogue.json');
const props = json('design/town-500m/phase5/placement-plan.json');
const layout = json('design/town-500m/layout.json');
const contract = json('design/town-500m/terrain-contract.json');
read('design/town-500m/phase2/terrain-authoring.cjs');
const apartmentScene = read('Scene/World/Town500m/Art/apartment_pilot.tscn');
const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
const smooth = (low, high, value) => { const t = clamp((value - low) / (high - low), 0, 1); return t * t * (3 - 2 * t); };
const round = value => Number(value.toFixed(6));
let state = seed;
function random() { state = (Math.imul(1664525, state) + 1013904223) >>> 0; return state / 4294967296; }
function cellNoise(x, z, salt) {
    let value = Math.imul(x | 0, 374761393) ^ Math.imul(z | 0, 668265263) ^ Math.imul(salt, 1274126177) ^ seed;
    value = Math.imul(value ^ (value >>> 13), 1274126177);
    return ((value ^ (value >>> 16)) >>> 0) / 4294967295;
}
function noise(x, z, scale, salt) {
    x /= scale; z /= scale;
    const ix = Math.floor(x), iz = Math.floor(z), tx = smooth(0, 1, x - ix), tz = smooth(0, 1, z - iz);
    const a = cellNoise(ix, iz, salt) * (1 - tx) + cellNoise(ix + 1, iz, salt) * tx;
    const b = cellNoise(ix, iz + 1, salt) * (1 - tx) + cellNoise(ix + 1, iz + 1, salt) * tx;
    return a * (1 - tz) + b * tz;
}
function segmentDistance(x, z, a, b) {
    const dx = b[0] - a[0], dz = b[1] - a[1], length2 = dx * dx + dz * dz;
    const t = length2 ? clamp(((x - a[0]) * dx + (z - a[1]) * dz) / length2, 0, 1) : 0;
    return Math.hypot(x - a[0] - t * dx, z - a[1] - t * dz);
}
function rectangleDistance(x, z, center, size, yaw = 0) {
    const angle = yaw * Math.PI / 180, dx = x - center[0], dz = z - center[1];
    const localX = Math.cos(angle) * dx - Math.sin(angle) * dz;
    const localZ = Math.sin(angle) * dx + Math.cos(angle) * dz;
    const qx = Math.abs(localX) - size[0] / 2, qz = Math.abs(localZ) - size[1] / 2;
    return Math.hypot(Math.max(0, qx), Math.max(0, qz)) + Math.min(Math.max(qx, qz), 0);
}
function readTriangles(file) {
    const vertices = [], faces = [];
    for (const line of read(file).split(/\r?\n/)) {
        if (line.startsWith('v ')) vertices.push(line.slice(2).trim().split(/\s+/).map(Number));
        if (line.startsWith('f ')) {
            const face = line.slice(2).trim().split(/\s+/).map(value => vertices[Number(value.split('/')[0]) - 1]);
            assert.equal(face.length, 3);
            if (Math.max(...face.map(v => v[0])) > -210 && Math.min(...face.map(v => v[0])) < -120 && Math.max(...face.map(v => v[2])) > -5 && Math.min(...face.map(v => v[2])) < 100) faces.push(face);
        }
    }
    return faces;
}
const roadFaces = ['asphalt', 'gravel', 'trail'].flatMap(kind => readTriangles(`Scene/World/Town500m/Circulation/${kind}.obj`));
const spurFaces = readTriangles('Scene/World/Town500m/Art/ApartmentSite/entry_spur.obj');
function triangleUnionDistance(x, z, faces) {
    let distance = Infinity;
    for (const face of faces) {
        if (terrain.triangleHeight(x, z, face) !== null) return 0;
        for (let edge = 0; edge < 3; edge++) distance = Math.min(distance, segmentDistance(x, z, [face[edge][0], face[edge][2]], [face[(edge + 1) % 3][0], face[(edge + 1) % 3][2]]));
    }
    return distance;
}
const trees = props.placements.filter(row => /(?:birch_tree|pine_tree|spruce_tree)/.test(row.catalog_id)).map(row => [row.position_m[0], row.position_m[2]]);
const apartmentTrees = [...apartmentScene.matchAll(/\[node name="(BirchWest|BirchNorth|BirchEast)"[^\n]*\]\r?\nposition = Vector3\(([^)]+)\)/g)].map(match => {
    const point = match[2].split(',').map(Number);
    assert(point.length === 3 && point.every(Number.isFinite));
    return {node: match[1], xz_m: [point[0], point[2]]};
});
assert.equal(apartmentTrees.length, 3, 'Read the three live apartment birches, not stale inferred tree positions');
trees.push(...apartmentTrees.map(row => row.xz_m));
const reused = previous.reused_assets.flatMap(group => group.instances.map(row => ({x: row.position_m[0], z: row.position_m[2], radius: group.support_radius_m})));
const service = [[-154, 74, .9], [-154, 75.15, .5]];
const apartment = previous.exclusions.apartment_visual_bounds_xz_m;
const apartmentCenter = [(apartment[0] + apartment[2]) / 2, (apartment[1] + apartment[3]) / 2];
const apartmentSize = [apartment[2] - apartment[0], apartment[3] - apartment[1]];
const bounds = [-198, 5, -130, 90];
const pockets = [
    {id: 'road', bounds: [-198, 5, -155, 38], density: 15},
    {id: 'north_tree', bounds: [-186, 38, -175.8, 48], density: 9},
    {id: 'west_tree', bounds: [-190, 68, -175.8, 86], density: 11},
    {id: 'entry_south', bounds: [-180.5, 48, -175.8, 57], density: 8},
    {id: 'entry_north', bounds: [-180.5, 65.5, -175.8, 68], density: 8}
];
const inBounds = (x, z, box) => x >= box[0] && z >= box[1] && x <= box[2] && z <= box[3];
const touched = (x, z) => pockets.some(pocket => inBounds(x, z, pocket.bounds));
const kinds = {
    short: {height: .18, triangles: 12, radius: .16, colors: ['75805B', '77734C']},
    dry: {height: .33, triangles: 12, radius: .16, colors: ['A39768', '8C714E', 'B6A477']},
    tall: {height: .65, triangles: 30, radius: .18, colors: ['A39768', 'B6A477']},
    weed: {height: .28, triangles: 30, radius: .20, colors: ['4E6045', '75805B']}
};
const camera = [-179, 27.4];
function clearances(x, z, radius) {
    return {
        road: triangleUnionDistance(x, z, roadFaces) - radius,
        spur: triangleUnionDistance(x, z, spurFaces) - radius,
        apartment: rectangleDistance(x, z, apartmentCenter, apartmentSize) - radius,
        building: Math.min(...catalogue.structures.map(row => rectangleDistance(x, z, row.position_xz_m, row.footprint_m, row.yaw_deg))) - radius,
        tree: Math.min(...trees.map(point => Math.hypot(x - point[0], z - point[1]))) - radius,
        service: Math.min(...service.map(row => Math.hypot(x - row[0], z - row[1]) - row[2])) - radius,
        reused: Math.min(...reused.map(row => Math.hypot(x - row.x, z - row.z) - row.radius)) - radius,
        camera: Math.hypot(x - camera[0], z - camera[1]) - radius
    };
}
const minimum = {road: .14, spur: .32, apartment: .6, building: .65, tree: .8, service: .25, reused: .04, camera: .55};
function allowed(gaps) { return Object.entries(minimum).every(([key, value]) => gaps[key] >= value); }
function upAt(x, z) {
    const delta = .08, dx = (terrain.heightAt(x + delta, z) - terrain.heightAt(x - delta, z)) / (delta * 2);
    const dz = (terrain.heightAt(x, z + delta) - terrain.heightAt(x, z - delta)) / (delta * 2);
    const length = Math.hypot(dx, 1, dz);
    return [-dx / length, 1 / length, -dz / length];
}
function tint(kind) {
    const hex = kinds[kind].colors[Math.floor(random() * kinds[kind].colors.length)];
    const shade = .87 + random() * .18;
    return [0, 2, 4].map(index => round(parseInt(hex.slice(index, index + 2), 16) / 255 * shade)).concat(1);
}
function makePatch(id, kind, height, instances, role) {
    return {id, mesh_kind: kind, height_m: height, count: instances.length, role, instances};
}
// Retained coordinates/tints stay byte-identical outside the replacement pockets.
const retained = previous.grass.patches.map(patch => makePatch(patch.id, patch.height_m <= .18 ? 'short' : 'dry', patch.height_m, patch.instances.filter(row => !touched(row.position_m[0], row.position_m[2])), 'Unchanged V2 placement outside V3 pockets')).filter(patch => patch.count);
const generated = Object.fromEntries(Object.keys(kinds).map(kind => [kind, []]));
const minima = Object.fromEntries(Object.keys(minimum).map(key => [key, Infinity]));
const pocketCounts = {};
let rejected = 0, proposed = 0, maximumSlope = 0;
const occupied = new Map();
function tooClose(x, z) {
    const cellX = Math.floor(x / .12), cellZ = Math.floor(z / .12);
    for (let ix = cellX - 1; ix <= cellX + 1; ix++) for (let iz = cellZ - 1; iz <= cellZ + 1; iz++) {
        if ((occupied.get(`${ix},${iz}`) || []).some(point => Math.hypot(x - point[0], z - point[1]) < .11)) return true;
    }
    const key = `${cellX},${cellZ}`;
    occupied.set(key, [...(occupied.get(key) || []), [x, z]]);
    return false;
}
for (const pocket of pockets) {
    const [x0, z0, x1, z1] = pocket.bounds;
    const attempts = Math.ceil((x1 - x0) * (z1 - z0) * pocket.density);
    pocketCounts[pocket.id] = {candidates: attempts, accepted: 0, by_kind: {short: 0, dry: 0, tall: 0, weed: 0}};
    for (let index = 0; index < attempts; index++) {
        proposed++;
        const x = x0 + random() * (x1 - x0), z = z0 + random() * (z1 - z0);
        const roadDistance = triangleUnionDistance(x, z, roadFaces);
        const treeDistance = Math.min(...trees.map(point => Math.hypot(x - point[0], z - point[1])));
        const large = noise(x + 2.4 * noise(x, z, 9, 11), z + 2.1 * noise(x, z, 7, 12), 4.4, 13);
        const fine = noise(x, z, 1.2, 14);
        const islands = smooth(.35, .64, large) * (.32 + .68 * fine);
        const roadContext = pocket.id === 'road' ? (1 - smooth(6.0, 11.5, roadDistance)) * smooth(.26, 1.0, roadDistance) : 1;
        const nearTree = 1 + .28 * (1 - smooth(1, 5, treeDistance));
        const density = clamp(islands * roadContext * nearTree, 0, .95);
        if (random() > density) { rejected++; continue; }
        const roll = random();
        let kind;
        if (roadDistance < 1.5) kind = roll < .52 ? 'weed' : roll < .88 ? 'short' : 'dry';
        else if (pocket.id.startsWith('entry')) kind = roll < .42 ? 'weed' : roll < .85 ? 'dry' : 'short';
        else kind = roll < .37 ? 'short' : roll < .88 ? 'dry' : roll < .965 ? 'tall' : 'weed';
        const gaps = clearances(x, z, kinds[kind].radius);
        if (!allowed(gaps)) { rejected++; continue; }
        const ground = terrain.heightAt(x, z), up = upAt(x, z);
        const slope = Math.acos(clamp(up[1], -1, 1)) * 180 / Math.PI;
        if (!Number.isFinite(ground) || slope > 25 || terrain.wet([x, z]) || tooClose(x, z)) { rejected++; continue; }
        maximumSlope = Math.max(maximumSlope, slope);
        Object.keys(minima).forEach(key => minima[key] = Math.min(minima[key], gaps[key]));
        generated[kind].push({position_m: [round(x), round(ground - .008), round(z)], ground_y_m: round(ground), up: up.map(value => Number(value.toFixed(8))), yaw_deg: round(random() * 360), tint: tint(kind)});
        pocketCounts[pocket.id].accepted++;
        pocketCounts[pocket.id].by_kind[kind]++;
    }
}
const newPatches = Object.entries(generated).map(([kind, instances]) => makePatch(`V3${kind[0].toUpperCase() + kind.slice(1)}`, kind, kinds[kind].height, instances, 'Deterministic warped density islands; geometry/route/root exclusions; cosmetic only')).filter(patch => patch.count);
const patches = [...retained, ...newPatches];
const grassCount = patches.reduce((sum, patch) => sum + patch.count, 0);
const grassTriangles = patches.reduce((sum, patch) => sum + patch.count * kinds[patch.mesh_kind].triangles, 0);
const reusedCount = previous.reused_assets.reduce((sum, group) => sum + group.instances.length, 0);
const reusedTriangles = previous.reused_assets.reduce((sum, group) => sum + group.expected_triangles * group.instances.length, 0);
const generatedCount = newPatches.reduce((sum, patch) => sum + patch.count, 0);
const retainedCount = retained.reduce((sum, patch) => sum + patch.count, 0);
assert(generatedCount > 1000, 'The pilot needs visible local clusters, not another sparse handful');
assert(pocketCounts.road.accepted > 1000);
assert(Object.values(generated).every(rows => rows.length));
assert.equal(reusedCount, 30);
for (const patch of retained) for (const row of patch.instances) assert(!touched(row.position_m[0], row.position_m[2]));
for (const patch of newPatches) for (const row of patch.instances) {
    assert(inBounds(row.position_m[0], row.position_m[2], bounds));
    assert(Math.abs(terrain.heightAt(row.position_m[0], row.position_m[2]) - row.ground_y_m) < .00001);
    assert(Math.abs(row.ground_y_m - row.position_m[1] - .008) < .000002);
    assert(allowed(clearances(row.position_m[0], row.position_m[2], kinds[patch.mesh_kind].radius)));
}
const plan = {
    schema_version: 1, seed, status: 'OFFLINE_PLACEMENT_CHECKED_NATIVE_ART_AND_PERFORMANCE_PENDING',
    scope: 'V3 bounded40m-road pilot plus small existing apartment/tree-contact pockets; no full-map rollout.',
    pilot_bounds_xz_m: bounds, unit_scale: true,
    authoring: 'Offline LCG + warped multiscale value-noise rejection, exact exported road unions and terrain triangles; no runtime RNG.',
    camera_reference: {xz_m: camera, target_xz_m: [-175, 24.4], eye_height_m: 1.7, fov_deg: 75},
    distribution: {pockets, minimum_footprint_clearance_m: minimum, maximum_slope_deg: 25, root_embed_m: .008, minimum_root_spacing_m: .11, large_noise_m: 4.4, fine_noise_m: 1.2, moisture: 'Existing hydrology excludes wet ground; pilot is dry, so no invented moisture simulation.', material: 'Road union and far-road soil control roadside density; foundation/tree context creates secondary sheltered pockets.'},
    exclusions: {generated_v3_minimum_footprint_clearance_m: minimum, retained_v2_source_rules: previous.exclusions, contract: 'V3 clearance values apply only to generated rows; retained coordinates/tints are kept from the Phase8 source. Blade geometry may change to the matching V3 silhouette.'},
    grass: {name: 'Four reusable opaque low-poly autumn silhouettes', height_range_m: [.1, .65], alpha: 'opaque;two-sided', collision: false, cast_shadow: false, visibility_end_m: 75, kinds, patches},
    reused_assets: previous.reused_assets,
    counts: {grass_tufts: grassCount, shrubs: previous.counts.shrubs, debris: previous.counts.debris, instances: grassCount + reusedCount, multimeshes: patches.length + previous.reused_assets.length, total_visual_triangles: grassTriangles + reusedTriangles},
    counts_are: 'Measured implementation observations, not approved hard budgets.',
    source_sha256: sources,
    static_validation: {generated_grass: generatedCount, retained_grass_unchanged: retainedCount, replaced_v2_grass: previous.counts.grass_tufts - retainedCount, unchanged_reused: reusedCount, candidates: proposed, rejected_candidates: rejected, new_grass_by_kind: Object.fromEntries(Object.entries(generated).map(([kind, rows]) => [kind, rows.length])), pockets: pocketCounts, minimum_new_grass_footprint_clearance_m: Object.fromEntries(Object.entries(minima).map(([key, value]) => [key, round(value)])), max_new_grass_slope_deg: round(maximumSlope), grass_triangles: grassTriangles, reused_triangles: reusedTriangles, native_support: 'PENDING', first_person_art: 'PENDING', performance: 'PENDING'}
};
const report = {status: 'OFFLINE_CHECKS_PASS_NATIVE_PENDING', seed, counts: plan.counts, ...plan.static_validation, apartment_tree_source: {path: 'Scene/World/Town500m/Art/apartment_pilot.tscn', trees: apartmentTrees}, exact_road_triangles_considered: roadFaces.length, exact_spur_triangles_considered: spurFaces.length, preservation: {source_plan_unchanged: true, reused_rows_unchanged: true, placements_outside_pockets_unchanged: true, writes_only_phase9: true}, limits: ['Native roots/collision/navigation/rendering/performance owned by primary integration.', 'Value-noise density does not simulate moisture; original material leaf detail is retained.', 'No new physics or AI concealment/penetration behavior.']};
function write(file, value) {
    const content = JSON.stringify(value, null, 2) + '\n', destination = path.join(__dirname, file);
    if (check) assert.equal(fs.readFileSync(destination, 'utf8'), content, `Stale ${file}`);
    else fs.writeFileSync(destination, content);
}
write('vegetation-plan.json', plan);
write('placement-report.json', report);
console.log(JSON.stringify({mode: check ? 'check' : 'write', ...plan.counts, generated_grass: generatedCount, retained_grass: retainedCount, pocket_counts: pocketCounts, plan_sha256: hash(JSON.stringify(plan, null, 2) + '\n')}));
