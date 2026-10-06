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
  const [w,h]=data.types.find(t=>t.id===b.type).footprint_m, r=b.yaw_deg*Math.PI/180;
  return [[-w/2,-h/2],[w/2,-h/2],[w/2,h/2],[-w/2,h/2]].map(([x,z])=>[b.xz[0]+Math.cos(r)*x+Math.sin(r)*z,b.xz[1]-Math.sin(r)*x+Math.cos(r)*z]);
};
const inside = (p,poly) => poly.every((a,i)=>cross(a,poly[(i+1)%poly.length],p)>=-1e-8);
const segmentPolygon = (a,b,poly) => inside(a,poly)||inside(b,poly) ? 0 : Math.min(...poly.map((p,i)=>segmentDistance(a,b,p,poly[(i+1)%poly.length])));
const polygonDistance = (a,b) => a.some(p=>inside(p,b))||b.some(p=>inside(p,a)) ? 0 : Math.min(...a.map((p,i)=>segmentPolygon(p,a[(i+1)%a.length],b)));
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
    if(foot) minimumFootpathGap=Math.min(minimumFootpathGap,gap);
    if(gap<(foot ? 0.6 : 1)) errors.push(`Road clearance ${b.id}/${road.id}: ${gap.toFixed(2)}`);
  }
  for(const fence of data.occluders) {
    const gap=segmentPolygon(...fence.path,p);
    if(gap<0.7) errors.push(`Fence clearance ${b.id}/${fence.id}: ${gap.toFixed(2)}`);
  }
}
for(const road of data.roads) {
  assert(data.nodes[road.from] && data.nodes[road.to]);
  const a=data.nodes[road.from],b=data.nodes[road.to];
  const half=road.width_m/2+road.sidewalk_m;
  if([a,b].some(p=>p.some(value=>Math.abs(value)+half>100)))errors.push(`Road envelope beyond bounds: ${road.id}`);
  for(const fence of data.occluders) {
    const gap=segmentDistance(a,b,...fence.path)-road.width_m/2-road.sidewalk_m;
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
const coverage=data.buildings.reduce((sum,b)=>{const[w,h]=data.types.find(t=>t.id===b.type).footprint_m;return sum+w*h;},0);
const report={status:errors.length?'FAIL':'PASS',scope:'2D rectangles, straight road envelopes, gate widths and graph only; no 3D LOS/nav/traversal',buildings:data.buildings.length,types:data.types.length,interiors:data.buildings.filter(b=>['ground','upper'].includes(b.access)).length,upper_interiors:data.buildings.filter(b=>b.access==='upper').length,roof_area_m2:+coverage.toFixed(2),roof_coverage_percent:+(coverage/400).toFixed(2),minimum_building_gap_m:+minimumBuildingGap.toFixed(2),minimum_footpath_gap_m:+minimumFootpathGap.toFixed(2),gate_minimum_envelope_width_m:gateRequirements,routes,errors,warnings};
fs.writeFileSync(`${__dirname}/layout-check.json`,JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));
assert.deepEqual(errors,[]);
