const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {analysis}=require('../town-concept-b/check-los.cjs');
// ponytail: certify only below-limit groups; clear over-limit witnesses already prove a 2D failure.
const {edges,pathLength,distance}=require('./check-layout.cjs');
const bytes=fs.readFileSync(path.join(__dirname,'layout.json'));
const layout=JSON.parse(bytes);
const input={types:[],buildings:[],nodes:{},roads:[],occluders:[],obstacles:[]};
const limits={},quick={},measured={};
for(const structure of layout.structures) {
  input.types.push({id:structure.id,footprint_m:structure.footprint_m});
  input.buildings.push({id:structure.id,type:structure.id,xz:structure.position_xz_m,yaw_deg:structure.yaw_deg,opaque:structure.height_m>=2});
}
for(const cover of layout.dressing.cover.filter(c=>c.opaque_proxy&&c.solid))input.obstacles.push({id:cover.id,kind:'barrier',opaque:true,xz:cover.position_xz_m,size_m:cover.size_xyz_m,yaw_deg:cover.yaw_deg});
function addGroup(id, points, width, limit, reason) {
  limits[id]=limit;
  const lengthBound=pathLength(points)+width;
  if(lengthBound<=limit) {
    quick[id]={status:'PASS',limit_m:limit,conservative_upper_bound_m:lengthBound,method:'Any two road-envelope endpoints are at most path length plus width apart; blockers can only shorten visibility',reason};
    return;
  }
  edges(points).forEach(([a,b],i)=>{
    const from=`${id}_${i}a`,to=`${id}_${i}b`;input.nodes[from]=a;input.nodes[to]=b;
    input.roads.push({id:`${id}:${i}`,from,to,width_m:width,los_group:id});
  });
}
function xClip(points, minimum, maximum) {
  const result=[];
  for(const [a,b]of edges(points)) {
    const dx=b[0]-a[0];
    const low=Math.max(0,(minimum-a[0])/dx),high=Math.min(1,(maximum-a[0])/dx);
    if(low>high)continue;
    for(const t of [low,high]) {
      const point=a.map((v,k)=>v+t*(b[k]-v));
      if(!result.length||distance(result.at(-1),point)>1e-6)result.push(point);
    }
  }
  return result;
}
const county=layout.corridors.find(c=>c.id==='P01');
addGroup('M',xClip(county.points_xz_m,-160.23,39.77),county.width_m,150,'Deliberate Town main road');
addGroup('COUNTY_W',xClip(county.points_xz_m,-250,-160.23),county.width_m,200,'Deliberate open county approach outside Town');
addGroup('COUNTY_E',xClip(county.points_xz_m,39.77,250),county.width_m,200,'Deliberate county/industry vista outside Town');
for(const corridor of layout.corridors.filter(c=>c.id!=='P01'&&!c.id.startsWith('GR_'))) {
  const town=['P05','P06'].includes(corridor.id)||corridor.id.startsWith('ACCESS_T')||corridor.id.startsWith('TOWN_');
  addGroup(corridor.id,corridor.points_xz_m,corridor.width_m,corridor.type==='rail'?200:town?80:120,'Whole authored corridor; no artificial splitting of long straight streets');
}
for(const edge of layout.terrain.route_graph.edges.filter(e=>['G01','G02','G03','G04','G15','G19','G20'].includes(e.id)))addGroup(`ROUTE_${edge.id}`,edge.points_xz_m,edge.clear_width_m,['G04'].includes(edge.id)?200:120,'Additional whole pedestrian route outside source corridors');
const result=analysis(input,{angleStepDeg:0.5,certify:false});
const needsBounds=Object.keys(result.groups).filter(id=>result.groups[id].measured_max_m<=limits[id]);
if(needsBounds.length) {
  const certified=analysis(input,{angleStepDeg:0.5,boundAngleStepDeg:0.1,certify:true,groups:needsBounds});
  Object.assign(result.groups,certified.groups);
  result.resolution.bound_angle_step_deg=0.1;
  result.resolution.certified_groups=needsBounds;
}
for(const [id,group]of Object.entries(result.groups)) {
  const limit=limits[id];
  measured[id]={...group,limit_m:limit,status:group.measured_max_m>limit+1e-6?'FAIL':group.conservative_upper_bound_m!==null&&group.conservative_upper_bound_m<=limit?'PASS':'UNRESOLVED',reason:group.conservative_upper_bound_m!==null?'Witnessed lower bound plus conservative continuous-angle upper certificate in the stated 2D proxy model':'Witnessed lower bound; failing segment needs no upper certificate'};
}
const groups={...quick,...measured};
const statuses=Object.values(groups).map(g=>g.status);
const report={layout_sha256:crypto.createHash('sha256').update(bytes).digest('hex'),status:statuses.includes('FAIL')?'FAIL':statuses.includes('UNRESOLVED')?'UNRESOLVED':'PASS',native_verified:false,
  scope:result.scope,method:result.method,resolution:result.resolution,blockers:result.blockers,groups,
  pending:['Do not start spatial acceptance with FAIL corridors; add plausible property/terrain/vehicle occlusion and rerun','Opaque footprint proxies ignore actual windows/doors,terrain and vegetation; native standing/ADS/lean/upstairs rays mandatory']};
fs.writeFileSync(path.join(__dirname,'los-check.json'),JSON.stringify(report,null,2)+'\n');
const summary={status:report.status,groups:Object.fromEntries(Object.entries(groups).map(([id,g])=>[id,{status:g.status,limit_m:g.limit_m,measured_m:g.measured_max_m??null,upper_m:g.conservative_upper_bound_m??null}]))};
console.log(JSON.stringify(summary,null,2));
