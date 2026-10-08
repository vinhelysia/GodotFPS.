const fs=require('node:fs');
const d=JSON.parse(fs.readFileSync(`${__dirname}/town-layout.json`,'utf8'));
const out=[];
const p=([x,z])=>`${(x+100).toFixed(2)},${(z+100).toFixed(2)}`;
const line=(points,attrs)=>out.push(`<polyline points="${points.map(p).join(' ')}" fill="none" ${attrs}/>`);
const label=(x,z,s,extra='')=>out.push(`<text x="${x+100}" y="${z+100}" ${extra}>${s}</text>`);
const rect=(x,z,w,h,attrs)=>out.push(`<rect x="${x+100}" y="${z+100}" width="${w}" height="${h}" ${attrs}/>`);
const points=b=>{const [w,h]=b.footprint_m??d.types.find(t=>t.id===b.type).footprint_m,r=b.yaw_deg*Math.PI/180;return[[-w/2,-h/2],[w/2,-h/2],[w/2,h/2],[-w/2,h/2]].map(([x,z])=>[b.xz[0]+Math.cos(r)*x+Math.sin(r)*z,b.xz[1]-Math.sin(r)*x+Math.cos(r)*z]);};
out.push('<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1600" viewBox="0 0 200 200" role="img" aria-labelledby="title desc">');
out.push('<title id="title">Town concept B — revised 2D design, scene synchronization pending</title><desc id="desc">Design revision 2026-10-08, not runtime evidence. 200 by 200 metres, north up. 33 structures, 14 reusable types. Spawn southwest; extraction northeast and southeast. Dark asphalt main road, gravel village lanes, dotted pedestrian paths. Red shapes are explicit vehicle/barrier blockers; orange lines are new privacy screens. RF is a gravel dead end with a pedestrian exit. Buildings labelled by catalogue ID; dot marks front entrance; plus marks an accessible upper floor. Green areas remain planned planting zones, not placed trees.</desc>');
out.push('<style>text{font-family:Arial,sans-serif;font-size:3.25px;fill:#282b27;text-anchor:middle;dominant-baseline:middle} .zone{font-size:3.5px;letter-spacing:.12px;fill:#5e6658} .building{stroke:#474b43;stroke-width:.28} .id{font-weight:600;paint-order:stroke;stroke:#f8f5e9;stroke-width:.7;stroke-linejoin:round} .minor{font-size:2.8px}</style>');
rect(-100,-100,200,200,'fill="#e9e3d6"');
for(const n of [-50,0,50]) {line([[n,-100],[n,100]],'stroke="#cec8bc" stroke-width=".18"');line([[-100,n],[100,n]],'stroke="#cec8bc" stroke-width=".18"');}
for(const v of d.vegetation)for(const poly of v.polygons||[v.polygon])out.push(`<polygon points="${poly.map(p).join(' ')}" fill="${v.kind==='forest_edge'?'#6e826a':v.kind==='orchard'||v.kind==='gardens'?'#a6b28a':'#b9b790'}" opacity=".62"/>`);
line(d.terrain.ditch_west,'stroke="#8a9c9f" stroke-width="2"');line(d.terrain.ditch_east,'stroke="#8a9c9f" stroke-width="2"');
rect(24,32,64,48,'fill="#c7c4b7" opacity=".75"');
rect(d.farmyard.center_xz[0]-4,d.farmyard.center_xz[1]-4,8,8,'fill="#b3aa91" stroke="#7e7560" stroke-width=".25"');
for(const r of d.roads) {
  const path=[d.nodes[r.from],d.nodes[r.to]], color=r.surface==='asphalt'?'#666c69':r.surface==='gravel'?'#a7a08c':'#8d8068';
  if(r.sidewalk_m)line(path,`stroke="#ccc9bf" stroke-width="${r.width_m+r.sidewalk_m*2}" stroke-linecap="round"`);
  line(path,`stroke="${color}" stroke-width="${r.width_m}" stroke-linecap="round" ${r.hierarchy==='footpath'||r.hierarchy==='alley'?'stroke-dasharray="1.2 1.2"':''}`);
}
for(const r of d.roads.filter(r=>r.hierarchy==='main'))line([d.nodes[r.from],d.nodes[r.to]],'stroke="#e3decd" stroke-width=".28" stroke-dasharray="2 3"');
const gateHalf=id=>d.depot.gates.find(g=>g.node===id).width_m/2;
const [xmin,zmin,xmax,zmax]=d.depot.bounds;
const north=d.nodes.GN[0],west=d.nodes.GW[1],south=d.nodes.GS[0];
const fences=[[[xmin,zmin],[north-gateHalf('GN'),zmin]],[[north+gateHalf('GN'),zmin],[xmax,zmin]],[[xmax,zmin],[xmax,zmax]],[[xmax,zmax],[south+gateHalf('GS'),zmax]],[[south-gateHalf('GS'),zmax],[xmin,zmax]],[[xmin,zmax],[xmin,west+gateHalf('GW')]],[[xmin,west-gateHalf('GW')],[xmin,zmin]]];
for(const f of fences)line(f,'stroke="#626f6b" stroke-width=".5" stroke-dasharray="1.1 .8"');
for(const f of d.occluders)line(f.path,`stroke="${Number(f.id.slice(1))>=14?'#c16c32':'#8f765b'}" stroke-width=".6"`);
for(const o of d.obstacles) {
  out.push(`<polygon points="${points({...o,footprint_m:[o.size_m[0],o.size_m[2]]}).map(p).join(' ')}" fill="#994f45" stroke="#59372f" stroke-width=".3"/>`);
  label(o.xz[0]+(o.id.startsWith('V_Q')?-6:o.affected_road?6:0),o.xz[1]-3,o.id,'class="minor id"');
}
line([d.pump_access.door_apron.from_xz,d.pump_access.door_apron.to_xz],'stroke="#8d8068" stroke-width="1.8"');
label(d.nodes.RF[0],d.nodes.RF[1]+5,'RF · DEAD END','class="minor"');
rect(37,41,18,18,'fill="none" stroke="#f2efdf" stroke-width=".3" stroke-dasharray="1.5 1.5"');
label(46,50,'Y','class="minor"');
for(const b of d.buildings) {
  const t=d.types.find(t=>t.id===b.type),fill=['T01','T02','T03'].includes(t.id)?'#c8aa86':['T04','T05','T10','T12'].includes(t.id)?'#c5c3aa':['T06','T07','T08','T14'].includes(t.id)?'#829a9a':'#aaa89b';
  out.push(`<polygon points="${points(b).map(p).join(' ')}" fill="${fill}" class="building" ${b.access==='shell'?'opacity=".78"':''}/>`);
  const r=b.yaw_deg*Math.PI/180,[w,h]=t.footprint_m;
  const entry=[b.xz[0]-Math.sin(r)*h/2,b.xz[1]-Math.cos(r)*h/2];
  if(b.access!=='shell')out.push(`<circle cx="${entry[0]+100}" cy="${entry[1]+100}" r=".65" fill="#282b27"/>`);
  const small=['T10','T11','T12','T13'].includes(t.id);
  label(b.xz[0],b.xz[1]+(small?-3.8:0),b.id,'class="id"');
  if(b.access==='upper')label(b.xz[0],b.xz[1]+2.6,'+','class="minor"');
}
label(-11,-23,'J','class="id"');
label(43,29,'GN','class="minor"');label(20,44,'GW','class="minor"');label(79,81,'GS','class="minor"');
for(const [id,point]of [['S',d.nodes.S],['E1',d.nodes.E1],['E2',d.nodes.E2]]) {
  if(id==='S')out.push(`<circle cx="${point[0]+100}" cy="${point[1]+100}" r="2.2" fill="#835e82" stroke="#f9f5e9" stroke-width=".6"/>`);
  else rect(point[0]-3,point[1]-3,6,6,'fill="#c0d1a6" stroke="#526c45" stroke-width=".55"');
  label(point[0],point[1]-4.5,id,'class="id"');
}
label(-77,61,'ORCHARD','class="zone"');label(-20,-91,'NORTH LANE','class="zone"');label(52,42,'DEPOT','class="zone"');label(-1,7,'VILLAGE','class="zone"');
out.push('<path d="M 5,13 L 5,5 M 3.7,7 L 5,5 L 6.3,7" fill="none" stroke="#323831" stroke-width=".55"/>');
out.push('<text x="9" y="7" text-anchor="start">N</text><text x="135" y="3.5" class="minor">200 m · North = −Z</text>');
out.push('<rect x="14" y="0" width="77" height="7.8" fill="#f4f0e5" opacity=".93"/>');
out.push('<rect x="16" y="1" width="3" height="2" fill="#c8aa86"/><text x="21" y="2" class="minor" style="text-anchor:start">Homes</text><rect x="35" y="1" width="3" height="2" fill="#829a9a"/><text x="40" y="2" class="minor" style="text-anchor:start">Work / depot</text><rect x="64" y="1" width="3" height="2" fill="#a6b28a"/><text x="69" y="2" class="minor" style="text-anchor:start">Planting</text>');
out.push('<text x="16" y="6" class="minor" style="text-anchor:start">● entry   + upstairs   S spawn   E extraction</text>');
out.push('<path d="M 164,195 L 189,195 M 164,194 L 164,196 M 189,194 L 189,196" stroke="#323831" stroke-width=".5" fill="none"/><text x="176.5" y="192">25 m</text>');
out.push('<rect x="7" y="192" width="100" height="7" fill="#f4f0e5" opacity=".95"/><text x="9" y="194.5" style="font-size:2.2px;text-anchor:start">Red: vehicle / barrier · Orange: new privacy fence · RF: foot exit only</text><text x="9" y="197.5" style="font-size:2.2px;text-anchor:start">08 OCT 2026 · 2D DESIGN CHECKED · SCENE SYNC PENDING</text>');
out.push('</svg>');
fs.writeFileSync(`${__dirname}/town-layout.svg`,out.join('\n'));
console.log('Wrote SVG: 200×200 world units, 33 labelled structures.');
