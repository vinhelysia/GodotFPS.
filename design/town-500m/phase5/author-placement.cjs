const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {wrapperPath} = require('./import-assets.cjs');
const root = path.resolve(__dirname, '../../..');
const read = file => JSON.parse(fs.readFileSync(path.join(__dirname, file), 'utf8'));
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const number = value => Number(value.toFixed(6));
const quoted = value => JSON.stringify(String(value));

function mergePlan() {
    const plans = ['town-industry-placement.json', 'outer-placement.json', 'shared-placement.json'].map(read);
    const placements = plans.flatMap(plan => plan.placements);
    const deferred = plans.flatMap(plan => plan.deferred || []);
    assert.equal(new Set(placements.map(row => row.id)).size, placements.length, 'Duplicate instance IDs');
    const assets = read('asset-catalog.json').assets;
    require('./review-placement.cjs').review(placements, assets);
    const types = [...new Set(assets.map(row => row.catalog_id))];
    const coverage = types.map(catalog_id => {
        const rows = placements.filter(row => row.catalog_id === catalog_id);
        const exception = deferred.find(row => row.catalog_id === catalog_id);
        assert(rows.length || exception?.reason, `Unaccounted catalogue type: ${catalog_id}`);
        return {catalog_id, status: rows.length ? 'planned' : 'deferred', instances: rows.map(row => row.id), reason: rows.length ? null : exception.reason};
    });
    for (const row of placements) {
        assert.deepEqual(row.scale, [1, 1, 1], `Native import scale required: ${row.id}`);
        const asset = assets.find(asset => asset.key === `${row.catalog_id}/${row.variant}`);
        assert(asset, `Unknown geometry ${row.id}`);
        row.scene_ref = wrapperPath(asset, row.finish || undefined, row.collision_policy === 'visual_only');
    }
    const plan = {
        schema_version: 1, date: '2026-10-20', status: 'UNIT_SCALE_OFFLINE_REVISION_NATIVE_PENDING',
        coordinate_system: 'metres; origin map centre; X east, Y up, Z south; Godot yaw in degrees',
        scope: 'Static Town500m props/art only. Preserve roads, terrain, buildings, raid/loot/player/save authority and the two existing crossings.',
        decisions: ['Cover143 catalogue types; incompatible types deferred with a specific reason.', 'All TownKit placements retain native import scale [1,1,1]; reposition for fit without resizing source assets.', 'No random runtime placement, autoload, new interaction or save migration.', 'Native tree helpers replace exactly the named old trunk shapes; changed collision requires fresh native validation.'],
        source_sha256: Object.fromEntries(['Scene/Town.tscn', 'design/town-500m/layout.json', 'design/town-500m/building-catalogue.json', 'design/town-500m/terrain-contract.json'].map(file => [file, hash(path.join(root, file))])),
        phases: [
            {id: 0, name: 'Coordinate/asset mapping', gate: 'All143 types covered; source bounds, floors, routes, doors and pair overlaps checked.'},
            {id: 1, name: 'Selective import', gate: 'Only selected geometry/dependencies copied with SHA checks; reusable finish/collision wrappers resolve natively.'},
            {id: 2, name: 'Static editable zone composition', gate: 'Every listed individual transform authored, honest proxy replacements and supported furniture/clutter.'},
            {id: 3, name: 'Native acceptance', gate: 'Imported materials/helpers, physical support, nav bake, existing full routes/interiors/ports/finite LOS and rendered views verified.'},
            {id: 4, name: 'Handoff', gate: 'Source protection/isolated saves/editor cleanup, before-after evidence, coverage table and limits recorded.'}
        ],
        counts: {instances: placements.length, catalogue_types: types.length, planned_types: coverage.filter(row => row.status === 'planned').length, deferred_types: coverage.filter(row => row.status === 'deferred').length, by_zone: placements.reduce((all, row) => (all[row.zone] = (all[row.zone] || 0) + 1, all), {})},
        placements, coverage, deferred: coverage.filter(row => row.status === 'deferred'),
        verification_limits: ['A coordinate plan and source export QA do not prove native traversal, LOS or FPS.', 'Map Phase4 spawn/extraction transaction wiring and lighting/AI/gameplay tuning are separate tasks.']
    };
    fs.writeFileSync(path.join(__dirname, 'placement-plan.json'), JSON.stringify(plan, null, 2) + '\n');
    writeDocuments(plan);
    return plan;
}

