// Offline placement proposal only; no scene, collider, terrain or gameplay mutation.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const terrain = require('../phase2/terrain-authoring.cjs');
const {rectangle, edges, segmentPolygon, polygonDistance} = require('../check-layout.cjs');
const read = name => JSON.parse(fs.readFileSync(path.join(__dirname, name), 'utf8'));
const catalog = read('asset-catalog.json');
const layout = read('../layout.json');
const buildings = read('../building-catalogue.json').structures;
const water = read('../terrain-contract.json').hydrology;
const facts = new Map(catalog.assets.map(a => [a.key, a]));
const records = [];
const deferred = [];
const round = n => Number(n.toFixed(6));
const sha = name => crypto.createHash('sha256').update(fs.readFileSync(path.join(__dirname, name))).digest('hex');
const rotate = (x,z,yaw) => {const a=yaw*Math.PI/180; return [Math.cos(a)*x+Math.sin(a)*z,-Math.sin(a)*x+Math.cos(a)*z];};
function add(id,zone,key,x,z,yaw=0,scale=1,role='',options={}) {
    assert.equal(scale, 1, `Native import scale required: ${id}`);
    const asset = facts.get(key);
    assert(asset, key);
    const support = options.support || {kind:'terrain'};
    const h = support.surface_y_m ?? terrain.heightAt(x,z);
    assert(Number.isFinite(h), `No dry support ${id}`);
    const y = h - asset.visual_bounds_godot_m[0][1]*scale;
    const record = {id,zone,catalog_id:asset.catalog_id,variant:asset.variant,finish:options.finish === undefined ? (asset.material_overrides.used ? 'used' : null) : options.finish,
        position_m:[x,round(y),z],yaw_deg:yaw,scale:[scale,scale,scale],support:{...support,surface_y_m:round(h),visual_min_y_m:asset.visual_bounds_godot_m[0][1]},
        collision_policy:options.collision_policy || (asset.collision_role==='none' || asset.collision_role==='visual_only' ? 'visual_only':'native'),role,
        rationale:options.rationale || role,...options};
    // Options retain support details but cannot accidentally discard the evaluated surface height.
    record.support = {...support,surface_y_m:round(h),visual_min_y_m:asset.visual_bounds_godot_m[0][1]};
    const b=asset.visual_bounds_godot_m;
    record.footprint_corners_xz_m = [[b[0][0],b[0][2]],[b[1][0],b[0][2]],[b[1][0],b[1][2]],[b[0][0],b[1][2]]].map(([a,c])=>{const r=rotate(a*scale,c*scale,yaw);return [round(x+r[0]),round(z+r[1])];});
    if(support.kind==='terrain' || support.kind==='existing_proxy') {
        const samples=[[x,z],...record.footprint_corners_xz_m].map(([a,c])=>terrain.heightAt(a,c));
        record.support.terrain_sample_range_y_m = [round(Math.min(...samples)),round(Math.max(...samples))];
        if(options.ground_contact==='embed_to_lowest') {
            record.support.terrain_center_y_m=round(h);
            record.support.surface_y_m=round(Math.min(...samples));
            record.support.embed_below_center_m=round(h-Math.min(...samples));
            record.position_m[1]=round(Math.min(...samples)-asset.visual_bounds_godot_m[0][1]*scale);
        }
    }
    records.push(record);
    return record;
}
function floor(id,zone,key,hostId,lx,lz,yaw=0,role='',options={}) {
    const host=buildings.find(b=>b.id===hostId);assert(host,hostId);
    const [dx,dz]=rotate(lx,lz,host.yaw_deg);
    return add(id,zone,key,round(host.position_xz_m[0]+dx),round(host.position_xz_m[1]+dz),yaw,1,role,{...options,support:{kind:'building_floor',host_id:hostId,local_position_m:[lx,0,lz],surface_y_m:host.pad_intent.surface_y_m+.2,evidence:hostId==='B04-ENTRY'?'Graybox/bunker_entry.tscn GroundFloor top localY=0':'Live building template GroundFloor centreY=-.1, thickness=.2; root=pad+.2'}});
}
function mount(id,zone,key,x,z,yaw,bottomY,host,role,options={}) {
    return add(id,zone,key,x,z,yaw,options.scale||1,role,{...options,collision_policy:'visual_only',support:{kind:'wall',host_id:host,surface_y_m:bottomY},contact_exception:'Intentional wall mount; face/contact and fasteners require native visual readback.'});
}
function defer(catalog_id,reason,proxy_ids=[]) {deferred.push({catalog_id,reason,proxy_ids,status:'DEFERRED_COMPATIBILITY_REVIEW'});}

