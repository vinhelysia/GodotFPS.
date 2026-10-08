const fs = require('node:fs');
const assert = require('node:assert/strict');

// Road-group endpoints include sidewalks; the connecting sightline may cross open yards.
// Buildings are solid footprint proxies, not doorway/window/upper-floor geometry.
const EPS = 1e-8;
const cross = (a, b) => a[0] * b[1] - a[1] * b[0];
const subtract = (a, b) => [a[0] - b[0], a[1] - b[1]];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1];

function rectangle(id, center, width, depth, yaw = 0) {
  assert(center.length === 2 && center.every(Number.isFinite), `Invalid center: ${id}`);
  assert(width > 0 && depth > 0 && Number.isFinite(yaw), `Invalid rectangle: ${id}`);
  const r = yaw * Math.PI / 180;
  return { id, center, half: [width / 2, depth / 2], axes: [[Math.cos(r), -Math.sin(r)], [Math.sin(r), Math.cos(r)]] };
}

function vertices(rect) {
  return [[-1,-1], [1,-1], [1,1], [-1,1]].map(sign => rect.center.map((v, i) =>
    v + sign[0] * rect.half[0] * rect.axes[0][i] + sign[1] * rect.half[1] * rect.axes[1][i]));
}

function intersect(a, b, c, d) {
  const ab = subtract(b, a), cd = subtract(d, c), ac = subtract(c, a), denominator = cross(ab, cd);
  if (Math.abs(denominator) < EPS) return null;
  const t = cross(ac, cd) / denominator, u = cross(ac, ab) / denominator;
  return t >= 0 && t <= 1 && u >= 0 && u <= 1 ? [a[0] + t * ab[0], a[1] + t * ab[1]] : null;
}

// Interval ordering only changes at a polygon vertex or an edge intersection.
// Between consecutive offset events every clipping endpoint is affine in the offset.
function events(rectangles) {
  const polygons = rectangles.map(vertices), points = polygons.flat();
  for (let i = 0; i < polygons.length; i++) for (let j = i + 1; j < polygons.length; j++) {
    const a = polygons[i], b = polygons[j];
    if ([0,1].some(k => Math.max(...a.map(p=>p[k])) < Math.min(...b.map(p=>p[k])) || Math.max(...b.map(p=>p[k])) < Math.min(...a.map(p=>p[k])))) continue;
    for (let k = 0; k < 4; k++) for (let l = 0; l < 4; l++) {
      const p = intersect(a[k], a[(k+1)%4], b[l], b[(l+1)%4]);
      if (p) points.push(p);
    }
  }
  return points;
}

function projected(rect, direction, normal, origin) {
  const center = subtract(rect.center, origin);
  return { rect, t: dot(center, direction), s: dot(center, normal),
    d: rect.axes.map(a=>dot(a, direction)), n: rect.axes.map(a=>dot(a, normal)),
    radius: rect.half.reduce((sum,h,i)=>sum+h*Math.abs(dot(rect.axes[i],normal)),0) };
}

function interval(p, offset, strict, allowPoints = false) {
  if (Math.abs(offset - p.s) > p.radius + EPS) return null;
  let low = -Infinity, high = Infinity;
  for (let i = 0; i < 2; i++) {
    const base = (offset - p.s) * p.n[i], h = p.rect.half[i], d = p.d[i];
    if (Math.abs(d) < EPS) {
      if (strict ? Math.abs(base) >= h - EPS : Math.abs(base) > h + EPS) return null;
    } else {
      const a = (-h - base) / d + p.t, b = (h - base) / d + p.t;
      low = Math.max(low, Math.min(a,b)); high = Math.min(high, Math.max(a,b));
    }
  }
  if(allowPoints && high >= low - EPS) return [Math.min(low,high),Math.max(low,high)];
  return high - low > EPS ? [low, high] : null;
}

