const fs = require('node:fs');
const assert = require('node:assert/strict');
const data = JSON.parse(fs.readFileSync(`${__dirname}/town-layout.json`, 'utf8'));
const cross = (a,b,c) => (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);
const pointSegment = (p,a,b) => {
  const dx=b[0]-a[0],dz=b[1]-a[1];
  const t=Math.max(0,Math.min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dz)/(dx*dx+dz*dz)));
  return Math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dz);
};
const intersects = (a,b,c,d) => {
  const boxOverlap=[0,1].every(i=>Math.max(Math.min(a[i],b[i]),Math.min(c[i],d[i])) <= Math.min(Math.max(a[i],b[i]),Math.max(c[i],d[i]))+1e-8);
  return boxOverlap && cross(a,b,c)*cross(a,b,d)<=1e-8 && cross(c,d,a)*cross(c,d,b)<=1e-8;
};
const segmentDistance = (a,b,c,d) => intersects(a,b,c,d) ? 0 : Math.min(pointSegment(a,c,d),pointSegment(b,c,d),pointSegment(c,a,b),pointSegment(d,a,b));
const polygon = b => {
  const [w,h]=b.footprint_m??data.types.find(t=>t.id===b.type).footprint_m, r=(b.yaw_deg??0)*Math.PI/180;
  return [[-w/2,-h/2],[w/2,-h/2],[w/2,h/2],[-w/2,h/2]].map(([x,z])=>[b.xz[0]+Math.cos(r)*x+Math.sin(r)*z,b.xz[1]-Math.sin(r)*x+Math.cos(r)*z]);
};
const inside = (p,poly) => poly.every((a,i)=>cross(a,poly[(i+1)%poly.length],p)>=-1e-8);
const segmentPolygon = (a,b,poly) => inside(a,poly)||inside(b,poly) ? 0 : Math.min(...poly.map((p,i)=>segmentDistance(a,b,p,poly[(i+1)%poly.length])));
const polygonDistance = (a,b) => a.some(p=>inside(p,b))||b.some(p=>inside(p,a)) ? 0 : Math.min(...a.map((p,i)=>segmentPolygon(p,a[(i+1)%a.length],b)));
// The true arc stays within sagitta_m of these chords; subtract it from clearance.
function fillet(a,b,c,radius) {
  const unit=v=>{const length=Math.hypot(...v);assert(length>0,'Zero-length fillet leg');return v.map(x=>x/length);};
  const u=unit(a.map((x,i)=>x-b[i])),v=unit(c.map((x,i)=>x-b[i]));
  const angle=Math.acos(Math.max(-1,Math.min(1,u[0]*v[0]+u[1]*v[1])));
  assert(angle>1e-8 && angle<Math.PI-1e-8,'Fillet needs a real corner');
  const tangent=radius/Math.tan(angle/2),bisector=unit(u.map((x,i)=>x+v[i]));
  assert(tangent<Math.hypot(...a.map((x,i)=>x-b[i])) && tangent<Math.hypot(...c.map((x,i)=>x-b[i])),'Fillet does not fit its legs');
  const center=b.map((x,i)=>x+bisector[i]*radius/Math.sin(angle/2));
  const start=b.map((x,i)=>x+u[i]*tangent),end=b.map((x,i)=>x+v[i]*tangent);
  const from=Math.atan2(start[1]-center[1],start[0]-center[0]),to=Math.atan2(end[1]-center[1],end[0]-center[0]);
  const sweep=((to-from+3*Math.PI)%(2*Math.PI))-Math.PI,steps=256;
  return {radius_m:radius,start,end,center,sagitta_m:radius*(1-Math.cos(sweep/steps/2)),
    points:Array.from({length:steps+1},(_,i)=>[center[0]+radius*Math.cos(from+sweep*i/steps),center[1]+radius*Math.sin(from+sweep*i/steps)])};
}
const close=(a,b)=>a.length===b.length&&a.every((x,i)=>Math.abs(x-b[i])<1e-6);
const errors=[], warnings=[];
let minimumBuildingGap=Infinity, minimumFootpathGap=Infinity;
for(const [i,b] of data.buildings.entries()) {
  const p=polygon(b);
  if(p.some(([x,z])=>Math.abs(x)>98 || Math.abs(z)>98)) errors.push(`Bounds: ${b.id}`);
  for(const other of data.buildings.slice(i+1)) {
    const gap=polygonDistance(p,polygon(other)); minimumBuildingGap=Math.min(minimumBuildingGap,gap);
    if(gap<2) errors.push(`Building gap ${b.id}/${other.id}: ${gap.toFixed(2)}`);
  }
  for(const road of data.roads) {
    const gap=segmentPolygon(data.nodes[road.from],data.nodes[road.to],p)-road.width_m/2-road.sidewalk_m;
    const foot=road.hierarchy==='footpath'||road.hierarchy==='alley';
    // D04 ends at the pump's exterior entry marker; only its owning P apron is exempt.
    const doorApproach=road.id==='D04' && b.id==='P' && road.door_approach_for==='P';
    if(foot&&!doorApproach) minimumFootpathGap=Math.min(minimumFootpathGap,gap);
    if(!doorApproach && gap<(foot ? 0.6 : 1)-1e-8) errors.push(`Road clearance ${b.id}/${road.id}: ${gap.toFixed(2)}`);
  }
  for(const fence of data.occluders) {
    const gap=segmentPolygon(...fence.path,p)-(fence.thickness_m??0.14)/2;
    if(gap<0.7) errors.push(`Fence clearance ${b.id}/${fence.id}: ${gap.toFixed(2)}`);
  }
}
const tight=data.tight_passage;
assert(tight && tight.minimum_clearance_each_side_m>=2 && tight.corner_radius_m>=data.road_rules.minimum_footpath_radius_m,'Missing tight-passage contract');
const tightClearance=[];
for(const id of tight.roads) {
  const road=data.roads.find(r=>r.id===id);assert(road && road.hierarchy==='footpath' && road.width_m===tight.width_m,`Tight path width: ${id}`);
  for(const building of tight.buildings) {
    const gap=segmentPolygon(data.nodes[road.from],data.nodes[road.to],polygon(data.buildings.find(b=>b.id===building)))-road.width_m/2-road.sidewalk_m;
    tightClearance.push({road:id,building,clearance_m:gap});
    if(gap<tight.minimum_clearance_each_side_m-1e-8)errors.push(`Tight clearance ${building}/${id}: ${gap}`);
  }
}
const tightFillets=[];
for(let i=1;i<tight.roads.length;i++) {
  const previous=data.roads.find(r=>r.id===tight.roads[i-1]),next=data.roads.find(r=>r.id===tight.roads[i]);
  assert(previous.to===next.from,'Tight path must be an ordered chain');
  const arc=fillet(data.nodes[previous.from],data.nodes[previous.to],data.nodes[next.to],tight.corner_radius_m);
  const half=Math.max(previous.width_m/2+previous.sidewalk_m,next.width_m/2+next.sidewalk_m);
  const clearance=tight.buildings.map(id=>{
    const shape=polygon(data.buildings.find(b=>b.id===id));
    const gap=Math.min(...arc.points.slice(1).map((p,k)=>segmentPolygon(arc.points[k],p,shape)))-half-arc.sagitta_m;
    if(gap<tight.minimum_clearance_each_side_m-1e-8)errors.push(`Tight fillet ${id}/${previous.to}: ${gap}`);
    return {building:id,conservative_clearance_m:gap};
  });
  const [xmin,xmax,zmin,zmax]=data.bounds_xz;
  if(arc.points.some(([x,z])=>x-half-arc.sagitta_m<xmin||x+half+arc.sagitta_m>xmax||z-half-arc.sagitta_m<zmin||z+half+arc.sagitta_m>zmax))errors.push(`Fillet beyond bounds: ${previous.to}`);
  const {points,...geometry}=arc;tightFillets.push({node:previous.to,...geometry,clearance});
}
const circulationFillets=[];
let minimumFilletBuildingGap=Infinity,minimumFilletFenceGap=Infinity;
for(const chain of data.road_rules.chains) {
  const roads=chain.map(id=>{const road=data.roads.find(r=>r.id===id);assert(road,`Unknown chain road: ${id}`);return road;});
  let previousArc=null;
  for(let i=1;i<roads.length;i++) {
    const previous=roads[i-1],next=roads[i];assert(previous.to===next.from,`Unjoined road chain: ${previous.id}/${next.id}`);
    const a=data.nodes[previous.from],b=data.nodes[previous.to],c=data.nodes[next.to];
    const ab=a.map((x,k)=>x-b[k]),cb=c.map((x,k)=>x-b[k]);
    if(Math.abs(cross([0,0],ab,cb))<1e-8&&ab[0]*cb[0]+ab[1]*cb[1]<0){previousArc=null;continue;}
    const foot=[previous,next].some(r=>['footpath','alley'].includes(r.hierarchy));
    const service=[previous,next].some(r=>r.hierarchy==='service');
    const secondary=[previous,next].some(r=>r.hierarchy==='secondary');
    const radius=foot?data.road_rules.default_footpath_radius_m:service?data.road_rules.minimum_service_radius_m:secondary?data.road_rules.minimum_secondary_radius_m:data.road_rules.default_main_radius_m;
    assert(Number.isFinite(radius)&&radius>0,'Missing road radius');
    const arc=fillet(a,b,c,radius),half=Math.max(previous.width_m/2+previous.sidewalk_m,next.width_m/2+next.sidewalk_m);
    if(previousArc && Math.hypot(...previousArc.end.map((x,k)=>x-a[k]))+Math.hypot(...arc.start.map((x,k)=>x-b[k]))>Math.hypot(...a.map((x,k)=>x-b[k]))+1e-8)errors.push(`Overlapping fillets on ${previous.id}`);
    previousArc=arc;
    const buildingClearance=data.buildings.map(building=>{
      const shape=polygon(building);
      const gap=Math.min(...arc.points.slice(1).map((p,k)=>segmentPolygon(arc.points[k],p,shape)))-half-arc.sagitta_m;
      minimumFilletBuildingGap=Math.min(minimumFilletBuildingGap,gap);
      if(gap<(foot?0.6:1)-1e-8)errors.push(`Fillet building ${building.id}/${previous.to}: ${gap.toFixed(3)}`);
      return {building:building.id,conservative_clearance_m:gap};
    });
    const fenceClearance=data.occluders.filter(f=>f.opaque!==false&&!/wire|mesh|chain/i.test(f.kind??'')).map(fence=>{
      let gap=Infinity;
      for(let j=1;j<fence.path.length;j++)for(let k=1;k<arc.points.length;k++)gap=Math.min(gap,segmentDistance(arc.points[k-1],arc.points[k],fence.path[j-1],fence.path[j]));
      gap-=half+arc.sagitta_m+(fence.thickness_m??0.14)/2;
      minimumFilletFenceGap=Math.min(minimumFilletFenceGap,gap);
      if(gap<0.6-1e-8)errors.push(`Fillet fence ${fence.id}/${previous.to}: ${gap.toFixed(3)}`);
      return {fence:fence.id,conservative_clearance_m:gap};
    });
    const [xmin,xmax,zmin,zmax]=data.bounds_xz;
    if(arc.points.some(([x,z])=>x-half-arc.sagitta_m<xmin||x+half+arc.sagitta_m>xmax||z-half-arc.sagitta_m<zmin||z+half+arc.sagitta_m>zmax))errors.push(`Circulation fillet beyond bounds: ${previous.to}`);
    const {points,...geometry}=arc;
    circulationFillets.push({node:previous.to,roads:[previous.id,next.id],...geometry,minimum_building_clearance:buildingClearance.sort((a,b)=>a.conservative_clearance_m-b.conservative_clearance_m)[0],minimum_fence_clearance:fenceClearance.sort((a,b)=>a.conservative_clearance_m-b.conservative_clearance_m)[0]});
  }
}
const pump=data.buildings.find(b=>b.id==='P'),pumpAccess=data.pump_access;
assert(pump.yaw_deg===90 && pumpAccess.building==='P' && pumpAccess.front==='West','Pump must face the yard west');
const pumpType=data.types.find(t=>t.id===pump.type),threshold=[pump.xz[0]-pumpType.footprint_m[1]/2,pump.xz[1]];
assert(close(pumpAccess.door_threshold_xz,threshold),'Pump threshold does not match its front -Z wall');
assert(close(data.nodes.PA,[threshold[0]-1.2,threshold[1]]) && pumpAccess.entry_node==='PA' && pumpAccess.yard_node==='Y','Pump entry marker/yard mismatch');
assert(close(pumpAccess.door_apron.from_xz,data.nodes.PA)&&close(pumpAccess.door_apron.to_xz,threshold)&&pumpAccess.door_apron.depth_m===1.2&&pumpAccess.door_apron.width_m===1.8,'Pump apron mismatch');
for(const [id,from,to]of [['D03','Y','PJ'],['D04','PJ','PA']]) {
  const road=data.roads.find(r=>r.id===id);assert(road?.from===from&&road.to===to&&road.hierarchy==='footpath'&&road.width_m===1.8,`Missing pump connector ${id}`);
}
assert(data.roads.find(r=>r.id==='D04').door_approach_for==='P' && data.roads.filter(r=>r.door_approach_for).length===1,'Door exemption must belong only to D04/P');
const pumpWarehouseGap=polygonDistance(polygon(pump),polygon(data.buildings.find(b=>b.id==='W')));
assert(pumpAccess.minimum_W_gap_m>=3 && pumpWarehouseGap>=pumpAccess.minimum_W_gap_m-1e-8,'Pump/warehouse gap below 3m');
const farm=data.farmyard;assert(farm&&close(farm.size_m,[8,8])&&close(farm.center_xz,data.nodes.RF),'Farmyard must be 8x8 at RF');
const farmShape=polygon({xz:farm.center_xz,footprint_m:farm.size_m});
assert(farmShape.every(([x,z])=>x>=data.bounds_xz[0]&&x<=data.bounds_xz[1]&&z>=data.bounds_xz[2]&&z<=data.bounds_xz[3]),'Farmyard beyond bounds');
const farmClearance=Math.min(...data.buildings.map(b=>polygonDistance(farmShape,polygon(b))));assert(farmClearance>=2,'Farmyard building gap below 2m');
const r04=data.roads.find(r=>r.id==='R04'),r05=data.roads.find(r=>r.id==='R05');
assert(r04?.from==='R3'&&r04.to==='RF'&&r04.surface==='gravel'&&r04.hierarchy!=='footpath','R04 must end at farmyard');
assert(r05?.from==='RF'&&r05.to==='N3'&&r05.hierarchy==='footpath','R05 must retain the pedestrian northern route');
assert(data.roads.filter(r=>(r.from==='RF'||r.to==='RF')&&!['footpath','alley'].includes(r.hierarchy)).length===1,'RF must be a vehicle dead end');
const obstacleChecks=[];
for(const [i,obstacle]of (data.obstacles??[]).entries()) {
  assert(obstacle.size_m?.length===3&&obstacle.size_m.every(x=>Number.isFinite(x)&&x>0)&&obstacle.size_m[1]>=2,`Invalid obstacle dimensions/height: ${obstacle.id}`);
  assert(obstacle.xz?.length===2&&obstacle.xz.every(Number.isFinite)&&Number.isFinite(obstacle.yaw_deg??0),`Invalid obstacle transform: ${obstacle.id}`);
  const shape=polygon({...obstacle,footprint_m:[obstacle.size_m[0],obstacle.size_m[2]]});
  assert(shape.every(([x,z])=>x>=data.bounds_xz[0]&&x<=data.bounds_xz[1]&&z>=data.bounds_xz[2]&&z<=data.bounds_xz[3]),`Obstacle beyond bounds: ${obstacle.id}`);
  const buildingGap=Math.min(...data.buildings.map(b=>polygonDistance(shape,polygon(b))));
  if(buildingGap<=1e-8)errors.push(`Obstacle/building overlap: ${obstacle.id}`);
  for(const other of data.obstacles.slice(i+1))if(polygonDistance(shape,polygon({...other,footprint_m:[other.size_m[0],other.size_m[2]]}))<=1e-8)errors.push(`Obstacle overlap: ${obstacle.id}/${other.id}`);
  const check={id:obstacle.id,minimum_building_gap_m:buildingGap};
  if(obstacle.affected_road) {
    const road=data.roads.find(r=>r.id===obstacle.affected_road);assert(road,`Unknown affected road: ${obstacle.id}`);
    const a=data.nodes[road.from],b=data.nodes[road.to],length=Math.hypot(b[0]-a[0],b[1]-a[1]),normal=[-(b[1]-a[1])/length,(b[0]-a[0])/length];
    const offsets=shape.map(p=>(p[0]-a[0])*normal[0]+(p[1]-a[1])*normal[1]),half=road.width_m/2+road.sidewalk_m;
    const gaps=[Math.min(...offsets)+half,half-Math.max(...offsets)];
    Object.assign(check,{affected_road:road.id,envelope_side_gaps_m:gaps,maximum_walk_gap_m:Math.max(...gaps)});
    if(Math.max(...gaps)<obstacle.minimum_walk_gap_m-1e-8)errors.push(`Walk gap ${obstacle.id}: ${Math.max(...gaps)}`);
  }
  obstacleChecks.push(check);
}
for(const road of data.roads) {
  assert(data.nodes[road.from] && data.nodes[road.to]);
  const a=data.nodes[road.from],b=data.nodes[road.to];
  const half=road.width_m/2+road.sidewalk_m;
  if([a,b].some(p=>p.some(value=>Math.abs(value)+half>100)))errors.push(`Road envelope beyond bounds: ${road.id}`);
  for(const fence of data.occluders) {
    const gap=segmentDistance(a,b,...fence.path)-road.width_m/2-road.sidewalk_m-(fence.thickness_m??0.14)/2;
    if(gap<0.6) errors.push(`Fence / road ${fence.id}/${road.id}: ${gap.toFixed(2)}`);
  }
}
for(const b of data.buildings.filter(b=>['G','W','I05','P'].includes(b.id))) {
  const [xmin,zmin,xmax,zmax]=data.depot.bounds;
  assert(polygon(b).every(([x,z])=>x>xmin && x<xmax && z>zmin && z<zmax),`Outside depot: ${b.id}`);
  const [px,pz,qx,qz]=data.depot.turning_pad;
  assert(polygonDistance(polygon(b),[[px,pz],[qx,pz],[qx,qz],[px,qz]])>1.5,`Turning pad blocked: ${b.id}`);
}
assert.equal(data.types.length,14);
assert.equal(new Set(data.buildings.map(b=>b.id)).size,33);
const gateRequirements={};
for(const gate of data.depot.gates) {
  const crossing=data.roads.filter(r=>r.from===gate.node||r.to===gate.node);
  const tangentIndex=gate.node==='GW'?1:0;
  const normalIndex=1-tangentIndex;
  const required=Math.max(...crossing.map(r=>{
    const a=data.nodes[r.from],b=data.nodes[r.to];
    const length=Math.hypot(b[0]-a[0],b[1]-a[1]);
    return (r.width_m+2*r.sidewalk_m)*length/Math.abs(b[normalIndex]-a[normalIndex]);
  }));
  gateRequirements[gate.node]=+required.toFixed(2);
  assert(gate.width_m>=required,`Gate envelope too narrow: ${gate.node}`);
}
const adjacency=Object.fromEntries(Object.keys(data.nodes).map(n=>[n,[]]));
for(const e of data.roads) { const w=Math.hypot(...data.nodes[e.to].map((x,i)=>x-data.nodes[e.from][i])); adjacency[e.from].push([e.to,w]); adjacency[e.to].push([e.from,w]); }
function shortest(target, blocked=[]) {
  const distance=Object.fromEntries(Object.keys(data.nodes).map(n=>[n,Infinity])),previous={},visited=new Set(); distance.S=0;
  for(let k=0;k<Object.keys(data.nodes).length;k++) {
    const current=Object.keys(distance).filter(n=>!visited.has(n)).sort((a,b)=>distance[a]-distance[b])[0];
    if(!current||!Number.isFinite(distance[current])) break;
    visited.add(current);
    for(const [next,w] of adjacency[current]) if(!blocked.includes(next)&&distance[current]+w<distance[next]) { distance[next]=distance[current]+w;previous[next]=current; }
  }
  const path=[];let n=target;while(n){path.unshift(n);n=previous[n];}
  return {meters:Math.round(distance[target]),path};
}
const reachable=new Set(['S']),queue=['S'];while(queue.length){const n=queue.shift();for(const [next]of adjacency[n])if(!reachable.has(next)){reachable.add(next);queue.push(next);}}
assert.equal(reachable.size,Object.keys(data.nodes).length,'Disconnected road nodes');
const routes={E1:shortest('E1'),E1_northern:shortest('E1',['J','GW','Q1']),E2:shortest('E2'),E2_alternate:shortest('E2',['GW'])};
for(const route of Object.values(routes))assert(Number.isFinite(route.meters));
const los=require('./check-los.cjs').analysis(data);
if(los.status!=='PASS')errors.push(`LOS is not certified PASS: ${los.status}`);
const coverage=data.buildings.reduce((sum,b)=>{const[w,h]=data.types.find(t=>t.id===b.type).footprint_m;return sum+w*h;},0);
const report={status:errors.length?'FAIL':'PASS',scope:'2D footprint/envelope/gate/graph checks; conservative swept fillets for every authored road chain and certified proxy LOS; no 3D camera/nav/traversal',buildings:data.buildings.length,types:data.types.length,interiors:data.buildings.filter(b=>['ground','upper'].includes(b.access)).length,upper_interiors:data.buildings.filter(b=>b.access==='upper').length,roof_area_m2:+coverage.toFixed(2),roof_coverage_percent:+(coverage/400).toFixed(2),minimum_building_gap_m:+minimumBuildingGap.toFixed(2),minimum_footpath_gap_m:+minimumFootpathGap.toFixed(2),gate_minimum_envelope_width_m:gateRequirements,circulation_fillets:{count:circulationFillets.length,minimum_building_clearance_m:minimumFilletBuildingGap,minimum_solid_fence_centerline_clearance_m:minimumFilletFenceGap,method:'256 arc chords; clearance reduced by circular sagitta bound; maximum adjoining road/sidewalk half-width; fences are design centerlines',fillets:circulationFillets},tight_passage:{straight:tightClearance,fillets:tightFillets,method:'256 arc chords; clearance reduced by exact circular sagitta bound'},pump_access:{threshold_xz:threshold,warehouse_gap_m:pumpWarehouseGap,door_apron_exemption:'D04/P only; exterior entry endpoint cap is 0.3m from P footprint'},farmyard:{minimum_building_gap_m:farmClearance,vehicle_dead_end:true,pedestrian_exit:'R05'},obstacles:obstacleChecks,routes,los,errors,warnings};
report.design_version=data.version;
report.design_sha256=require('node:crypto').createHash('sha256').update(fs.readFileSync(`${__dirname}/town-layout.json`)).digest('hex');
report.circulation_fillets.minimum_solid_fence_clearance_m=minimumFilletFenceGap;
delete report.circulation_fillets.minimum_solid_fence_centerline_clearance_m;
report.circulation_fillets.method='256 arc chords minus circular sagitta bound; maximum adjoining road/sidewalk half-width; fence half-thickness included';
report.route_scope='Connected nominal pedestrian graph lengths. Vehicle obstacles have local projected bypass widths; actual detours/nav/player traversal require graybox 3D.';
report.native_scene_synchronized=false;
report.pending_3d_validation=data.pending_3d_validation;
fs.writeFileSync(`${__dirname}/layout-check.json`,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
assert.deepEqual(errors,[]);