// Bunker: one real entry room, a separate supply yard and external utility service area.
floor('OB-B04-locker-01','bunker','bunker_metal_locker/closed','B04-ENTRY',2.8,-.7,0,'Guard locker against west room wall');
floor('OB-B04-locker-02','bunker','bunker_metal_locker/closed','B04-ENTRY',2.8,.1,0,'Second locker; central doorway/aisle stays open');
floor('OB-B04-radio','bunker','bunker_radio_cabinet/with-controls','B04-ENTRY',2.8,2.8,0,'Radio cabinet in northwest guard office corner');
floor('OB-B04-bed','bunker','bunker_bunk_bed/made-up','B04-ENTRY',-2.6,1.3,90,'Rest bunk on east wall, away from south entry');
floor('OB-B04-case','bunker','bunker_military_supply_crate/metal','B04-ENTRY',-2.5,-1.1,15,'Guard emergency equipment beside bunk');
mount('OB-B04-phone','bunker','bunker_wall_phone/mounted',-149.8,-150.72,0,11.42,'B04-ENTRY','Rear wall duty telephone');
mount('OB-B04-electric-sign','bunker','bunker_military_warning_sign/electric',-151.25,-150.72,0,11.82,'B04-ENTRY','Electrical warning above radio corner');
mount('OB-B05-breaker','bunker','bunker_breaker_panel/closed',-198.13,-147,270,11.1,'B05-A','Closed external workshop breaker panel');
add('OB-B05-generator','bunker','bunker_diesel_generator/large',-207,-173,0,1,'Generator on compound upper service shoulder above workshop',{assembly_group:'B05-utility'});
add('OB-B05-shaft','bunker','bunker_ventilation_shaft/tall',-207,-170,0,1,'Utility exhaust shaft beside upper service plant',{assembly_group:'B05-utility'});
mount('OB-B05-duct','bunker','bunker_ventilation_duct/straight',-199.15,-147,90,12.1,'B05-A','External wall duct above utility equipment',{assembly_group:'B05-utility'});
add('OB-B05-pipe','bunker','bunker_pipe_valve_kit/straight',-210,-172,90,1,'Grounded utility pipe beside generator',{assembly_group:'B05-utility'});
add('OB-B05-valve','bunker','bunker_pipe_valve_kit/wheel',-210,-169.7,90,1,'Valve at utility pipe service end',{assembly_group:'B05-utility'});
add('OB-B05-drum-01','bunker','shared_oil_drum/closed',-204,-172,0,1,'Generator fuel drum',{assembly_group:'B05-utility'});
add('OB-B05-drum-02','bunker','shared_oil_drum/dented',-204,-171.1,20,1,'Retired fuel drum beside sealed stock',{assembly_group:'B05-utility'});
add('OB-B05-reel','bunker','shared_cable_reel/wood',-204.4,-174.5,30,1,'Service cable stock',{assembly_group:'B05-utility'});
add('OB-supply-net','bunker','bunker_camouflage_net/draped',-171,-184,0,1,'Covered external supply sorting bay',{assembly_group:'Bunker-supply',ground_contact:'embed_to_lowest',contact_exception:'Four canopy posts intentionally embed up to.26m into natural ground; net never floats. Native pole/terrain contact still needs review.'});
add('OB-supply-wood-01','bunker','bunker_military_supply_crate/wood',-172.3,-184.3,0,1,'Crate under covered bay edge',{assembly_group:'Bunker-supply'});
add('OB-supply-wood-02','bunker','bunker_military_supply_crate/wood',-169.7,-184.3,0,1,'Second crate; centre of bay remains accessible',{assembly_group:'Bunker-supply'});
add('OB-supply-wood-03','bunker','bunker_military_supply_crate/wood',-172.6,-187,10,1,'Inbound stock outside canopy',{assembly_group:'Bunker-supply'});
add('OB-supply-metal-01','bunker','bunker_military_supply_crate/metal',-170.8,-187.2,0,1,'Sealed radio spares',{assembly_group:'Bunker-supply'});
add('OB-supply-metal-02','bunker','bunker_military_supply_crate/metal',-169.6,-187.2,0,1,'Sealed communications spares',{assembly_group:'Bunker-supply'});
add('OB-supply-pallet','bunker','shared_wood_pallet/loaded',-165.6,-184.5,90,1,'Inbound pallet beside sorting bay',{assembly_group:'Bunker-supply'});
add('OB-supply-dumpster','bunker','shared_industrial_dumpster/closed',-178,-180,90,1,'Military supply packaging disposal');
add('OB-B06-light','bunker','bunker_floodlight_mast/dual',-154,-123.8,0,1,'Gate-side floodlight, outside six metre gate and patrol reservation');
add('OB-B06-hedgehog-01','bunker','bunker_anti_vehicle_hedgehog/single',-137,-133,0,1,'Stored vehicle obstacle east of open checkpoint approach');
add('OB-B06-hedgehog-02','bunker','bunker_anti_vehicle_hedgehog/single',-137,-129,0,1,'Second stored obstacle, no gate blockage');
mount('OB-B06-stop','bunker','bunker_military_warning_sign/stop',-146,-126.37,0,11.2,'B06-A','Checkpoint warning on booth south face');
// Fence top is a local visual addition to an existing boundary, never a replacement gate.
add('OB-bunker-wiretop','bunker','bunker_razorwire_fence_top/straight',-205,-220.45,0,1,'Short surviving razor-wire run on north compound fence',{collision_policy:'visual_only',support:{kind:'surface',host_id:'BUNKER-fence-north',surface_y_m:terrain.heightAt(-205,-220.45)+2.4},contact_exception:'Intentional fence-top contact; retain original continuous wire-fence collision.'});
defer('bunker_blast_door','Existing B04 door is 1.2×2.4m. Source closed assembly is 1.44×2.556m and open leaf has 1.56m depth; neither clearance nor leaf sweep is certified. Keep current doorway and no functional-door mechanics.',['B04-ENTRY']);
defer('bunker_bunker_portal_trim','Source frame is 2.8×3.2×.8m, while B04 lintel/clear opening are already fixed at 1.2×2.4m. Aperture and lintel contact must be native-fitted before replacing trim.',['B04-ENTRY']);
defer('bunker_checkpoint_gate','Source gate is 8.8m wide; canonical compound gate is exactly6m. Unit-scale assembly cannot replace the protected gate and must not close its pedestrian/vehicle access.',['B06-A']);
defer('bunker_watchtower_kit','Existing B07/B08 are4×4×8m sealed opaque proxies; platform is4.06×4.06×4.1m and roof extends to5.8m. Unit-scale assembly cannot hide those proxies without invisible solid upper volume or changed silhouette.',['B07-A','B08-A']);