function sweep(roads, blockers, origin, angleStepDeg, upper = false) {
  const points = events([...roads, ...blockers]), roadVertices = roads.flatMap(vertices);
  const steps = Math.ceil(180 / angleStepDeg), step = Math.PI / steps;
  // Include rectangle diagonals/edges as exact directions, useful also for the empty-space check.
  const angles = Array.from({length:steps}, (_,i)=>i*step);
  for (let i=0;i<roadVertices.length;i++) for(let j=i+1;j<roadVertices.length;j++) {
    const delta=subtract(roadVertices[j],roadVertices[i]);
    if(Math.hypot(...delta)>EPS) angles.push((Math.atan2(delta[1],delta[0])+Math.PI)%Math.PI);
  }
  let best = { length_m: 0, endpoints_xz: null }, lines = 0;
  for (const angle of angles) {
    const direction=[Math.cos(angle),Math.sin(angle)], normal=[-direction[1],direction[0]];
    const roadIntervals=roads.map(r=>projected(r,direction,normal,origin));
    const blockerIntervals=blockers.map(r=>projected(r,direction,normal,origin));
    const offsets=points.map(p=>dot(subtract(p,origin),normal)).sort((a,b)=>a-b);
    const minOffset=Math.min(...roadIntervals.map(p=>p.s-p.radius)), maxOffset=Math.max(...roadIntervals.map(p=>p.s+p.radius));
    for(let i=0;i<offsets.length;i++) {
      if(i && offsets[i]-offsets[i-1]<EPS) continue;
      if(offsets[i]<minOffset-EPS || offsets[i]>maxOffset+EPS) continue;
      // At events, use both one-sided limits. Upper sweep also retains boundary tangencies.
      for(const shift of upper ? [0,-1e-7,1e-7] : [-1e-7,1e-7]) {
        const offset=offsets[i]+shift;
        const roadHits=roadIntervals.map(p=>interval(p,offset,false,upper)).filter(Boolean);
        if(!roadHits.length)continue;
        lines++;
        const low=Math.min(...roadHits.map(p=>p[0])), high=Math.max(...roadHits.map(p=>p[1]));
        if(high-low<=best.length_m)continue;
        const blocked=blockerIntervals.map(p=>interval(p,offset,true)).filter(p=>p && p[1]>low && p[0]<high).sort((a,b)=>a[0]-b[0]);
        let start=low;
        for(const block of [...blocked,[high,high]]) {
          if(block[0]>start) {
            const end=Math.min(high,block[0]);
            const allowed=roadHits.map(p=>[Math.max(start,p[0]),Math.min(end,p[1])]).filter(p=>p[1]>=p[0]);
            if(allowed.length) {
              let a=Math.min(...allowed.map(p=>p[0])), b=Math.max(...allowed.map(p=>p[1]));
              if(!upper){a+=1e-7;b-=1e-7;}
              if(b-a>best.length_m) best={length_m:b-a,endpoints_xz:[a,b].map(t=>origin.map((v,k)=>v+direction[k]*t+normal[k]*offset)),angle_deg:angle*180/Math.PI};
            }
          }
          start=Math.max(start,block[1]);
          if(start>=high)break;
        }
      }
    }
  }
  return {...best, evaluated_lines:lines, actual_angle_step_deg:step*180/Math.PI};
}

