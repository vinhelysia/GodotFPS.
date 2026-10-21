// Offline merge of reviewed Phase3 placement corrections, never loaded by Godot.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {applyProposal} = require('./check-phase3-los.cjs');
const {check} = require('../check-layout.cjs');
const root = path.resolve(__dirname, '..');
const read = file => JSON.parse(fs.readFileSync(path.join(root, file), 'utf8'));
const bytes = data => JSON.stringify(data, null, 2) + '\n';
const hash = data => crypto.createHash('sha256').update(data).digest('hex');
const proposal = read('phase3/dressing-proposal.json');
const catalogue = read('building-catalogue.json');
const terrain = read('terrain-contract.json');
const layout = applyProposal(read('layout.json'), proposal);
for (const move of proposal.structure_moves) {
    const structure = catalogue.structures.find(s => s.id === move.id);
    assert(structure, move.id);
    structure.position_xz_m = move.position_xz_m;
}
for (const replacement of proposal.corridor_replacements) {
    const corridor = terrain.corrected_corridors.find(c => c.id === replacement.id);
    if (corridor) Object.assign(corridor, replacement);
    else assert(replacement.id.startsWith('GR_') && terrain.route_graph.edges.some(e => 'GR_' + e.id === replacement.id), replacement.id);
}
for (const replacement of proposal.graph_edge_replacements || []) {
    const edge = terrain.route_graph.edges.find(e => e.id === replacement.id);
    assert(edge, replacement.id);
    Object.assign(edge, replacement);
}
for (const addition of proposal.additional_corridors || []) {
    const corridor = terrain.corrected_corridors.find(c => c.id === addition.id);
    if (corridor) Object.assign(corridor, addition); else terrain.corrected_corridors.push(addition);
}
layout.terrain = terrain;
layout.structures = catalogue.structures;
layout.status = 'Phase3 canonical graybox composition; native acceptance pending';
layout.provenance.phase3_proposal_sha256 = hash(fs.readFileSync(path.join(root, 'phase3/dressing-proposal.json')));
const contents = {'building-catalogue.json': bytes(catalogue), 'terrain-contract.json': bytes(terrain)};
for (const entry of layout.provenance.contracts) {
    entry.sha256 = hash(contents[entry.path] || fs.readFileSync(path.join(root, entry.path)));
}
const spatial = check(layout);
assert.equal(spatial.status, 'PASS', spatial.errors.join('\n'));
contents['layout.json'] = bytes(layout);
for (const [file, content] of Object.entries(contents)) {
    if (process.argv.includes('--check')) assert.equal(fs.readFileSync(path.join(root, file), 'utf8'), content, file);
    else fs.writeFileSync(path.join(root, file), content);
}
console.log(JSON.stringify({mode: process.argv.includes('--check') ? 'check' : 'write', spatial: spatial.status, counts: spatial.counts}));
