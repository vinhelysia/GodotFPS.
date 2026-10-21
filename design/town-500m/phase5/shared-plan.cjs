const fs = require('node:fs');
const assert = require('node:assert/strict');
const path = require('node:path');
const terrain = require('../phase2/terrain-authoring.cjs');
const assets = JSON.parse(fs.readFileSync(path.join(__dirname, 'asset-catalog.json'))).assets;
const placements = [];

function ground(id, zone, catalog_id, variant, x, z, yaw, finish, role, group) {
    const asset = assets.find(row => row.key === `${catalog_id}/${variant}`);
    assert(asset, catalog_id);
    const surface = terrain.heightAt(x, z);
    assert(Number.isFinite(surface), id);
    const row = {id, zone, catalog_id, variant, finish, position_m: [x, Number((surface - asset.visual_bounds_godot_m[0][1]).toFixed(6)), z], yaw_deg: yaw, scale: [1, 1, 1], support: {kind: 'terrain', surface_y_m: surface}, collision_policy: asset.collision_role === 'none' || asset.collision_role === 'decorative' ? 'visual_only' : 'native', role, rationale: role, assembly_group: group};
    placements.push(row);
    return row;
}

// Exact authored yards/roadside groups, never a random world scatter.
ground('S_SECURITY_BAGS_A', 'bunker', 'shared_sandbag_barrier', 'straight', -175, -119, 0, 'used', 'Roadside guard position west of the existing south gate', 'south-gate-security');
ground('S_SECURITY_BAGS_B', 'bunker', 'shared_sandbag_barrier', 'straight', -172.1, -119, 0, 'worn', 'Adjacent matching guard position, preserving the open approach', 'south-gate-security');
ground('S_SECURITY_JERSEY_A', 'bunker', 'shared_concrete_jersey_barrier', 'intact', -174.8, -121, 0, 'used', 'Concrete protection behind the guard bag line', 'south-gate-security');
ground('S_SECURITY_JERSEY_B', 'bunker', 'shared_concrete_jersey_barrier', 'damaged', -172.6, -121, 0, 'worn', 'Matching second barrier with selective damage', 'south-gate-security');

for (let i = 0; i < 3; i++) ground(`S_T09_FENCE_${i + 1}`, 'town', 'shared_wood_fence', i === 2 ? 'broken' : 'plank', -149 + i * 2.15, 140, 0, i === 1 ? 'used' : 'worn', 'Same-type remnants of the damaged residential garden boundary', 'T09-garden-boundary');
for (let i = 0; i < 3; i++) ground(`S_DEPOT_FENCE_${i + 1}`, 'town', 'shared_metal_fence', 'straight', -36 + i * 2.13, 85, 0, i === 1 ? 'clean' : 'used', 'Matching municipal depot yard boundary, leaving both ends open', 'depot-yard-boundary');
for (let i = 0; i < 3; i++) ground(`S_FACTORY_FENCE_${i + 1}`, 'industry', 'shared_chainlink_fence', 'straight', 132, -106 + i * 2.13, 90, 'used', 'Coherent factory utility-yard partition clear of the warehouse door', 'factory-utility');

for (const [id, zone, x, z] of [['W', 'farmland', -175, 5], ['T', 'town', 0, 12], ['I', 'industry', 125, -104]]) ground(`S_POLE_${id}`, zone, 'shared_concrete_utility_pole', 'insulators', x, z, 0, 'used', 'Remnant roadside utility line; no powered gameplay dependency', 'roadside-utilities');
ground('S_UTILITY_TRUCK', 'industry', 'shared_utility_truck', 'parked', 167, -102, 90, 'worn', 'Abandoned maintenance truck parked in the north service yard', 'factory-utility');
ground('S_REPAIR_SLAB', 'industry', 'shared_concrete_slab', 'horizontal', 138, -100, 0, 'used', 'Stored service slab on the utility-yard perimeter', 'factory-utility');
ground('S_REPAIR_RUBBLE', 'industry', 'shared_concrete_rubble', 'small', 137, -103, 15, 'worn', 'Small demolished footing beside the stored service slab', 'factory-utility');
ground('S_REPAIR_SHEET', 'industry', 'shared_corrugated_sheet', 'bent', 141, -104, 8, 'worn', 'Removed damaged roofing sheet beside the utility repair stock', 'factory-utility');

const left = ground('S_HEAT_SUPPORT_L', 'industry', 'shared_district_heating_pipe', 'support', 140, -108, 0, 'used', 'Left pipe saddle on the service-yard perimeter', 'district-heating-remnant');
const right = ground('S_HEAT_SUPPORT_R', 'industry', 'shared_district_heating_pipe', 'support', 143, -108, 0, 'used', 'Right matching pipe saddle', 'district-heating-remnant');
const pipe = ground('S_HEAT_PIPE', 'industry', 'shared_district_heating_pipe', 'straight', 141.5, -108, 0, 'used', 'Disconnected district-heating section seated on matching supports', 'district-heating-remnant');
const supportAsset = assets.find(row => row.key === `${left.catalog_id}/${left.variant}`);
const pipeAsset = assets.find(row => row.key === `${pipe.catalog_id}/${pipe.variant}`);
const supportTop = Math.max(left.position_m[1], right.position_m[1]) + supportAsset.visual_bounds_godot_m[1][1];
pipe.position_m[1] = Number((supportTop - pipeAsset.visual_bounds_godot_m[0][1]).toFixed(6));
pipe.support = {kind: 'surface', host_id: left.id, surface_y_m: supportTop};
pipe.contact_exception = {with_ids: [left.id, right.id], reason: 'Pipe rests on its two authored saddles; contact is intentional.'};

for (const [id, x, z, variant] of [['T', -115, 25, 'round'], ['I', 135, 45, 'rectangular']]) {
    const row = ground(`S_MANHOLE_${id}`, id === 'T' ? 'town' : 'industry', 'shared_manhole_cover', variant, x, z, 0, 'used', 'Flush municipal drain cover; visual-only surface detail', 'drainage');
    row.collision_policy = 'visual_only';
}
ground('S_FARM_SIGN', 'farmland', 'shared_wood_post_sign', 'direction', -175, 177, 90, 'used', 'Farm approach direction marker on the verge, outside the extraction pad', 'farm-entry');
ground('S_RIVER_SIGN', 'river', 'shared_wood_post_sign', 'warning', 42, -56, 0, 'worn', 'Riverbank warning beside the existing northern bridge approach', 'bridge-warning');

const signAsset = assets.find(row => row.key === 'shared_cyrillic_signs/nameplate');
placements.push({id: 'S_SHOP_NAMEPLATE', zone: 'town', catalog_id: signAsset.catalog_id, variant: signAsset.variant, finish: 'used', position_m: [8, 3.55 - signAsset.visual_bounds_godot_m[0][1], -6.83], yaw_deg: 0, scale: [1, 1, 1], support: {kind: 'wall', host_id: 'T04-A', evidence: 'Town corner shop front exterior face: root(10,2.2,-11), yaw180, frontlocalZ=-4; plaque clear of door.'}, collision_policy: 'visual_only', role: 'Cyrillic corner-shop identification fixed to front wall', rationale: 'Sign follows the existing shop façade and keeps the central doorway clear.'});

fs.writeFileSync(path.join(__dirname, 'shared-placement.json'), JSON.stringify({schema_version: 1, placements, deferred: []}, null, 2) + '\n');
console.log(`SHARED_PLAN ${placements.length} authored instances`);