// Hills: small natural clusters and abandoned ridge equipment outside authored route envelopes.
add('OH-rock-01','hills','hills_rock_cluster/medium',-46,-194,15,1,'Natural outcrop beside ridge relay service area');
add('OH-rock-02','hills','hills_rock_cluster/small',-43.4,-192.5,70,1,'Satellite stone at outcrop toe');
add('OH-cliff-01','hills','hills_cliff_wedge/straight',-208,-90,0,1,'Short exposed escarpment face east of old ruin',{ground_contact:'embed_to_lowest',contact_exception:'Natural cliff toe embeds in slope to lowest footprint sample; does not flatten terrain or replace existing LOS cover.'});
add('OH-revetment','hills','hills_trench_kit/straight',-57,-184,25,1,'Abandoned surface revetment; no terrain excavation or trench traversal',{ground_contact:'embed_to_lowest',contact_exception:'Source toe -.12m and foundation embed in slope; continuous terrain remains, so this is a surface revetment only.'});
add('OH-wall','hills','hills_broken_retaining_wall/low',-209,-99.5,0,1,'Detached ruined retaining-wall section beside H04',{ground_contact:'embed_to_lowest',contact_exception:'Broken masonry foundation intentionally embeds to lowest footprint sample; no floating base.'});
add('OH-case-01','hills','hills_field_equipment_case/closed',-53.7,-184.4,20,1,'Abandoned survey equipment by revetment');
add('OH-case-02','hills','hills_field_equipment_case/closed',-52.5,-185.8,12,1,'Second field case in abandoned observation cache');
add('OH-mast-spare','hills','hills_radio_mast/antenna',-18,-225,0,1,'Short retired relay antenna beside existing H03 service site',{rationale:'Complete4m antenna variant stands on a separate service footing; does not replace the13m H03 sealed proxy.'});
defer('hills_observation_platform','H01 is4×4×5m closed proxy; finished platform including approach is4.06×8.23m and only3/4.1m high. Unit-scale use would consume protected ridge access and mismatch sealed physics.',['H01-A']);
defer('hills_pillbox','H02 is6×5×2.7m closed proxy; finished closed shell is6.3×5.38×2.7m. Replacing a continuous opaque box with aperture geometry requires explicit shot/LOS/closed-access fit, so retain it.',['H02-A']);
defer('hills_hill_shelter','No existing shelter footprint exists in the fixed hills building catalogue. Adding4.3×3.3m shelter would be a new building and cover landmark; keep finished source available for a later authored-layout decision.');