function writeDocuments(plan) {
    const lines = ['# Town500m — kế hoạch placement từng prop', '', `Ngày ${plan.date}. ${plan.counts.instances} instances; ${plan.counts.planned_types} / ${plan.counts.catalogue_types} types sẽ đặt; ${plan.counts.deferred_types} ngoại lệ có lý do.`, '',
        'Tọa độ world XYZ (m), rotation XYZ (degrees; Godot Euler order YXZ); không đổi roads/buildings/spawn/extract. Toàn bộ TownKit props giữ native import scale (1,1,1). Mỗi dòng là một editable scene instance; JSON là nguồn tọa độ và rotation đã author. Revision này cần native acceptance mới.', '',
        ...plan.phases.map(phase => `${phase.id + 1}. ${phase.name}: ${phase.gate}`), '',
        '## Placement theo zone', '', '| ID | Prop / geometry | Finish | XYZ m | Rotation XYZ ° | Scale | Support / host | Collision | Vai trò |', '|---|---|---|---|---|---|---|---|---|'];
    const csv = ['id,zone,catalog_id,variant,finish,x,y,z,yaw_deg,rotation_x_deg,rotation_y_deg,rotation_z_deg,scale,collision_policy,support_kind,support_host'];
    for (const row of plan.placements) {
        const rotation = row.rotation_deg || [0, row.yaw_deg, 0];
        lines.push(`| ${row.id} | ${row.catalog_id} / ${row.variant} | ${row.finish || 'source'} | ${row.position_m.map(number).join(', ')} | ${rotation.map(number).join(', ')} | ${row.scale.map(number).join(', ')} | ${row.support.kind} / ${row.support.host_id || row.proxy_id || 'terrain'} | ${row.collision_policy} | ${row.role} |`);
        csv.push([row.id, row.zone, row.catalog_id, row.variant, row.finish, ...row.position_m, row.yaw_deg, ...rotation, row.scale[0], row.collision_policy, row.support.kind, row.support.host_id || row.proxy_id || ''].map(quoted).join(','));
    }
    lines.push('', `## Coverage đủ ${plan.counts.catalogue_types} types`, '', '| Prop type | Instance IDs hoặc lý do defer |', '|---|---|');
    for (const row of plan.coverage) lines.push(`| ${row.catalog_id} | ${row.instances.length ? row.instances.join(', ') : '**DEFER:** ' + row.reason} |`);
    lines.push('', '## Giới hạn và verify', '', ...plan.verification_limits.map(limit => '- ' + limit));
    fs.writeFileSync(path.join(__dirname, 'placement-plan.txt'), lines.join('\n') + '\n');
    fs.writeFileSync(path.join(__dirname, 'placement-coordinates.csv'), csv.join('\n') + '\n');
    const colours = {town: '#d1ae7e', industry: '#9aaeb7', bunker: '#697f72', hills: '#a1b58c', forest: '#567e5e', farmland: '#c8bc73', river: '#73a4bf', lake: '#91bacd'};
    const esc = text => String(text).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;');
    const layout = JSON.parse(fs.readFileSync(path.join(__dirname, '../layout.json')));
    const polygons = layout.zones.map(zone => `<polygon points="${zone.polygon_xz_m.map(point => point.map(value => value + 250).join(',')).join(' ')}" fill="${colours[zone.id] || '#b5b5a5'}" opacity=".35" stroke="#65766a" stroke-width=".5"/>`);
    const roads = layout.corridors.map(road => `<polyline points="${road.points_xz_m.map(point => point.map(value => value + 250).join(',')).join(' ')}" fill="none" stroke="#6c675b" stroke-width="${road.width_m}" opacity=".5"/>`);
    const dots = plan.placements.map(row => `<circle cx="${row.position_m[0] + 250}" cy="${row.position_m[2] + 250}" r="1.5" fill="${colours[row.zone] || '#303d35'}" stroke="#172b24" stroke-width=".3"><title>${esc(row.id + ' / ' + row.catalog_id + ' / ' + row.position_m.join(', '))}</title></circle>`);
    fs.writeFileSync(path.join(__dirname, 'placement-map.svg'), `<svg xmlns="http://www.w3.org/2000/svg" viewBox="-15 -20 530 540"><rect x="-15" y="-20" width="530" height="540" fill="#eeeade"/><text x="0" y="-7" font-size="8" font-family="sans-serif">Town500m / exact prop coordinates / North=-Z</text>${polygons.join('')}${roads.join('')}${dots.join('')}<rect width="500" height="500" fill="none" stroke="#253d31"/><text x="0" y="513" font-size="6" font-family="sans-serif">Each dot = one scene instance; hover for ID/XYZ. Full table: placement-plan.txt / CSV.</text></svg>`);
}

