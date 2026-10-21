// Offline authoring: node design/town-500m/phase3/author-nav-exclusions.cjs [--check]
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../..');
const cataloguePath = path.resolve(__dirname, '../building-catalogue.json');
const catalogue = JSON.parse(fs.readFileSync(cataloguePath, 'utf8'));
const round = n => Number(n.toFixed(9));
const vector = a => `Vector3(${a.map(round).join(', ')})`;
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const templates = new Map();
const parseVector = (body, key) => {
    const match = body.match(new RegExp(`^${key} = Vector3\\(([^)]+)\\)`, 'm'));
    return match ? match[1].split(',').map(Number) : [0, 0, 0];
};
function bounds(points) {
    return [0, 1, 2].map(i => Math.min(...points.map(p => p[i])))
        .concat([0, 1, 2].map(i => Math.max(...points.map(p => p[i])))).map(round);
}
function boxCorners(size, position, yaw = 0) {
    const result = [], c = Math.cos(yaw), s = Math.sin(yaw);
    for (const x of [-size[0] / 2, size[0] / 2]) for (const y of [-size[1] / 2, size[1] / 2]) for (const z of [-size[2] / 2, size[2] / 2]) {
        result.push([position[0] + c * x + s * z, position[1] + y, position[2] - s * x + c * z]);
    }
    return result;
}
function inspectScene(ref) {
    const file = path.join(root, ref.slice(6)), text = fs.readFileSync(file, 'utf8');
    const sections = text.split(/(?=^\[)/m).filter(s => s.startsWith('[')).map(s => {
        const end = s.indexOf(']');
        return {header: s.slice(1, end), body: s.slice(end + 1), attributes: Object.fromEntries([...s.slice(1, end).matchAll(/(\w+)="([^"]*)"/g)].map(m => [m[1], m[2]]))};
    });
    const resources = new Map(sections.filter(s => s.header.startsWith('sub_resource ')).map(s => [s.attributes.id, s]));
    const nodes = sections.filter(s => s.header.startsWith('node '));
    const nodePath = n => !n.attributes.parent || n.attributes.parent === '.' ? n.attributes.name : `${n.attributes.parent}/${n.attributes.name}`;
    const nodeMap = new Map(nodes.map(n => [nodePath(n), n]));
    const positionOf = n => {
        const own = parseVector(n.body, 'position');
        const parent = nodeMap.get(n.attributes.parent);
        return parent ? own.map((v, i) => v + positionOf(parent)[i]) : own;
    };
    const floors = [], roofPoints = [], ceilings = [], importedRoofs = [];
    for (const node of nodes) {
        const resourceRef = node.body.match(/^(?:shape|mesh) = SubResource\("([^"]+)"\)/m);
        if (!resourceRef) continue;
        const resource = resources.get(resourceRef[1]);
        assert(resource);
        const name = node.attributes.name === 'Collision' || node.attributes.name === 'Mesh' ? node.attributes.parent.split('/').pop() : node.attributes.name;
        if (resource.attributes.type === 'BoxShape3D' && /^(GroundFloor|UpperFloor|LowerStep|UpperStep|MidLanding)/.test(name)) {
            const aabb = bounds(boxCorners(parseVector(resource.body, 'size'), positionOf(node)));
            floors.push({node: nodePath(node), bounds_local_m: aabb, top_local_y_m: aabb[4]});
        }
        if (resource.attributes.type === 'BoxMesh' && /Roof|SolidShell/.test(name)) {
            roofPoints.push(...boxCorners(parseVector(resource.body, 'size'), positionOf(node)));
        }
        if (resource.attributes.type === 'ConcavePolygonShape3D' && /Ceiling/.test(name)) {
            const values = resource.body.match(/data = PackedVector3Array\(([^)]+)\)/)[1].split(',').map(Number);
            const points = [];
            for (let i = 0; i < values.length; i += 3) points.push(values.slice(i, i + 3).map((v, j) => v + positionOf(node)[j]));
            ceilings.push({node: nodePath(node), bounds_local_m: bounds(points), backface_collision: /backface_collision = true/.test(resource.body), collision_layer: 1});
        }
        if (resource.attributes.type === 'BoxShape3D' && name === 'Roof') {
            const aabb = bounds(boxCorners(parseVector(resource.body, 'size'), positionOf(node)));
            ceilings.push({node: nodePath(node), bounds_local_m: aabb, closed_box: true, collision_layer: 1});
        }
    }
    for (const node of nodes.filter(n => /^Roof_/.test(n.attributes.name))) {
        const extId = node.header.match(/instance=ExtResource\("([^"]+)"\)/)[1];
        const ext = sections.find(s => s.header.startsWith('ext_resource ') && s.attributes.id === extId);
        assert.equal(ext.attributes.path, 'res://Scene/Props/TownKit/metal_roof_8x8.tscn');
        const glbPath = path.join(root, 'Assets/Blender/TownKit/assets/metal_roof_8x8.glb');
        const glb = fs.readFileSync(glbPath);
        const gltf = JSON.parse(glb.subarray(20, 20 + glb.readUInt32LE(12)).toString());
        assert(gltf.nodes.every(n => !n.translation && !n.rotation && !n.scale && !n.matrix));
        assert(gltf.nodes.every(n => !/colonly|collision/i.test(n.name)), 'Imported roof should remain visual only');
        const points = gltf.meshes.flatMap(m => m.primitives.map(p => gltf.accessors[p.attributes.POSITION]));
        const low = [0, 1, 2].map(i => Math.min(...points.map(p => p.min[i])));
        const high = [0, 1, 2].map(i => Math.max(...points.map(p => p.max[i])));
        const size = high.map((v, i) => v - low[i]), centre = high.map((v, i) => (v + low[i]) / 2);
        const yaw = parseVector(node.body, 'rotation')[1], p = positionOf(node), c = Math.cos(yaw), s = Math.sin(yaw);
        const transformedCentre = [p[0] + c * centre[0] + s * centre[2], p[1] + centre[1], p[2] - s * centre[0] + c * centre[2]];
        const corners = boxCorners(size, transformedCentre, yaw);
        roofPoints.push(...corners);
        importedRoofs.push({node: nodePath(node), wrapper: ext.attributes.path, glb: 'res://Assets/Blender/TownKit/assets/metal_roof_8x8.glb', source_sha256: hash(glbPath), bounds_local_m: bounds(corners), collider_nodes_in_gltf: 0});
    }
    assert(roofPoints.length > 0, ref);
    const roofBounds = bounds(roofPoints);
    const ceilingY = ceilings.length ? Math.min(...ceilings.map(c => c.bounds_local_m[1])) : roofBounds[4];
    return {scene_ref: ref, source_sha256: hash(file), floors, ceilings, imported_roofs: importedRoofs, roof_visual_bounds_local_m: roofBounds, start_ceiling_local_y_m: ceilingY};
}

const placements = [], nodes = ['[node name="NavigationExclusions" type="Node3D"]'];
for (const s of catalogue.structures) {
    const ref = s.scene_ref || `res://Scene/World/Town500m/Graybox/${s.kind}.tscn`;
    if (!templates.has(ref)) templates.set(ref, inspectScene(ref));
    const evidence = templates.get(ref);
    const rootY = s.pad_intent.surface_y_m + s.pad_intent.root_above_pad_m;
    const b = evidence.roof_visual_bounds_local_m;
    const footprint = [-s.footprint_m[0] / 2, -s.footprint_m[1] / 2, s.footprint_m[0] / 2, s.footprint_m[1] / 2];
    // Include wall tops and exact imported roof outsets; keep a tenth-metre geometric margin.
    const outline = [Math.min(footprint[0], b[0]) - 0.1, Math.min(footprint[1], b[2]) - 0.1,
        Math.max(footprint[2], b[3]) + 0.1, Math.max(footprint[3], b[5]) + 0.1].map(round);
    const localMinY = round(evidence.start_ceiling_local_y_m - 0.1);
    const minY = round(rootY + localMinY), maxY = round(rootY + b[4] + 0.2);
    const floors = evidence.floors.map(f => ({...f, top_world_y_m: round(rootY + f.top_local_y_m)}));
    assert(floors.every(f => f.top_world_y_m < minY), `${s.id}: exclusion touches a ground/upper floor or stair`);
    assert(s.pad_intent.surface_y_m < minY, `${s.id}: exclusion reaches terrain pad`);
    const vertices = [[outline[0], 0, outline[1]], [outline[2], 0, outline[1]], [outline[2], 0, outline[3]], [outline[0], 0, outline[3]]];
    const yaw = s.yaw_deg * Math.PI / 180;
    nodes.push(`[node name="${s.id}" type="NavigationObstacle3D" parent="."]\nposition = ${vector([s.position_xz_m[0], minY, s.position_xz_m[1]])}\nrotation = ${vector([0, yaw, 0])}\nheight = ${round(maxY - minY)}\nradius = 0.0\nvertices = PackedVector3Array(${vertices.flat().map(round).join(', ')})\navoidance_enabled = false\naffect_navigation_mesh = true\ncarve_navigation_mesh = true\nmetadata/town500_id = "${s.id}"\nmetadata/source_scene = "${ref}"\nmetadata/roof_exclusion_only = true`);
    placements.push({id: s.id, source_ref: s.source_ref, zone: s.zone_id, scene_ref: ref, footprint_m: s.footprint_m, position_xz_m: s.position_xz_m, yaw_deg: s.yaw_deg, root_world_y_m: round(rootY), access: s.access, floor_tops_world_y_m: [...new Set(floors.map(f => f.top_world_y_m))], floors, start_ceiling_world_y_m: round(rootY + evidence.start_ceiling_local_y_m), min_y_world_m: minY, max_y_world_m: maxY, exclusion_height_m: round(maxY - minY), exclusion_local_bounds_xz_m: outline, roof_visual_world_y_m: [round(rootY + b[1]), round(rootY + b[4])], canopy: /bus_shelter/.test(ref)});
}
assert.equal(placements.length, 76);
assert.equal(placements.filter(p => p.access.upper).length, 4);
const scene = `[gd_scene format=3]\n\n${nodes.join('\n\n')}\n`;
const report = {
    status: 'OFFLINE_BOUNDS_AND_AUTHORING_PASS_NATIVE_BAKE_PENDING',
    catalogue_sha256: hash(cataloguePath),
    totals: {placements: placements.length, source_scenes: templates.size, accessible_upper_instances: 4, navigation_obstacles: 76},
    method: 'Static NavigationObstacle3D bake exclusions. No post-bake centroid deletion, manual clipping, runtime script or collision change. Every outline encloses canonical footprint and live visual roof XZ bounds with0.1m margin; globalY=live ceiling minus0.1m; top=live roof maximum plus0.2m. Y extrusion preserves all authored floors/stair treads below the roof.',
    properties: {avoidance_enabled: false, affect_navigation_mesh: true, carve_navigation_mesh: true, radius: 0},
    official_documentation: 'https://docs.godotengine.org/en/stable/classes/class_navigationobstacle3d.html#class-navigationobstacle3d-property-affect-navigation-mesh',
    coordinate_test_for_native_audit: 'For world vertex(x,y,z), dx=x-rootX,dz=z-rootZ; localX=cos(yaw)*dx-sin(yaw)*dz; localZ=sin(yaw)*dx+cos(yaw)*dz. Compare localXZ with exclusion_local_bounds_xz_m and worldY with[min_y_world_m,max_y_world_m]. Use this to report bake residue only, never delete polygons by centroid.',
    conventions: ['Existing editable template ceiling ConcavePolygonShape3D is downward one-sided with backface_collision=false, layer1; visual roofs have no explicit collider in those templates. Thin wall-top faces may still enter a static-collider bake.', 'Imported metal roof wrapper has no collision properties and GLB contains no collision-helper nodes. Its POSITION accessor bounds, identity GLB node transforms and live wrapper placement/yaw are used for exact roof bounds.', 'Pending primitives are closed BoxShape3D solids. B04 floor/walls/lintel/roof are closed boxes. Native exclusions suppress rooftop navigation independently of physical closure.', 'Bus shelter catalogue height3.2m differs from live canopy ceiling2.6m and visual roof2.6..2.75m; bounds use live source. Shelter floor and space under canopy remain below the extrusion.', 'Warehouse visual roof and ceiling cover rear localZ0..9m, while full footprint has walls up to7m. Full footprint exclusion at6.9m also suppresses wall tops; ground remains below it.'],
    limits: ['No native bake/import/editor/runtime performed by this worker. Primary must verify that parser includes these obstacle nodes and carve removes all roof polygons.', 'Native voxel/edge/polygon simplification still affects carve boundaries. Any residual/straddling roof polygons require reported native geometry and a deliberate follow-up; centroid-only filtering is rejected because it can create holes or delete unrelated surfaces.', 'All direct floor and stair BoxShape3D bounds are asserted below exclusion bottom. Native routes, ground/upper-floor continuity, canopy clearance and imported facade top-edge collision still need primary tests.', 'Obstacles must be instanced under the same existing NavigationRegion3D source hierarchy with identity payload transform before the native bake.'],
    templates: Object.fromEntries(templates),
    placements,
    payload: 'res://Scene/World/Town500m/navigation_exclusions.tscn',
    payload_sha256: crypto.createHash('sha256').update(scene).digest('hex')
};
const outputs = new Map([
    ['Scene/World/Town500m/navigation_exclusions.tscn', scene],
    ['design/town-500m/phase3/nav-roof-exclusion.json', JSON.stringify(report, null, 2) + '\n']
]);
for (const [file, content] of outputs) {
    const absolute = path.join(root, file);
    if (process.argv.includes('--check')) assert.equal(fs.readFileSync(absolute, 'utf8'), content, `Stale ${file}`);
    else fs.writeFileSync(absolute, content);
}
console.log('Nav roof exclusion AUTHOR/CHECK PASS:76 obstacles, all direct floors/stairs below exclusion; native bake pending.');