// Native tree visuals and helpers replace the same93 canonical vegetation proxies.
const treeChoice = ['forest_pine_tree/C', 'forest_spruce_tree/C', 'forest_birch_tree/B'];
for (const [i,seed] of layout.dressing.vegetation.entries()) {
    const key = seed.id === 'H008' ? treeChoice[0] : treeChoice[seed.zone_id === 'farmland' ? 2 : i % 3];
    const [x, z] = seed.position_xz_m;
    const record=add(`OT-${seed.id}`,seed.zone_id,key,seed.id === 'H008' ? -247.35 : x,z,seed.id === 'H008' ? 0 : (i*47)%360,1,'Native-size tree replacing its named canonical vegetation proxy',{finish:null,collision_policy:'native',proxy_id:seed.id,support:{kind:'terrain'},rationale:'Keep species and instance coverage; use original imported trunk helper and disable only the exact old trunk shape. Edge trees may move inward to retain complete crowns.'});
    record.proxy_replacement = {kind:'vegetation_native_replacement',preserve_collision:false,retired_shape_path:`Concealment/${seed.id}/TrunkBody/Shape`,original_position_xz_m:seed.position_xz_m,native_contact_review_required:true};
}
// Ranger camp in the closed cottage's external yard; nothing placed inside inaccessible buildings.
add('OF-tarp','forest','forest_tarp_camp/intact',117,-178,0,1,'Ranger rest canopy in F01 southern yard',{assembly_group:'Forest-ranger-camp'});
add('OF-cot','forest','forest_ranger_shelter_props/cot',115.9,-178,90,1,'Camp cot under west edge of tarp',{assembly_group:'Forest-ranger-camp'});
add('OF-table','forest','forest_ranger_shelter_props/table',118.1,-178,0,1,'Ranger field table under east edge of tarp',{assembly_group:'Forest-ranger-camp'});
add('OF-shelf','forest','forest_ranger_shelter_props/shelf',118.2,-179.15,0,1,'Small supply shelf below tarp rear edge',{assembly_group:'Forest-ranger-camp'});
add('OF-fire','forest','forest_campfire_ring/ash',121.5,-174,0,1,'Cold campfire clear of fabric and access route',{assembly_group:'Forest-ranger-camp'});
add('OF-stump','forest','forest_tree_stump/old',123.2,-174.6,25,1,'Natural sitting stump beside cold fire',{assembly_group:'Forest-ranger-camp'});
add('OF-log','forest','forest_fallen_log/short',124.8,-173.7,15,1,'Fallen seating log outside camp approach',{assembly_group:'Forest-ranger-camp'});
add('OF-woodcrate','forest','shared_wooden_crate/small',118.1,-178,0,1,'Equipment crate on ranger table',{assembly_group:'Forest-ranger-camp',collision_policy:'visual_only',support:{kind:'surface',host_id:'OF-table',surface_y_m:terrain.heightAt(118.1,-178)+.75},contact_exception:'Intentional tabletop assembly; table surface top from actual GLB maxY=.75m.'});
add('OF-undergrowth-01','forest','forest_undergrowth/A',122,-181,40,1,'Undergrowth beside cottage yard edge',{collision_policy:'visual_only'});
add('OF-undergrowth-02','forest','forest_undergrowth/B',125,-179,75,1,'Undergrowth at camp perimeter',{collision_policy:'visual_only'});
add('OF-debris-01','forest','forest_small_forest_debris/A',121.7,-181,110,1,'Leaf and twig litter outside camp',{collision_policy:'visual_only'});
add('OF-debris-02','forest','forest_small_forest_debris/C',123.2,-180.4,25,1,'Broken branch litter outside camp',{collision_policy:'visual_only'});
add('OF-trail-sign','forest','forest_forest_trail_sign/painted',134,-184,40,1,'Ranger route sign beside forest trail, outside its clear envelope');
add('OF-trailer','forest','forest_logging_trailer/loaded',177,-140,0,1,'Loaded trailer parked south of F02 storage shed',{assembly_group:'Forest-logging'});
add('OF-logstock-01','forest','forest_log_stack/long',172,-139,0,1,'Cut logs waiting beside logging trailer',{assembly_group:'Forest-logging'});
add('OF-logstock-02','forest','forest_log_stack/short',174,-136,90,1,'Offcuts separate from long timber',{assembly_group:'Forest-logging'});
add('OF-timber','forest','shared_timber_stack/boards',179,-136.5,0,1,'Sawn boards beside closed saw shed',{assembly_group:'Forest-logging'});
defer('forest_hunting_stand','Existing F03 is3×3×4.5m sealed opaque proxy. Enclosed finished stand is2.2×3.011×4.6m with open legs/ladder; hiding its solid box creates invisible obstruction, while a second stand is an unapproved landmark.',['F03-A']);

