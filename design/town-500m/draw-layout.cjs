const fs=require('node:fs');
const path=require('node:path');
const data=JSON.parse(fs.readFileSync(path.join(__dirname,'layout.json'),'utf8'));
const colors={town:'#d9bfa0',industry:'#9daab2',bunker:'#859892',hills:'#9aaa84',forest:'#bdd1a5',farmland:'#ddd7ae',river:'#66a8c7',lake:'#82b5cd'};
const escape=text=>String(text).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/"/g,'&quot;');
const points=values=>values.map(p=>p.join(',')).join(' ');
const rectangle=require('./check-layout.cjs').rectangle;
function mapContent() {
  const svg=['<rect x="-250" y="-250" width="500" height="500" fill="#cbd8b8"><title>Unzoned dry land: open woodland and transition ground</title></rect>'];
  for(const zone of data.zones) svg.push(`<polygon points="${points(zone.polygon_xz_m)}" fill="${colors[zone.id]}" fill-opacity=".55" stroke="none"/>`);
  for(let line=-200;line<=200;line+=100)svg.push(`<path d="M${line},-250 V250 M-250,${line} H250" stroke="#345048" stroke-opacity=".12" stroke-width=".4"/>`);
  for(const plot of data.plots) {
    const center=plot.position_xz_m??plot.center_xz_m??plot.source_position_xz_m;
    const size=plot.footprint_m??plot.envelope_size_m??plot.source_footprint_m;
    if(!center||!size)continue;
    svg.push(`<polygon points="${points(rectangle(center,size,0))}" fill="none" stroke="#7d674d" stroke-opacity=".6" stroke-width=".5" stroke-dasharray="2,2"><title>${escape(plot.id)} plot envelope, not a building</title></polygon>`);
  }
  for(const water of [data.terrain.hydrology.river.actual_water_polygon_xz_m,data.terrain.hydrology.lake.actual_water_polygon_xz_m])svg.push(`<polygon points="${points(water)}" fill="#69a9c7" stroke="#477f98" stroke-width=".5"/>`);
  const priority=c=>c.type==='county_road'?2:c.type==='rail'?1:0;
  for(const corridor of [...data.corridors].sort((a,b)=>priority(a)-priority(b))) {
    const rail=corridor.type==='rail',county=corridor.type==='county_road';
    svg.push(`<polyline points="${points(corridor.points_xz_m)}" fill="none" stroke="${rail?'#8b8580':county?'#5b5e58':'#b0a489'}" stroke-width="${corridor.width_m}" stroke-linejoin="round"><title>${escape(corridor.id)} ${escape(corridor.name)}</title></polyline>`);
    if(rail)svg.push(`<polyline points="${points(corridor.points_xz_m)}" fill="none" stroke="#343b36" stroke-width=".9" stroke-dasharray="4,3"/>`);
  }
  for(const tree of data.dressing.vegetation)svg.push(`<circle cx="${tree.position_xz_m[0]}" cy="${tree.position_xz_m[1]}" r="${tree.crown_radius_m}" fill="${tree.kind==='pine'?'#6e9576':tree.kind==='orchard_tree'?'#a2a066':'#9a9c72'}" fill-opacity=".55"><title>${escape(tree.id)} ${escape(tree.kind)}</title></circle>`);
  for(const piece of data.dressing.cover)svg.push(`<polygon points="${points(rectangle(piece.position_xz_m,[piece.size_xyz_m[0],piece.size_xyz_m[2]],piece.yaw_deg))}" fill="#92815e" stroke="#4a5348" stroke-width=".25"><title>${escape(piece.id)} ${escape(piece.kind)} ${piece.size_xyz_m.join('x')}m</title></polygon>`);
  for(const building of data.structures) {
    const center=building.position_xz_m;
    svg.push(`<polygon points="${points(rectangle(center,building.footprint_m,building.yaw_deg))}" fill="${building.access?.upper?'#cad6db':building.access?.ground?'#edf0df':'#aeb7a4'}" stroke="#314941" stroke-width=".6"><title>${escape(building.id)} ${escape(building.kind)} ${building.footprint_m.join('x')}m; ground ${Boolean(building.access?.ground)}, upper ${Boolean(building.access?.upper)}</title></polygon>`);
    svg.push(`<text x="${center[0]}" y="${center[1]+1}" text-anchor="middle" font-size="3.1" font-weight="bold" fill="#17382f">${escape(building.id)}</text>`);
    if(building.door_threshold_xz_m) {
      const door=building.door_threshold_xz_m;
      svg.push(`<circle cx="${door[0]}" cy="${door[1]}" r=".65" fill="#166b57"/>`);
    }
  }
  const fence=data.boundaries.bunker_fence;
  for(const segment of fence?.segments_xz_m??[])svg.push(`<polyline points="${points(segment)}" fill="none" stroke="#485c4c" stroke-width=".6" stroke-dasharray="2,1.5"><title>Mesh fence; six metre south gate stays open</title></polyline>`);
  for(const bridge of data.terrain.bridges) {
    svg.push(`<polygon points="${points(rectangle(bridge.anchor_xz_m,[bridge.deck_length_m,bridge.deck_clear_width_m],bridge.yaw_deg))}" fill="#cec5ae" stroke="#395448" stroke-width=".5"/>`);
    svg.push(`<text x="${bridge.anchor_xz_m[0]}" y="${bridge.anchor_xz_m[1]-5}" font-size="4" font-weight="bold" fill="#224139">${bridge.id}</text>`);
  }
  const dock=data.terrain.dock;
  svg.push(`<polygon points="${points(rectangle(dock.deck_center_xz_m,dock.deck_size_m))}" fill="#a28a62" stroke="#395448" stroke-width=".5"><title>DOCK ${dock.deck_size_m.join('x')}m at Y${dock.deck_surface_y_m}m</title></polygon>`);
  svg.push(`<text x="${dock.deck_center_xz_m[0]}" y="${dock.deck_center_xz_m[1]+1}" text-anchor="middle" font-size="3.1" fill="#17382f">DOCK</text>`);
  svg.push(`<polyline points="${points([dock.gangway_from_xz_m,dock.gangway_to_xz_m])}" stroke="#957f58" stroke-width="${dock.gangway_clear_width_m}"/>`);
  for(const marker of data.markers) {
    const [x,z]=marker.position_xz_m;
    svg.push(`<polygon points="${points(rectangle(marker.position_xz_m,marker.pad_size_xz_m))}" fill="none" stroke="${marker.kind==='spawn'?'#7552a5':'#437f32'}" stroke-width=".5" stroke-dasharray="1,1"/>`);
    svg.push(marker.kind==='spawn'?`<circle cx="${x}" cy="${z}" r="3" fill="#8c77d7" stroke="#443d64" stroke-width=".6"/>`:`<polygon points="${points([[x,z-4],[x+4,z],[x,z+4],[x-4,z]])}" fill="#79a84b" stroke="#35602c" stroke-width=".6"/>`);
    svg.push(`<text x="${x+5}" y="${z-4}" font-size="5.2" font-weight="bold" fill="#17382f">${escape(marker.id)}</text>`);
  }
  svg.push('<rect x="-250" y="-250" width="500" height="500" fill="none" stroke="#314941" stroke-width=".7"/>');
  return svg.join('\n');
}
const content=mapContent();
function page(title,zone=null) {
  const poly=zone?.polygon_xz_m;
  let xmin=-250,zmin=-250,width=500,height=500;
  if(poly) { xmin=Math.max(-250,Math.min(...poly.map(p=>p[0]))-15);zmin=Math.max(-250,Math.min(...poly.map(p=>p[1]))-15);width=Math.min(250,Math.max(...poly.map(p=>p[0]))+15)-xmin;height=Math.min(250,Math.max(...poly.map(p=>p[1]))+15)-zmin; }
  const count=data.structures.filter(b=>!zone||b.zone_id===zone.id).length;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1400" height="1030" viewBox="0 0 700 515">
<rect width="700" height="515" fill="#f5f5eb"/>
<g font-family="Arial,sans-serif"><text x="22" y="24" fill="#203d33" font-size="15" font-weight="bold">${escape(title)}</text>
<text x="22" y="38" fill="#587266" font-size="6">Phase3 canonical geometry • North=-Z • 1unit=1m • see phase3 native verification receipt</text>
<svg x="22" y="48" width="450" height="450" viewBox="${xmin} ${zmin} ${width} ${height}" preserveAspectRatio="xMidYMid meet">${content}</svg>
<g transform="translate(496,65)"><text font-size="10" font-weight="bold" fill="#203d33">CANONICAL CONTRACT</text>
${[['Town plots','12 envelopes; real buildings'],['Structures',`${count} in this view scope`],['River','2 bridges; no ford or log'],['E-B','Southwest farm gate'],['Extracts','4 active; F +5seconds'],['Spawn','S1/S2 equal choice once'],['Interiors','Green ground / blue upper'],['Gray fill','Closed shell / solid prop'],['Small dots','Door thresholds'],['Dashed pads','Spawn/extraction reservations']].map(([a,b],i)=>`<text y="${21+i*21}" font-size="7" font-weight="bold" fill="#365548">${escape(a)}</text><text y="${29+i*21}" font-size="6" fill="#647c70">${escape(b)}</text>`).join('')}
<text y="265" font-size="7" font-weight="bold" fill="#365548">ZONES</text>
${data.zones.map((z,i)=>`<rect y="${275+i*16}" width="8" height="8" fill="${colors[z.id]}"/><text x="14" y="${282+i*16}" font-size="7" fill="#365548">${escape(z.name)}</text>`).join('')}
</g><text x="22" y="510" font-size="5.5" fill="#587266">Same layout.json drives this diagram and spatial report. Footprints do not certify3D door/stair/collision/visibility or route pacing.</text></g></svg>`;
}
fs.writeFileSync(path.join(__dirname,'master-map.svg'),page('TOWN500m — CANONICAL GRAYBOX'));
for(const zone of data.zones)fs.writeFileSync(path.join(__dirname,`zone-${zone.id}.svg`),page(`${zone.name.toUpperCase()} — GRAYBOX`,zone));
console.log('Drawn master map and8zone SVGs from canonical layout.json');
