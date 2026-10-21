// Offline authoring only: every XZ below is selected by hand; this is not a runtime spawner.
const fs = require('fs');
const path = require('path');
const assert = require('assert/strict');
const project = path.resolve(__dirname, '../../..');
const layout = JSON.parse(fs.readFileSync(path.join(project, 'design/town-500m/layout.json')));
const catalogue = JSON.parse(fs.readFileSync(path.join(__dirname, 'asset-catalog.json')));
const terrain = require('../phase2/terrain-authoring.cjs');
const buildings = new Map(layout.structures.map(b => [b.id, b]));
const assets = new Map(catalogue.assets.map(a => [a.key, a]));
const placements = [];
const deferred = [];
const round = n => +n.toFixed(6);

function rotate(x, z, yaw) {
    const a = yaw * Math.PI / 180;
    return [Math.cos(a) * x + Math.sin(a) * z, -Math.sin(a) * x + Math.cos(a) * z];
}
function add(id, zone, catalog_id, variant, finish, xyz, yaw, scale, support, role, rationale, extra = {}) {
    assert.equal(scale, 1, `Native import scale required: ${id}`);
    const asset = assets.get(`${catalog_id}/${variant}`);
    assert(asset, `Unknown asset ${catalog_id}/${variant}`);
    placements.push({id, zone, catalog_id, variant, finish, position_m: xyz.map(round), yaw_deg: yaw,
        scale: [scale, scale, scale], support, collision_policy: asset.collision_role === 'decorative' ? 'visual_only' : 'native',
        role, rationale, ...extra});
    return placements.at(-1);
}
function floor(id, host, catalog, variant, x, z, yaw, role, group, finish = 'used', scale = 1) {
    const b = buildings.get(host), a = assets.get(`${catalog}/${variant}`);
    assert(b?.access.ground, `${host} has no enterable ground contract`);
    const [dx, dz] = rotate(x, z, b.yaw_deg);
    const floorY = b.pad_intent.surface_y_m + b.pad_intent.root_above_pad_m;
    return add(id, b.zone_id, catalog, variant, finish, [b.position_xz_m[0] + dx, floorY - a.visual_bounds_godot_m[0][1] * scale, b.position_xz_m[1] + dz], b.yaw_deg + yaw, scale,
        {kind: 'building_floor', host_id: host, local_position_m: [x, round(-a.visual_bounds_godot_m[0][1] * scale), z], floor_y_m: floorY,
            evidence: `${b.scene_ref}: Architecture/GroundFloor at localY=-0.1, BoxShape height0.2; native instance rootY=${floorY}`},
        role, 'Furniture follows a perimeter work/wait/storage zone; central door-to-interior and east stair circulation remain open.', {assembly_group: group});
}
function ground(id, zone, catalog, variant, x, z, yaw, role, group, finish = 'used', scale = 1, extra = {}) {
    const a = assets.get(`${catalog}/${variant}`), y = terrain.heightAt(x, z);
    return add(id, zone, catalog, variant, finish, [x, y - a.visual_bounds_godot_m[0][1] * scale, z], yaw, scale,
        {kind: 'terrain', surface_y_m: round(y), evidence: 'phase2/terrain-authoring.cjs::heightAt on exported dry terrain'},
        role, 'Position selected on the service yard or courtyard perimeter, away from authored swept routes and existing patrols.', {assembly_group: group, ...extra});
}
function wall(id, host, catalog, variant, x, z, bottomFromFloor, yaw, role, group, finish = 'used', scale = 1) {
    const b = buildings.get(host), a = assets.get(`${catalog}/${variant}`), [dx, dz] = rotate(x, z, b.yaw_deg);
    const floorY = b.pad_intent.surface_y_m + b.pad_intent.root_above_pad_m;
    return add(id, b.zone_id, catalog, variant, finish,
        [b.position_xz_m[0] + dx, floorY + bottomFromFloor - a.visual_bounds_godot_m[0][1] * scale, b.position_xz_m[1] + dz], b.yaw_deg + yaw, scale,
        {kind: 'wall', host_id: host, local_position_m: [x, round(bottomFromFloor - a.visual_bounds_godot_m[0][1] * scale), z], bottom_above_floor_m: bottomFromFloor, floor_y_m: floorY,
            mounting_plane: 'rear of GLB is localZ=0; local+Z faces away from its wall', evidence: 'authored wall face in host .tscn; source GLB back plane atZ0'},
        role, 'Mount on a verified solid wall face; no frame crosses the door aperture or stair port.', {assembly_group: group, collision_policy: 'visual_only'});
}
function on(id, hostId, catalog, variant, dx, dz, yaw, role, group, finish = 'used', scale = 1, supportTop = null) {
    const host = placements.find(p => p.id === hostId), a = assets.get(`${catalog}/${variant}`), hostAsset = assets.get(`${host.catalog_id}/${host.variant}`);
    const [ox, oz] = rotate(dx, dz, host.yaw_deg);
    const localTop = supportTop ?? hostAsset.visual_bounds_godot_m[1][1];
    const top = host.position_m[1] + localTop * host.scale[1];
    return add(id, host.zone, catalog, variant, finish, [host.position_m[0] + ox, top - a.visual_bounds_godot_m[0][1] * scale, host.position_m[2] + oz], host.yaw_deg + yaw, scale,
        {kind: 'surface', host_id: hostId, surface_y_m: round(top), host_local_top_y_m: localTop,
            local_offset_xz_m: [dx, dz], evidence: 'GLB visual top bounds for flat pallet/crate/table surface; no guessed vertical offset'},
        role, 'Compact deliberate stack, physically supported by its named host; no loose floating clutter.', {assembly_group: group, collision_policy: catalog === 'shared_street_litter' ? 'visual_only' : 'native'});
}
function defer(catalog_id, reason) { deferred.push({catalog_id, reason, action: 'Retain current geometry; do not hide/remove any original collider or opaque proxy.'}); }

