const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const terrain = require('../phase2/terrain-authoring.cjs');
const {worldBox, overlap3d} = require('./check-placement.cjs');

function review(placements, assets) {
    const byId = new Map(placements.map(row => [row.id, row]));
    const assetFor = row => assets.find(asset => asset.key === `${row.catalog_id}/${row.variant}`);
    function move(id, x, z) {
        const row = byId.get(id);
        assert(row, id);
        row.position_m[0] = x;
        row.position_m[2] = z;
        row.review = 'Exact reviewed coordinate correction after conservative footprint/contact check.';
        if (row.support.kind === 'terrain') {
            const height = terrain.heightAt(x, z);
            row.position_m[1] = height - assetFor(row).visual_bounds_godot_m[0][1] * row.scale[0];
            row.support.surface_y_m = height;
        }
    }
    move('OH-case-01', -51, -181);
    move('OF-debris-01', 120.9, -179.7);
    move('OA-feed-01', -202.8, 115);
    move('OA-tools-02', -49.9, 210.7);
    move('OR-rock-02', 49.2, -149.5);
    move('OL-litter', 192.5, 132.8);
    move('S_SECURITY_JERSEY_A', -174.8, -123.8);
    move('S_SECURITY_JERSEY_B', -172.6, -123.8);
    move('S_RIVER_SIGN', 40.2, -58.5);
    move('OF-trailer', 177, -139);
    move('T_ROAD_SEDAN_B', -11.23, 28.66);
    move('S_SHOP_NAMEPLATE', 8, -6.957);
    move('OB-B05-breaker', -198.005, -147);
    move('OB-B06-stop', -146, -126.495);
    move('OL-lifering', 188, 135.995);
    move('OB-B05-duct', -198.505, -145);
    // Keep upright native trunks in soil without crossing the protected paths.
    move('OT-H003', -73.454, -163.724);
    move('OT-F047', 92.65, -102.5);

    // Restrict this inherited support link to the actual floor that owns the stack.
    for (const id of ['I_WAREHOUSE_CRATE_C', 'I_WAREHOUSE_CRATE_D']) byId.get(id).support.building_host_id = 'I01-A';
    for (const row of placements) {
        if (typeof row.contact_exception !== 'string') continue;
        const reason = row.contact_exception;
        delete row.contact_exception;
        row.support.contact_note = reason;
        if (row.contacts_with_ids?.length) row.contact_exception = {with_ids: row.contacts_with_ids, reason};
    }
    for (const [id, others] of [
        ['OF-tarp', ['OF-cot', 'OF-table', 'OF-shelf', 'OF-woodcrate']],
        ['OB-supply-net', ['OB-supply-wood-01', 'OB-supply-wood-02']]
    ]) byId.get(id).contact_exception = {with_ids: others, reason: 'Full canopy envelope encloses the named furniture; individual roof/poles and furniture require native shape/eye-height verification.'};
    byId.get('OB-bunker-wiretop').support = {...byId.get('OB-bunker-wiretop').support, existing_scene_path: 'NavigationRegion3D/Level/Town500Dressing/Fences/BUNKER_0_4', contact_note: 'Specific north fence segment; exact native height/contact still required.'};
    byId.get('OB-bunker-wiretop').position_m = [-202.8375, 20.874749, -220.45];
    byId.get('OB-bunker-wiretop').support.surface_y_m = 20.874749;
    byId.get('S_HEAT_PIPE').support.host_ids = ['S_HEAT_SUPPORT_L', 'S_HEAT_SUPPORT_R'];
    byId.get('S_HEAT_PIPE').position_m[0] = 139.5;
    byId.get('S_HEAT_PIPE').support.contact_note = 'Long span supported at two separated saddles; a single-support footprint containment check is not applicable.';

    // Small local search within the authored yard, preserving each logical group.
    for (const id of ['I_YARD_FORKLIFT', 'I_YARD_BEAM_A', 'I_RAIL_SIGNAL']) {
        const row = byId.get(id), origin = [...row.position_m], candidates = [];
        for (let dx = -3; dx <= 3; dx += .5) for (let dz = -3; dz <= 3; dz += .5) candidates.push([dx, dz]);
        candidates.sort((a, b) => Math.hypot(...a) - Math.hypot(...b));
        for (const [dx, dz] of candidates) {
            const candidate = {...row, position_m: [origin[0] + dx, origin[1], origin[2] + dz]};
            const box = worldBox(candidate, assetFor(row).visual_bounds_godot_m);
            const heights = box.polygon.map(([x, z]) => terrain.heightAt(x, z));
            if (!heights.every(Number.isFinite) || Math.max(...heights) - Math.min(...heights) > .015) continue;
            if (placements.some(other => other.id !== id && overlap3d(box, worldBox(other, assetFor(other).visual_bounds_godot_m)))) continue;
            move(id, origin[0] + dx, origin[2] + dz);
            break;
        }
    }
    const contacts = JSON.parse(fs.readFileSync(path.join(__dirname, 'contact-adjustments.json'), 'utf8').replace(/^\uFEFF/, ''));
    for (const [id, contact] of Object.entries(contacts)) {
        const row = byId.get(id);
        assert(row && row.support.kind === 'terrain', `Unexpected native terrain contact: ${id}`);
        if (contact.scale) assert.deepEqual(row.scale, contact.scale, `Stale contact scale: ${id}`);
        if (contact.position_xz_m) assert.deepEqual([row.position_m[0], row.position_m[2]], contact.position_xz_m, `Stale contact position: ${id}`);
        row.rotation_deg = contact.rotation_deg;
        row.position_m[1] = contact.y;
        row.support.native_contact_adjustment = contact.evidence;
        if (contact.ground_contact === 'tree_root_embed') {
            row.ground_contact = contact.ground_contact;
            row.support.root_contact_gaps_m = contact.gaps_m;
        }
    }
    delete byId.get('OB-B06-hedgehog-01').rotation_deg;
    delete byId.get('OB-B06-hedgehog-01').support.native_contact_adjustment;
    move('OB-B06-hedgehog-01', -137, -132.25);
    for (const row of placements) {
        row.position_m = row.position_m.map(value => Number(value.toFixed(6)));
        if (!row.footprint_corners_xz_m) continue;
        const box = worldBox(row, assetFor(row).visual_bounds_godot_m);
        row.footprint_corners_xz_m = box.polygon.map(point => point.map(value => Number(value.toFixed(6))));
        if (row.support.kind === 'terrain') {
            const heights = box.polygon.map(([x, z]) => terrain.heightAt(x, z));
            row.support.terrain_sample_range_y_m = [Math.min(...heights), Math.max(...heights)].map(value => Number(value.toFixed(6)));
        }
    }
    return placements;
}
module.exports = {review};