// Farm machinery and feed stay beside existing sheds/barn; protected field/spawn routes remain empty.
add('OA-tractor','farmland','farmland_farm_tractor/abandoned',-207,95,0,1,'Tractor parked north of A04 barn service wall',{assembly_group:'Farm-A04-machinery'});
add('OA-trailer','farmland','farmland_farm_trailer/empty',-212.4,95,0,1,'Unhitched trailer aligned beside tractor',{assembly_group:'Farm-A04-machinery'});
add('OA-plough','farmland','farmland_plough_attachment/multi-furrow',-205,91.2,15,1,'Detached plough in machinery service patch',{assembly_group:'Farm-A04-machinery'});
add('OA-cart','farmland','farmland_wood_cart/loaded',-216.5,95.5,90,1,'Timber cart by barn west return',{assembly_group:'Farm-A04-machinery'});
add('OA-hopper','farmland','farmland_grain_hopper/tall',-205,115,0,1,'Grain hopper adjacent to A04 feed end',{assembly_group:'Farm-A04-machinery'});
add('OA-wheelbarrow','farmland','farmland_wheelbarrow/loaded',-207.6,115.5,40,1,'Feed handling wheelbarrow beside hopper',{assembly_group:'Farm-A04-machinery'});
add('OA-feed-01','farmland','farmland_feed_sack_stack/stack',-203.4,115,0,1,'Bagged feed beside hopper, visibly hand-sized',{assembly_group:'Farm-A04-machinery'});
add('OA-feed-02','farmland','farmland_feed_sack_stack/stack',-203.4,117,10,1,'Separate second feed stack with access around it',{assembly_group:'Farm-A04-machinery'});
add('OA-trough','farmland','farmland_water_trough/filled',-196,146.5,0,1,'Livestock trough outside A05 shelter');
add('OA-pump','farmland','farmland_well_pump/hand',-196,148,0,1,'Hand pump serving trough');
add('OA-firewood','farmland','farmland_firewood_stack/stack',-201.4,-28,90,1,'Firewood beside farmhouse east side');
add('OA-milkcan','farmland','farmland_farm_small_clutter/milk-can',-202.2,-30.4,0,1,'Milk can beside farmhouse work corner');
add('OA-bucket','farmland','farmland_farm_small_clutter/bucket',-201.5,-30.4,10,1,'Water bucket in farmhouse work corner');
floor('OA-barn-feed-01','farmland','farmland_feed_sack_stack/stack','A06-A',-8,5.8,0,'Feed sacks in rear west barn storage bay');
floor('OA-barn-feed-02','farmland','farmland_feed_sack_stack/stack','A06-A',-6.4,5.8,0,'Second feed stack in rear barn bay');
floor('OA-barn-crate','farmland','shared_wooden_crate/large','A06-A',8,5.7,0,'Barn tools in rear east storage bay');
floor('OA-barn-pallet','farmland','shared_wood_pallet/empty','A06-A',7,3.2,90,'Empty feed pallet beside barn storage');
add('OA-hay-01','farmland','farmland_hay_bale/round',-163.5,212.2,0,1,'Round bale in side barn yard');
add('OA-hay-02','farmland','farmland_hay_bale/round',-165.1,212.4,12,1,'Second round bale in barn stock cluster');
add('OA-hay-03','farmland','farmland_hay_bale/rectangular',-163.8,214,0,1,'Small square bale beside round stock');
add('OA-hay-04','farmland','farmland_hay_bale/round',-55,210.5,90,1,'Hay stock on A07 southern service side');
add('OA-cart-02','farmland','farmland_wood_cart/empty',-48,210.5,0,1,'Household cart beside A07 service yard');
add('OA-tools-02','farmland','farmland_farm_small_clutter/bucket',-49.2,210.7,0,1,'Bucket near household cart');
add('OA-farmgate','farmland','farmland_farm_gate/open',-180,-28,90,1,'Open loose-leaf gate at A02 tool-yard side, does not span a circulation route',{rationale:'Decorative yard fixture east of existing closed tool shed; no new enclosure, scripted gate or route restriction.'});
defer('farmland_barn_door','A06 warehouse opening is6m wide×4m high; completed barn-door frame is5.45×3m. Unit-scale frame would narrow the verified entrance and leave unexplained gaps. Preserve original open portal, no door mechanics.',['A06-A']);