// Clinic: two examination bays, reception, matching waiting seats and medical storage.
floor('T_CLINIC_BED_A', 'T05-A', 'town_clinic_examination_bed', 'with-sheet', -3.8, 2.8, 0, 'examination bay', 'T05-clinic-exam', 'clean');
floor('T_CLINIC_BED_B', 'T05-A', 'town_clinic_examination_bed', 'bare', 3.8, 2.8, 0, 'second examination bay', 'T05-clinic-exam');
floor('T_CLINIC_SHELF_A', 'T05-A', 'town_pharmacy_shelf', 'stocked', -5.1, 0.7, 90, 'medical storage against west wall', 'T05-clinic-storage', 'clean');
floor('T_CLINIC_SHELF_B', 'T05-A', 'town_pharmacy_shelf', 'empty', -5.1, -0.7, 90, 'matching partly cleared medical storage', 'T05-clinic-storage');
floor('T_CLINIC_DESK', 'T05-A', 'town_office_furniture', 'desk', 3.4, -1.8, 0, 'reception desk east of main aisle', 'T05-clinic-reception', 'clean');
floor('T_CLINIC_FILE_A', 'T05-A', 'town_office_furniture', 'cabinet', 5.05, -2.1, 0, 'reception filing bank', 'T05-clinic-reception');
floor('T_CLINIC_FILE_B', 'T05-A', 'town_office_furniture', 'cabinet', 5.05, -1.35, 0, 'matching reception filing bank', 'T05-clinic-reception');
floor('T_CLINIC_WAIT_A', 'T05-A', 'town_waiting_room_chair', 'row', -3.5, -3.6, 0, 'waiting row clear of entry throat', 'T05-clinic-waiting', 'clean');
floor('T_CLINIC_WAIT_B', 'T05-A', 'town_waiting_room_chair', 'row', 3.5, -3.6, 0, 'matching waiting row', 'T05-clinic-waiting');
wall('T_CLINIC_NOTICE', 'T05-A', 'town_notice_board', 'wall', -3.4, -4.745, 1.1, 0, 'clinic public notices facing room', 'T05-clinic-waiting');
wall('T_CLINIC_AC', 'T05-A', 'town_air_conditioner', 'small', 3.4, -5.005, 2.35, 180, 'reception AC outdoors above frontage', 'T05-clinic-reception', 'clean');
on('T_CLINIC_PAPER', 'T_CLINIC_DESK', 'shared_street_litter', 'paper', 0, 0, 0, 'abandoned paperwork on desk; source paper footprint already0.70x0.57m', 'T05-clinic-reception', 'used', 1);

// T02 pharmacy: shelf bank at rear; two same-model counters leave a 2m central cross aisle.
floor('T_PHARM_SHELF_A', 'T02-A', 'town_pharmacy_shelf', 'stocked', -4.5, 3.1, 180, 'pharmacy rear shelf bank', 'T02-pharmacy-retail', 'clean');
floor('T_PHARM_SHELF_B', 'T02-A', 'town_pharmacy_shelf', 'stocked', -3.1, 3.1, 180, 'matching pharmacy shelf bank', 'T02-pharmacy-retail');
floor('T_PHARM_SHELF_C', 'T02-A', 'town_pharmacy_shelf', 'empty', -1.7, 3.1, 180, 'cleared end of pharmacy bank', 'T02-pharmacy-retail');
floor('T_PHARM_COUNTER_A', 'T02-A', 'town_shop_counter', 'straight', -3.7, 0.6, 0, 'retail counter west bay', 'T02-pharmacy-retail', 'clean');
floor('T_PHARM_COUNTER_B', 'T02-A', 'town_shop_counter', 'straight', 3.7, 0.6, 0, 'retail counter east bay', 'T02-pharmacy-retail');
floor('T_PHARM_FILE', 'T02-A', 'town_office_furniture', 'cabinet', 5.1, 2.8, 180, 'dispensary records', 'T02-pharmacy-admin');
wall('T_PHARM_SIGN', 'T02-A', 'town_shop_cyrillic_sign', 'pharmacy', -3.2, -4.005, 2.48, 180, 'Cyrillic pharmacy facade sign', 'T02-pharmacy-frontage', 'clean');
wall('T_PHARM_AWNING', 'T02-A', 'town_store_awning', 'canvas', 2.8, -4.005, 2.5, 180, 'retained canvas retail awning', 'T02-pharmacy-frontage');
wall('T_PHARM_METER', 'T02-A', 'town_wall_electric_meter', 'single', -5.2, 4.005, 1.3, 0, 'rear service electric meter', 'T02-pharmacy-service');

// T04 grocery: preserve exact USP/provision pickup locations on west side of room.
floor('T_GROCERY_COUNTER', 'T04-A', 'town_shop_counter', 'corner', -3.7, 2.4, 180, 'grocery cash counter opposite pickup area', 'T04-grocery-retail', 'clean');
floor('T_GROCERY_SHELF_A', 'T04-A', 'town_pharmacy_shelf', 'empty', -5.1, -0.2, 90, 'empty small-goods shelf bank', 'T04-grocery-retail');
floor('T_GROCERY_SHELF_B', 'T04-A', 'town_pharmacy_shelf', 'empty', -5.1, 1.3, 90, 'matching cleared goods bank', 'T04-grocery-retail');
floor('T_GROCERY_DESK', 'T04-A', 'town_office_furniture', 'desk', -3.8, -2.8, 0, 'shopkeeper accounts corner', 'T04-grocery-admin');
wall('T_GROCERY_SIGN', 'T04-A', 'town_shop_cyrillic_sign', 'grocery', -3.2, -4.005, 2.48, 180, 'Cyrillic grocery fascia', 'T04-grocery-frontage', 'clean');
wall('T_GROCERY_AWNING', 'T04-A', 'town_store_awning', 'metal', 2.8, -4.005, 2.5, 180, 'metal awning at retail bay', 'T04-grocery-frontage', 'clean');
wall('T_GROCERY_AC', 'T04-A', 'town_air_conditioner', 'large', 3.1, 4.005, 2.1, 0, 'rear condenser over service side', 'T04-grocery-service');

