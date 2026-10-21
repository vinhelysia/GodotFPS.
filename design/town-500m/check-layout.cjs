const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const EPS = 1e-7;
// ponytail: straight sweeps only; test rounded corners and actual 3D colliders at the graybox gate.
const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
const cross = (a, b, c) => (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);

function pointSegment(p, a, b) {
  const dx = b[0]-a[0], dz = b[1]-a[1], length2 = dx*dx+dz*dz;
  const t = length2 ? Math.max(0, Math.min(1, ((p[0]-a[0])*dx+(p[1]-a[1])*dz)/length2)) : 0;
  return Math.hypot(p[0]-a[0]-t*dx, p[1]-a[1]-t*dz);
}
function intersects(a, b, c, d) {
  const boxes = [0,1].every(k => Math.max(Math.min(a[k],b[k]),Math.min(c[k],d[k])) <= Math.min(Math.max(a[k],b[k]),Math.max(c[k],d[k]))+EPS);
  return boxes && cross(a,b,c)*cross(a,b,d)<=EPS && cross(c,d,a)*cross(c,d,b)<=EPS;
}
function segmentDistance(a, b, c, d) {
  return intersects(a,b,c,d) ? 0 : Math.min(pointSegment(a,c,d),pointSegment(b,c,d),pointSegment(c,a,b),pointSegment(d,a,b));
}
function inside(p, polygon) {
  let result = false;
  for (let i=0,j=polygon.length-1; i<polygon.length; j=i++) {
    const a=polygon[j],b=polygon[i];
    if (pointSegment(p,a,b)<EPS) return true;
    if ((a[1]>p[1])!==(b[1]>p[1]) && p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]) result=!result;
  }
  return result;
}
function segmentPolygon(a,b,polygon) {
  if (inside(a,polygon)||inside(b,polygon)) return 0;
  return Math.min(...polygon.map((p,i)=>segmentDistance(a,b,p,polygon[(i+1)%polygon.length])));
}
function polygonDistance(a,b) {
  if (a.some(p=>inside(p,b))||b.some(p=>inside(p,a))) return 0;
  return Math.min(...a.map((p,i)=>segmentPolygon(p,a[(i+1)%a.length],b)));
}
function rectangle(center, size, yaw=0) {
  const r=yaw*Math.PI/180;
  return [[-1,-1],[1,-1],[1,1],[-1,1]].map(([x,z])=>[
    center[0]+Math.cos(r)*x*size[0]/2+Math.sin(r)*z*size[1]/2,
    center[1]-Math.sin(r)*x*size[0]/2+Math.cos(r)*z*size[1]/2]);
}
const edges = points => points.slice(1).map((p,i)=>[points[i],p]);
const pathLength = points => edges(points).reduce((sum,[a,b])=>sum+distance(a,b),0);
function lineIntersections(center,axis,polygon) {
  const hits=[];
  for(const [a,b]of edges([...polygon,polygon[0]])) {
    const dx=b[0]-a[0],dz=b[1]-a[1],denominator=axis[0]*dz-axis[1]*dx;
    if(Math.abs(denominator)<EPS)continue;
    const px=a[0]-center[0],pz=a[1]-center[1];
    const t=(px*dz-pz*dx)/denominator,u=(px*axis[1]-pz*axis[0])/denominator;
    if(u>=-EPS&&u<=1+EPS)hits.push(t);
  }
  return hits.sort((a,b)=>a-b);
}
function shortest(graph, from, to, removed=[]) {
  const distances = {[from]:0}, previous={}, pending=new Set(Object.keys(graph.nodes));
  while (pending.size) {
    const current=[...pending].sort((a,b)=>(distances[a]??Infinity)-(distances[b]??Infinity))[0];
    if (!Number.isFinite(distances[current])) break;
    pending.delete(current);
    if (current===to) {
      const route=[]; let node=to;
      while (node!==from) { route.unshift(previous[node].edge.id); node=previous[node].node; }
      return {length_m:distances[to],edge_ids:route};
    }
    for (const edge of graph.edges) {
      if (removed.includes(edge.bridge_id)) continue;
      const next=edge.from===current?edge.to:edge.to===current?edge.from:null;
      if (!next||!pending.has(next)) continue;
      const length=distances[current]+pathLength(edge.points_xz_m);
      if (length<(distances[next]??Infinity)) {distances[next]=length;previous[next]={node:current,edge};}
    }
  }
  return null;
}
function finite(value, location='root') {
  if (typeof value==='number') assert(Number.isFinite(value),`Non-finite ${location}`);
  else if (Array.isArray(value)) value.forEach((item,i)=>finite(item,`${location}[${i}]`));
  else if (value&&typeof value==='object') Object.entries(value).forEach(([key,item])=>finite(item,`${location}.${key}`));
}