// River maintenance stock is entirely on dry ground, beyond the protected6m bank reserve.
add('OR-deck-stock','river','river_bridge_deck/segment',109,38,0,1,'Spare deck section in existing east-bank bridge maintenance patch',{assembly_group:'River-dry-maintenance',rationale:'Stored horizontal bridge component; no new deck, ford, log link or walkable span over water.'});
add('OR-parapet-stock','river','river_bridge_parapet/end',111,45,0,1,'Spare parapet unit beside deck stock',{assembly_group:'River-dry-maintenance'});
add('OR-support-stock','river','river_bridge_support/pier',116,39,0,1,'Retired cast bridge pier stored upright on dry maintenance patch',{assembly_group:'River-dry-maintenance'});
add('OR-culvert','river','river_culvert_pipe_end/round',116,46,90,1,'Uninstalled culvert end in bridge repair stock',{assembly_group:'River-dry-maintenance'});
add('OR-block-01','river','river_erosion_block/small',109,48,15,1,'Spare erosion-control block in repair stock',{assembly_group:'River-dry-maintenance'});
add('OR-rock-01','river','river_riverbank_rock/large',47,-148,20,1,'Dry high-bank rock outside six metre bank reserve',{ground_contact:'embed_to_lowest',contact_exception:'Natural stone toe embeds below higher corner samples.'});
add('OR-rock-02','river','river_riverbank_rock/small',48.5,-149,85,1,'Satellite high-bank stone');
add('OR-reed-01','river','river_river_reeds/dense',46,-143,30,1,'Dry-bank reed patch behind protected reserve',{collision_policy:'visual_only'});
add('OR-reed-02','river','river_river_reeds/sparse',48,-142,80,1,'Second dry-bank reed patch',{collision_policy:'visual_only'});
add('OR-driftwood','river','river_driftwood/branch',50,-146,20,1,'Driftwood left above flood line',{collision_policy:'visual_only'});
add('OR-log-debris','river','river_log_crossing/side',52,-143.5,75,1,'Discarded log on dry upper bank, explicitly no crossing',{collision_policy:'visual_only',rationale:'Source catalog name is log_crossing, but this is nontraversal dry-bank timber debris. No wet overlap, bank-reserve intrusion, collider or stepping chain; exactly R01/R02 remain water crossings.'});
add('OR-litter-01','river','river_bridge_litter/trash',112,47,20,1,'Repair litter beside stored parapet',{collision_policy:'visual_only'});
add('OR-litter-02','river','river_bridge_litter/sticks',50,-140.5,55,1,'Flood-carried sticks above reserve',{collision_policy:'visual_only'});