// Civic office long houses: furnish west strip; stair volume stays entirely free.
floor('T_CIVIC_DESK_A', 'T03-A', 'town_office_furniture', 'desk', -2.8, -3.8, 90, 'municipal clerk desk', 'T03-civic-office', 'clean');
floor('T_CIVIC_DESK_B', 'T03-A', 'town_office_furniture', 'desk', -2.8, 0, 90, 'matching clerk desk', 'T03-civic-office');
floor('T_CIVIC_FILE_A', 'T03-A', 'town_office_furniture', 'cabinet', -2.8, 4.7, 0, 'records bank', 'T03-civic-files');
floor('T_CIVIC_FILE_B', 'T03-A', 'town_office_furniture', 'cabinet', -2.1, 4.7, 0, 'matching records bank', 'T03-civic-files');
floor('T_CIVIC_FILE_C', 'T03-A', 'town_office_furniture', 'cabinet', -1.4, 4.7, 0, 'matching records bank end', 'T03-civic-files', 'clean');
floor('T_CIVIC_WAIT', 'T03-A', 'town_waiting_room_chair', 'row', -2.0, -5.6, 0, 'office waiting row west of foyer', 'T03-civic-office');
wall('T_CIVIC_NOTICE', 'T03-A', 'town_notice_board', 'wall', -2.3, -8.005, 1.1, 180, 'municipal notice board outdoors', 'T03-civic-frontage');
floor('T_COMMUNITY_DESK', 'T07-A', 'town_office_furniture', 'desk', -2.8, -3.6, 90, 'community services office', 'T07-community-office');
floor('T_COMMUNITY_FILE_A', 'T07-A', 'town_office_furniture', 'cabinet', -2.8, 5.4, 0, 'community archive bank', 'T07-community-office');
floor('T_COMMUNITY_FILE_B', 'T07-A', 'town_office_furniture', 'cabinet', -2.1, 5.4, 0, 'community archive bank', 'T07-community-office');
floor('T_COMMUNITY_WAIT', 'T07-A', 'town_waiting_room_chair', 'row', -2, -5.7, 0, 'community waiting row', 'T07-community-office', 'clean');
wall('T_SERVICES_SIGN', 'T07-B', 'town_shop_cyrillic_sign', 'services', -3.0, -4.005, 2.48, 180, 'small service-office sign', 'T07-services-frontage');
floor('T_SERVICES_DESK', 'T07-B', 'town_office_furniture', 'desk', -4.2, 2.7, 0, 'service counter administration', 'T07-services-office');
floor('T_SERVICES_FILES_A', 'T07-B', 'town_office_furniture', 'cabinet', 4.8, 2.7, 0, 'service office files', 'T07-services-office');
floor('T_SERVICES_FILES_B', 'T07-B', 'town_office_furniture', 'cabinet', 4.1, 2.7, 0, 'matching files', 'T07-services-office', 'clean');

// Residential: sealed apartment block receives exterior services only; no invented access.
floor('T_HOME_DESK', 'T01-A', 'town_office_furniture', 'desk', -3.5, 2.7, 0, 'household study corner', 'T01-household');
floor('T_HOME_CABINET', 'T01-A', 'town_office_furniture', 'cabinet', 3.7, 2.7, 0, 'household storage', 'T01-household');
wall('T_HOME_RADIATOR', 'T01-A', 'town_apartment_radiator', 'small', 3.0, 3.745, 0.16, 180, 'domestic heating at rear wall', 'T01-household', 'clean');
wall('T_HOME_METER', 'T01-A', 'town_wall_electric_meter', 'single', -3.7, 4.005, 1.3, 0, 'domestic service meter', 'T01-household');
wall('T_APARTMENT_MAIL', 'T06-A', 'town_apartment_mailboxes', 'row', 0, 6.005, 1.1, 0, 'mail bank on solid rear facade panel', 'T06-apartment-services', 'clean');
wall('T_APARTMENT_DISH', 'T06-A', 'town_satellite_dish', 'angled', 8, 6.005, 4.6, 0, 'single satellite dish on upper solid panel', 'T06-apartment-services');
wall('T_APARTMENT_METER', 'T06-A', 'town_wall_electric_meter', 'double', -8, 6.005, 1.3, 0, 'paired apartment electric service', 'T06-apartment-services');
ground('T_COURTYARD_SWING', 'town', 'town_playground_swing', 'with-seat', -87, 69, 0, 'abandoned shared courtyard playground', 'T06-courtyard', 'used');
ground('T_COURTYARD_BENCH_A', 'town', 'town_courtyard_bench', 'painted', -94, 69, 90, 'courtyard bench facing playground', 'T06-courtyard', 'clean');
ground('T_COURTYARD_BENCH_B', 'town', 'town_courtyard_bench', 'painted', -79, 69, -90, 'matching courtyard bench', 'T06-courtyard');
floor('T_HOME_LONG_DESK', 'T06-B', 'town_office_furniture', 'desk', -2.8, -3.7, 90, 'residential study corner away from stair', 'T06-residential');
floor('T_HOME_LONG_FILE', 'T06-B', 'town_office_furniture', 'cabinet', -2.8, 5.4, 0, 'residential utility cupboard', 'T06-residential');
wall('T_HOME_LONG_RADIATOR', 'T06-B', 'town_apartment_radiator', 'large', -3.495, 1.8, 0.16, 90, 'heating under west wall', 'T06-residential', 'clean');
floor('T_HOME_EAST_DESK', 'T12-A', 'town_office_furniture', 'desk', -2.8, -3.7, 90, 'residential study corner', 'T12-residential');
floor('T_HOME_EAST_CABINET', 'T12-A', 'town_office_furniture', 'cabinet', -2.8, 5.4, 0, 'residential utility cupboard', 'T12-residential');
wall('T_HOME_EAST_RADIATOR', 'T12-A', 'town_apartment_radiator', 'large', -3.495, 1.8, 0.16, 90, 'domestic perimeter heating', 'T12-residential');

