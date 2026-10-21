const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {rectangle, polygonDistance, segmentPolygon, inside, edges} = require('../check-layout.cjs');
const {applyProposal} = require('../phase3/check-phase3-los.cjs');
const terrain = require('../phase2/terrain-authoring.cjs');
const {wrapperPath} = require('./import-assets.cjs');

const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const EPS = 1e-4;
const isTree = asset => /^forest_(pine|spruce|birch)_tree$/.test(asset.catalog_id);
const numbers = (value, length) => Array.isArray(value) && value.length === length && value.every(Number.isFinite);

function worldBox(placement, bounds) {
    if (placement.rotation_deg) {
        const [rx, ry, rz] = placement.rotation_deg.map(value => value * Math.PI / 180);
        const points = [];
        for (const x of [bounds[0][0], bounds[1][0]]) for (const y of [bounds[0][1], bounds[1][1]]) for (const z of [bounds[0][2], bounds[1][2]]) {
            // Godot's default Euler order is YXZ. Keep Y for the existing oriented-box checks.
            const a = x * Math.cos(rz) - y * Math.sin(rz), b = x * Math.sin(rz) + y * Math.cos(rz);
            points.push([a, b * Math.cos(rx) - z * Math.sin(rx), b * Math.sin(rx) + z * Math.cos(rx)]);
        }
        const tiltedBounds = [0, 1].map(side => [0, 1, 2].map(axis => (side ? Math.max : Math.min)(...points.map(point => point[axis]))));
        const {rotation_deg, ...yawPlacement} = placement;
        return worldBox({...yawPlacement, yaw_deg: ry * 180 / Math.PI}, tiltedBounds);
    }
    const scale = placement.scale[0], yaw = placement.yaw_deg * Math.PI / 180;
    const localCenter = [0, 1, 2].map(axis => (bounds[0][axis] + bounds[1][axis]) * scale / 2);
    const size = [0, 1, 2].map(axis => (bounds[1][axis] - bounds[0][axis]) * scale);
    const center = [placement.position_m[0] + Math.cos(yaw) * localCenter[0] + Math.sin(yaw) * localCenter[2], placement.position_m[1] + localCenter[1], placement.position_m[2] - Math.sin(yaw) * localCenter[0] + Math.cos(yaw) * localCenter[2]];
    return {center, size, yaw_deg: placement.yaw_deg, polygon: rectangle([center[0], center[2]], [size[0], size[2]], placement.yaw_deg), min_y: center[1] - size[1] / 2, max_y: center[1] + size[1] / 2};
}

function overlap3d(a, b) {
    const yDepth = Math.min(a.max_y, b.max_y) - Math.max(a.min_y, b.min_y);
    if (yDepth <= EPS) return null;
    let minimumDepth = yDepth;
    for (const box of [a, b]) for (let edge = 0; edge < 2; edge++) {
        const start = box.polygon[edge], end = box.polygon[edge + 1];
        const dx = end[0] - start[0], dz = end[1] - start[1], length = Math.hypot(dx, dz);
        if (length <= EPS) return null;
        const axis = [-dz / length, dx / length];
        const project = polygon => polygon.map(point => point[0] * axis[0] + point[1] * axis[1]);
        const ap = project(a.polygon), bp = project(b.polygon);
        const depth = Math.min(Math.max(...ap), Math.max(...bp)) - Math.max(Math.min(...ap), Math.min(...bp));
        if (depth <= EPS) return null;
        minimumDepth = Math.min(minimumDepth, depth);
    }
    return {minimum_axis_overlap_m: minimumDepth, y_overlap_m: yDepth};
}

