const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const geometry = require('./check-layout.cjs');
const load = name => JSON.parse(fs.readFileSync(path.join(__dirname,name),'utf8').replace(/^\uFEFF/,''));
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
// Re-seeding would move the reviewed cover reservations after Phase3 route edits.
assert(!fs.existsSync(path.join(__dirname, 'layout.json')) || !load('layout.json').provenance?.phase3_proposal_sha256,
  'Phase3 canonical layout exists; use phase3/merge-layout.cjs and the static authoring helpers. Do not re-seed Phase0.');
const source=load('reference/map_layout_godot.json');
const architecture=load('building-catalogue.json');
const terrain=load('terrain-contract.json');
const gameplay=load('gameplay-contract.json');
const corridors=structuredClone(terrain.corrected_corridors);
const bunkerFence=structuredClone(source.barriers.bunker_fence);
const gate=terrain.route_graph.nodes.B_GATE.xz_m;
const [nw,ne,se,sw]=bunkerFence.polygon_xz_m;
bunkerFence.gate={id:'B06_GATE',center_xz_m:gate,clear_width_m:6,surface_y_m:10};
bunkerFence.thickness_m=0.2;
bunkerFence.segments_xz_m=[[nw,ne],[ne,se],[se,[gate[0]+3,gate[1]]],[[gate[0]-3,gate[1]],sw],[sw,nw]];
const fenceShapes=bunkerFence.segments_xz_m.map(([a,b])=>geometry.rectangle(a.map((n,i)=>(n+b[i])/2),[geometry.distance(a,b),bunkerFence.thickness_m],Math.atan2(a[1]-b[1],b[0]-a[0])*180/Math.PI));
const structures=architecture.structures;
const shape = b => geometry.rectangle(b.position_xz_m,b.footprint_m,b.yaw_deg);
const wet=[terrain.hydrology.river.actual_water_polygon_xz_m,terrain.hydrology.lake.actual_water_polygon_xz_m];
const markers=[
  ...gameplay.insertion.markers.map(m=>({...m,kind:'spawn'})),
  ...gameplay.extraction.markers.map(m=>({...m,kind:'extract',countdown_seconds:5,always_active:true}))
];
// Graph-only walk routes need actual authored surfaces, not imaginary connections.
for (const edge of terrain.route_graph.edges) {
  if (['bridge','gangway'].includes(edge.kind)) continue;
  corridors.push({id:`GR_${edge.id}`,name:`${edge.from} to ${edge.to}`,type:'footpath',surface:'dirt',width_m:edge.clear_width_m,points_xz_m:edge.points_xz_m,surface_y_m:edge.surface_y_m,maximum_grade_percent:edge.maximum_grade_percent,source_graph_edge:edge.id,overlap_rule:'Union with higher-priority asphalt/gravel; no duplicate coplanar rendering'});
}
function projection(p,a,b) {
  const dx=b[0]-a[0],dz=b[1]-a[1],length2=dx*dx+dz*dz;
  const t=length2?Math.max(0,Math.min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dz)/length2)):0;
  return [a[0]+t*dx,a[1]+t*dz];
}
const county=corridors.find(c=>c.id==='P01');
function nearestCounty(p) {
  return geometry.edges(county.points_xz_m).map(([a,b])=>projection(p,a,b)).sort((a,b)=>geometry.distance(a,p)-geometry.distance(b,p))[0];
}
function surfaceHeight(corridor,point) {
  let profile=corridor.surface_y_m??terrain.road_surface_profiles_y_m[corridor.id];
  if (!profile) {
    const graphMatch=terrain.route_graph.edges.find(e=>e.points_xz_m.length===corridor.points_xz_m.length&&e.points_xz_m.every((p,i)=>geometry.distance(p,corridor.points_xz_m[i])<1e-5));
    profile=graphMatch?.surface_y_m;
  }
  if (!profile) return corridor.id==='P03'?1.5:corridor.id==='P09'?2.5:2;
  const segments=geometry.edges(corridor.points_xz_m).map(([a,b],index)=>({a,b,index,point:projection(point,a,b)})).sort((a,b)=>geometry.distance(a.point,point)-geometry.distance(b.point,point));
  const segment=segments[0],length=geometry.distance(segment.a,segment.b);
  const t=length?geometry.distance(segment.a,segment.point)/length:0;
  return profile[segment.index]+t*(profile[segment.index+1]-profile[segment.index]);
}
for (const [id,points] of [
  ['TOWN_ALLEY_N',[corridors.find(c=>c.id==='P05').points_xz_m[0],nearestCounty(corridors.find(c=>c.id==='P05').points_xz_m[0])]],
  ['TOWN_EAST_N',[corridors.find(c=>c.id==='P06').points_xz_m[0],nearestCounty(corridors.find(c=>c.id==='P06').points_xz_m[0])]],
  ['TOWN_ALLEY_S',[corridors.find(c=>c.id==='P05').points_xz_m.at(-1),corridors.find(c=>c.id==='P03').points_xz_m[0]]],
  ['TOWN_EAST_S',[corridors.find(c=>c.id==='P06').points_xz_m.at(-1),corridors.find(c=>c.id==='P03').points_xz_m[0]]]
]) {
  const start=corridors.find(c=>c.id===(id.startsWith('TOWN_ALLEY')?'P05':'P06'));
  const end=corridors.find(c=>c.id===(id.endsWith('_N')?'P01':'P03'));
  corridors.push({id,name:id,type:'footpath',surface:'dirt',width_m:2.5,points_xz_m:points,surface_y_m:[surfaceHeight(start,points[0]),surfaceHeight(end,points.at(-1))],maximum_grade_percent:15,reason:'Connect source alley endpoints to county road or south farm lane'});
}
const accessPaths=[];
function clearAccess(points, width) {
  return geometry.edges(points).every(([a,b])=>[...structures.map(shape),...wet,...fenceShapes].every(p=>geometry.segmentPolygon(a,b,p)-width/2>=0.5));
}
for (const building of structures.filter(b=>b.access?.ground)) {
  const start=building.door_apron.to_xz_m;
  const candidates=corridors.filter(c=>c.type!=='rail'&&!c.door_approach_for).flatMap(c=>geometry.edges(c.points_xz_m).map(([a,b])=>({corridor:c.id,point:projection(start,a,b)}))).sort((a,b)=>geometry.distance(start,a.point)-geometry.distance(start,b.point));
  let chosen=null;
  for (const candidate of candidates) {
    if (geometry.distance(start,candidate.point)<0.1) {chosen={...candidate,points:[start,candidate.point]};break;}
    const attempts=[[start,candidate.point],[start,[start[0],candidate.point[1]],candidate.point],[start,[candidate.point[0],start[1]],candidate.point]];
    const points=attempts.find(p=>clearAccess(p,1.8));
    if (points) {chosen={...candidate,points};break;}
  }
  assert(chosen,`No clear authored door connector ${building.id}`);
  const startY=building.pad_intent.surface_y_m,endY=surfaceHeight(corridors.find(c=>c.id===chosen.corridor),chosen.point),total=geometry.pathLength(chosen.points);
  let travelled=0;
  const profile=chosen.points.map((p,i)=>{if(i)travelled+=geometry.distance(chosen.points[i-1],p);return startY+(endY-startY)*(total?travelled/total:0);});
  const access={id:`ACCESS_${building.id}`,name:`${building.id} door access`,type:'footpath',surface:'gravel',width_m:1.8,points_xz_m:chosen.points,surface_y_m:profile,connects_to_corridor:chosen.corridor,door_approach_for:building.id,pad_surface_y_m:startY,maximum_grade_percent:15,reason:'Door exterior apron to nearest clear authored circulation, preserving existing walls'};
  corridors.push(access);accessPaths.push(access);
}
const reservedPaths=[
  ...corridors.filter(c=>c.type!=='rail').map(c=>({points:c.points_xz_m,half:c.width_m/2})),
  ...terrain.route_graph.edges.map(e=>({points:e.points_xz_m,half:e.clear_width_m/2})),
  ...gameplay.encounters.actors.map(a=>({points:[...a.patrol_points_xz_m,a.patrol_points_xz_m[0]],half:1})),
  ...structures.filter(b=>b.access?.ground&&b.door_apron?.from_xz_m).map(b=>({points:[b.door_apron.from_xz_m,b.door_apron.to_xz_m],half:b.door_apron.width_m/2}))
];
const markerPads=markers.map(m=>geometry.rectangle(m.position_xz_m,m.pad_size_xz_m));
const structureShapes=structures.map(shape);
const cover=[];
const corrections=[];
const templates={
  wrecked_cars:{size:[1.8,1.6,4.5],role:'solid_cover'},
  low_walls:{size:[3,1.4,0.35],role:'solid_cover'},
  pallets:{size:[1.2,1.1,1],role:'solid_cover'},
  sandbags:{size:[2,1.05,0.7],role:'solid_cover'},
  boulders:{size:[3,2.3,2.4],role:'solid_cover'},
  hay_bales:{size:[1.5,1.3,1.5],role:'solid_cover'},
  reeds_and_rocks:{size:[1.2,0.9,1.2],role:'concealment',solid:false}
};