// Workshop/garage: avoid GunLocker(11,74), crate(20,73), M700(20,75), provisions(-29/25,122).
floor('T_GARAGE_BENCH_A', 'T08-A', 'town_workshop_bench', 'tool-covered', -2, 3.9, 180, 'repair bench on clear rear wall away from GunLocker', 'T08-garage-repair');
floor('T_GARAGE_BENCH_B', 'T08-A', 'town_workshop_bench', 'plain', 0.2, 3.9, 180, 'matching repair bench away from M700', 'T08-garage-repair', 'clean');
floor('T_GARAGE_COMPRESSOR', 'T08-A', 'industry_air_compressor', 'horizontal', -5.8, -1.8, 0, 'portable compressor by repair zone', 'T08-garage-repair');
floor('T_GARAGE_TIRE_A', 'T08-A', 'shared_tire_stack', 'stacked', -5.7, -3.4, 0, 'matching spare tire bank', 'T08-garage-tires');
floor('T_GARAGE_TIRE_B', 'T08-A', 'shared_tire_stack', 'stacked', -4.8, -3.4, 0, 'matching spare tire bank', 'T08-garage-tires');
floor('T_WORKSHOP_BENCH_A', 'T11-A', 'town_workshop_bench', 'plain', -2.8, -3, 90, 'workshop wall bench away from provisions', 'T11-workshop-repair', 'clean');
floor('T_WORKSHOP_BENCH_B', 'T11-A', 'town_workshop_bench', 'tool-covered', -2.8, -5.4, 90, 'matching repair station', 'T11-workshop-repair');
floor('T_WORKSHOP_CART', 'T11-A', 'industry_welding_cart', 'covered', -2.7, 0, 90, 'welding supplies in repair strip', 'T11-workshop-repair');
wall('T_WORKSHOP_LIGHT', 'T11-A', 'industry_work_light', 'mounted', -3.495, -4.2, 2.1, 90, 'unpowered mounted workshop task light', 'T11-workshop-repair');

// Public market and roadside bus stop are readable groups, not random street clutter.
ground('T_MARKET_STALL_A', 'town', 'town_market_stall', 'empty', -48, 108, 90, 'market stall beside kiosk group', 'T10-market');
ground('T_MARKET_STALL_B', 'town', 'town_market_stall', 'tarp-covered', -48, 112, 90, 'matching abandoned covered market stall', 'T10-market', 'clean');
ground('T_MARKET_CRATE_A', 'town', 'shared_wooden_crate', 'medium', -47.8, 116.5, 0, 'produce freight stack behind stalls', 'T10-market-freight');
on('T_MARKET_CRATE_B', 'T_MARKET_CRATE_A', 'shared_wooden_crate', 'small', 0, 0, 0, 'stacked produce crate', 'T10-market-freight', 'clean', 1);
ground('T_MARKET_CRATE_C', 'town', 'shared_wooden_crate', 'medium', -46.7, 116.5, 0, 'matching produce freight stack', 'T10-market-freight', 'clean');
ground('T_BUS_SHELTER', 'town', 'town_soviet_bus_shelter', 'intact', -125, 29, 0, 'county-road bus stop on north clinic shoulder', 'T05-bus-stop', 'clean');
ground('T_BUS_BOARD', 'town', 'town_notice_board', 'freestanding', -120.7, 29.2, 0, 'public timetable board next to bus stop', 'T05-bus-stop');
ground('T_BUS_LITTER', 'town', 'shared_street_litter', 'paper', -123.6, 27.3, 10, 'small localized autumn bus-stop litter outside shelter slab', 'T05-bus-stop', 'used', 1);

// Existing sedan proxies: exact centre/yaw and smaller native envelope; original stays until root checks replacement.
for (const [id, proxy] of [['T_ROAD_SEDAN_A', 'C01-01'], ['T_ROAD_SEDAN_B', 'C01-02']]) {
    const c = layout.dressing.cover.find(c => c.id === proxy);
    ground(id, 'town', 'shared_old_sedan', 'abandoned', ...c.position_xz_m, c.yaw_deg, 'existing abandoned road sedan art candidate', 'town-road-wrecks', id.endsWith('A') ? 'used' : 'worn', 1,
        {proxy_id: proxy, collision_policy: 'native', replacement_status: 'candidate; keep original proxy until native LOS/readability acceptance',
            replacement_fit: {old_size_xyz_m: c.size_xyz_m, new_size_xyz_m: [1.65, 1.45, 4.1], concern: 'lower roof by0.15m; never retain invisible original cover collider after hiding mesh'}});
}