// Lake: all new fishing clutter stays on the existing dry shore; deck and gangway untouched.
add('OL-pier-stock','lake','lake_wood_pier/straight',185,132.5,90,1,'Spare pier section stored beside L04 boat shed',{rationale:'Dry storage only. Original L03 deck/gangway visuals and exact physics remain; this2×2.5m part does not extend any water walkway.'});
add('OL-boat','lake','lake_rowboat/beached',183,137,0,1,'Beached rowboat on boat-shed dry service apron',{assembly_group:'Lake-boatshed'});
add('OL-net','lake','lake_fishing_net/rolled',184,135,0,1,'Rolled fishing net beside beached boat',{assembly_group:'Lake-boatshed'});
add('OL-oars','lake','lake_boat_toolkit/oars',183,135.7,90,1,'Oars stored beside beached boat',{assembly_group:'Lake-boatshed',collision_policy:'visual_only'});
add('OL-toolbox','lake','lake_boat_toolkit/toolbox',185.4,134.9,10,1,'Boat repair toolbox beside net',{assembly_group:'Lake-boatshed'});
add('OL-crate-01','lake','lake_fishing_crate/closed',190,134,0,1,'Closed fishing crate by boat shed rear service side',{assembly_group:'Lake-boatshed'});
add('OL-crate-02','lake','lake_fishing_crate/closed',191.2,134,10,1,'Second closed crate in fishing stock',{assembly_group:'Lake-boatshed'});
add('OL-trap-01','lake','lake_fishing_trap/basket',190,132.5,0,1,'Basket trap drying beside crates',{assembly_group:'Lake-boatshed'});
add('OL-trap-02','lake','lake_fishing_trap/cage',191.2,132.5,15,1,'Metal trap beside basket trap',{assembly_group:'Lake-boatshed'});
add('OL-rope','lake','lake_rope_coil/large',188,132.7,0,1,'Mooring rope stored at boat shed',{assembly_group:'Lake-boatshed',collision_policy:'visual_only'});
add('OL-lantern','lake','lake_lantern/off',190,134,0,1,'Unlit lantern atop fishing crate',{assembly_group:'Lake-boatshed',collision_policy:'visual_only',support:{kind:'surface',host_id:'OL-crate-01',surface_y_m:terrain.heightAt(190,134)+.38},contact_exception:'Intentional crate-top assembly; no added Light3D or night-light behavior.'});
mount('OL-lifering','lake','lake_life_ring/mounted',188,135.87,180,3.05,'L04-A','Lifesaving ring mounted on boat shed north service wall');
add('OL-bollard','lake','lake_mooring_bollard/timber',169,148.5,0,1,'Retired timber bollard stored above shoreline reserve');
add('OL-bench','lake','lake_lakeside_bench/worn',160,138.3,180,1,'Existing settlement shore overlook, back from path and bank');
floor('OL-intake-stock','lake','lake_water_intake_pipe/intake','L01-A',1.7,1.2,90,'Spare intake pipe along pump-house rear wall',{collision_policy:'visual_only',rationale:'Stored spare pipe in existing pump house, no wet approach or added water mechanics.'});
add('OL-cattails-01','lake','lake_cattails/dense',161,151,45,1,'Dry upper-shore cattail patch outside six metre bank reserve',{collision_policy:'visual_only'});
add('OL-cattails-02','lake','lake_cattails/sparse',162,151,10,1,'Sparse cattails near upper shore patch',{collision_policy:'visual_only'});
add('OL-litter','lake','shared_street_litter/tin',192,133.4,30,1,'Small discarded tin near fishing work stock',{collision_policy:'visual_only'});