function permitted(polygon, margin=0.5, previous=[]) {
  if (polygon.some(([x,z])=>Math.abs(x)>249||Math.abs(z)>249)) return false;
  const coverShapes=cover.map(p=>geometry.rectangle(p.position_xz_m,[p.size_xyz_m[0],p.size_xyz_m[2]],p.yaw_deg));
  if ([...wet,...structureShapes,...markerPads,...fenceShapes,...coverShapes,...previous].some(p=>geometry.polygonDistance(polygon,p)<margin)) return false;
  for (const route of reservedPaths) {
    if (geometry.edges(route.points).some(([a,b])=>geometry.segmentPolygon(a,b,polygon)-route.half<margin)) return false;
  }
  return true;
}
function nearby(center, size, yaw, margin, previous, radius=20) {
  for (let ring=0;ring<=radius;ring+=2) {
    const candidates=ring===0?[[0,0]]:Array.from({length:16},(_,i)=>[ring*Math.cos(i*Math.PI/8),ring*Math.sin(i*Math.PI/8)]);
    for (const offset of candidates) {
      const position=center.map((v,i)=>Number((v+offset[i]).toFixed(3)));
      if (permitted(geometry.rectangle(position,size,yaw),margin,previous)) return position;
    }
  }
  return null;
}
for (const cluster of source.cover_clusters) {
  const template=templates[cluster.kind];assert(template,`Unknown cover ${cluster.id}`);
  for (let index=0;index<cluster.count;index++) {
    const center=cluster.centers_xz_m[index%cluster.centers_xz_m.length];
    const row=Math.floor(index/cluster.centers_xz_m.length);
    const seed=[center[0]+(row%2?3:-3)*Math.ceil(row/2),center[1]+(row%3-1)*2];
    const yaw=cluster.kind==='wrecked_cars'?82:cluster.kind==='low_walls'?90:0;
    const position=nearby(seed,[template.size[0],template.size[2]],yaw,0.6,cover.map(p=>geometry.rectangle(p.position_xz_m,[p.size_xyz_m[0],p.size_xyz_m[2]],p.yaw_deg)));
    assert(position,`No reserved-safe cover position ${cluster.id}/${index}`);
    cover.push({id:`${cluster.id}-${String(index+1).padStart(2,'0')}`,source_ref:cluster.id,zone_id:cluster.zone_id,kind:cluster.kind,position_xz_m:position,size_xyz_m:template.size,yaw_deg:yaw,collider_role:template.role,solid:template.solid??true,opaque_proxy:template.size[1]>=2,model_status:'dimensioned graybox; finished asset/modeling budget pending'});
    corrections.push({id:cover.at(-1).id,original_cluster_center_xz_m:center,position_xz_m:position});
  }
}
const vegetation=[];
for (const tree of source.vegetation.instances) {
  const trunkDiameter=tree.kind==='pine'?0.5:0.45;
  const position=nearby(tree.position_xz_m,[trunkDiameter,trunkDiameter],0,2,vegetation.map(t=>geometry.rectangle(t.position_xz_m,[t.trunk_diameter_m,t.trunk_diameter_m])),30);
  assert(position,`No route-safe tree position ${tree.id}`);
  vegetation.push({...tree,source_ref:tree.id,position_xz_m:position,trunk_diameter_m:trunkDiameter,physics:'trunk only; separate static collider, no per-tree script',opaque_proxy:false,model_status:tree.kind==='broadleaf'?'TreeKit birch candidate; verify scale/export before native import':'species-specific finished asset pending'});
  if (geometry.distance(position,tree.position_xz_m)>0.01) corrections.push({id:tree.id,original_xz_m:tree.position_xz_m,position_xz_m:position});
}
const source_mapping=architecture.source_mapping;
assert(source_mapping.length===53,'Source mapping must cover53 entries');
const layout={
  title:'Town500m canonical Phase0 layout',schema_version:1,status:'OFFLINE CANDIDATE — check layout-check.json and native gates before scene implementation',
  provenance:{source_sha256:sha(fs.readFileSync(path.join(__dirname,'reference/map_layout_godot.json'))),contracts:['building-catalogue.json','terrain-contract.json','gameplay-contract.json'].map(name=>({path:name,sha256:sha(fs.readFileSync(path.join(__dirname,name)))})),baseline_commit:'4b8be66239d7929d1343dbe27c16e4807809e259'},
  coordinate_system:source.coordinate_system,
  zones:source.zones.map(z=>({id:z.id,name:z.name,polygon_xz_m:z.polygon_xz_m,role:z.id==='industry'?'Industrial loot and rail yard; E-B relocated southwest':z.id==='bunker'?'Exterior compound and one entry room; no underground transition':z.id==='river'?'River separator; only county and north footbridge traversable':z.role})),
  plots:architecture.plots,templates:architecture.templates,structures,source_mapping,
  terrain,corridors,access_paths:accessPaths,markers,gameplay,
  dressing:{cover,vegetation,placement_corrections:corrections,rule:'Deterministic offline reservation search around source cluster/tree anchors; never runtime generation',native_pending:['Art/collider shape and trunk/crown scale','Cover3D LOS and camera/lean visibility','Dense vegetation density/combat/performance pass']},
  boundaries:{whole_map_wall:false,bunker_fence:bunkerFence,natural:terrain.natural_boundary_contract},
  native_verified:false,
  pending:['MCP editor disconnected at Phase0 start; fresh baseline/capture pending','Graybox/nav/player traversal, glass/bullets and water death','Scoped2D LOS report must be reviewed independently of footprint PASS','Measured jump reach may require channel wider than20m','Terrain triangulation/interpolation and rounded-corner sweeps require authored geometry check']
};
fs.writeFileSync(path.join(__dirname,'layout.json'),JSON.stringify(layout,null,2)+'\n');
console.log(`Town500m layout prepared: ${structures.length} structures, ${cover.length} cover pieces, ${vegetation.length} trees; no runtime files touched`);