// Industry warehouse: west machinery bay, east freight bay, clear 4m central entry aisle and side exit.
floor('I_WAREHOUSE_CRANE', 'I01-A', 'industry_gantry_crane', 'fixed', -7.6, 4.8, 0, 'static repair gantry in machinery bay', 'I01-machinery', 'clean');
floor('I_WAREHOUSE_BENCH_A', 'I01-A', 'town_workshop_bench', 'tool-covered', -10.6, 0.8, 90, 'warehouse workshop west perimeter', 'I01-machinery');
floor('I_WAREHOUSE_BENCH_B', 'I01-A', 'town_workshop_bench', 'plain', -10.6, -1.6, 90, 'matching warehouse bench', 'I01-machinery', 'clean');
floor('I_WAREHOUSE_CART', 'I01-A', 'industry_welding_cart', 'cylinders', -8.7, 0.8, 0, 'welding cart next to gantry repair bay', 'I01-machinery');
floor('I_WAREHOUSE_COMPRESSOR', 'I01-A', 'industry_air_compressor', 'vertical', -10.6, -4.4, 0, 'fixed workshop compressor', 'I01-machinery');
floor('I_WAREHOUSE_TRIPOD', 'I01-A', 'industry_work_light', 'tripod', -7.4, -4.4, 45, 'unpowered task light in maintenance bay', 'I01-machinery');
wall('I_WAREHOUSE_GAUGE', 'I01-A', 'industry_industrial_gauge', 'multi', -12.045, -4.4, 1.3, 90, 'maintenance pressure gauge on solid west wall', 'I01-machinery', 'clean', 1);
floor('I_WAREHOUSE_PALLET_A', 'I01-A', 'shared_wood_pallet', 'loaded', 7.2, 5.7, 0, 'freight bank east warehouse bay', 'I01-freight');
floor('I_WAREHOUSE_PALLET_B', 'I01-A', 'shared_wood_pallet', 'loaded', 8.7, 5.7, 0, 'matching freight bank', 'I01-freight', 'clean');
floor('I_WAREHOUSE_PALLET_C', 'I01-A', 'shared_wood_pallet', 'loaded', 10.2, 5.7, 0, 'matching freight bank end', 'I01-freight');
floor('I_WAREHOUSE_EMPTY_A', 'I01-A', 'shared_wood_pallet', 'empty', 7.2, 3.8, 0, 'empty return pallet bank', 'I01-freight', 'clean');
floor('I_WAREHOUSE_EMPTY_B', 'I01-A', 'shared_wood_pallet', 'empty', 8.7, 3.8, 0, 'matching return pallets', 'I01-freight');
floor('I_WAREHOUSE_CRATE_A', 'I01-A', 'shared_wooden_crate', 'large', 7.2, -5.4, 0, 'sorted dispatch wooden cases', 'I01-cases', 'clean');
floor('I_WAREHOUSE_CRATE_B', 'I01-A', 'shared_wooden_crate', 'large', 8.7, -5.4, 0, 'matching dispatch wooden cases', 'I01-cases');
on('I_WAREHOUSE_CRATE_C', 'I_WAREHOUSE_CRATE_A', 'shared_wooden_crate', 'medium', 0, 0, 0, 'top case in dispatch stack', 'I01-cases', 'clean');
on('I_WAREHOUSE_CRATE_D', 'I_WAREHOUSE_CRATE_B', 'shared_wooden_crate', 'medium', 0, 0, 0, 'top case in matching dispatch stack', 'I01-cases');
floor('I_WAREHOUSE_REEL_A', 'I01-A', 'shared_cable_reel', 'wood', 7.5, -2.3, 0, 'cable stock bank', 'I01-cable-stock');
floor('I_WAREHOUSE_REEL_B', 'I01-A', 'shared_cable_reel', 'wood', 9.3, -2.3, 0, 'matching cable stock bank', 'I01-cable-stock', 'clean');

// Dispatch office: consistent desks and files at1:1 scale, room centre and entry clear.
floor('I_DISPATCH_DESK_A', 'I02-A', 'town_office_furniture', 'desk', -2.8, -3.5, 90, 'dispatch administration desk', 'I02-dispatch-office', 'clean');
floor('I_DISPATCH_DESK_B', 'I02-A', 'town_office_furniture', 'desk', -2.8, 0, 90, 'matching freight scheduling desk', 'I02-dispatch-office');
floor('I_DISPATCH_FILE_A', 'I02-A', 'town_office_furniture', 'cabinet', -2.8, 5.3, 0, 'dispatch file bank', 'I02-dispatch-files');
floor('I_DISPATCH_FILE_B', 'I02-A', 'town_office_furniture', 'cabinet', -2.1, 5.3, 0, 'matching dispatch file bank', 'I02-dispatch-files');
floor('I_DISPATCH_FILE_C', 'I02-A', 'town_office_furniture', 'cabinet', -1.4, 5.3, 0, 'matching dispatch file bank end', 'I02-dispatch-files', 'clean');
floor('I_DISPATCH_WAIT', 'I02-A', 'town_waiting_room_chair', 'row', -2, -5.6, 0, 'driver waiting row', 'I02-dispatch-office');
wall('I_DISPATCH_NOTICE', 'I02-A', 'town_notice_board', 'wall', -2.3, -8.005, 1.1, 180, 'warehouse work notices by office', 'I02-dispatch-frontage');
on('I_DISPATCH_PAPERS', 'I_DISPATCH_DESK_A', 'shared_street_litter', 'paper', 0, 0, 0, 'abandoned scheduling paperwork on desktop; source footprint already0.70x0.57m', 'I02-dispatch-office', 'used', 1);

// South depot workshop, tools and stock are grouped around the perimeter.
floor('I_SOUTH_BENCH_A', 'I05-A', 'town_workshop_bench', 'tool-covered', -4.5, 3.8, 180, 'south depot repair bench', 'I05-repair');
floor('I_SOUTH_BENCH_B', 'I05-A', 'town_workshop_bench', 'plain', -2.3, 3.8, 180, 'matching repair bench', 'I05-repair', 'clean');
floor('I_SOUTH_CART', 'I05-A', 'industry_welding_cart', 'covered', -5.6, 1.7, 0, 'repair cart near benches', 'I05-repair');
floor('I_SOUTH_COMPRESSOR', 'I05-A', 'industry_air_compressor', 'horizontal', -5.7, -1.2, 0, 'repair bay portable compressor', 'I05-repair');
floor('I_SOUTH_DRUM_A', 'I05-A', 'shared_oil_drum', 'closed', 5.3, 3.7, 0, 'lubricant drum bank', 'I05-service-stock', 'clean');
floor('I_SOUTH_DRUM_B', 'I05-A', 'shared_oil_drum', 'closed', 4.5, 3.7, 0, 'matching lubricant bank', 'I05-service-stock');
floor('I_SOUTH_TIRES_A', 'I05-A', 'shared_tire_stack', 'stacked', 5.5, 1.9, 0, 'spare tire service bank', 'I05-service-stock');
floor('I_SOUTH_TIRES_B', 'I05-A', 'shared_tire_stack', 'stacked', 4.6, 1.9, 0, 'matching spare tire service bank', 'I05-service-stock');
wall('I_SOUTH_TASKLIGHT', 'I05-A', 'industry_work_light', 'mounted', -4.3, 4.745, 2.6, 180, 'unpowered rear task light', 'I05-repair', 'clean');