function inheritedScene(originalPath, replacements, catalogue) {
    const text = fs.readFileSync(path.join(root, originalPath), 'utf8');
    const nodes = [...text.matchAll(/^\[node name="([^"]+)"[^\n]*\]$/gm)].map(match => {
        const parent = match[0].match(/parent="([^"]+)"/)?.[1];
        return {name: match[1], path: parent && parent !== '.' ? `${parent}/${match[1]}` : match[1], parent, shape: match[0].includes('type="CollisionShape3D"')};
    });
    const rootNode = nodes.find(node => !node.parent);
    const overrides = new Map();
    const override = (node, property) => {
        if (!overrides.has(node.path)) overrides.set(node.path, {node, properties: []});
        overrides.get(node.path).properties.push(property);
    };
    for (const row of replacements) {
        const id = row.proxy_id.replaceAll('-', '_');
        const source = nodes.find(node => node.path === `Concealment/${id}` || node.path === `HardCover/${id}` || node.path === row.proxy_id);
        assert(source, `Proxy not found in ${originalPath}: ${row.proxy_id}`);
        const building = catalogue.find(item => item.id === row.proxy_id);
        assert(!building?.scene_ref, `Refusing to retire an actual building: ${row.proxy_id}`);
        override(source, 'visible = false');
        if (row.collision_policy === 'native') {
            const shapes = nodes.filter(node => node.shape && node.path.startsWith(source.path + '/'));
            if (row.proxy_replacement?.kind === 'vegetation_native_replacement') {
                assert.deepEqual(shapes.map(node => node.path), [row.proxy_replacement.retired_shape_path], `Unexpected old trunk shapes: ${row.id}`);
            }
            for (const node of shapes) override(node, 'disabled = true');
            // Instanced container/wagon collisions are defined in their source scene, not the POI text.
            if (building) {
                const shapePath = 'Architecture/SolidShell/Collision';
                const sourceScene = fs.readFileSync(path.join(root, `Scene/World/Town500m/Graybox/${building.kind}.tscn`), 'utf8');
                assert(sourceScene.includes('[node name="Collision" type="CollisionShape3D" parent="Architecture/SolidShell"]'), `Unexpected proxy collision: ${row.proxy_id}`);
                override({name: 'Collision', parent: `${source.path}/Architecture/SolidShell`, path: `${source.path}/${shapePath}`}, 'disabled = true');
            }
        }
    }
    const body = [...overrides.values()].map(({node, properties}) => `[node name=${quoted(node.name)} parent=${quoted(node.parent || '.')} ]\n${[...new Set(properties)].join('\n')}`).join('\n\n');
    return `[gd_scene load_steps=2 format=3]\n\n[ext_resource type="PackedScene" path="res://${originalPath}" id="1"]\n\n[node name=${quoted(rootNode.name)} instance=ExtResource("1")]\n\n${body}\n`;
}

