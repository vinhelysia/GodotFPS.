// Independent offline candidate. No canonical, scene, terrain or dressing writes.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {applyProposal, inputFor} = require('./check-phase3-los.cjs');
const {check, pathLength} = require('../check-layout.cjs');
const {analysis} = require('../../town-concept-b/check-los.cjs');
const source = require('../layout.json');
const base = JSON.parse(fs.readFileSync(`${__dirname}/dressing-proposal.json`));
const layout = applyProposal(source, base);
const originalForest = source.corridors.find(c => c.id === 'P07');
const forestPoints = [originalForest.points_xz_m[0], originalForest.points_xz_m[1],
    [106.82, -74], [88, -74], [88, -94], [106.82, -94], ...originalForest.points_xz_m.slice(2, 4),
    [145, -136.36], [145, -156], ...originalForest.points_xz_m.slice(4)];
const forestHeights = forestPoints.map((p, i) => i < forestPoints.length - 2 ? 3 : 2);
const farmPoints = [[-190, 120], [-179, 160], [-179, 183], [-130, 183], [-104, 183], [-104, 205], [-100, 210], [-65, 220], [-65, 235]];
const farmHeights = farmPoints.map(() => 1.5);
const changes = {corridor_replacements: [], graph_edge_replacements: [], cover_replacements: [], additional_cover: []};
function replaceCorridor(id, points, heights, reason) {
    const corridor = layout.corridors.find(c => c.id === id);
    assert(corridor, id);
    const replacement = {id, points_xz_m: points, surface_y_m: heights, reason};
    Object.assign(corridor, replacement);
    const terrainCorridor = layout.terrain.corrected_corridors.find(c => c.id === id);
    if (terrainCorridor) Object.assign(terrainCorridor, replacement);
    changes.corridor_replacements.push(replacement);
}
function replaceGraph(id, points, heights, reason) {
    const edge = layout.terrain.route_graph.edges.find(e => e.id === id);
    assert(edge, id);
    assert.deepEqual(points[0], edge.points_xz_m[0]);
    assert.deepEqual(points.at(-1), edge.points_xz_m.at(-1));
    const replacement = {id, points_xz_m: points, surface_y_m: heights, reason};
    Object.assign(edge, replacement);
    changes.graph_edge_replacements.push(replacement);
    replaceCorridor(`GR_${id}`, points, heights, reason);
}
const forestReason = 'Forest extraction trail follows the west end of an opaque forestry-service boundary and skirts the east side of a granite outcrop; fixed tree trunks and cache remain clear.';
const farmReason = 'Farm extraction path follows the east end of a feed-yard property return north of A06, then rejoins the original southwest extraction approach; no extra route group or extraction changes.';
replaceCorridor('P07', forestPoints, forestHeights, forestReason);
replaceGraph('G13', forestPoints.slice(0, 7), forestHeights.slice(0, 7), forestReason);
replaceGraph('G14', forestPoints.slice(6), forestHeights.slice(6), forestReason);
replaceCorridor('P11', farmPoints, farmHeights, farmReason);
replaceGraph('G17', farmPoints, farmHeights, farmReason);
const forestryReturn = {id: 'LOS_P07_YARD', position_xz_m: [118.75, -82], size_xyz_m: [45.5, 3, .5], reason: forestReason};
Object.assign(layout.dressing.cover.find(c => c.id === forestryReturn.id), forestryReturn);
changes.cover_replacements.push(forestryReturn);
const granite = {id: 'LOS_P07_ROCK', position_xz_m: [165.5, -166], size_xyz_m: [23, 5, 14], reason: 'Keep the existing bluff east edge and extend its west edge3m to close the final tangent extraction vista.'};
Object.assign(layout.dressing.cover.find(c => c.id === granite.id), granite);
changes.cover_replacements.push(granite);
for (const cover of [
    {id: 'LOS_P07_GRANITE_RETURN', los_group: 'P07', position_xz_m: [130, -146], size_xyz_m: [20, 5, 8], kind: 'rock_bluff', reason: 'Granite outcrop closes the long cross-clearing bypass; extraction trail passes around its east side.'},
    {id: 'LOS_P11_PROPERTY_RETURN', los_group: 'P11', position_xz_m: [-141, 174], size_xyz_m: [72, 3, .3], kind: 'opaque_farm_property_return', reason: farmReason},
    {id: 'LOS_P11_FIELD_CORNER', los_group: 'P11', position_xz_m: [-173, 177.325], size_xyz_m: [.3, 3, 5.35], kind: 'opaque_farm_property_return', reason: 'Short feed-yard boundary corner closes the west diagonal; the path passes south of its end.'}
]) {
    const row = {...cover, yaw_deg: 0, solid: true, opaque_proxy: true, collider_role: 'solid_cover', source_ref: 'PHASE3_LOS', model_status: 'dimensioned graybox; native/finished art pending'};
    layout.dressing.cover.push(row);
    changes.additional_cover.push(row);
}
const spatial = check(layout);
const groups = ['P07', 'P11'];
const {input} = inputFor(layout);
const result = analysis(input, {groups, angleStepDeg: process.argv.includes('--quick') ? 2 : .5, boundAngleStepDeg: .1, certify: !process.argv.includes('--quick')});
for (const group of Object.values(result.groups)) {
    group.limit_m = 120;
    group.status = group.measured_max_m > 120 ? 'FAIL' : group.conservative_upper_bound_m !== null && group.conservative_upper_bound_m <= 120 ? 'PASS' : 'UNRESOLVED';
}
result.status = Object.values(result.groups).every(g => g.status === 'PASS') ? 'PASS' : 'HOLD';
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const report = {status: spatial.status !== 'PASS' ? 'SPATIAL_FAIL' : result.status === 'PASS' ? '2D_PROXY_PASS_NATIVE_PENDING' : 'HOLD',
    scope: 'Independent P07 forest/P11 farm only; all original group extents and120m limits preserved.',
    source_sha256: Object.fromEntries(['layout.json', 'phase3/dressing-proposal.json', 'phase3/check-phase3-los.cjs'].map(file => [file, sha(`${__dirname}/../${file}`)])),
    changes, spatial, groups: result.groups, method: result.method, scope_of_certificate: result.scope,
    route_lengths_m: {P07: {before: pathLength(originalForest.points_xz_m), after: pathLength(forestPoints)}, P11: {before: pathLength(source.corridors.find(c => c.id === 'P11').points_xz_m), after: pathLength(farmPoints)}},
    integration: ['Apply matching P07/P11 and GR_G13/GR_G17 corridor replacements to canonical layout AND terrain contract.',
        'Apply G13/G17 edge polylines/profiles to terrain.route_graph; endpoints, node IDs, bank ownership, bridges and links stay identical.',
        'Preserve the base dressing proposal; append only these new opaque return pieces.',
        'Rebuild static terrain/circulation authoring after canonical changes; old walking/nav receipts are historical until retested.',
        'Rerun canonical check-layout and full Phase3 LOS certificate, then native stand/ADS/bothlean/upstairs and physical routes.'],
    native_verified: false};
if (!process.argv.includes('--quick')) {
    const file = `${__dirname}/los-forest-farm-proposal.json`, content = JSON.stringify(report, null, 2) + '\n';
    if (process.argv.includes('--check')) assert.equal(fs.readFileSync(file, 'utf8'), content, 'Stale forest/farm proposal');
    else fs.writeFileSync(file, content);
}
console.log(JSON.stringify({status: report.status, spatial_errors: spatial.errors, groups: result.groups, route_lengths_m: report.route_lengths_m}, null, 2));
