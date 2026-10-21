// Offline proposal only; canonical geometry and editor state are never written.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {inputFor} = require('./check-phase3-los.cjs');
const {check, rectangle, edges, distance, segmentPolygon, polygonDistance, pathLength} = require('../check-layout.cjs');
const {analysis} = require('../../town-concept-b/check-los.cjs');
const source = JSON.parse(fs.readFileSync(`${__dirname}/../layout.json`));
const layout = structuredClone(source);
const changes = {corridor_replacements: [], graph_edge_replacements: [], cover_replacements: [], additional_cover: [], additional_corridors: [], remove_cover_ids: []};
function replaceCover(row) {
    const cover = layout.dressing.cover.find(c => c.id === row.id);
    assert(cover, row.id);
    Object.assign(cover, row);
    changes.cover_replacements.push(row);
}
function addCover(row) {
    assert(!layout.dressing.cover.some(c => c.id === row.id), row.id);
    const cover = {yaw_deg: 0, solid: true, opaque_proxy: true, collider_role: 'solid_cover', source_ref: 'PHASE3_LOS', model_status: 'dimensioned graybox; native/finished art pending', ...row};
    layout.dressing.cover.push(cover);
    changes.additional_cover.push(cover);
}
function replaceCorridor(row) {
    const corridor = layout.corridors.find(c => c.id === row.id);
    assert(corridor, row.id);
    Object.assign(corridor, row);
    Object.assign(layout.terrain.corrected_corridors.find(c => c.id === row.id), row);
    changes.corridor_replacements.push(row);
}
const county = layout.corridors.find(c => c.id === 'P01');
const countyPoints = [...county.points_xz_m.slice(0,-1), [130,-8],[170,-8],[180,5.73],county.points_xz_m.at(-1)];
replaceCorridor({id:'P01', points_xz_m: countyPoints, surface_y_m:[...county.surface_y_m.slice(0,-1),2,2,2,2], reason:'Full8m service-road bypass south of abandoned delivery wreck; road reservation follows actual passable asphalt, original east/west extents retained.'});
replaceCover({id:'LOS_COUNTY_E_SCREEN',position_xz_m:[144,12],size_xyz_m:[.3,2.6,30],grounding:'terrain_conforming_wall',reason:'Opaque loading-yard boundary crosses retired road alignment; full8m service road routes around its south end.'});
replaceCover({id:'LOS_P04_FREIGHT',position_xz_m:[217.5,-60],size_xyz_m:[36,3.6,3.1],yaw_deg:0,allow_rail_overlap:true,kind:'derailed_freight_wreck',assembly:'two coupled opaque freight wagons; combined36m length',reason:'Two coupled derailed freight wagons form one continuous opaque assembly across rail reservation; unchanged track remains visible,2.5m service trail bypasses west.'});
const rail=source.corridors.find(c=>c.id==='P04');
const railX=z=>rail.points_xz_m[1][0]+(z-rail.points_xz_m[1][1])*(rail.points_xz_m[2][0]-rail.points_xz_m[1][0])/(rail.points_xz_m[2][1]-rail.points_xz_m[1][1]);
const bypass={id:'P04_SERVICE_BYPASS',name:'Derailed freight west service bypass',type:'footpath',surface:'gravel',width_m:2.5,maximum_grade_percent:15,reservation_margin_each_side_m:1,points_xz_m:[[railX(-80),-80],[197.5,-80],[197.5,-54],[railX(-54),-54]],surface_y_m:[2,2,2,2],connects_to_corridor:'P04',reason:'Physical2.5m trail around derailed railcar west end; track geometry is retained.'};
layout.corridors.push(bypass); layout.terrain.corrected_corridors.push(structuredClone(bypass)); changes.additional_corridors.push(bypass);
addCover({id:'LOS_P12_INNER_WEST_PANEL',los_group:'P12',position_xz_m:[-219.5,-170.05],size_xyz_m:[.3,2.6,97.9],kind:'opaque_fence_panel',grounding:'terrain_conforming_wall',reason:'Selective inner west compound opaque section; local1m terrain-conforming panels preserve at least2.6m exposure and6m gate.'});
addCover({id:'LOS_P12_ROCK_ABUTMENT',los_group:'P12',position_xz_m:[-222.2,-143],size_xyz_m:[2,4,24],kind:'rock_bluff',grounding:'terrain_conforming_wall',reason:'Escarpment abutment east of trail, terrain-conforming segmented graybox; gate and route clearance preserved.'});
for(const id of ['LOS_P12_PANEL','LOS_P12_ROCK','LOS_P12_YARD_RETURN']) replaceCover({id,grounding:'terrain_conforming_wall'});
assert.deepEqual(layout.boundaries.bunker_fence,source.boundaries.bunker_fence,'Bunker fence/gate changed');
assert.deepEqual(layout.corridors.find(c=>c.id==='P04'),rail,'Track polyline changed');
assert.equal(layout.corridors.find(c=>c.id==='P01').width_m,8,'County road narrowed');
assert.equal(bypass.width_m,2.5,'Rail bypass narrowed');
assert.deepEqual(layout.terrain.route_graph,source.terrain.route_graph,'Unrelated graph changed');
assert.equal(layout.dressing.cover.length,source.dressing.cover.length+2,'Unintended cover removal/addition');
const spatial=check(layout);
const dressingProposal=JSON.parse(fs.readFileSync(`${__dirname}/dressing-proposal.json`));
const dressingFenceErrors=[];
for(const fence of dressingProposal.fences) for(const [a,b] of fence.segments_xz_m) {
    const fenceShape=rectangle(a.map((v,k)=>(v+b[k])/2),[distance(a,b),fence.thickness_m],Math.atan2(a[1]-b[1],b[0]-a[0])*180/Math.PI);
    for(const row of [...changes.cover_replacements,...changes.additional_cover]) {
        const cover=layout.dressing.cover.find(c=>c.id===row.id),shape=rectangle(cover.position_xz_m,[cover.size_xyz_m[0],cover.size_xyz_m[2]],cover.yaw_deg);
        if(polygonDistance(shape,fenceShape)<.5-1e-7) dressingFenceErrors.push(`Cover/fence ${row.id}/${fence.id}`);
    }
    for(const row of [...changes.corridor_replacements,...changes.additional_corridors]) {
        const corridor=layout.corridors.find(c=>c.id===row.id);
        if(Math.min(...edges(corridor.points_xz_m).map(([p,q])=>segmentPolygon(p,q,fenceShape)))-corridor.width_m/2<.5-1e-7) dressingFenceErrors.push(`Route/fence ${row.id}/${fence.id}`);
    }
}
spatial.errors.push(...dressingFenceErrors);
spatial.status=spatial.errors.length?'FAIL':'PASS';
const {input}=inputFor(layout);
const groups=['COUNTY_E','P04','P12'];
const quick=process.argv.includes('--quick');
const result=analysis(input,{groups,angleStepDeg:quick?2:.5,boundAngleStepDeg:.1,certify:!quick});
for(const [id,g] of Object.entries(result.groups)) {g.limit_m=id==='P12'?120:200;g.status=g.measured_max_m>g.limit_m?'FAIL':g.conservative_upper_bound_m!==null&&g.conservative_upper_bound_m<=g.limit_m?'PASS':'UNRESOLVED';}
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(`${__dirname}/../${file}`)).digest('hex');
const report={status:spatial.status!=='PASS'?'SPATIAL_FAIL':Object.values(result.groups).every(g=>g.status==='PASS')?'2D_PROXY_PASS_NATIVE_PENDING':'HOLD',scope:'Independent COUNTY_E200m/P04rail200m/P12NW120m; full original groups and widths retained, canonical/read-only.',source_sha256:Object.fromEntries(['layout.json','terrain-contract.json','building-catalogue.json','phase3/check-phase3-los.cjs','phase3/dressing-proposal.json'].map(file=>[file,hash(file)])),changes,spatial,groups:result.groups,method:result.method,scope_of_certificate:result.scope,
route_lengths_m:{P01:{before:pathLength(source.corridors.find(c=>c.id==='P01').points_xz_m),after:pathLength(countyPoints)},P04_SERVICE_BYPASS:pathLength(bypass.points_xz_m)},
integration:[
'Apply P01 replacement to layout.corridors and terrain-contract.corrected_corridors; preserve8m width and full COUNTY_E group.',
'Add P04_SERVICE_BYPASS to both corridor collections; rail polyline and all route-graph edges remain byte-identical. No graph edge currently uses this rail segment.',
'Replace existing LOS_COUNTY_E_SCREEN and LOS_P04_FREIGHT by IDs; append exactly2 P12 pieces. Preserve all81 current base cover IDs.',
'County service bypass takes southern asphalt alignment around the existing opaque loading-yard boundary; retire superseded straight road visual and author real8m road geometry.',
'P04 assembly is two coupled wagons with continuous36x3.1m opaque body footprint; do not leave an unmodeled coupling gap behind this proxy. Author bypass as a physical2.5m service trail.',
'Every changed P12 cover uses terrain_conforming_wall: native authoring must subdivide into<=1m panels and retain reported local exposure; a single lowest-corner box invalidates2D proxy acceptance.',
'Regenerate terrain/circulation/dressing and rerun full canonical spatial and all-group LOS. Then inspect native collision, bake navigation, test actual service bypasses and original extraction routes.',
'Native standing/ADS/both lean/upstairs/high-ground rays remain mandatory. Trees and wire are not opaque blockers;6m bunker gate remains untouched.'
],native_verified:false};
if(!quick) {const file=`${__dirname}/los-industry-bunker-proposal.json`,content=JSON.stringify(report,null,2)+'\n';if(process.argv.includes('--check'))assert.equal(fs.readFileSync(file,'utf8'),content,'Stale industry/bunker proposal');else fs.writeFileSync(file,content);}
console.log(JSON.stringify({status:report.status,spatial_errors:spatial.errors,groups:result.groups},null,2));