function check(data) {
  finite(data);
  const errors=[], warnings=[], add=(ok,message)=>{if(!ok)errors.push(message);};
  const within=polygon=>polygon.every(([x,z])=>x>=-250-EPS&&x<=250+EPS&&z>=-250-EPS&&z<=250+EPS);
  const structures=data.structures, terrain=data.terrain, graph=terrain.route_graph;
  const wet=[terrain.hydrology.river.actual_water_polygon_xz_m,terrain.hydrology.lake.actual_water_polygon_xz_m];
  const fence=data.boundaries.bunker_fence;
  const fenceShapes=fence.segments_xz_m.map(([a,b])=>rectangle(a.map((n,i)=>(n+b[i])/2),[distance(a,b),fence.thickness_m],Math.atan2(a[1]-b[1],b[0]-a[0])*180/Math.PI));
  const shapes=new Map(structures.map(b=>[b.id,rectangle(b.position_xz_m,b.footprint_m,b.yaw_deg)]));
  add(new Set(structures.map(b=>b.id)).size===structures.length,'Duplicate structure ID');
  add(data.plots.length===12,'Town must have 12 plots');
  const town=structures.filter(b=>b.zone_id==='town');
  add(town.length>=25&&town.length<=35,`Town structure count ${town.length}`);
  const upper=town.filter(b=>b.access?.upper).length, ground=town.filter(b=>b.access?.ground).length;
  add(upper>=3&&upper<=4,`Town upper interior count ${upper}`);
  add(ground/town.length>=0.4&&ground/town.length<=0.65,`Town ground access ${ground}/${town.length}`);
  let minimumBuildingGap=Infinity,minimumRoadGap=Infinity;
  const buildingChecks=[];
  for (const [i,b] of structures.entries()) {
    const shape=shapes.get(b.id);
    add(b.footprint_m.every(n=>n>0)&&b.height_m>0,`Invalid dimensions ${b.id}`);
    add(within(shape),`Structure outside bounds ${b.id}`);
    for(const wall of fenceShapes)add(polygonDistance(shape,wall)>=0.5-EPS,`Structure overlaps fence ${b.id}`);
    for (const other of structures.slice(i+1)) {
      const gap=polygonDistance(shape,shapes.get(other.id));
      minimumBuildingGap=Math.min(minimumBuildingGap,gap);
      add(gap>=0.05-EPS,`Structure overlap/touch ${b.id}/${other.id}: ${gap.toFixed(3)}m`);
    }
    if (b.collider_role!=='water_deck') for (const water of wet) add(polygonDistance(shape,water)>=0.5-EPS,`Structure water clearance ${b.id}`);
    if (b.scene_ref) add(fs.existsSync(path.join(__dirname,'../..',b.scene_ref.replace('res://',''))),`Missing reusable scene ${b.id}`);
    let nearestRoute=Infinity;
    for (const corridor of data.corridors.filter(c=>c.type!=='rail')) {
      const gap=Math.min(...edges(corridor.points_xz_m).map(([a,p])=>segmentPolygon(a,p,shape)))-corridor.width_m/2;
      nearestRoute=Math.min(nearestRoute,gap);minimumRoadGap=Math.min(minimumRoadGap,gap);
      add(gap>=0.5-EPS,`Structure route clearance ${b.id}/${corridor.id}: ${gap.toFixed(3)}m`);
    }
    for (const edge of graph.edges) {
      if (edge.kind==='gangway'&&b.collider_role==='water_deck') continue;
      const gap=Math.min(...edges(edge.points_xz_m).map(([a,p])=>segmentPolygon(a,p,shape)))-edge.clear_width_m/2;
      add(gap>=0.5-EPS,`Structure graph clearance ${b.id}/${edge.id}: ${gap.toFixed(3)}m`);
    }
    if (b.access?.ground) {
      add(Array.isArray(b.door_threshold_xz_m)&&b.door_threshold_xz_m.length===2,`Missing doorway ${b.id}`);
      const apron=b.door_apron;
      if (apron?.from_xz_m&&apron?.to_xz_m) {
        for (const other of structures.filter(s=>s.id!==b.id)) add(segmentPolygon(apron.from_xz_m,apron.to_xz_m,shapes.get(other.id))-apron.width_m/2>=0.5-EPS,`Door apron blocked ${b.id}/${other.id}`);
      }
    }
    buildingChecks.push({id:b.id,nearest_authored_corridor_clearance_m:nearestRoute});
  }
  const corridorChecks=[];
  for(const corridor of data.corridors) {
    const profile=corridor.surface_y_m;
    add(Array.isArray(profile)&&profile.length===corridor.points_xz_m.length,`Missing corridor height profile ${corridor.id}`);
    let maximumGrade=0;
    for(const [i,[a,b]]of edges(corridor.points_xz_m).entries()) {
      const length=distance(a,b),rise=Math.abs(profile?.[i+1]-profile?.[i]);
      const grade=length>EPS?rise/length*100:rise>EPS?Infinity:0;
      maximumGrade=Math.max(maximumGrade,grade);
      add(Number.isFinite(grade)&&grade<=corridor.maximum_grade_percent+EPS,`Corridor grade ${corridor.id}: ${grade.toFixed(3)}%`);
      for(const shape of fenceShapes)add(segmentPolygon(a,b,shape)-corridor.width_m/2>=0.5-EPS,`Route crosses fence ${corridor.id}`);
      const bridge=terrain.bridges.find(p=>p.id===corridor.bridge_id);
      const onDeck=bridge&&distance(a,bridge.deck_ports_xz_m.west)<1e-5&&distance(b,bridge.deck_ports_xz_m.east)<1e-5;
      if(!onDeck)for(const water of wet)add(segmentPolygon(a,b,water)-corridor.width_m/2>=0.5-EPS,`Dry corridor enters water ${corridor.id}`);
    }
    corridorChecks.push({id:corridor.id,length_m:pathLength(corridor.points_xz_m),maximum_grade_percent:maximumGrade});
  }
  const markerChecks=[];
  for (const marker of data.markers) {
    const pad=rectangle(marker.position_xz_m,marker.pad_size_xz_m);
    const gap=Math.min(...wet.map(p=>polygonDistance(pad,p)));
    add(within(pad),`Marker pad outside bounds ${marker.id}`);
    add(gap>=1-EPS,`Wet marker pad ${marker.id}: ${gap.toFixed(3)}m`);
    for (const [id,shape] of shapes) add(polygonDistance(pad,shape)>=1-EPS,`Marker pad blocked ${marker.id}/${id}`);
    const graphNode=graph.nodes[marker.id.replace('-','_')];
    add(Boolean(graphNode)&&distance(marker.position_xz_m,graphNode.xz_m)<1e-5,`Marker graph binding ${marker.id}`);
    markerChecks.push({id:marker.id,water_clearance_m:gap});
  }
  add(data.markers.filter(m=>m.kind==='spawn').length===2,'Exactly two spawns required');
  add(data.markers.filter(m=>m.kind==='extract').length===4,'Exactly four extracts required');
  add(terrain.bridges.length===2&&terrain.bridges.map(b=>b.id).sort().join(',')==='R01,R02','Exactly R01/R02 bridges required');
  const bridgeChecks=[];
  for (const bridge of terrain.bridges) {
    add(bridge.deck_length_m>=bridge.actual_water_gap_along_axis_m+6-EPS,`Bridge span ${bridge.id}`);
    add(bridge.deck_clear_width_m>=(bridge.id==='R01'?8:2.5),`Bridge width ${bridge.id}`);
    add(within(rectangle(bridge.anchor_xz_m,[bridge.deck_length_m,bridge.deck_clear_width_m],bridge.yaw_deg)),`Bridge outside bounds ${bridge.id}`);
    const west=bridge.deck_ports_xz_m.west,east=bridge.deck_ports_xz_m.east;
    const middle=west.map((n,i)=>(n+east[i])/2);
    const axis=bridge.axis_west_to_east_xz;
    add(distance(middle,bridge.anchor_xz_m)<1e-4&&Math.abs(distance(west,east)-bridge.deck_length_m)<1e-4,`Bridge anchor/ports binding ${bridge.id}`);
    const r=bridge.yaw_deg*Math.PI/180;
    add(Math.hypot(axis[0]-Math.cos(r),axis[1]+Math.sin(r))<1e-5,`Bridge yaw/axis ${bridge.id}`);
    add(inside(bridge.anchor_xz_m,wet[0]),`Bridge anchor outside river ${bridge.id}`);
    const hits=lineIntersections(bridge.anchor_xz_m,axis,wet[0]);
    const left=hits.filter(n=>n<=0).at(-1),right=hits.find(n=>n>=0);
    add(Number.isFinite(left)&&Number.isFinite(right)&&Math.abs(right-left-bridge.actual_water_gap_along_axis_m)<1e-3,`Bridge actual bank span ${bridge.id}`);
    add(-bridge.deck_length_m/2+bridge.landing_overlap_each_bank_m<=left+1e-3&&bridge.deck_length_m/2-bridge.landing_overlap_each_bank_m>=right-1e-3,`Bridge landings cover banks ${bridge.id}`);
    const graphEdge=graph.edges.find(e=>e.bridge_id===bridge.id);
    add(Boolean(graphEdge)&&distance(graphEdge.points_xz_m[0],west)<1e-5&&distance(graphEdge.points_xz_m.at(-1),east)<1e-5,`Bridge graph/deck binding ${bridge.id}`);
    bridgeChecks.push({id:bridge.id,water_gap_m:bridge.actual_water_gap_along_axis_m,deck_length_m:bridge.deck_length_m,clear_width_m:bridge.deck_clear_width_m});
  }
  const graphChecks=[], routes=[];
  for (const edge of graph.edges) {
    const from=graph.nodes[edge.from],to=graph.nodes[edge.to];
    add(Boolean(from&&to),`Unknown graph endpoint ${edge.id}`);if(!from||!to)continue;
    add(distance(from.xz_m,edge.points_xz_m[0])<1e-5&&distance(to.xz_m,edge.points_xz_m.at(-1))<1e-5,`Graph endpoint mismatch ${edge.id}`);
    add(edge.surface_y_m.length===edge.points_xz_m.length&&Math.abs(edge.surface_y_m[0]-from.surface_y_m)<1e-5&&Math.abs(edge.surface_y_m.at(-1)-to.surface_y_m)<1e-5,`Graph endpoint height mismatch ${edge.id}`);
    if (from.bank!==to.bank) add(edge.kind==='bridge'&&['R01','R02'].includes(edge.bridge_id),`Unexpected bank crossing ${edge.id}`);
    let maximumGrade=0;
    for (const [i,[a,b]] of edges(edge.points_xz_m).entries()) {
      const grade=Math.abs(edge.surface_y_m[i+1]-edge.surface_y_m[i])/distance(a,b)*100;
      maximumGrade=Math.max(maximumGrade,grade);
      add(grade<=edge.maximum_grade_percent+EPS,`Graph grade ${edge.id}: ${grade.toFixed(3)}%`);
      if (!['bridge','gangway'].includes(edge.kind)) for (const water of wet) add(segmentPolygon(a,b,water)-edge.clear_width_m/2>=0.5-EPS,`Dry graph enters water ${edge.id}`);
    }
    graphChecks.push({id:edge.id,length_m:pathLength(edge.points_xz_m),maximum_grade_percent:maximumGrade});
  }
  for (const spawn of ['S1','S2']) for (const extract of ['E_A','E_B','E_C','E_D']) {
    const route=shortest(graph,spawn,extract),withoutCounty=shortest(graph,spawn,extract,['R01']),withoutFoot=shortest(graph,spawn,extract,['R02']),withoutBoth=shortest(graph,spawn,extract,['R01','R02']);
    add(Boolean(route&&withoutCounty&&withoutFoot),`Disconnected route ${spawn}/${extract}`);
    add(graph.nodes[extract].bank==='east'?!withoutBoth:Boolean(withoutBoth),`Two-bank cut failure ${spawn}/${extract}`);
    routes.push({from:spawn,to:extract,route,without_R01:withoutCounty,without_R02:withoutFoot,without_both:withoutBoth});
  }
  const source=JSON.parse(fs.readFileSync(path.join(__dirname,'reference/map_layout_godot.json'),'utf8'));
  const sourceIds=new Set(source.structures.map(s=>s.id));
  const coverage=new Set(data.source_mapping.map(m=>m.source_id));
  add(coverage.size===53&&data.source_mapping.length===53,'Every source object needs one mapping');
  const actualIds=new Set([...structures.map(b=>b.id),...terrain.bridges.map(b=>b.id),'DOCK']);
  for(const mapping of data.source_mapping) {
    add(sourceIds.has(mapping.source_id),`Unknown source mapping ${mapping.source_id}`);
    for(const id of mapping.actual_ids)add(actualIds.has(id),`Missing mapping target ${mapping.source_id}/${id}`);
    add(['retain','resize','split','replace','defer','retire'].includes(mapping.action),`Unknown mapping action ${mapping.source_id}`);
  }
  const accessChecks=[];
  for(const access of data.access_paths) {
    const building=structures.find(b=>b.id===access.door_approach_for);
    add(Boolean(building?.access?.ground)&&distance(access.points_xz_m[0],building.door_apron.to_xz_m)<1e-5,`Access doorway binding ${access.id}`);
    let maximumGrade=0;
    for(const [i,[a,b]]of edges(access.points_xz_m).entries()) {
      const length=distance(a,b),rise=Math.abs(access.surface_y_m[i+1]-access.surface_y_m[i]);
      const grade=length>EPS?rise/length*100:rise>EPS?Infinity:0;
      maximumGrade=Math.max(maximumGrade,grade);
    }
    add(maximumGrade<=access.maximum_grade_percent+EPS,`Access slope ${access.id}: ${maximumGrade.toFixed(3)}%`);
    accessChecks.push({id:access.id,length_m:pathLength(access.points_xz_m),maximum_grade_percent:maximumGrade});
  }
  add(new Set(data.access_paths.map(p=>p.door_approach_for)).size===structures.filter(b=>b.access?.ground).length,'Every ground interior needs authored access');
  const dressing=data.dressing;
  const reserves=data.markers.map(m=>({id:m.id,shape:rectangle(m.position_xz_m,m.pad_size_xz_m)}));
  const patrols=data.gameplay.encounters.actors.map(a=>({id:a.node_path,points:[...a.patrol_points_xz_m,a.patrol_points_xz_m[0]]}));
  const checkReserve=(shape,id,margin)=> {
    for(const reserve of reserves)add(polygonDistance(shape,reserve.shape)>=margin-EPS,`Dressing blocks pad ${id}/${reserve.id}`);
    for(const patrol of patrols)add(Math.min(...edges(patrol.points).map(([a,b])=>segmentPolygon(a,b,shape)))-1>=margin-EPS,`Dressing blocks patrol ${id}/${patrol.id}`);
    for(const building of structures.filter(b=>b.access?.ground))add(segmentPolygon(building.door_apron.from_xz_m,building.door_apron.to_xz_m,shape)-building.door_apron.width_m/2>=margin-EPS,`Dressing blocks doorway ${id}/${building.id}`);
  };
  for (const [i,piece] of dressing.cover.entries()) {
    const shape=rectangle(piece.position_xz_m,[piece.size_xyz_m[0],piece.size_xyz_m[2]],piece.yaw_deg);
    for(const other of dressing.cover.slice(i+1))add(polygonDistance(shape,rectangle(other.position_xz_m,[other.size_xyz_m[0],other.size_xyz_m[2]],other.yaw_deg))>=0.5-EPS,`Cover overlap ${piece.id}/${other.id}`);
    add(within(shape),`Cover bounds ${piece.id}`);
    for (const [id,p] of shapes) add(polygonDistance(shape,p)>=0.5-EPS,`Cover overlaps structure ${piece.id}/${id}`);
    for (const corridor of data.corridors.filter(c=>c.type!=='rail')) add(Math.min(...edges(corridor.points_xz_m).map(([a,b])=>segmentPolygon(a,b,shape)))-corridor.width_m/2>=0.5-EPS,`Cover closes route ${piece.id}/${corridor.id}`);
    for(const wall of fenceShapes)add(polygonDistance(shape,wall)>=0.5-EPS,`Cover overlaps fence ${piece.id}`);
    for(const water of wet)add(polygonDistance(shape,water)>=0.5-EPS,`Cover in water ${piece.id}`);
    checkReserve(shape,piece.id,0.5);
  }
  for(const [i,tree] of dressing.vegetation.entries()) {
    const shape=rectangle(tree.position_xz_m,[tree.trunk_diameter_m,tree.trunk_diameter_m]);
    for(const other of dressing.vegetation.slice(i+1))add(polygonDistance(shape,rectangle(other.position_xz_m,[other.trunk_diameter_m,other.trunk_diameter_m]))>=2-EPS,`Trunk overlap ${tree.id}/${other.id}`);
    for(const piece of dressing.cover)add(polygonDistance(shape,rectangle(piece.position_xz_m,[piece.size_xyz_m[0],piece.size_xyz_m[2]],piece.yaw_deg))>=2-EPS,`Tree touches cover ${tree.id}/${piece.id}`);
    add(within(shape),`Tree bounds ${tree.id}`);
    for(const [id,p]of shapes)add(polygonDistance(shape,p)>=2-EPS,`Tree touches structure ${tree.id}/${id}`);
    for(const water of wet)add(polygonDistance(shape,water)>=2-EPS,`Tree in river reserve ${tree.id}`);
    for(const corridor of data.corridors.filter(c=>c.type!=='rail'))add(Math.min(...edges(corridor.points_xz_m).map(([a,b])=>segmentPolygon(a,b,shape)))-corridor.width_m/2>=2-EPS,`Tree blocks route ${tree.id}/${corridor.id}`);
    for(const wall of fenceShapes)add(polygonDistance(shape,wall)>=2-EPS,`Tree overlaps fence ${tree.id}`);
    checkReserve(shape,tree.id,2);
  }
  const dock=terrain.dock,dockShape=rectangle(dock.deck_center_xz_m,dock.deck_size_m),landing=rectangle(dock.gangway_from_xz_m,dock.shore_landing_size_m);
  add(within(dockShape)&&within(landing),'Dock/landing bounds');
  add(inside(dock.gangway_to_xz_m,dockShape),'Gangway misses dock');
  add(Math.abs(distance(dock.gangway_from_xz_m,dock.gangway_to_xz_m)-dock.gangway_length_m)<1e-5,'Gangway length binding');
  add(wet.every(p=>polygonDistance(landing,p)>=0.5-EPS),'Dock shore landing wet');
  const northVertices=wet[0].filter(p=>Math.abs(p[1]+250)<EPS);
  add(northVertices.length>=2&&Math.max(...northVertices.map(p=>p[0]))-Math.min(...northVertices.map(p=>p[0]))>=20-EPS,'River narrows at north boundary');
  warnings.push('Geometry covers straight swept polylines, solid footprint proxies and topology, not native terrain/collision, rounded corners, windows or full 3D visibility.');
  return {status:errors.length?'FAIL':'PASS',errors,warnings,scope:'Offline Phase0 spatial checks only',counts:{source_objects:coverage.size,town_plots:data.plots.length,town_structures:town.length,all_structures:structures.length,town_ground_interiors:ground,town_upper_interiors:upper,bridges:terrain.bridges.length,cover:dressing.cover.length,trees:dressing.vegetation.length},minimum_building_gap_m:minimumBuildingGap,minimum_structure_corridor_clearance_m:minimumRoadGap,building_checks:buildingChecks,corridor_checks:corridorChecks,marker_checks:markerChecks,bridge_checks:bridgeChecks,graph_checks:graphChecks,access_checks:accessChecks,routes,native_verified:false};
}
function selfCheck() {
  assert.equal(segmentPolygon([-5,0],[5,0],rectangle([0,0],[2,2])),0);
  assert.equal(polygonDistance(rectangle([0,0],[2,2]),rectangle([4,0],[2,2])),2);
  assert.equal(inside([0,0],rectangle([0,0],[2,2],45)),true);
  assert.equal(inside([4,0],rectangle([0,0],[2,2],45)),false);
  assert.equal(intersects([0,0],[1,0],[2,0],[3,0]),false);
  assert.equal(intersects([0,0],[2,0],[1,0],[3,0]),true);
  assert.throws(()=>finite({a:[Infinity]}),/Non-finite/);
  const graph={nodes:{A:{},B:{},C:{}},edges:[{id:'a',from:'A',to:'B',points_xz_m:[[0,0],[3,4]]},{id:'b',from:'B',to:'C',bridge_id:'R01',points_xz_m:[[3,4],[3,8]]}]};
  assert.equal(shortest(graph,'A','C').length_m,9);
  assert.equal(shortest(graph,'A','C',['R01']),null);
  const layout=JSON.parse(fs.readFileSync(path.join(__dirname,'layout.json'),'utf8'));
  assert.equal(check(layout).status,'PASS');
  const cases=[
    [d=>{d.terrain.bridges[0].anchor_xz_m=[0,-200];},/Bridge anchor/],
    [d=>{d.dressing.cover[0].position_xz_m=[200,210];},/Cover in water/],
    [d=>{d.dressing.vegetation[0].position_xz_m=d.markers[0].position_xz_m;},/Dressing blocks pad/],
    [d=>{d.source_mapping[0].source_id='FAKE';},/Unknown source mapping/],
    [d=>{d.source_mapping[0].actual_ids=['MISSING'];},/Missing mapping target/],
    [d=>{d.access_paths[0].surface_y_m[0]+=30;},/Access slope/],
    [d=>{delete d.corridors[0].surface_y_m;},/Missing corridor height profile/],
    [d=>{const [x,z]=d.boundaries.bunker_fence.gate.center_xz_m;d.boundaries.bunker_fence.segments_xz_m.push([[x-3,z],[x+3,z]]);},/Route crosses fence/]
  ];
  for(const [mutate,pattern]of cases) {
    const invalid=structuredClone(layout);mutate(invalid);
    assert(check(invalid).errors.some(e=>pattern.test(e)),`Negative case not rejected: ${pattern}`);
  }
  console.log('Town500m checker self-check PASS: geometry, graph cuts and eight negative data cases');
}
module.exports={check,rectangle,edges,inside,pointSegment,segmentPolygon,polygonDistance,distance,pathLength};
if (require.main===module) {
  if (process.argv.includes('--self-check')) selfCheck();
  else {
    const file=path.join(__dirname,'layout.json'),bytes=fs.readFileSync(file),data=JSON.parse(bytes);
    const report={layout_sha256:crypto.createHash('sha256').update(bytes).digest('hex'),...check(data)};
    fs.writeFileSync(path.join(__dirname,'layout-check.json'),JSON.stringify(report,null,2)+'\n');
    console.log(JSON.stringify({status:report.status,counts:report.counts,errors:report.errors},null,2));
    process.exitCode=report.status==='PASS'?0:1;
  }
}
