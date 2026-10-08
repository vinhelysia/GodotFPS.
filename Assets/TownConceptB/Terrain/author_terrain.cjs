// Offline authoring only: node Assets/TownConceptB/Terrain/author_terrain.cjs
// No runtime generator. JSON design remains the source of footprint/road truth.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../..');
const design = JSON.parse(fs.readFileSync(path.join(root, 'design/town-concept-b/town-layout.json')));
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const lerp = (a, b, t) => a + (b - a) * t;
const baseHeight = (x, z) => clamp(1.2 - (x + z) * 1.2 / 190, 0, 2.4);
const types = Object.fromEntries(design.types.map(t => [t.id, t]));
const depot = design.depot.bounds;
const insideDepot = (x,z) => x >= depot[0] && x <= depot[2] && z >= depot[1] && z <= depot[3];
const pads = design.buildings.map(b => ({...b, size: types[b.type].footprint_m,
    height: insideDepot(...b.xz) ? .5 : baseHeight(...b.xz)}));
function localXZ(p, pad) {
    const a = pad.yaw_deg * Math.PI / 180, c = Math.cos(a), s = Math.sin(a);
    const dx = p[0]-pad.xz[0], dz = p[1]-pad.xz[1];
    return [c*dx-s*dz, s*dx+c*dz];
}
function rectangle(cx, cz, width, depth, yaw = 0) {
    const a=yaw*Math.PI/180,c=Math.cos(a),s=Math.sin(a);
    return [[-width/2,-depth/2],[width/2,-depth/2],[width/2,depth/2],[-width/2,depth/2]]
        .map(([x,z])=>[cx+c*x+s*z,cz-s*x+c*z]);
}
const padPolygons = pads.map(p=>rectangle(...p.xz,p.size[0]+.8,p.size[1]+.8,p.yaw_deg));
function rectangleDistance(x,z,b) {
    return Math.hypot(Math.max(b[0]-x,0,x-b[2]),Math.max(b[1]-z,0,z-b[3]));
}
function distanceToSegment(p,a,b) {
    const dx=b[0]-a[0],dz=b[1]-a[1],t=clamp(((p[0]-a[0])*dx+(p[1]-a[1])*dz)/(dx*dx+dz*dz),0,1);
    return Math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dz);
}
function earthHeight(x,z) {
    if(insideDepot(x,z)) return .5;
    let h=lerp(.5,baseHeight(x,z),clamp(rectangleDistance(x,z,depot)/6,0,1));
    let best=Infinity, nearest=null;
    for(const p of pads) {
        const q=localXZ([x,z],p);
        const d=Math.hypot(Math.max(0,Math.abs(q[0])-p.size[0]/2-.4),Math.max(0,Math.abs(q[1])-p.size[1]/2-.4));
        if(d<best) {best=d;nearest=p;}
    }
    if(best<4) h=lerp(nearest.height,h,clamp(best/4,0,1));
    return h;
}
const roadChains = [
    ['M01','M02','M03','M04','M05'], ['S01','S02','S03','S04'],
    ['W01','W02','W03','W04','W05'], ['R01','R02','R03','R04'],
    ['Q01','Q02','Q03','Q04'], ['D01','D02'], ['P01','P02','P03'],
    ['F01','F02'], ['F03','F04'], ['E01','E02'], ['X01','X02','X03','X04','X05']
];
const edges = Object.fromEntries(design.roads.map(r=>[r.id,r]));
const subtract=(a,b)=>[a[0]-b[0],a[1]-b[1]];
const add=(a,b)=>[a[0]+b[0],a[1]+b[1]];
const scale=(a,s)=>[a[0]*s,a[1]*s];
const norm=a=>scale(a,1/Math.hypot(...a));
const dot=(a,b)=>a[0]*b[0]+a[1]*b[1];
const cross=(a,b)=>a[0]*b[1]-a[1]*b[0];
const roadPaths={};
const curves=[];
for(const ids of roadChains) {
    const first=edges[ids[0]], points=[design.nodes[first.from],...ids.map(id=>design.nodes[edges[id].to])];
    const corners=points.map((p,i)=>({start:p,end:p,arc:[]}));
    for(let i=1;i<points.length-1;i++) {
        const p=points[i],u=norm(subtract(p,points[i-1])),v=norm(subtract(points[i+1],p));
        const angle=Math.acos(clamp(dot(u,v),-1,1));
        if(angle<.015 || angle>Math.PI-.015) continue;
        let radius=first.hierarchy==='main'?18:first.hierarchy==='secondary'?12:first.hierarchy==='service'?8:2;
        const trim=radius*Math.tan(angle/2);
        assert(trim<=Math.min(Math.hypot(...subtract(p,points[i-1])),Math.hypot(...subtract(points[i+1],p)))*.48,
            `Curve radius cannot fit ${ids[i-1]}/${ids[i]}`);
        const start=add(p,scale(u,-trim)),end=add(p,scale(v,trim)),turn=Math.sign(cross(u,v));
        const center=add(start,scale([-u[1],u[0]],turn*radius));
        const a0=Math.atan2(start[1]-center[1],start[0]-center[0]);
        const count=Math.ceil(radius*angle/1.25),arc=[];
        for(let j=0;j<=count;j++) {const a=a0+turn*angle*j/count;arc.push([center[0]+radius*Math.cos(a),center[1]+radius*Math.sin(a)]);}
        corners[i]={start,end,arc};
        curves.push({node:Object.keys(design.nodes).find(k=>design.nodes[k]===p),radius_m:radius,edges:[ids[i-1],ids[i]],start,end,center});
    }
    for(let i=0;i<ids.length;i++) {
        const a=corners[i].end,b=corners[i+1].start;
        // Divide the corner arc between its incoming/outgoing edge, keeping all 38 IDs.
        const startArc=corners[i].arc,endArc=corners[i+1].arc;
        let line=[];
        if(startArc.length) line.push(...startArc.slice(Math.floor(startArc.length/2)));
        else line.push(a);
        const steps=Math.max(1,Math.ceil(Math.hypot(...subtract(b,a))/2));
        for(let j=1;j<=steps;j++) line.push([lerp(a[0],b[0],j/steps),lerp(a[1],b[1],j/steps)]);
        if(endArc.length) line.push(...endArc.slice(1,Math.floor(endArc.length/2)+1));
        roadPaths[ids[i]]=line;
    }
}
const ditchLines=[design.terrain.ditch_west,design.terrain.ditch_east];
function ditchDistance(x,z) {
    let d=Infinity;
    for(const line of ditchLines) for(let i=1;i<line.length;i++) d=Math.min(d,distanceToSegment([x,z],line[i-1],line[i]));
    return d;
}
function roadDistance(x,z) {
    let d=Infinity;
    for(const r of design.roads) {const line=roadPaths[r.id];for(let i=1;i<line.length;i++)
        {
            // Rectangular road end caps must remain filled, not acquire circular ditch cut-ins.
            let a=line[i-1],b=line[i];const tangent=norm(subtract(b,a)),extension=r.width_m/2+r.sidewalk_m;
            if(i===1) a=add(a,scale(tangent,-extension));
            if(i===line.length-1) b=add(b,scale(tangent,extension));
            d=Math.min(d,distanceToSegment([x,z],a,b)-extension-.05);
        }}
    return d;
}
function authoredHeight(x,z) {
    const depth=.6*clamp(1-ditchDistance(x,z),0,1)*clamp(roadDistance(x,z)/.8,0,1);
    return clamp(earthHeight(x,z)-depth,-.6,2.4);
}
// Split convex polygons along a line; matching cuts on adjacent terrain cells share vertices.
function splitPolygon(poly,a,b) {
    const pos=[],neg=[];
    for(let i=0;i<poly.length;i++) {
        const p=poly[i],q=poly[(i+1)%poly.length],dp=cross(subtract(b,a),subtract(p,a)),dq=cross(subtract(b,a),subtract(q,a));
        if(dp>=-1e-8) pos.push(p);
        if(dp<=1e-8) neg.push(p);
        if((dp>1e-8&&dq < -1e-8)||(dp < -1e-8&&dq>1e-8)) {
            const t=dp/(dp-dq),v=[lerp(p[0],q[0],t),lerp(p[1],q[1],t)];pos.push(v);neg.push(v);
        }
    }
    return [pos,neg];
}
function partitionRectangle(poly,rect) {
    let inside=poly,outside=[];
    for(let i=0;i<4 && inside.length>=3;i++) {
        const [keep,drop]=splitPolygon(inside,rect[i],rect[(i+1)%4]);
        if(drop.length>=3) outside.push(drop);inside=keep;
    }
    return {inside,outside};
}
function area(poly) {return Math.abs(poly.reduce((s,p,i)=>s+cross(p,poly[(i+1)%poly.length]),0))/2;}
function bounds(poly) {return [Math.min(...poly.map(p=>p[0])),Math.min(...poly.map(p=>p[1])),Math.max(...poly.map(p=>p[0])),Math.max(...poly.map(p=>p[1]))];}
const overlap=(a,b)=>a[0]<=b[2]&&a[2]>=b[0]&&a[1]<=b[3]&&a[3]>=b[1];
let terrainPolygons=[];
for(let x=-100;x<100;x+=8) for(let z=-100;z<100;z+=8) {
    const x1=Math.min(100,x+8),z1=Math.min(100,z+8);
    terrainPolygons.push([[x,z],[x1,z],[x1,z1]],[[x,z],[x1,z1],[x,z1]]);
}
// Put exact culvert/causeway edges into the terrain before carving the ditches.
// These remain earthen road crossings; the hollow pipe mesh is visual drainage below.
for(const culvert of design.terrain.culverts) {
    const road=edges[culvert.road],a=design.nodes[road.from],b=design.nodes[road.to],d=subtract(b,a);
    const yaw=-Math.atan2(d[1],d[0])*180/Math.PI;
    for(const width of [road.width_m+.1,road.width_m+1.7]) {
        const rect=rectangle(...culvert.xz,6,width,yaw),rb=bounds(rect),next=[];
        for(const poly of terrainPolygons) {
            if(!overlap(bounds(poly),rb)) {next.push(poly);continue;}
            const parts=partitionRectangle(poly,rect);next.push(...parts.outside);
            if(parts.inside.length>=3) next.push(parts.inside);
        }
        terrainPolygons=next.filter(p=>area(p)>1e-8);
    }
}
// Exact pad/depot edges rather than an approximately flat height grid.
const flatRects=[{poly:rectangle(56,56,64,48),height:.5},...pads.map((p,i)=>({poly:padPolygons[i],height:p.height}))];
let flatPolygons=[];
for(const flat of flatRects) {
    const next=[],fb=bounds(flat.poly);
    for(const poly of terrainPolygons) {
        if(!overlap(bounds(poly),fb)) {next.push(poly);continue;}
        const parts=partitionRectangle(poly,flat.poly);
        next.push(...parts.outside.filter(p=>area(p)>1e-8));
        if(parts.inside.length>=3&&area(parts.inside)>1e-8) flatPolygons.push({poly:parts.inside,height:flat.height});
    }
    terrainPolygons=next;
}
// Ditch bands introduce true valley/bank vertices in the sparse terrain surface.
for(const line of ditchLines) for(let i=1;i<line.length;i++) {
    const a=line[i-1],b=line[i],d=subtract(b,a),len=Math.hypot(...d),yaw=-Math.atan2(d[1],d[0])*180/Math.PI;
    for(const side of [-.5,.5]) {
        const u=norm(d),normal=[-u[1],u[0]],center=add(scale(add(a,b),.5),scale(normal,side));
        const rect=rectangle(...center,len,1,yaw),rb=bounds(rect),next=[];
        for(const poly of terrainPolygons) {
            if(!overlap(bounds(poly),rb)) {next.push(poly);continue;}
            const parts=partitionRectangle(poly,rect);next.push(...parts.outside);
            if(parts.inside.length>=3) next.push(parts.inside);
        }
        terrainPolygons=next.filter(p=>area(p)>1e-8);
    }
}
let triangles=[];
function triangulate(poly,height) {
    for(let i=1;i<poly.length-1;i++) if(area([poly[0],poly[i],poly[i+1]])>1e-8)
        triangles.push([poly[0],poly[i],poly[i+1]].map(([x,z])=>[x,height===undefined?authoredHeight(x,z):height,z]));
}
terrainPolygons.forEach(p=>triangulate(p));flatPolygons.forEach(p=>triangulate(p.poly,p.height));
function triangleHeight(x,z,t) {
    const [a,b,c]=t,den=(b[2]-c[2])*(a[0]-c[0])+(c[0]-b[0])*(a[2]-c[2]);
    const u=((b[2]-c[2])*(x-c[0])+(c[0]-b[0])*(z-c[2]))/den;
    const v=((c[2]-a[2])*(x-c[0])+(a[0]-c[0])*(z-c[2]))/den;
    if(u>=-1e-7&&v>=-1e-7&&u+v<=1+1e-7) return u*a[1]+v*b[1]+(1-u-v)*c[1];
    return null;
}
function heightAt(x,z) {
    for(const t of triangles) {const h=triangleHeight(x,z,t);if(h!==null)return h;}
    throw new Error(`Outside authored terrain: ${x}, ${z}`);
}
const num=v=>Number(v.toFixed(6)).toString();
function writeOBJ(name,faces) {
    let lines=['# Static Concept B graybox, metres, identity world transform.'];
    for(const t of faces) for(const v of t) lines.push('v '+v.map(num).join(' '));
    for(const t of faces) {
        const u=t[1].map((v,i)=>v-t[0][i]),v=t[2].map((v,i)=>v-t[0][i]);
        // OBJ faces are counter-clockwise as viewed from outside; Y-up terrain needs reversed XZ winding.
        const n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];
        const length=Math.hypot(...n),normal=n.map(q=>q/length);
        lines.push('vn '+normal.map(num).join(' '));
    }
    faces.forEach((t,i)=>lines.push(`f ${i*3+1}//${i+1} ${i*3+2}//${i+1} ${i*3+3}//${i+1}`));
    fs.writeFileSync(path.join(root,name),lines.join('\n')+'\n');
}
// Godot front-face winding is clockwise; OBJ importer converts it. Collider uses matching upward triangles.
function upward(faces) {return faces.map(t=>[t[0],t[2],t[1]]);}
function clipRoadToTerrain(poly,offset) {
    const output=[],pb=bounds(poly);
    for(const t of triangles) {
        const xz=t.map(v=>[v[0],v[2]]);if(!overlap(bounds(xz),pb)) continue;
        let cut=xz;
        for(let i=0;i<poly.length&&cut.length>=3;i++) cut=splitPolygon(cut,poly[i],poly[(i+1)%poly.length])[0];
        for(let i=1;i<cut.length-1;i++) if(area([cut[0],cut[i],cut[i+1]])>1e-8)
            output.push([cut[0],cut[i],cut[i+1]].map(([x,z])=>[x,triangleHeight(x,z,t)+offset,z]));
    }
    return output;
}
function roadStrip(line,start,end,offset) {
    let faces=[];
    const offsets=line.map((p,i)=>{
        const a=line[Math.max(0,i-1)],b=line[Math.min(line.length-1,i+1)],u=norm(subtract(b,a));return [-u[1],u[0]];
    });
    for(let i=1;i<line.length;i++) {
        const p=line[i-1],q=line[i],n=offsets[i-1],m=offsets[i];
        const poly=[add(p,scale(n,start)),add(q,scale(m,start)),add(q,scale(m,end)),add(p,scale(n,end))];
        if(cross(subtract(poly[1],poly[0]),subtract(poly[2],poly[0]))<0) poly.reverse();
        faces.push(...clipRoadToTerrain(poly,offset));
    }
    return faces;
}
const clearance=[];
function segmentRectangleDistance(a,b,p) {
    a=localXZ(a,p);b=localXZ(b,p);
    const w=p.size[0]/2,d=p.size[1]/2,rect=[[-w,-d],[w,-d],[w,d],[-w,d]];
    const pointDistance=q=>Math.hypot(Math.max(0,Math.abs(q[0])-w),Math.max(0,Math.abs(q[1])-d));
    let distance=Math.min(pointDistance(a),pointDistance(b));
    for(let i=0;i<4;i++) {
        const c=rect[i],e=rect[(i+1)%4],ab=subtract(b,a),ce=subtract(e,c),den=cross(ab,ce);
        if(Math.abs(den)>1e-9) {
            const u=cross(subtract(c,a),ce)/den,v=cross(subtract(c,a),ab)/den;
            if(u>=0&&u<=1&&v>=0&&v<=1) return 0;
        }
        distance=Math.min(distance,distanceToSegment(c,a,b));
    }
    return distance;
}
for(const road of design.roads) {
    const line=roadPaths[road.id],radius=road.width_m/2+road.sidewalk_m;
    let min=Infinity,nearest='';
    for(const p of pads) for(let i=1;i<line.length;i++) {
        // The arc is sampled at <=1.25m: reserve a conservative .02m sagitta envelope.
        const d=segmentRectangleDistance(line[i-1],line[i],p)-radius-.02;
        if(d<min){min=d;nearest=p.id;}
    }
    clearance.push({road:road.id,minimum_sample_clearance_m:min,building:nearest});
}
function build() {
    assert.equal(pads.length,33);assert.equal(Object.keys(roadPaths).length,38);
    const failures=clearance.filter(c=>c.minimum_sample_clearance_m<-.02);
    assert.equal(failures.length,0,JSON.stringify(failures));
    assert(curves.filter(c=>edges[c.edges[0]].hierarchy==='secondary').every(c=>c.radius_m>=12));
    for(const pad of pads) {
        const poly=rectangle(...pad.xz,...pad.size,pad.yaw_deg);
        for(const p of [pad.xz,...poly]) assert(Math.abs(heightAt(...p)-pad.height)<1e-6,`Pad is not flat: ${pad.id}`);
    }
    const totalArea=triangles.reduce((sum,t)=>sum+area(t.map(v=>[v[0],v[2]])),0);
    assert(Math.abs(totalArea-40000)<1e-4,`Terrain area mismatch: ${totalArea}`);
    const vertexHeights=new Map();
    for(const triangle of triangles) for(const [x,y,z] of triangle) {
        assert(y>=-.600001&&y<=2.400001,'Terrain outside height range');
        const key=x.toFixed(5)+','+z.toFixed(5);
        if(vertexHeights.has(key)) assert(Math.abs(vertexHeights.get(key)-y)<1e-6,`Height seam: ${key}`);
        vertexHeights.set(key,y);
    }
    const dir=path.join(root,'Assets/TownConceptB/Roads');fs.mkdirSync(dir,{recursive:true});
    let resources=[],nodes=[],maximumRoadSlope=0;
    function checkRoadGrade(faces) {
        for(const t of faces) {
            const u=t[1].map((v,i)=>v-t[0][i]),v=t[2].map((v,i)=>v-t[0][i]);
            const n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];
            const slope=Math.atan2(Math.hypot(n[0],n[2]),Math.abs(n[1]))*180/Math.PI;
            maximumRoadSlope=Math.max(maximumRoadSlope,slope);
            assert(slope<15,`Road slope ${slope} exceeds graybox grade ceiling`);
        }
    }
    function addMesh(name,resourcePath,faces,material,collision=true) {
        writeOBJ(resourcePath,upward(faces));
        resources.push(`[ext_resource type="ArrayMesh" path="res://${resourcePath}" id="mesh_${name}"]`);
        nodes.push(`[node name="${name}" type="MeshInstance3D" parent="."]\nmesh = ExtResource("mesh_${name}")\nmaterial_override = SubResource("${material}")`);
        if(collision) {
            resources.push(`[sub_resource type="ConcavePolygonShape3D" id="collision_${name}"]\ndata = PackedVector3Array(${faces.flat(2).map(num).join(', ')})\nbackface_collision = true`);
            nodes.push(`[node name="StaticBody3D" type="StaticBody3D" parent="${name}"]\ncollision_layer = 1\ncollision_mask = 0`);
            nodes.push(`[node name="CollisionShape3D" type="CollisionShape3D" parent="${name}/StaticBody3D"]\nshape = SubResource("collision_${name}")`);
        }
    }
    addMesh('Terrain','Assets/TownConceptB/Terrain/terrain.obj',triangles,'earth');
    for(const r of design.roads) {
        const line=roadPaths[r.id],half=r.width_m/2;
        const roadFaces=roadStrip(line,-half,half,.025);checkRoadGrade(roadFaces);
        addMesh(`Road_${r.id}`,`Assets/TownConceptB/Roads/${r.id}.obj`,roadFaces,r.surface);
        if(r.sidewalk_m>0) {
            const faces=[...roadStrip(line,-half-r.sidewalk_m,-half,.035),...roadStrip(line,half,half+r.sidewalk_m,.035)];
            checkRoadGrade(faces);
            addMesh(`Sidewalk_${r.id}`,`Assets/TownConceptB/Roads/${r.id}_sidewalk.obj`,faces,'concrete');
        }
    }
    for(let i=0;i<design.terrain.culverts.length;i++) {
        const culvert=design.terrain.culverts[i],road=edges[culvert.road];
        let closest=null,distance=Infinity;
        for(const line of ditchLines) for(let j=1;j<line.length;j++) {
            const d=distanceToSegment(culvert.xz,line[j-1],line[j]);
            if(d<distance){distance=d;closest=norm(subtract(line[j],line[j-1]));}
        }
        const axis=closest,side=[-axis[1],axis[0]],roadAxis=norm(subtract(design.nodes[road.to],design.nodes[road.from]));
        const length=(road.width_m+1.6)/Math.max(.3,Math.abs(cross(axis,roadAxis)));
        const y=earthHeight(...culvert.xz)-.35,faces=[],rings=[];
        for(const end of [-length/2,length/2]) for(const radius of [.34,.3]) {
            const ring=[];
            for(let j=0;j<12;j++) {const a=j*Math.PI/6;
                ring.push([culvert.xz[0]+axis[0]*end+side[0]*radius*Math.cos(a),y+radius*Math.sin(a),culvert.xz[1]+axis[1]*end+side[1]*radius*Math.cos(a)]);}
            rings.push(ring);
        }
        for(let j=0;j<12;j++) {const k=(j+1)%12;
            for(const [a,b] of [[0,2],[3,1],[1,0],[2,3]]) faces.push([rings[a][j],rings[b][j],rings[b][k]],[rings[a][j],rings[b][k],rings[a][k]]);
        }
        addMesh(`Culvert_${culvert.road}`,`Assets/TownConceptB/Terrain/culvert_${culvert.road}.obj`,faces,'concrete',false);
    }
    const materials={earth:[.28,.28,.25],asphalt:[.13,.14,.15],gravel:[.34,.33,.30],dirt:[.31,.27,.22],concrete:[.48,.48,.45]};
    const mats=Object.entries(materials).map(([id,c])=>`[sub_resource type="StandardMaterial3D" id="${id}"]\nalbedo_color = Color(${c.join(', ')}, 1)\nroughness = 1\ncull_mode = 2`);
    const ext=resources.filter(r=>r.startsWith('[ext')),sub=resources.filter(r=>r.startsWith('[sub'));
    const scene=`[gd_scene load_steps=${ext.length+sub.length+mats.length+1} format=3]\n\n${ext.join('\n\n')}\n\n${mats.join('\n\n')}\n\n${sub.join('\n\n')}\n\n[node name="TerrainRoads" type="Node3D"]\nmetadata/authoring_only = "Assets/TownConceptB/Terrain/author_terrain.cjs"\nmetadata/coordinate_contract = "identity X east Z south; building pad+.2 foundation"\n\n${nodes.join('\n\n')}\n`;
    fs.writeFileSync(path.join(root,'Scene/World/TownConceptB/terrain_roads.tscn'),scene);
    const contract={units:'m',root_transform:'identity',bounds_xz:design.bounds_xz,
        design_sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'design/town-concept-b/town-layout.json'))).digest('hex'),
        verification:{offline:'33 flat pads; 40000m2 coverage; shared-vertex seam;38 curve envelopes;>=12m secondary radii; road grades',native:'pending primary Godot MCP',maximum_road_slope_degrees:maximumRoadSlope},
        height_policy:'Exact baked triangle barycentric height; foundation root = pad_y + .2',
        pads:pads.map(p=>({id:p.id,xz:p.xz,yaw_deg:p.yaw_deg,pad_y:p.height,root_y:p.height+.2,footprint_m:p.size})),
        nodes:Object.fromEntries(Object.entries(design.nodes).map(([id,p])=>[id,{xz:p,ground_y:heightAt(...p),road_surface_y:heightAt(...p)+.025}])),
        road_paths:roadPaths,curves,road_clearance:clearance,terrain_triangles:triangles};
    fs.writeFileSync(path.join(__dirname,'ground_contract.json'),JSON.stringify(contract));
    console.log(JSON.stringify({terrain_triangles:triangles.length,terrain_vertices:vertexHeights.size,roads:38,pads:33,minimum_curve_clearance_m:Math.min(...clearance.map(c=>c.minimum_sample_clearance_m)),maximum_road_slope_degrees:maximumRoadSlope,curves:curves.length}));
}
if(require.main===module) build();
module.exports={heightAt,baseHeight,pads,roadPaths,curves,triangles,clearance};