// Open yard: existing structures and 6m gate remain clear; machinery is parked off route.
ground('I_YARD_FORKLIFT', 'industry', 'industry_forklift', 'intact', 175, -89, 90, 'forklift parked at warehouse loading yard edge', 'I01-loading-yard');
ground('I_YARD_PIPE_A', 'industry', 'industry_steel_pipe_stack', 'large', 176, -95, 0, 'pipe stock in aligned yard bank', 'I01-steel-stock', 'clean');
ground('I_YARD_PIPE_B', 'industry', 'industry_steel_pipe_stack', 'small', 176, -98, 0, 'matching pipe stock bank', 'I01-steel-stock');
ground('I_YARD_BEAM_A', 'industry', 'industry_steel_beam_stack', 'large', 183, -95, 0, 'steel beam bank alongside pipe stock', 'I01-steel-stock');
ground('I_YARD_BEAM_B', 'industry', 'industry_steel_beam_stack', 'small', 183, -98, 0, 'matching steel beam stock', 'I01-steel-stock', 'clean');
ground('I_YARD_SLEEPERS_A', 'industry', 'industry_rail_sleepers', 'short', 199.7, -103, 0, 'stored sleepers west of live rail corridor', 'industry-rail-maintenance');
ground('I_YARD_SLEEPERS_B', 'industry', 'industry_rail_sleepers', 'short', 199.7, -101, 0, 'matching sleeper stock bank', 'industry-rail-maintenance', 'clean');
ground('I_RAIL_SIGNAL', 'industry', 'industry_rail_signal', 'one', 206.7, -106, 180, 'nonfunctional signal beside rail approach', 'industry-rail-maintenance');
ground('I_SERVICE_TANK', 'industry', 'industry_fuel_tank', 'short', 167, -43, 0, 'small workshop fuel service tank on ground', 'industry-fuel-service', 'clean');
ground('I_SERVICE_PUMP', 'industry', 'industry_fuel_pump', 'manual', 170, -43, 0, 'manual pump beside service tank', 'industry-fuel-service');
ground('I_SERVICE_DRUM_A', 'industry', 'shared_oil_drum', 'closed', 167, -46, 0, 'same-type spare drum bank', 'industry-fuel-service', 'clean');
ground('I_SERVICE_DRUM_B', 'industry', 'shared_oil_drum', 'closed', 168, -46, 0, 'same-type spare drum bank', 'industry-fuel-service');
ground('I_SERVICE_DRUM_C', 'industry', 'shared_oil_drum', 'dented', 169, -46, 0, 'single worn drum at bank end', 'industry-fuel-service', 'worn');
ground('I_YARD_DUMPSTER', 'industry', 'shared_industrial_dumpster', 'closed', 178, -50, 90, 'controlled yard waste station', 'industry-waste');
ground('I_YARD_SCRAP', 'industry', 'shared_scrap_metal_pile', 'small', 181, -50, 0, 'localized repair scrap beside waste station', 'industry-waste', 'worn');
ground('I_SOUTH_REEL_A', 'industry', 'shared_cable_reel', 'metal', 167, 57, 0, 'south yard cable bank', 'I05-yard-cable');
ground('I_SOUTH_REEL_B', 'industry', 'shared_cable_reel', 'metal', 169, 57, 0, 'matching cable bank', 'I05-yard-cable', 'clean');
ground('I_SOUTH_TIMBER_A', 'industry', 'shared_timber_stack', 'boards', 174, 57, 0, 'packing board stock beside south workshop', 'I05-yard-packing');
ground('I_SOUTH_TIMBER_B', 'industry', 'shared_timber_stack', 'boards', 174, 59, 0, 'matching packing board stock', 'I05-yard-packing', 'clean');
ground('I_SOUTH_CABINET', 'industry', 'shared_electrical_cabinet', 'large', 167, 66, 90, 'standalone depot electrical service cabinet', 'I05-yard-service', 'clean');

// Six existing container positions: GLB long axis Z, graybox long axis X -> +90deg correction.
for (const [host, finish] of [['I04-A', 'used'], ['I04-B', 'clean'], ['I04-C', 'used'], ['I06-A', 'clean'], ['I06-B', 'used'], ['I06-C', 'worn']]) {
    const b = buildings.get(host);
    ground(`I_CONTAINER_${host}`, 'industry', 'industry_shipping_container', 'single', ...b.position_xz_m, b.yaw_deg + 90, 'existing closed freight container art replacement candidate', `${b.source_ref}-container-bank`, finish, 1,
        {proxy_id: host, replacement_status: 'candidate; retain original proxy until parent verifies native collider/LOS fit',
            replacement_fit: {old_world_size_xyz_m: [2.44, 2.59, 6.06], new_world_size_xyz_m: [2.4, 2.6, 6], foot_y_m: 2, top_delta_m: 0.01,
                removal_rule: 'No invisible old collider: accept native imported collider and remove old opaque proxy only after finite LOS/traversal checks.'}});
}
// Railcars stay1:1. The parent explicitly accepts0.05m side margin as a review candidate.
for (const [id, host, catalog, variant] of [['I_RAIL_BOXCAR', 'I08-A', 'industry_rail_boxcar', 'shut'], ['I_RAIL_TANK', 'I09-A', 'industry_rail_tank_wagon', 'plain']]) {
    const b = buildings.get(host), a = assets.get(`${catalog}/${variant}`);
    ground(id, 'industry', catalog, variant, ...b.position_xz_m, b.yaw_deg + 90, 'same-centre rail freight art replacement candidate', 'industry-existing-rail-freight', 'used', 1,
        {proxy_id: host, contact_exception: 'Intentional rail vehicle footprint occupies the existing railcar/track host; no new track blockage.',
            replacement_status: 'candidate only; parent must accept finite LOS and real native collider before replacing current geometry',
            replacement_fit: {old_world_size_xyz_m: [3.1, 4, 14], new_world_size_xyz_m: [a.dimensions_godot_m[2], a.dimensions_godot_m[1], a.dimensions_godot_m[0]],
                side_extension_each_m: 0.05, height_extension_m: round(a.dimensions_godot_m[1] - 4), native_bottom_offset_m: 0.035,
                removal_rule: 'Never hide old proxy while retaining its whole solid box; use native imported collision after required acceptance.'}});
}

