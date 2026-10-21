const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {analysis} = require('../../town-concept-b/check-los.cjs');
const {check, edges, pathLength, distance} = require('../check-layout.cjs');
const source = path.join(__dirname, '..');
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

function applyProposal(layout, proposal) {
    const result = structuredClone(layout);
    for (const move of proposal.structure_moves) Object.assign(result.structures.find(s => s.id === move.id), move);
    for (const replacement of proposal.corridor_replacements) {
        const corridor = result.corridors.find(c => c.id === replacement.id);
        Object.assign(corridor, replacement);
        const terrainCorridor = result.terrain.corrected_corridors.find(c => c.id === replacement.id);
        if (terrainCorridor) Object.assign(terrainCorridor, replacement);
    }
    for (const replacement of proposal.graph_edge_replacements || []) {
        Object.assign(result.terrain.route_graph.edges.find(e => e.id === replacement.id), replacement);
    }
    for (const corridor of proposal.additional_corridors || []) {
        const existing = result.corridors.find(c => c.id === corridor.id);
        if (existing) Object.assign(existing, corridor); else result.corridors.push(corridor);
    }
    result.dressing.cover = result.dressing.cover.filter(c => !(proposal.remove_cover_ids || []).includes(c.id));
    for (const cover of proposal.additional_cover) {
        const existing = result.dressing.cover.find(c => c.id === cover.id);
        if (existing) Object.assign(existing, cover); else result.dressing.cover.push(cover);
    }
    return result;
}

function inputFor(layout) {
    const input = {types: [], buildings: [], nodes: {}, roads: [], occluders: [], obstacles: []};
    const limits = {}, quick = {};
    for (const s of layout.structures) {
        input.types.push({id: s.id, footprint_m: s.footprint_m});
        input.buildings.push({id: s.id, type: s.id, xz: s.position_xz_m, yaw_deg: s.yaw_deg, opaque: s.height_m >= 2});
    }
    for (const c of layout.dressing.cover.filter(c => c.solid && c.opaque_proxy)) input.obstacles.push({id: c.id, kind: 'barrier', opaque: true, xz: c.position_xz_m, size_m: c.size_xyz_m, yaw_deg: c.yaw_deg});
    function add(id, points, width, limit) {
        limits[id] = limit;
        if (pathLength(points) + width <= limit) {quick[id] = {status: 'PASS', limit_m: limit, conservative_upper_bound_m: pathLength(points) + width, method: 'Whole path length plus width bound'}; return;}
        edges(points).forEach(([a, b], i) => {
            const from = `${id}_${i}a`, to = `${id}_${i}b`;
            input.nodes[from] = a; input.nodes[to] = b;
            input.roads.push({id: `${id}:${i}`, from, to, width_m: width, los_group: id});
        });
    }
    function clip(points, low, high) {
        const out = [];
        for (const [a, b] of edges(points)) {
            const dx = b[0] - a[0], t0 = Math.max(0, (low - a[0]) / dx), t1 = Math.min(1, (high - a[0]) / dx);
            if (t0 > t1) continue;
            for (const t of [t0, t1]) {const p = a.map((v, k) => v + t * (b[k] - v)); if (!out.length || distance(out.at(-1), p) > 1e-6) out.push(p);}
        }
        return out;
    }
    const county = layout.corridors.find(c => c.id === 'P01');
    add('M', clip(county.points_xz_m, -160.23, 39.77), county.width_m, 150);
    add('COUNTY_W', clip(county.points_xz_m, -250, -160.23), county.width_m, 200);
    add('COUNTY_E', clip(county.points_xz_m, 39.77, 250), county.width_m, 200);
    for (const c of layout.corridors.filter(c => c.id !== 'P01' && !c.id.startsWith('GR_'))) add(c.id, c.points_xz_m, c.width_m, c.type === 'rail' ? 200 : ['P05', 'P06'].includes(c.id) || c.id.startsWith('ACCESS_T') || c.id.startsWith('TOWN_') ? 80 : 120);
    for (const e of layout.terrain.route_graph.edges.filter(e => ['G01', 'G02', 'G03', 'G04', 'G15', 'G19', 'G20'].includes(e.id))) add(`ROUTE_${e.id}`, e.points_xz_m, e.clear_width_m, e.id === 'G04' ? 200 : 120);
    return {input, limits, quick};
}

function run(layout, proposal, options = {}) {
    const proposed = applyProposal(layout, proposal), spatial = check(proposed);
    const {input, limits, quick} = inputFor(proposed);
    // Spatial failure stays visible; a failed candidate is never silently certified as buildable.
    const result = analysis(input, {angleStepDeg: options.angleStepDeg || 0.5, certify: false, groups: options.groups});
    const passing = Object.keys(result.groups).filter(id => result.groups[id].measured_max_m <= limits[id]);
    if (passing.length && options.certify !== false) Object.assign(result.groups, analysis(input, {angleStepDeg: 0.5, boundAngleStepDeg: 0.1, certify: true, groups: passing}).groups);
    for (const [id, group] of Object.entries(result.groups)) {
        group.limit_m = limits[id];
        group.status = group.measured_max_m > limits[id] + 1e-6 ? 'FAIL' : group.conservative_upper_bound_m !== null && group.conservative_upper_bound_m <= limits[id] ? 'PASS' : 'UNRESOLVED';
    }
    const groups = {...(options.groups ? {} : quick), ...result.groups};
    return {status: spatial.status !== 'PASS' ? 'SPATIAL FAIL' : Object.values(groups).every(g => g.status === 'PASS') ? '2D PROXY PASS; NATIVE PENDING' : 'HOLD', spatial, groups, scope: result.scope, method: result.method, blockers: result.blockers, native_verified: false};
}

if (require.main === module) {
    const layout = JSON.parse(fs.readFileSync(path.join(source, 'layout.json')));
    const proposal = JSON.parse(fs.readFileSync(path.join(__dirname, 'dressing-proposal.json')));
    const groupArg = process.argv.find(a => a.startsWith('--groups='));
    const angleArg = process.argv.find(a => a.startsWith('--angle='));
    const report = run(layout, proposal, {groups: groupArg?.split('=')[1].split(','), angleStepDeg: angleArg ? Number(angleArg.split('=')[1]) : 0.5, certify: !process.argv.includes('--sample-only')});
    report.source_sha256 = {'layout.json': hash(path.join(source, 'layout.json')), 'dressing-proposal.json': hash(path.join(__dirname, 'dressing-proposal.json'))};
    if (!groupArg && !process.argv.includes('--sample-only')) {
        const content = JSON.stringify(report, null, 2) + '\n', file = path.join(__dirname, 'los-proposal-report.json');
        if (process.argv.includes('--check')) require('node:assert/strict').equal(fs.readFileSync(file, 'utf8'), content, 'Stale LOS report'); else fs.writeFileSync(file, content);
    }
    console.log(JSON.stringify({status: report.status, spatial: report.spatial.errors, groups: Object.fromEntries(Object.entries(report.groups).map(([id, g]) => [id, {status: g.status, measured_m: g.measured_max_m, upper_m: g.conservative_upper_bound_m, endpoints: g.witness_endpoints_xz}]))}, null, 2));
}
module.exports = {applyProposal, inputFor, run};