function validate(plan, catalog, layout, heightAt = terrain.heightAt) {
    const errors = [], warnings = [], contacts = [], crownExemptions = [], terrainFits = [], accepted = [];
    const add = (type, ids, detail) => errors.push({type, ids: ids.filter(Boolean), ...detail});
    const assets = new Map(catalog.assets.map(asset => [asset.key, asset]));
    const types = new Set(catalog.assets.map(asset => asset.catalog_id));
    const structures = new Map(layout.structures.map(structure => [structure.id, structure]));
    const covers = new Map((layout.dressing.cover || []).map(cover => [cover.id, cover]));
    const trees = new Map((layout.dressing.vegetation || []).map(tree => [tree.id, tree]));
    const bridges = new Map((layout.terrain.bridges || []).map(bridge => [bridge.id, bridge]));
    const placed = new Map(), covered = new Set(), deferred = new Map();
    const records = plan.placements;
    if (!Array.isArray(records)) return {status: 'FAIL', errors: [{type: 'invalid_plan', ids: [], reason: 'placements[] is required'}], warnings};
    const replacedTrees = new Set(records.filter(row => row.collision_policy === 'native' && row.proxy_replacement?.kind === 'vegetation_native_replacement' && row.proxy_replacement.preserve_collision === false).map(row => row.proxy_id));
    for (const entry of plan.deferred || plan.deferred_types || []) {
        if (!types.has(entry.catalog_id) || typeof entry.reason !== 'string' || !entry.reason.trim()) add('invalid_deferral', [entry.catalog_id], {reason: 'Each deferred type needs a known catalog_id and a concrete reason'});
        else if (deferred.has(entry.catalog_id)) add('duplicate_deferral', [entry.catalog_id], {});
        else deferred.set(entry.catalog_id, entry.reason.trim());
    }
    for (const placement of records) {
        if (typeof placement.id !== 'string' || !placement.id.trim()) {add('invalid_id', [], {record: placement}); continue;}
        if (placed.has(placement.id)) {add('duplicate_id', [placement.id], {}); continue;}
        placed.set(placement.id, placement);
        const key = placement.key || `${placement.catalog_id}/${placement.variant || placement.catalog_variant}`;
        const asset = assets.get(key);
        if (!asset) {add('unknown_asset', [placement.id], {key}); continue;}
        covered.add(asset.catalog_id);
        if (!numbers(placement.position_m, 3) || !numbers(placement.scale, 3) || !Number.isFinite(placement.yaw_deg) || (placement.rotation_deg !== undefined && !numbers(placement.rotation_deg, 3))) {add('invalid_transform', [placement.id], {reason: 'Finite position_m[3], scale[3], yaw_deg and optional rotation_deg[3] required'}); continue;}
        if (placement.scale.some(scale => scale !== 1)) {add('invalid_scale', [placement.id], {scale: placement.scale, reason: 'TownKit placement must retain native import scale [1,1,1]'}); continue;}
        if (!['native', 'visual_only'].includes(placement.collision_policy)) {add('invalid_collision_policy', [placement.id], {value: placement.collision_policy}); continue;}
        if (placement.finish && !asset.material_overrides[placement.finish] && placement.finish !== 'embedded') add('unknown_finish', [placement.id], {finish: placement.finish});
        const support = placement.support;
        if (!support || !['terrain', 'building_floor', 'wall', 'surface', 'existing_proxy'].includes(support.kind)) add('invalid_support', [placement.id], {support});
        if (support && ['building_floor', 'wall'].includes(support.kind) && !structures.has(support.host_id)) add('unknown_host_structure', [placement.id, support.host_id], {});
        if (placement.proxy_id && !covers.has(placement.proxy_id) && !trees.has(placement.proxy_id) && !structures.has(placement.proxy_id) && !bridges.has(placement.proxy_id)) add('unknown_proxy', [placement.id, placement.proxy_id], {});
        if (isTree(asset) && (placement.collision_policy !== 'native' || !trees.has(placement.proxy_id) || placement.proxy_replacement?.kind !== 'vegetation_native_replacement' || placement.proxy_replacement.preserve_collision !== false || placement.proxy_replacement.retired_shape_path !== `Concealment/${placement.proxy_id}/TrunkBody/Shape`)) add('tree_collision_policy', [placement.id, placement.proxy_id], {reason: 'Native tree helpers must replace the exact named canonical trunk shape'});
        const visual = worldBox(placement, asset.visual_bounds_godot_m);
        const collision = asset.source_collision_bounds_godot_m ? worldBox(placement, asset.source_collision_bounds_godot_m) : null;
        if (visual.polygon.some(([x, z]) => x < -250 - EPS || x > 250 + EPS || z < -250 - EPS || z > 250 + EPS)) add('outside_world_bounds', [placement.id], {polygon_xz_m: visual.polygon});
        if (support?.kind === 'terrain') {
            const centerHeight = heightAt(placement.position_m[0], placement.position_m[2]);
            if (!Number.isFinite(centerHeight)) add('no_dry_terrain', [placement.id], {position_m: placement.position_m});
            else if (placement.ground_contact === 'tree_root_embed') {
                const gaps = support.root_contact_gaps_m;
                if (!isTree(asset) || !numbers(gaps, 4) || gaps.some(gap => gap < -.15 || gap > .02) || visual.min_y < centerHeight - .15 || visual.min_y > centerHeight + .02 || (placement.rotation_deg && (placement.rotation_deg[0] !== 0 || placement.rotation_deg[2] !== 0))) add('invalid_tree_root_contact', [placement.id], {gaps_m: gaps, bottom_y_m: visual.min_y, terrain_y_m: centerHeight});
                contacts.push({ids: [placement.id, 'terrain'], reason: 'Upright native-size tree root fitted into soil: declared four-toe gaps bounded to[-0.15,0.02]m; fresh native terrain rays required.', gaps_m: gaps});
            }
            else if (placement.rotation_deg && support.native_contact_adjustment) {
                const angles = placement.rotation_deg;
                if (!numbers(angles, 3) || Math.abs(angles[0]) > 20 || Math.abs(angles[2]) > 20 || Math.abs(placement.position_m[1] + asset.visual_bounds_godot_m[0][1] * placement.scale[0] - centerHeight) > .5) add('invalid_native_ground_pose', [placement.id], {angles});
                contacts.push({ids: [placement.id, 'terrain'], reason: 'Authored native-normal contact pose; conservative tilted bounds checked here, actual low vertices must pass native support rays.'});
            } else if (Math.abs(visual.min_y - centerHeight) > .05 + EPS) {
                const embedded = placement.ground_contact === 'embed_to_lowest' && /^hills_|river_riverbank_rock$|bunker_camouflage_net$/.test(asset.catalog_id);
                const supports = [[placement.position_m[0], placement.position_m[2]], ...visual.polygon].map(point => heightAt(...point));
                const exactLowest = embedded && supports.every(Number.isFinite) && Math.abs(visual.min_y - Math.min(...supports)) < .002 && centerHeight - visual.min_y <= .3;
                if (exactLowest) contacts.push({ids: [placement.id, 'terrain'], reason: 'Documented masonry/stone/post toe embedded to measured lowest support, maximum0.3m.', depth_m: centerHeight - visual.min_y});
                else add('grounding_error', [placement.id], {bottom_y_m: visual.min_y, terrain_y_m: centerHeight, error_m: visual.min_y - centerHeight});
            }
            const samples = visual.polygon.map(([x, z]) => heightAt(x, z)).filter(Number.isFinite);
            terrainFits.push({id: placement.id, center_y_m: centerHeight, bottom_y_m: visual.min_y, footprint_terrain_range_m: samples.length ? [Math.min(...samples), Math.max(...samples)] : null});
        }
        if (support?.kind === 'building_floor' && structures.has(support.host_id)) {
            const host = structures.get(support.host_id), footprint = rectangle(host.position_xz_m, host.footprint_m, host.yaw_deg);
            if (!visual.polygon.every(point => inside(point, footprint))) add('floor_prop_outside_host', [placement.id, host.id], {});
            const hostFloor = heightAt(...host.position_xz_m) + (host.pad_intent?.root_above_pad_m ?? .2);
            const floorLevels = [hostFloor, ...(host.access?.upper ? [hostFloor + 3.2] : [])];
            if (!floorLevels.some(level => Math.abs(level - visual.min_y) <= .05 + EPS)) add('building_floor_grounding', [placement.id, host.id], {bottom_y_m: visual.min_y, expected_floor_levels_y_m: floorLevels});
        }
        accepted.push({placement, asset, visual, collision});
    }

    for (const type of types) if (!covered.has(type) && !deferred.has(type)) add('uncovered_catalog_type', [type], {reason: 'No placement or justified deferral'});
    for (const type of deferred.keys()) if (covered.has(type)) warnings.push({type: 'covered_and_deferred', ids: [type], reason: deferred.get(type)});

    const byId = new Map(accepted.map(record => [record.placement.id, record]));
    const contactLinks = new Map();
    function addContact(a, b, reason) {
        if (!byId.has(a) || !byId.has(b) || a === b || typeof reason !== 'string' || !reason.trim()) {add('invalid_contact_exception', [a, b], {reason}); return;}
        const key = [a, b].sort().join('|');
        contactLinks.set(key, reason.trim());
    }
    for (const contact of plan.intentional_contacts || []) addContact(contact.a, contact.b, contact.reason);
    for (const {placement} of accepted) {
        const exception = placement.contact_exception;
        if (exception) {
            if (!Array.isArray(exception.with_ids) || !exception.with_ids.length) add('invalid_contact_exception', [placement.id], {reason: 'contact_exception needs with_ids[] and reason'});
            else for (const other of exception.with_ids) addContact(placement.id, other, exception.reason);
        }
        if (placement.support?.kind === 'surface') {
            const hostId = placement.support.host_id, host = byId.get(hostId);
            const existingFence = hostId === 'BUNKER-fence-north' && placement.id === 'OB-bunker-wiretop' && placement.support.existing_scene_path === 'NavigationRegion3D/Level/Town500Dressing/Fences/BUNKER_0_4';
            if (!host && !bridges.has(hostId) && !structures.has(hostId) && !covers.has(hostId) && !existingFence) add('unknown_surface_host', [placement.id, hostId], {});
            if (host) {
                const box = byId.get(placement.id).visual;
                if (Math.abs(box.min_y - host.visual.max_y) > .05 + EPS) add('surface_grounding', [placement.id, hostId], {bottom_y_m: box.min_y, host_top_y_m: host.visual.max_y});
                const multiHosts = (placement.support.host_ids || []).map(id => byId.get(id));
                const spansSupports = multiHosts.length >= 2 && multiHosts.every(support => support && inside([support.visual.center[0], support.visual.center[2]], box.polygon) && polygonDistance(support.visual.polygon, box.polygon) < EPS && Math.abs(support.visual.max_y - box.min_y) < .05);
                if (!spansSupports && !box.polygon.every(point => inside(point, host.visual.polygon))) add('surface_overhang', [placement.id, hostId], {});
            }
        }
    }

    for (let i = 0; i < accepted.length; i++) for (let j = i + 1; j < accepted.length; j++) {
        const a = accepted[i], b = accepted[j], ids = [a.placement.id, b.placement.id];
        const overlap = overlap3d(a.visual, b.visual);
        if (!overlap) continue;
        const reason = contactLinks.get([...ids].sort().join('|'));
        if (reason) {contacts.push({ids, reason, ...overlap}); continue;}
        if (isTree(a.asset) || isTree(b.asset)) {
            const trunkA = isTree(a.asset) ? a.collision : a.visual, trunkB = isTree(b.asset) ? b.collision : b.visual;
            if (trunkA && trunkB && !overlap3d(trunkA, trunkB)) {crownExemptions.push({ids, reason: 'Natural crown envelope overlap; actual imported trunk envelopes do not intersect'}); continue;}
        }
        add('visual_obb_intersection', ids, overlap);
    }

    const routes = [...layout.corridors.map(corridor => ({id: corridor.id, type: corridor.type, points: corridor.points_xz_m, width: corridor.width_m, heights: corridor.surface_y_m})), ...layout.terrain.route_graph.edges.map(route => ({id: route.id, points: route.points_xz_m, width: route.clear_width_m, heights: route.surface_y_m}))];
    for (const {placement, asset, visual, collision} of accepted) {
        if (placement.collision_policy !== 'native' || !collision) continue;
        for (const route of routes) {
            const gaps = edges(route.points).map(([a, b], index) => {
                const heights = [route.heights?.[index] ?? heightAt(...a), route.heights?.[index + 1] ?? heightAt(...b)];
                if (heights.every(Number.isFinite) && (collision.min_y >= Math.max(...heights) + 1.8 || collision.max_y <= Math.min(...heights))) return Infinity;
                return segmentPolygon(a, b, collision.polygon) - route.width / 2;
            });
            const gap = Math.min(...gaps);
            if (gap < -EPS) {
                const own = structures.get(placement.proxy_id);
                const occupiedRailcar = route.type === 'rail' && own?.kind === 'railcar' && edges(route.points).some(([a, b]) => segmentPolygon(a, b, rectangle(own.position_xz_m, own.footprint_m, own.yaw_deg)) < route.width / 2);
                if (occupiedRailcar) contacts.push({ids: [placement.id, own.id, route.id], reason: 'Finished wagon replaces its own canonical wagon already occupying this same rail route; no road/footpath exemption.', clearance_m: gap});
                else add('native_route_intrusion', [placement.id, route.id], {clearance_m: gap});
            }
        }
        for (const host of structures.values()) {
            const apron = host.door_apron;
            if (apron?.from_xz_m && apron?.to_xz_m) {
                const clearance = segmentPolygon(apron.from_xz_m, apron.to_xz_m, collision.polygon) - Math.max(1.8, apron.width_m || 1.8) / 2;
                const floorY = heightAt(...host.position_xz_m) + (host.pad_intent?.root_above_pad_m ?? .2);
                if (clearance < -EPS && collision.min_y < floorY + 1.8 && collision.max_y > floorY) add('door_apron_intrusion', [placement.id, host.id], {clearance_m: clearance, required_clear_width_m: Math.max(1.8, apron.width_m || 1.8)});
            }
            const supportHost = placed.get(placement.support?.host_id);
            const ownHost = (placement.support?.host_id === host.id && ['building_floor', 'wall'].includes(placement.support.kind)) || (placement.support?.kind === 'surface' && placement.support.building_host_id === host.id && supportHost?.support?.kind === 'building_floor' && supportHost.support.host_id === host.id);
            if (ownHost || placement.proxy_id === host.id) continue;
            const footprint = rectangle(host.position_xz_m, host.footprint_m, host.yaw_deg);
            if (polygonDistance(collision.polygon, footprint) < EPS) add('native_other_building_footprint', [placement.id, host.id], {});
        }
        for (const cover of covers.values()) {
            if (!cover.solid || cover.id === placement.proxy_id || cover.id === placement.support?.host_id) continue;
            const height = heightAt(...cover.position_xz_m), box = worldBox({position_m: [cover.position_xz_m[0], height, cover.position_xz_m[1]], yaw_deg: cover.yaw_deg || 0, scale: [1, 1, 1]}, [[-cover.size_xyz_m[0] / 2, 0, -cover.size_xyz_m[2] / 2], [cover.size_xyz_m[0] / 2, cover.size_xyz_m[1], cover.size_xyz_m[2] / 2]]);
            if (overlap3d(collision, box)) add('native_existing_cover_intersection', [placement.id, cover.id], {});
        }
        for (const tree of trees.values()) {
            if (replacedTrees.has(tree.id)) continue;
            const radius = tree.trunk_diameter_m / 2, height = heightAt(...tree.position_xz_m);
            const box = worldBox({position_m: [tree.position_xz_m[0], height, tree.position_xz_m[1]], yaw_deg: 0, scale: [1, 1, 1]}, [[-radius, 0, -radius], [radius, tree.height_m * .6, radius]]);
            if (overlap3d(collision, box)) add('native_existing_trunk_intersection', [placement.id, tree.id], {});
        }
        if (asset.collision_role === 'none' && collision) warnings.push({type: 'collision_role_mismatch', ids: [placement.id], reason: 'Source role none but collision mesh bounds exist'});
    }

    return {
        schema_version: 1, status: errors.length ? 'FAIL' : 'OFFLINE_CHECK_PASS_NATIVE_PENDING', placements: records.length, valid_transform_placements: accepted.length,
        catalog_types: types.size, covered_types: covered.size, deferred_types: deferred.size,
        coverage: [...types].map(catalog_id => ({catalog_id, status: covered.has(catalog_id) ? 'placed' : deferred.has(catalog_id) ? 'deferred' : 'missing', reason: deferred.get(catalog_id) || null})),
        errors, warnings, intentional_contacts_observed: contacts, natural_crown_envelope_exemptions: crownExemptions, terrain_fit_diagnostics: terrainFits,
        calculated_placements: accepted.map(({placement, visual, collision, asset}) => ({id: placement.id, key: asset.key, wrapper_res_path: wrapperPath(asset, placement.finish, placement.collision_policy === 'visual_only'), visual_world_y_m: [visual.min_y, visual.max_y], visual_polygon_xz_m: visual.polygon, native_collision_polygon_xz_m: collision?.polygon || null})),
        native_town_verified: false,
        limits: ['Offline yaw-oriented full visual/collision envelopes are conservative; an OBB conflict requires explicit review, not a claim of triangle intersection.', 'Natural tree crowns are exempt only when actual imported trunk envelopes do not overlap.', 'Terrain corners are diagnostics; center grounding does not certify every support contact on sloped terrain.', 'Existing heavy native geometry, detailed building walls, door traversal, player movement, navigation and renderer acceptance require native Godot verification.'],
    };
}