function analysis(data, options = {}) {
  const angleStepDeg=options.angleStepDeg ?? 0.25, certify=options.certify ?? true;
  assert(angleStepDeg>0 && angleStepDeg<=5,'angleStepDeg must be in (0,5]');
  const blockers=[];
  const blockerCounts={building_footprints:0,solid_fence_segments:0,vehicles_or_wrecks:0,barriers:0};
  for(const b of data.buildings ?? []) {
    if(b.opaque===false)continue;
    const type=data.types.find(t=>t.id===b.type); assert(type,`Unknown building type: ${b.type}`);
    blockers.push(rectangle(b.id,b.xz,...type.footprint_m,b.yaw_deg??0));
    blockerCounts.building_footprints++;
  }
  for(const fence of data.occluders ?? []) {
    if(!(fence.height_m>=2) || fence.opaque===false || /wire|mesh|chain/i.test(fence.kind??''))continue;
    assert(fence.path.length>=2,`Invalid fence: ${fence.id}`);
    for(let i=1;i<fence.path.length;i++) {
      const a=fence.path[i-1],b=fence.path[i],delta=subtract(b,a);
      blockers.push(rectangle(`${fence.id}:${i}`,a.map((v,k)=>(v+b[k])/2),Math.hypot(...delta),fence.thickness_m??0.14,-Math.atan2(delta[1],delta[0])*180/Math.PI));
      blockerCounts.solid_fence_segments++;
    }
  }
  for(const o of data.obstacles ?? []) {
    if(o.opaque!==true)continue;
    assert(['vehicle','barrier','wreck','solid_barrier'].includes(o.kind),`Unsupported opaque obstacle kind: ${o.id}/${o.kind}`);
    assert(Array.isArray(o.size_m) && o.size_m.length===3 && o.size_m.every(v=>Number.isFinite(v)&&v>0),`Invalid obstacle size_m: ${o.id}`);
    if(o.size_m[1]<2)continue;
    blockers.push(rectangle(o.id,o.xz,o.size_m[0],o.size_m[2],o.yaw_deg??0));
    blockerCounts[['vehicle','wreck'].includes(o.kind)?'vehicles_or_wrecks':'barriers']++;
  }
  const groups={};
  for(const road of data.roads) {
    if(road.disabled===true || road.enabled===false)continue;
    const a=data.nodes[road.from],b=data.nodes[road.to];assert(a&&b,`Unknown road node: ${road.id}`);
    const delta=subtract(b,a),group=road.los_group??road.id.replace(/[0-9].*$/,'');
    (groups[group]??=[]).push(rectangle(road.id,a.map((v,k)=>(v+b[k])/2),Math.hypot(...delta),road.width_m+2*(road.sidewalk_m??0),-Math.atan2(delta[1],delta[0])*180/Math.PI));
  }
  const results={};
  for(const [group,roads] of Object.entries(groups)) {
    if(options.groups && !options.groups.includes(group))continue;
    const points=roads.flatMap(vertices),origin=[0,1].map(k=>(Math.min(...points.map(p=>p[k]))+Math.max(...points.map(p=>p[k])))/2);
    const measured=sweep(roads,blockers,origin,angleStepDeg);
    if(measured.endpoints_xz) {
      const [a,b]=measured.endpoints_xz,delta=subtract(b,a),length=Math.hypot(...delta);
      const direction=delta.map(v=>v/length),normal=[-direction[1],direction[0]];
      for(const point of [a,b]) assert(roads.some(r=>r.axes.every((axis,i)=>Math.abs(dot(subtract(point,r.center),axis))<=r.half[i]+1e-6)),`Witness outside ${group} road envelope`);
      for(const blocker of blockers) {
        const hit=interval(projected(blocker,direction,normal,a),0,true);
        assert(!hit || hit[1]<=EPS || hit[0]>=length-EPS,`Witness intersects ${blocker.id}`);
      }
    }
    const limit=group==='M'?150:80;
    let bound=null,erosion=null,boundLines=0;
    if(certify) {
      const boundStep=options.boundAngleStepDeg??0.05;
      assert(boundStep>0 && boundStep<=5,'boundAngleStepDeg must be in (0,5]');
      const halfStep=Math.PI/Math.ceil(180/boundStep)/2;
      const radius=Math.max(...points.map(p=>Math.hypot(...subtract(p,origin))));
      erosion=radius*Math.sin(halfStep);
      const expanded=roads.map(r=>({...r,half:r.half.map(h=>h+erosion)}));
      const eroded=blockers.filter(r=>r.half.every(h=>h>erosion+EPS)).map(r=>({...r,half:r.half.map(h=>h-erosion)}));
      // Project any clear segment onto its nearest grid angle through its midpoint.
      // Endpoint displacement <= (segment length/2)*sin(delta) <= R*sin(delta).
      // Expanded roads contain those projections; eroded blockers cannot intersect them.
      const upper=sweep(expanded,eroded,origin,boundStep,true);
      bound=upper.length_m/Math.cos(halfStep)+1e-5;boundLines=upper.evaluated_lines;
    }
    results[group]={limit_m:limit,status:measured.length_m>limit+1e-6?'FAIL':bound!==null&&bound<=limit?'PASS':'UNRESOLVED',
      measured_max_m:measured.length_m,conservative_upper_bound_m:bound,witness_endpoints_xz:measured.endpoints_xz,
      witness_angle_deg:measured.angle_deg,roads:roads.map(r=>r.id),evaluated_lines:measured.evaluated_lines,bound_evaluated_lines:boundLines,bound_erosion_m:erosion};
  }
  const statuses=Object.values(results).map(r=>r.status);
  return {status:statuses.includes('FAIL')?'FAIL':statuses.includes('UNRESOLVED')?'UNRESOLVED':'PASS',
    scope:'2D same-group road-envelope endpoints (carriageway + sidewalks), arbitrary connecting angles through open space; straight design rectangles; no global off-road endpoints or 3D camera/nav proof',
    method:'Analytic line/rotated-rectangle intersections and all offset topology events per sampled angle. Lower value is a clear witnessed segment, not the exhaustive maximum. Upper uses road expansion/blocker erosion by R*sin(half angle step), then divides by cos(half angle step); this bounds every unsampled direction in the stated proxy model.',
    resolution:{measured_angle_step_deg:angleStepDeg,bound_angle_step_deg:certify?(options.boundAngleStepDeg??0.05):null,offsets:'all polygon vertices and edge-intersection events; one-sided 1e-7m nudges',numeric_tolerance_m:1e-5},
    blockers:{count:blockers.length,...blockerCounts,ids:blockers.map(b=>b.id),excludes:'trees, terrain, wire/mesh fences; obstacles without opaque:true; fences/vehicles/barriers <2m'},groups:results};
}