defer('town_metal_garage_door', 'Door library is static3.28m wide/2.62m high with open-leaf sweep; existing functional doors/garage port geometry do not match. No decorative second door, behavior change or blocked door port.');
defer('town_entrance_steps', 'Asset landing rises1.5m, while live ground-floor thresholds are0.2m over terrain; placing it at an entry breaks step/door contracts. It needs a deliberately redesigned stair entrance, outside furnishing scope.');
defer('industry_rail_gondola', '3.5m high asset cannot replace4m railcar or3.6m derailed opaque proxy honestly. No remaining canonical wagon host; adding another wagon would block rail/service corridor or require a new siding.');
defer('industry_rail_switch', 'Existing authored rail is a continuous single line, with no matching branching track. Switch lever is not placed as unexplained debris and does not authorize track geometry changes.');
defer('industry_rail_buffer_stop', 'P04 rail is through-running at both map edges; there is no siding terminus to support a buffer stop. Blocking the live rail/service route for catalogue coverage is unjustified.');
defer('industry_warehouse_shutter', '4.28m width/3.75m height frame is not compatible with the current warehouse/garage aperture and lintel. Retrofitting or layering it over the functional opening would change access and door behavior.');

const wanted = [...new Set(catalogue.assets.filter(a => ['town', 'industry'].includes(a.zone)).map(a => a.catalog_id))];
const coverage = wanted.map(catalog_id => ({catalog_id, placement_ids: placements.filter(p => p.catalog_id === catalog_id).map(p => p.id),
    deferred: deferred.find(d => d.catalog_id === catalog_id) ?? null}));
for (const c of coverage) assert(c.placement_ids.length || c.deferred, `Uncovered category ${c.catalog_id}`);
assert.equal(new Set(placements.map(p => p.id)).size, placements.length);
assert(placements.every(p => p.position_m.every(Number.isFinite) && p.scale[0] === p.scale[1] && p.scale[1] === p.scale[2]));

