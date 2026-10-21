// Offline task receipt; native physics, terrain-pilot contact and navigation remain separate gates.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {worldBox} = require('../phase5/check-placement.cjs');
const {rectangle, polygonDistance} = require('../check-layout.cjs');
const root = path.resolve(__dirname, '../../..');
const snapshot = path.resolve(root, '../.agent-snapshots/town500_unit_scale_20261020');
const phase5 = 'design/town-500m/phase5/';
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const json = file => JSON.parse(read(file).replace(/^\uFEFF/, ''));
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const sourceHashes = {};
function bind(file) {
    sourceHashes[file] = sha(path.join(root, file));
}

const before = JSON.parse(fs.readFileSync(path.join(snapshot, phase5, 'placement-plan.json')));
const plan = json(phase5 + 'placement-plan.json');
const assets = new Map(json(phase5 + 'asset-catalog.json').assets.map(asset => [asset.key, asset]));
assert.equal(plan.placements.length, 371);
assert.deepEqual(plan.placements.map(row => row.id).sort(), before.placements.map(row => row.id).sort());
assert.deepEqual(plan.coverage, before.coverage, 'Coverage and justified deferrals must be preserved');
const oldRows = new Map(before.placements.map(row => [row.id, row]));
const changes = [];
const sources = ['town-industry-placement.json', 'outer-placement.json', 'shared-placement.json', 'placement-plan.json'];
for (const file of sources) {
    for (const row of json(phase5 + file).placements) assert.deepEqual(row.scale, [1, 1, 1], `${file}: ${row.id}`);
    bind(phase5 + file);
}

const dressing = read('Scene/World/Town500m/Art/dressing.tscn');
const seenRetired = new Set();
for (const row of plan.placements) {
    const old = oldRows.get(row.id);
    assert.equal(row.catalog_id, old.catalog_id, `Species/type changed: ${row.id}`);
    assert.equal(row.variant, old.variant, `Geometry variant changed: ${row.id}`);
    assert.equal(row.finish, old.finish, `Finish changed: ${row.id}`);
    const sceneFile = `Scene/World/Town500m/Props/${row.zone}.tscn`;
    const scene = read(sceneFile);
    const block = scene.split(`[node name="${row.id}" parent="." instance=`)[1]?.split('\n\n')[0];
    assert(block, `Missing scene instance: ${row.id}`);
    assert(block.includes('scale = Vector3(1, 1, 1)'), `Scene scale: ${row.id}`);
    const actualPosition = block.match(/position = Vector3\(([^)]+)\)/)[1].split(',').map(Number);
    assert(actualPosition.every((value, axis) => Math.abs(value - row.position_m[axis]) < 1e-6), `Scene position: ${row.id}`);
    const actualRotation = block.match(/rotation = Vector3\(([^)]+)\)/)[1].split(',').map(Number);
    assert(actualRotation.every((value, axis) => Math.abs(value - (row.rotation_deg || [0, row.yaw_deg, 0])[axis] * Math.PI / 180) < 1e-6), `Scene rotation: ${row.id}`);
    const resourceId = block.match(/^ExtResource\("([^"]+)"\)/)[1];
    assert(scene.includes(`path="${row.scene_ref}" id="${resourceId}"`), `Scene resource: ${row.id}`);
    const wrapper = row.scene_ref.slice(6);
    assert(!/^(scale|transform) = /m.test(read(wrapper)), `Wrapper compensation: ${row.id}`);
    bind(sceneFile);
    bind(wrapper);
    if (row.proxy_replacement?.kind === 'vegetation_native_replacement') {
        assert.equal(row.collision_policy, 'native');
        assert.equal(row.proxy_replacement.preserve_collision, false);
        const shapePath = `Concealment/${row.proxy_id}/TrunkBody/Shape`;
        assert.equal(row.proxy_replacement.retired_shape_path, shapePath);
        assert(!seenRetired.has(shapePath), `Duplicate retirement: ${shapePath}`);
        seenRetired.add(shapePath);
        assert(dressing.includes(`[node name="Shape" parent="Concealment/${row.proxy_id}/TrunkBody" ]\ndisabled = true`), `Old trunk still active: ${row.id}`);
        assert(dressing.includes(`[node name="${row.proxy_id}" parent="Concealment" ]\nvisible = false`), `Old tree visual still visible: ${row.id}`);
        assert(!/^process_mode = 4$/m.test(read(wrapper)), `Native tree helper disabled: ${row.id}`);
    }
    const fields = ['scale', 'position_m', 'rotation_deg', 'collision_policy', 'scene_ref'];
    const changed = fields.filter(field => JSON.stringify(row[field]) !== JSON.stringify(old[field]));
    if (changed.length) changes.push({id: row.id, fields: changed, before: Object.fromEntries(changed.map(field => [field, old[field] ?? null])), after: Object.fromEntries(changed.map(field => [field, row[field] ?? null]))});
}
assert.equal(seenRetired.size, 93);
assert.equal(changes.filter(row => row.fields.includes('scale')).length, 113);