function selfCheck() {
    const tilt = worldBox({position_m: [0, 0, 0], yaw_deg: 0, rotation_deg: [90, 0, 0], scale: [1, 1, 1]}, [[0, 0, 0], [1, 2, 3]]);
    assert.deepEqual(tilt.center.map(value => Number(value.toFixed(6))), [.5, -1.5, 1]);
    assert.deepEqual(tilt.size.map(value => Number(value.toFixed(6))), [1, 3, 2]);
    const box = worldBox({position_m: [10, 2, -5], yaw_deg: 90, scale: [2, 2, 2]}, [[0, 0, 0], [1, 1, 2]]);
    assert.deepEqual(box.center.map(value => Number(value.toFixed(6))), [12, 3, -6]);
    const unit = worldBox({position_m: [0, 0, 0], yaw_deg: 0, scale: [1, 1, 1]}, [[-.5, 0, -.5], [.5, 1, .5]]);
    assert(overlap3d(unit, unit));
    assert.equal(overlap3d(unit, {...unit, min_y: 1, max_y: 2}), null);
    const apart = worldBox({position_m: [2, 0, 0], yaw_deg: 35, scale: [1, 1, 1]}, [[-.5, 0, -.5], [.5, 1, .5]]);
    assert.equal(overlap3d(unit, apart), null);
    const catalog = {assets: [{key: 'test/a', catalog_id: 'test', variant: 'a', material_overrides: {}, wrapper_res_path: 'res://Scene/Props/TownKit/Catalog/test__a.tscn', visual_bounds_godot_m: [[-.5, 0, -.5], [.5, 1, .5]], source_collision_bounds_godot_m: null}]};
    const layout = {structures: [], dressing: {cover: [], vegetation: []}, corridors: [], terrain: {bridges: [], route_graph: {edges: []}}};
    const placement = {id: 'one', catalog_id: 'test', variant: 'a', position_m: [0, 0, 0], yaw_deg: 0, scale: [1, 1, 1], collision_policy: 'visual_only', support: {kind: 'terrain'}};
    assert.equal(validate({placements: [placement]}, catalog, layout, () => 0).errors.length, 0);
    const invalid = validate({placements: [placement, {...placement, scale: [1, 2, 1]}]}, catalog, layout, () => 0);
    assert(invalid.errors.some(error => error.type === 'duplicate_id'));
    assert(validate({placements: [{...placement, scale: [1, 2, 1]}]}, catalog, layout, () => 0).errors.some(error => error.type === 'invalid_scale'));
    for (const scale of [0, -1, .58, .78, .8, .95, 1.5, 2]) {
        assert(validate({placements: [{...placement, scale: [scale, scale, scale]}]}, catalog, layout, () => 0).errors.some(error => error.type === 'invalid_scale'));
    }
    assert(validate({placements: [placement, {...placement, id: 'two'}]}, catalog, layout, () => 0).errors.some(error => error.type === 'visual_obb_intersection'));
    assert(validate({placements: {}}, catalog, layout, () => 0).errors.some(error => error.type === 'invalid_plan'));
    const treeCatalog = {assets: [{...catalog.assets[0], key: 'forest_pine_tree/a', catalog_id: 'forest_pine_tree', source_collision_bounds_godot_m: [[-.5, 0, -.5], [.5, 1, .5]]}]};
    const treeLayout = {...layout, dressing: {cover: [], vegetation: [{id: 'F001', position_xz_m: [0, 0], trunk_diameter_m: 1, height_m: 2}]}};
    const tree = {...placement, catalog_id: 'forest_pine_tree', proxy_id: 'F001', collision_policy: 'native', proxy_replacement: {kind: 'vegetation_native_replacement', preserve_collision: false, retired_shape_path: 'Concealment/F001/TrunkBody/Shape'}};
    assert.equal(validate({placements: [tree]}, treeCatalog, treeLayout, () => 0).errors.length, 0);
    for (const changed of [{collision_policy: 'visual_only'}, {proxy_replacement: {...tree.proxy_replacement, preserve_collision: true}}, {proxy_replacement: {...tree.proxy_replacement, retired_shape_path: 'wrong'}}]) {
        assert(validate({placements: [{...tree, ...changed}]}, treeCatalog, treeLayout, () => 0).errors.some(error => error.type === 'tree_collision_policy'));
    }
    const rootedTree = {...tree, ground_contact: 'tree_root_embed', position_m: [0, -.1, 0], support: {kind: 'terrain', root_contact_gaps_m: [-.1, -.1, 0, 0]}};
    assert.equal(validate({placements: [rootedTree]}, treeCatalog, treeLayout, () => 0).errors.length, 0);
    for (const gap of [-.151, .021]) {
        assert(validate({placements: [{...rootedTree, support: {...rootedTree.support, root_contact_gaps_m: [gap, 0, 0, 0]}}]}, treeCatalog, treeLayout, () => 0).errors.some(error => error.type === 'invalid_tree_root_contact'));
    }
    console.log('PLACEMENT_CHECK_SELF_CHECK_OK transformed bounds, yaw OBB separation/contact, duplicate IDs, strict unit scale, pair clipping, exact trunk retirement policy');
}

function run(planFile = path.join(__dirname, 'placement-plan.json')) {
    const catalogFile = path.join(__dirname, 'asset-catalog.json'), layoutFile = path.join(__dirname, '../layout.json'), proposalFile = path.join(__dirname, '../phase3/dressing-proposal.json');
    const layout = applyProposal(read(layoutFile), read(proposalFile));
    const report = validate(read(planFile), read(catalogFile), layout);
    report.source_sha256 = Object.fromEntries([planFile, catalogFile, layoutFile, proposalFile].map(file => [path.relative(__dirname, file).replaceAll('\\', '/'), hash(file)]));
    fs.writeFileSync(path.join(__dirname, 'placement-check.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify({status: report.status, placements: report.placements, covered_types: report.covered_types, deferred_types: report.deferred_types, errors: report.errors.length, by_type: report.errors.reduce((counts, error) => ({...counts, [error.type]: (counts[error.type] || 0) + 1}), {})}));
    return report;
}

if (require.main === module) {
    if (process.argv.includes('--self-check')) selfCheck();
    else {const report = run(process.argv[2]); if (report.errors.length) process.exitCode = 1;}
}
module.exports = {worldBox, overlap3d, validate, run};