// Conservative offline footprint checks. Native geometry/contact/LOS remains the parent's acceptance gate.
function footprint(p) {
    const [lo, hi] = assets.get(`${p.catalog_id}/${p.variant}`).visual_bounds_godot_m;
    return [[lo[0], lo[2]], [hi[0], lo[2]], [hi[0], hi[2]], [lo[0], hi[2]]].map(([x, z]) => {
        const [dx, dz] = rotate(x * p.scale[0], z * p.scale[2], p.yaw_deg);
        return [p.position_m[0] + dx, p.position_m[2] + dz];
    });
}
function pointSegment(p, a, b) {
    const dx = b[0] - a[0], dz = b[1] - a[1], length2 = dx * dx + dz * dz;
    const t = length2 ? Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / length2)) : 0;
    return Math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dz);
}
const cross = (a, b, c) => (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
function segmentDistance(a, b, c, d) {
    if (cross(a, b, c) * cross(a, b, d) < 0 && cross(c, d, a) * cross(c, d, b) < 0) return 0;
    return Math.min(pointSegment(a, c, d), pointSegment(b, c, d), pointSegment(c, a, b), pointSegment(d, a, b));
}
function inside(point, polygon) {
    const turns = polygon.map((p, i) => cross(p, polygon[(i + 1) % polygon.length], point));
    return turns.every(n => n >= -1e-8) || turns.every(n => n <= 1e-8);
}
function polygonDistance(a, b) {
    if (a.some(p => inside(p, b)) || b.some(p => inside(p, a))) return 0;
    let result = Infinity;
    for (let i = 0; i < a.length; i++) for (let j = 0; j < b.length; j++) result = Math.min(result,
        segmentDistance(a[i], a[(i + 1) % a.length], b[j], b[(j + 1) % b.length]));
    return result;
}
function routeDistance(poly, points) {
    let result = Infinity;
    for (let i = 1; i < points.length; i++) {
        if (inside(points[i - 1], poly) || inside(points[i], poly)) return 0;
        for (let j = 0; j < poly.length; j++) result = Math.min(result, segmentDistance(points[i - 1], points[i], poly[j], poly[(j + 1) % poly.length]));
    }
    return result;
}
function yRange(p) {
    const b = assets.get(`${p.catalog_id}/${p.variant}`).visual_bounds_godot_m;
    return [p.position_m[1] + b[0][1] * p.scale[1], p.position_m[1] + b[1][1] * p.scale[1]];
}
function structureFootprint(b) {
    const [w, d] = b.footprint_m;
    return [[-w / 2, -d / 2], [w / 2, -d / 2], [w / 2, d / 2], [-w / 2, d / 2]].map(([x, z]) => {
        const [dx, dz] = rotate(x, z, b.yaw_deg);
        return [b.position_xz_m[0] + dx, b.position_xz_m[1] + dz];
    });
}
const offlineIssues = [];
let checkedRoutePairs = 0, checkedPropPairs = 0, checkedSupportCorners = 0;
const groundChecks = [];
for (const p of placements) {
    const poly = footprint(p);
    if (p.support.kind === 'terrain') {
        const ys = poly.map(q => terrain.heightAt(...q));
        const delta = Math.max(...ys) - Math.min(...ys);
        checkedSupportCorners += 4;
        groundChecks.push({id: p.id, corner_height_range_m: round(delta), surface_y_m: p.support.surface_y_m});
        if (delta > 0.015) offlineIssues.push({type: 'sloped_support', id: p.id, range_m: round(delta)});
        if (!p.proxy_id) {
            for (const corridor of layout.corridors) {
                checkedRoutePairs++;
                const clearance = routeDistance(poly, corridor.points_xz_m) - corridor.width_m / 2;
                if (clearance < 1 - 1e-5) offlineIssues.push({type: 'corridor_reservation', id: p.id, corridor: corridor.id, edge_clearance_m: round(clearance)});
            }
            for (const b of layout.structures) if (polygonDistance(poly, structureFootprint(b)) < 1.4 - 1e-5) {
                offlineIssues.push({type: 'structure_clearance', id: p.id, building: b.id, clearance_m: round(polygonDistance(poly, structureFootprint(b)))});
            }
        }
    }
    if (p.support.kind === 'building_floor') {
        const b = buildings.get(p.support.host_id);
        for (const point of poly) {
            const local = rotate(point[0] - b.position_xz_m[0], point[1] - b.position_xz_m[1], -b.yaw_deg);
            checkedSupportCorners++;
            if (Math.abs(local[0]) > b.footprint_m[0] / 2 - 0.24 || Math.abs(local[1]) > b.footprint_m[1] / 2 - 0.24) offlineIssues.push({type: 'interior_wall_envelope', id: p.id, local_xz_m: local.map(round)});
        }
        const doorLocalZ = -b.footprint_m[1] / 2;
        const localWalk = [[0, doorLocalZ - 1.2], [0, doorLocalZ + 1.2], [0, 0]].map(([x, z]) => {
            const [dx, dz] = rotate(x, z, b.yaw_deg); return [b.position_xz_m[0] + dx, b.position_xz_m[1] + dz];
        });
        const walkClearance = routeDistance(poly, localWalk);
        if (walkClearance < 0.7 - 1e-5) offlineIssues.push({type: 'interior_1p4m_aisle', id: p.id, edge_distance_m: round(walkClearance)});
        if (b.scene_ref.includes('t02_long_house')) {
            const stair = [[0.6, -1.7], [3.5, -1.7], [3.5, 4.6], [0.6, 4.6]].map(([x, z]) => {
                const [dx, dz] = rotate(x, z, b.yaw_deg); return [b.position_xz_m[0] + dx, b.position_xz_m[1] + dz];
            });
            if (polygonDistance(poly, stair) < 0.1) offlineIssues.push({type: 'stair_reservation', id: p.id});
        }
    }
    if (p.support.kind === 'surface') {
        const host = placements.find(h => h.id === p.support.host_id), hostPoly = footprint(host);
        if (!poly.every(q => inside(q, hostPoly))) offlineIssues.push({type: 'stack_overhang', id: p.id, host: host.id});
    }
}
for (let i = 0; i < placements.length; i++) for (let j = i + 1; j < placements.length; j++) {
    const a = placements[i], b = placements[j], ay = yRange(a), by = yRange(b);
    if (Math.min(ay[1], by[1]) - Math.max(ay[0], by[0]) < 0.002) continue;
    checkedPropPairs++;
    if (polygonDistance(footprint(a), footprint(b)) === 0) offlineIssues.push({type: 'prop_visual_intersection', ids: [a.id, b.id]});
}
const gameplay = JSON.parse(fs.readFileSync(path.join(project, 'design/town-500m/phase3/gameplay-placement-proposal.json')));
for (const p of placements.filter(p => ['building_floor', 'terrain'].includes(p.support.kind) && !p.proxy_id)) {
    for (const item of [...gameplay.props, ...gameplay.provisions]) {
        const distance = routeDistance(footprint(p), [[item.position_m[0], item.position_m[2]], [item.position_m[0], item.position_m[2]]]);
        if (distance < 1.4) offlineIssues.push({type: 'existing_interaction_clearance', id: p.id, node: item.node_path, edge_distance_m: round(distance)});
    }
}
const offlineVerification = {status: offlineIssues.length ? 'NEEDS_SPATIAL_REVIEW' : 'OFFLINE_CHECKS_PASS_NATIVE_PENDING',
    coverage_complete: true, unique_ids: true, finite_uniform_transforms: true,
    route_reservation_each_side_m: 1, local_walk_width_m: 1.4, support_flatness_limit_m: 0.015,
    checked_route_pairs: checkedRoutePairs, checked_prop_pairs: checkedPropPairs, checked_support_corners: checkedSupportCorners,
    issues: offlineIssues, terrain_support: groundChecks,
    limits: 'Conservative visual footprint/vertical interval checks. Host wall contact is intentional. No actual imported collision, physics, navmesh, LOS or render result.'};
const plan = {schema_version: 1, status: 'HAND_AUTHORED_SPATIAL_PLAN_OFFLINE_CHECKED_NATIVE_PENDING',
    scope: 'Town/Industry furnishing plus selected shared utility/freight; no gameplay, functional doors, AI, loot, patrol, extraction or access edits.',
    authoring: 'Each XZ chosen by hand in this helper. Only coordinate transforms, catalogue support calculations and named stacks are evaluated. No grid/random scatter.',
    geometry_source: 'phase5/asset-catalog.json actual GLB visual vertex bounds through full Y-up node transforms',
    floor_contract: 'Live building GroundFloor collider top localY0 + canonical instance root2.2; terrain placements use exported-mesh heightAt; all support rootY subtracts asset minY*scale.',
    style: 'Modern post-Soviet late-autumn abandonment: mostly maintained clean/used matched groups, selective worn waste/wrecks; all props retain native import scale1:1.',
    preserve: ['23 ground/four upper marker-port contracts', 'all corridors with2m route clearance and1.4m local walks', 'existing door openings and stair volumes', 'original loot/Props/Persist parents and exact pickup positions', 'all existing actors/patrols', 'all opaque LOS geometry until native replacement acceptance'],
    counts: {placements: placements.length, town: placements.filter(p => p.zone === 'town').length, industry: placements.filter(p => p.zone === 'industry').length,
        covered_town_industry_types: coverage.filter(c => c.placement_ids.length).length, deferred_town_industry_types: deferred.length,
        shared_types_used: new Set(placements.filter(p => p.catalog_id.startsWith('shared_')).map(p => p.catalog_id)).size},
    replacements_are_review_candidates: true, offline_verification: offlineVerification,
    placements, coverage, deferred,
    verification_limits: ['Offline authored coordinates and exact source support only; not native collision/contact/navigation/LOS/render PASS.', 'Parent owns scene merge/editor acceptance and may reject/relocate any collision candidate.', 'Furnishing extents include full visual AABBs; native collider shape and wall mounting require final editor checks.']};
fs.writeFileSync(path.join(__dirname, 'town-industry-placement.json'), JSON.stringify(plan, null, 2) + '\n');
console.log(JSON.stringify(plan.counts));
console.log(JSON.stringify(offlineVerification));