// The original import receipt binds asset bytes independently of the revised placement plan.
const importReceipt = json(phase5 + 'asset-import-report.json');
for (const row of importReceipt.files) {
    const file = row.res_path.slice(6);
    assert.equal(sha(path.join(root, file)), row.sha256, `Imported payload changed: ${file}`);
    bind(file);
    if (fs.existsSync(path.join(root, file + '.import'))) bind(file + '.import');
}
const apartmentYard = rectangle([-162.75, 58], [29.5, 52], 0);
for (const row of plan.placements) {
    const box = worldBox(row, assets.get(`${row.catalog_id}/${row.variant}`).visual_bounds_godot_m);
    assert(polygonDistance(box.polygon, apartmentYard) > 1e-4, `Apartment reservation conflict: ${row.id}`);
}
const check = json(phase5 + 'placement-check.json');
assert.equal(check.status, 'OFFLINE_CHECK_PASS_NATIVE_PENDING');
assert.equal(check.errors.length, 0);
assert.equal(check.source_sha256['placement-plan.json'], sourceHashes[phase5 + 'placement-plan.json'], 'Stale placement check');
for (const file of ['town-industry-plan.cjs', 'outer-plan.cjs', 'shared-plan.cjs', 'author-placement.cjs', 'review-placement.cjs', 'check-placement.cjs', 'contact-adjustments.json', 'placement-check.json', 'asset-catalog.json']) bind(phase5 + file);
for (const file of ['Scene/World/Town500m/Props/town_props.tscn', 'Scene/World/Town500m/Art/dressing.tscn', 'Scene/World/Town500m/Art/industry.tscn', 'Scene/World/Town500m/Dressing/dressing.tscn', 'Scene/Town.tscn', 'project.godot', 'tests/town500_props_capture_regression.gd', 'design/town-500m/phase6/check-unit-scale.cjs']) bind(file);
const protectedBefore = JSON.parse(fs.readFileSync(path.join(snapshot, 'protected-start.json'), 'utf8').replace(/^\uFEFF/, ''));
const protectedSources = protectedBefore.map(row => ({path: path.relative(root, row.Path).replaceAll('\\', '/'), before_sha256: row.Hash.toLowerCase(), after_sha256: sha(row.Path), unchanged: sha(row.Path) === row.Hash.toLowerCase()}));
const report = {
    status: 'OFFLINE_UNIT_SCALE_PASS_NATIVE_PENDING',
    instances: 371, native_scale_instances: 371, corrected_nonunit_instances: 113,
    catalogue_types: plan.counts.catalogue_types, covered_types: plan.counts.planned_types, deferred_types: plan.counts.deferred_types,
    native_tree_helpers_enabled: 93, exact_old_trunk_shapes_retired: seenRetired.size,
    unchanged_imported_payloads: importReceipt.files.length,
    apartment_yard_reservation_conflicts: [], protected_sources: protectedSources, changes,
    native_town_verified: false, source_sha256: sourceHashes,
    limits: ['No Godot MCP or CLI operation in this file-only job; editor belongs to primary.', 'Previous Phase5 native receipts precede this geometry revision and are historical.', 'Canonical phase2 terrain support calculations need fresh rays against final terrain pilot.', 'Primary must verify native helpers, contacts, routes/interiors/bridges/LOS and final navigation after apartment integration.'],
};
fs.writeFileSync(path.join(__dirname, 'unit-scale-verification.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({status: report.status, instances: report.instances, corrected: report.corrected_nonunit_instances, retired_trunks: report.exact_old_trunk_shapes_retired, imported_payloads_unchanged: report.unchanged_imported_payloads, sources: Object.keys(sourceHashes).length}));