function authorScenes() {
    const plan = read('placement-plan.json');
    for (const row of plan.placements) assert.deepEqual(row.scale, [1, 1, 1], `Native import scale required: ${row.id}`);
    const catalogue = JSON.parse(fs.readFileSync(path.join(__dirname, '../building-catalogue.json'))).structures;
    const output = path.join(root, 'Scene/World/Town500m/Props');
    const art = path.join(root, 'Scene/World/Town500m/Art');
    fs.mkdirSync(output, {recursive: true});
    fs.mkdirSync(art, {recursive: true});
    for (const zone of Object.keys(plan.counts.by_zone)) {
        const rows = plan.placements.filter(row => row.zone === zone);
        const resources = [...new Set(rows.map(row => row.scene_ref))];
        for (const file of resources) assert(fs.existsSync(path.join(root, file.replace('res://', ''))), `Not imported: ${file}`);
        const external = resources.map((file, i) => `[ext_resource type="PackedScene" path=${quoted(file)} id="${i + 1}"]`).join('\n');
        const nodes = rows.map(row => `[node name=${quoted(row.id)} parent="." instance=ExtResource("${resources.indexOf(row.scene_ref) + 1}")]\nposition = Vector3(${row.position_m.map(number).join(', ')})\nrotation = Vector3(${(row.rotation_deg || [0, row.yaw_deg, 0]).map(value => number(value * Math.PI / 180)).join(', ')})\nscale = Vector3(${row.scale.map(number).join(', ')})\nmetadata/town_prop_id = ${quoted(row.id)}\nmetadata/catalog_id = ${quoted(row.catalog_id)}\nmetadata/role = ${quoted(row.role)}`).join('\n\n');
        fs.writeFileSync(path.join(output, `${zone}.tscn`), `[gd_scene load_steps=${resources.length + 1} format=3]\n\n${external}\n\n[node name=${quoted(zone)} type="Node3D"]\n\n${nodes}\n`);
    }
    const zones = Object.keys(plan.counts.by_zone);
    fs.writeFileSync(path.join(output, 'town_props.tscn'), `[gd_scene load_steps=${zones.length + 1} format=3]\n\n${zones.map((zone, i) => `[ext_resource type="PackedScene" path="res://Scene/World/Town500m/Props/${zone}.tscn" id="${i + 1}"]`).join('\n')}\n\n[node name="Town500Props" type="Node3D"]\nmetadata/placement_plan = "res://design/town-500m/phase5/placement-plan.json"\n\n${zones.map((zone, i) => `[node name=${quoted(zone)} parent="." instance=ExtResource("${i + 1}")]`).join('\n\n')}\n`);
    const replacements = plan.placements.filter(row => row.proxy_id);
    const dressing = replacements.filter(row => !catalogue.some(item => item.id === row.proxy_id));
    fs.writeFileSync(path.join(art, 'dressing.tscn'), inheritedScene('Scene/World/Town500m/Dressing/dressing.tscn', dressing, catalogue));
    const poiZones = [...new Set(replacements.filter(row => catalogue.some(item => item.id === row.proxy_id)).map(row => catalogue.find(item => item.id === row.proxy_id).zone_id))];
    for (const zone of poiZones) fs.writeFileSync(path.join(art, `${zone}.tscn`), inheritedScene(`Scene/World/Town500m/POI/${zone}.tscn`, replacements.filter(row => catalogue.find(item => item.id === row.proxy_id)?.zone_id === zone), catalogue));
    fs.writeFileSync(path.join(art, 'navigation_exclusions.tscn'), '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="PackedScene" path="res://Scene/World/Town500m/navigation_exclusions.tscn" id="1"]\n\n[node name="RoofNavigationExclusions" instance=ExtResource("1")]\n\n[node name="I09-A" parent="."]\nposition = Vector3(198.3, 5.6, 59.09)\nheight = 1.6\n');
    console.log(`AUTHORED ${plan.placements.length} static instances in ${zones.length} zones; ${replacements.length} explicit proxy replacements`);
}

if (require.main === module) {
    if (process.argv.includes('--scenes')) authorScenes();
    else console.log(mergePlan().counts);
}
module.exports = {mergePlan, authorScenes, writeDocuments};