const contacts = {
    'OB-supply-net':['OB-supply-wood-01','OB-supply-wood-02'],
    'OB-supply-wood-01':['OB-supply-net'], 'OB-supply-wood-02':['OB-supply-net'],
    'OF-tarp':['OF-cot','OF-table','OF-shelf','OF-woodcrate'],
    'OF-cot':['OF-tarp'], 'OF-table':['OF-tarp','OF-woodcrate'], 'OF-shelf':['OF-tarp'],
    'OF-woodcrate':['OF-tarp','OF-table'],
    'OL-crate-01':['OL-lantern'], 'OL-lantern':['OL-crate-01']
};
for(const r of records) if(contacts[r.id]) r.contacts_with_ids=contacts[r.id];
const covered=new Set(records.map(r=>r.catalog_id));
const zoneTypes=[...new Set(catalog.assets.filter(a=>['bunker','hills','forest','farmland','river','lake'].includes(a.zone)).map(a=>a.catalog_id))];
assert(zoneTypes.every(id=>covered.has(id)||deferred.some(d=>d.catalog_id===id)), 'Missing outer category disposition');
assert.equal(new Set(records.map(r=>r.id)).size,records.length);
assert.equal(records.filter(r=>r.proxy_replacement).length,93);
assert(records.filter(r=>r.proxy_replacement).every(r=>r.proxy_replacement.preserve_collision===false));
for(const r of records) assert(r.scale.every(v=>v===1),r.id);
const wetPolygons=[water.river.actual_water_polygon_xz_m,water.lake.actual_water_polygon_xz_m];
const inspection=[];
for(const r of records.filter(r=>!r.proxy_id)) {
    const footprint=r.footprint_corners_xz_m;
    const wetDistance=Math.min(...wetPolygons.map(p=>polygonDistance(footprint,p)));
    if(r.support.kind==='terrain') assert(wetDistance>=6-1e-5,`${r.id} intrudes bank reserve (${wetDistance})`);
    const routeDistances=layout.corridors.filter(c=>c.type!=='rail').map(c=>({id:c.id,clearance:Math.min(...edges(c.points_xz_m).map(([a,b])=>segmentPolygon(a,b,footprint)))-c.width_m/2}));
    const conflicts=routeDistances.filter(d=>d.clearance<.7);
    if(conflicts.length && r.support.kind==='terrain') inspection.push({id:r.id,reason:'route-margin review',conflicts});
    const host=r.support.host_id;
    const structureConflicts=buildings.filter(b=>b.id!==host&&polygonDistance(footprint,rectangle(b.position_xz_m,b.footprint_m,b.yaw_deg))<.15).map(b=>b.id);
    if(structureConflicts.length) inspection.push({id:r.id,reason:'structure contact review',host_ids:structureConflicts});
    if(r.collision_policy==='native') {
        const treeConflicts=layout.dressing.vegetation.filter(v=>polygonDistance(footprint,rectangle(v.position_xz_m,[v.trunk_diameter_m,v.trunk_diameter_m],0))<.3).map(v=>v.id);
        if(treeConflicts.length) inspection.push({id:r.id,reason:'existing trunk clearance',proxy_ids:treeConflicts});
        const coverConflicts=layout.dressing.cover.filter(c=>polygonDistance(footprint,rectangle(c.position_xz_m,[c.size_xyz_m[0],c.size_xyz_m[2]],c.yaw_deg))<.3).map(c=>c.id);
        if(coverConflicts.length) inspection.push({id:r.id,reason:'existing cover clearance',proxy_ids:coverConflicts});
    }
    if(r.support.kind==='terrain'&&r.ground_contact!=='embed_to_lowest'&&r.support.terrain_sample_range_y_m[1]-r.support.terrain_sample_range_y_m[0]>.3) inspection.push({id:r.id,reason:'sloped-ground contact',range_y_m:r.support.terrain_sample_range_y_m});
}
const output={schema_version:1,status:'OFFLINE_DRAFT_NATIVE_FIT_REQUIRED',coordinate_system:'Godot +X east,+Z south,+Y up; yaw X=cos*x+sin*z,Z=-sin*x+cos*z',
    source_sha256:{'asset-catalog.json':sha('asset-catalog.json'),'layout.json':sha('../layout.json'),'building-catalogue.json':sha('../building-catalogue.json'),'terrain-contract.json':sha('../terrain-contract.json')},
    invariants:{crossings:['R01','R02'],additional_crossings:0,canonical_vegetation_seeds:93,extra_trees:0,preserve_roads_terrain_buildings_markers_patrols:true,preserve_existing_hardcover_physics_and_opacity:true,new_gameplay_mechanics:false,minimum_route_margin_m:.7,minimum_interior_walk_clearance_m:1.4,minimum_bank_setback_m:6,minimum_open_water_gap_m:20},
    counts:{records:records.length,existing_vegetation_visual_replacements:93,outer_zone_catalog_types:zoneTypes.length,covered_outer_types:zoneTypes.filter(t=>covered.has(t)).length,deferred_outer_types:deferred.length,shared_types_used:new Set(records.filter(r=>r.catalog_id.startsWith('shared_')).map(r=>r.catalog_id)).size},
    placements:records,coverage:zoneTypes.map(catalog_id=>({catalog_id,status:covered.has(catalog_id)?'PLACED_PROPOSAL':'DEFERRED',instance_ids:records.filter(r=>r.catalog_id===catalog_id).map(r=>r.id)})),deferred,inspection,
    native_gates:['Review each accepted contact exception in editor at ground-eye height.','Keep all old opaque LOS/structure/cover proxies visually and physically unchanged unless exact fit is independently proven.','Confirm species trunk/canopy contact, collider diameters and no trees in actual ports; no additional scatter.','Walk all8spawn-to-extract routes,23ground/fourupper interiors, bridges and dock; no collider replacement can inherit previous PASS.','Measure rendered FPS with final placements; imported mesh counts/material passes and transparency cost remain unmeasured.','Exactly two crossings remain. River/lake deck/support/pier/log catalog examples are dry storage/debris, no wet walkway or stepping chain.']};
const target=path.join(__dirname,'outer-placement.json');
fs.writeFileSync(target,JSON.stringify(output,null,2)+'\n');
console.log(JSON.stringify({counts:output.counts,inspection},null,2));