function selfCheck() {
  const data={types:[],buildings:[],nodes:{A:[0,0],B:[100,0]},roads:[{id:'R01',from:'A',to:'B',width_m:10}],occluders:[],obstacles:[]};
  const run=()=>analysis(data,{angleStepDeg:1,boundAngleStepDeg:0.5});
  let report=run();assert(Math.abs(report.groups.R.measured_max_m-Math.hypot(100,10))<1e-5);assert(report.groups.R.conservative_upper_bound_m>=Math.hypot(100,10));
  data.obstacles=[{id:'block',kind:'barrier',opaque:true,xz:[50,0],size_m:[2,3,40],yaw_deg:0}];
  report=run();assert(report.groups.R.measured_max_m<51 && report.groups.R.status==='PASS');
  data.obstacles[0].yaw_deg=30;report=run();assert(report.groups.R.measured_max_m<60);
  data.obstacles=[];data.occluders=[{id:'top',height_m:2,path:[[50,1],[50,10]]},{id:'bottom',height_m:2,path:[[50,-10],[50,-1]]}];
  report=run();assert(report.groups.R.measured_max_m>100,'Fence opening must remain visible');
  data.occluders[1].kind='wire';assert.equal(run().blockers.count,1);
  data.occluders=[];data.obstacles=[{id:'low',kind:'barrier',opaque:true,xz:[50,0],size_m:[2,1,40]}];
  assert.equal(run().blockers.count,0,'Low barrier must not count as standing cover');
  data.obstacles[0].size_m=[2,2];assert.throws(run,/Invalid obstacle size_m/);
  data.obstacles[0].size_m=[2,2,Infinity];assert.throws(run,/Invalid obstacle size_m/);
  console.log('check-los self-check: PASS (empty, blocked, rotated, fence opening, wire/low barrier exclusion, invalid size)');
}

module.exports={analysis};
if(require.main===module) {
  if(process.argv.includes('--self-check'))selfCheck();
  else {
    const data=JSON.parse(fs.readFileSync(process.argv.find((a,i)=>i>1&&!a.startsWith('--'))??`${__dirname}/town-layout.json`,'utf8'));
    console.log(JSON.stringify(analysis(data,{certify:!process.argv.includes('--sample-only')}),null,2));
  }
}
