const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');

const projectRoot = path.resolve(__dirname, '../../..');
const sourceRoot = 'C:/Stuff/Blender/TownKit';
const targetPrefix = 'Assets/Blender/TownKit/props/';
const catalogPath = path.join(__dirname, 'asset-catalog.json');
const hash = data => crypto.createHash('sha256').update(data).digest('hex');
const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const slash = value => value.replaceAll('\\', '/');
const rounded = value => Number(value.toFixed(6));

function inside(root, candidate) {
    const relative = path.relative(path.resolve(root), path.resolve(candidate));
    assert(relative && !relative.startsWith('..') && !path.isAbsolute(relative), `Path escapes root: ${candidate}`);
    return path.resolve(candidate);
}

function readGlb(file) {
    const bytes = fs.readFileSync(file);
    assert(bytes.length >= 20 && bytes.readUInt32LE(0) === 0x46546c67 && bytes.readUInt32LE(4) === 2, `Invalid GLB: ${file}`);
    assert.equal(bytes.readUInt32LE(8), bytes.length, `Truncated GLB: ${file}`);
    assert.equal(bytes.readUInt32LE(16), 0x4e4f534a, `Missing GLB JSON: ${file}`);
    const jsonEnd = 20 + bytes.readUInt32LE(12);
    assert(jsonEnd <= bytes.length, `Truncated GLB JSON: ${file}`);
    const json = JSON.parse(bytes.subarray(20, jsonEnd).toString('utf8'));
    const binaryOffset = jsonEnd + 8;
    assert(binaryOffset <= bytes.length && bytes.readUInt32LE(jsonEnd + 4) === 0x004e4942, `Missing GLB binary: ${file}`);
    return {bytes, json, binary: bytes.subarray(binaryOffset, binaryOffset + bytes.readUInt32LE(jsonEnd))};
}

const identity = () => [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
function multiply(a, b) {
    const result = Array(16).fill(0);
    for (let column = 0; column < 4; column++) for (let row = 0; row < 4; row++) {
        for (let k = 0; k < 4; k++) result[column * 4 + row] += a[k * 4 + row] * b[column * 4 + k];
    }
    return result;
}

function nodeMatrix(node) {
    if (node.matrix) return node.matrix;
    const [x, y, z, w] = node.rotation || [0, 0, 0, 1];
    const [sx, sy, sz] = node.scale || [1, 1, 1];
    const [tx, ty, tz] = node.translation || [0, 0, 0];
    return [
        (1 - 2 * (y * y + z * z)) * sx, 2 * (x * y + z * w) * sx, 2 * (x * z - y * w) * sx, 0,
        2 * (x * y - z * w) * sy, (1 - 2 * (x * x + z * z)) * sy, 2 * (y * z + x * w) * sy, 0,
        2 * (x * z + y * w) * sz, 2 * (y * z - x * w) * sz, (1 - 2 * (x * x + y * y)) * sz, 0,
        tx, ty, tz, 1,
    ];
}

function geometryFacts(json, binary) {
    const minimum = [Infinity, Infinity, Infinity], maximum = [-Infinity, -Infinity, -Infinity];
    const visualMeshes = [], collisionNodes = [];
    let triangles = 0;
    function walk(index, parentMatrix, parents) {
        const node = json.nodes[index], world = multiply(parentMatrix, nodeMatrix(node));
        const nodePath = [...parents, node.name || `Node${index}`];
        const collision = /-(colonly|convcolonly|col|convcol)$/.test(node.name || '');
        if (node.mesh !== undefined && collision) collisionNodes.push(nodePath.join('/'));
        if (node.mesh !== undefined && !collision) {
            const mesh = json.meshes[node.mesh], materials = [];
            for (const primitive of mesh.primitives) {
                const accessor = json.accessors[primitive.attributes.POSITION];
                const view = json.bufferViews[accessor.bufferView];
                assert(accessor.type === 'VEC3' && accessor.componentType === 5126 && !accessor.sparse && view.buffer === 0, `Unsupported visual POSITION: ${nodePath.join('/')}`);
                const stride = view.byteStride || 12, offset = (view.byteOffset || 0) + (accessor.byteOffset || 0);
                assert(offset + (accessor.count - 1) * stride + 12 <= binary.length, `Truncated visual POSITION: ${node.name}`);
                for (let vertex = 0; vertex < accessor.count; vertex++) {
                    const point = [0, 1, 2].map(axis => binary.readFloatLE(offset + vertex * stride + axis * 4));
                    for (let axis = 0; axis < 3; axis++) {
                        const value = world[axis] * point[0] + world[4 + axis] * point[1] + world[8 + axis] * point[2] + world[12 + axis];
                        minimum[axis] = Math.min(minimum[axis], value);
                        maximum[axis] = Math.max(maximum[axis], value);
                    }
                }
                const count = primitive.indices === undefined ? accessor.count : json.accessors[primitive.indices].count;
                assert((primitive.mode ?? 4) === 4 && count % 3 === 0, `Nontriangle visual: ${node.name}`);
                triangles += count / 3;
                const material = json.materials?.[primitive.material];
                materials.push({name: material?.name || null, alpha_mode: material?.alphaMode || 'OPAQUE'});
            }
            visualMeshes.push({path: nodePath.join('/'), surfaces: materials});
        }
        for (const child of node.children || []) walk(child, world, nodePath);
    }
    for (const index of json.scenes[json.scene || 0].nodes) walk(index, identity(), []);
    assert(minimum.concat(maximum).every(Number.isFinite), 'Empty or invalid visual bounds');
    return {
        visual_bounds_godot_m: [minimum.map(rounded), maximum.map(rounded)],
        dimensions_godot_m: maximum.map((value, axis) => rounded(value - minimum[axis])),
        bounds_method: 'Actual GLB Y-up visual POSITION vertices with full scene-node transforms; collision-only excluded',
        visual_triangles: triangles,
        visual_meshes: visualMeshes,
        collision_nodes: collisionNodes,
    };
}

function buildCatalog() {
    const ledgerFile = path.join(sourceRoot, 'production/production_state.json');
    const manifestFile = path.join(sourceRoot, 'props/asset_manifest.json');
    const ledger = readJson(ledgerFile), manifest = readJson(manifestFile);
    const assets = manifest.filter(asset => asset.catalog_id).map(asset => {
        const delivered = ledger.assets.find(entry => entry.asset_id === asset.catalog_id);
        assert(delivered, `Asset missing from ledger: ${asset.catalog_id}`);
        const glb = inside(path.join(sourceRoot, 'props'), asset.glb);
        const sourceRelative = slash(path.relative(path.join(sourceRoot, 'props'), glb));
        const folder = sourceRelative.split('/')[0];
        assert(sourceRelative.startsWith(`${folder}/godot/`), `Unexpected source delivery layout: ${glb}`);
        const {json, bytes, binary} = readGlb(glb);
        const facts = geometryFacts(json, binary);
        let collisionBounds = null;
        if (facts.collision_nodes.length) {
            const collisionJson = {...json, nodes: json.nodes.map(node => {
                const copy = {...node};
                if (copy.mesh !== undefined && !/-(colonly|convcolonly|col|convcol)$/.test(copy.name || '')) delete copy.mesh;
                else copy.name = (copy.name || '').replace(/-(colonly|convcolonly|col|convcol)$/, '');
                return copy;
            })};
            collisionBounds = geometryFacts(collisionJson, binary).visual_bounds_godot_m;
        }
        const materialOverrides = {...asset.variant_overrides};
        for (const finish of asset.variants || []) {
            if (!finish.variant || !finish.material || materialOverrides[finish.variant]) continue;
            const material = path.join(sourceRoot, 'props', folder, 'godot/materials', `${finish.material}.tres`);
            if (fs.existsSync(material)) materialOverrides[finish.variant] = `res://${targetPrefix}${folder}/materials/${finish.material}.tres`;
        }
        return {
            key: `${asset.catalog_id}/${asset.catalog_variant}`,
            catalog_id: asset.catalog_id,
            variant: asset.catalog_variant,
            asset: asset.asset,
            zone: delivered.zone,
            priority: delivered.priority,
            source_prop_folder: folder,
            source_glb: slash(glb),
            source_glb_sha256: hash(bytes),
            glb_res_path: `res://${targetPrefix}${folder}/${sourceRelative.split('/godot/')[1]}`,
            wrapper_res_path: `res://Scene/Props/TownKit/Catalog/${asset.catalog_id}__${asset.catalog_variant}.tscn`,
            collision_role: delivered.collision,
            pivot: {origin_godot_m: [0, 0, 0], source_notes: asset.pivot || asset.origin || asset.pivot_description || json.nodes.find(node => node.extras?.pivot)?.extras.pivot || null, bottom_offset_y_m: facts.visual_bounds_godot_m[0][1]},
            material_overrides: materialOverrides,
            ...facts,
            source_collision_bounds_godot_m: collisionBounds,
            source_ready: {
                ledger_status: delivered.status,
                source_export: asset.pass_source_export === true,
                source_reopened: asset.source_reopened === true,
                actual_glb_reimport: asset.actual_glb_reimport === true,
                isolated_native_godot: asset.native_godot?.pass === true,
                source_visual_review: asset.visual_review_pass === true,
                native_town_placement_verified: false,
            },
        };
    });
    assert.equal(assets.length, 310);
    assert.equal(new Set(assets.map(asset => asset.catalog_id)).size, 143);
    assert.equal(new Set(assets.map(asset => asset.key)).size, assets.length);
    const catalog = {schema_version: 1, source_ledger: slash(ledgerFile), source_ledger_sha256: hash(fs.readFileSync(ledgerFile)), source_manifest: slash(manifestFile), source_manifest_sha256: hash(fs.readFileSync(manifestFile)), catalog_types: 143, geometry_variants: 310, coordinate_system: 'Godot/glTF Y-up, metres; unit wrapper transform', acceptance: 'Source metadata and offline GLB inspection only. Native Town import, collision, visual, gameplay and FPS acceptance are separate.', assets};
    fs.writeFileSync(catalogPath, JSON.stringify(catalog, null, 2) + '\n');
    console.log(`CATALOG_OK ${assets.length} variants / ${catalog.catalog_types} types`);
    return catalog;
}

function defaultFinish(asset) {
    const finishes = Object.keys(asset.material_overrides);
    return ['used', 'dusty', 'summer', 'green'].find(finish => finishes.includes(finish)) || finishes[0] || 'embedded';
}

function wrapperPath(asset, finish = defaultFinish(asset), visualOnly = false) {
    const suffix = `${finish === defaultFinish(asset) ? '' : `__${finish}`}${visualOnly ? '__visual' : ''}`;
    return asset.wrapper_res_path.replace(/\.tscn$/, `${suffix}.tscn`);
}

function resourceSource(asset, resPath) {
    const prefix = `res://${targetPrefix}${asset.source_prop_folder}/`;
    assert(resPath.startsWith(prefix), `Resource is outside delivered prop: ${resPath}`);
    const tail = resPath.slice(prefix.length);
    assert(!tail.includes('\\') && !tail.split('/').some(part => !part || part === '.' || part === '..'), `Unsafe resource path: ${resPath}`);
    const prop = path.join(sourceRoot, 'props', asset.source_prop_folder);
    const source = inside(prop, path.join(prop, tail.startsWith('textures/') ? tail : `godot/${tail}`));
    assert(fs.existsSync(source) && fs.statSync(source).isFile(), `Missing delivered dependency: ${source}`);
    assert(!fs.lstatSync(source).isSymbolicLink(), `Symbolic dependency rejected: ${source}`);
    inside(prop, fs.realpathSync(source));
    return source;
}

function relativeDependency(asset, fromSource, fromRes, uri) {
    if (uri.startsWith('data:')) return null;
    const decoded = decodeURIComponent(uri);
    assert(decoded && !decoded.includes('\\') && !decoded.includes('\0') && !/^[a-z]+:|^[\/]/i.test(decoded) && !/[?#]/.test(decoded), `Unsafe external GLB URI: ${uri}`);
    const source = inside(path.join(sourceRoot, 'props', asset.source_prop_folder), path.resolve(path.dirname(fromSource), decoded));
    const resPath = `res://${path.posix.normalize(path.posix.join(path.posix.dirname(fromRes.slice(6)), decoded))}`;
    assert.equal(resourceSource(asset, resPath).toLowerCase(), source.toLowerCase(), `Dependency remap changes URI meaning: ${uri}`);
    return {source, resPath};
}

function wrapperText(asset, finish, visualOnly) {
    const material = asset.material_overrides[finish];
    assert(finish === 'embedded' || material, `Unknown finish ${asset.key}/${finish}`);
    const materialNames = new Set(Object.values(asset.material_overrides).map(value => path.posix.basename(value, '.tres')));
    const overrides = [];
    for (const mesh of asset.visual_meshes) {
        const surfaces = mesh.surfaces.map((surface, index) => ({...surface, index})).filter(surface => surface.alpha_mode === 'OPAQUE' && materialNames.has(surface.name));
        if (!material || !surfaces.length) continue;
        const parts = mesh.path.split('/'), name = parts.pop(), parent = ['Model', ...parts].join('/');
        overrides.push(`[node name="${name}" parent="${parent}"]\n${surfaces.map(surface => `surface_material_override/${surface.index} = ExtResource("2_finish")`).join('\n')}`);
    }
    const useMaterial = overrides.length > 0;
    return `[gd_scene load_steps=${useMaterial ? 3 : 2} format=3]\n\n[ext_resource type="PackedScene" path="${asset.glb_res_path}" id="1_model"]\n${useMaterial ? `[ext_resource type="Material" path="${material}" id="2_finish"]\n` : ''}\n[node name="${asset.catalog_id}__${asset.variant}" type="Node3D"]\n${visualOnly ? 'process_mode = 4\n' : ''}metadata/catalog_id = "${asset.catalog_id}"\nmetadata/catalog_variant = "${asset.variant}"\nmetadata/finish = "${finish}"\nmetadata/collision_policy = "${visualOnly ? 'visual_only_inherited_disable_mode_remove' : 'native_import'}"\n\n[node name="Model" parent="." instance=ExtResource("1_model")]\n${overrides.length ? `\n${overrides.join('\n\n')}\n` : ''}`;
}

function selectionRecords(plan) {
    const records = Array.isArray(plan) ? plan : plan.selected_assets || plan.assets || plan.placements;
    assert(Array.isArray(records) && records.length > 0, 'Plan needs selected_assets[], assets[] or placements[]');
    return records;
}

function importSelected(planFile, checkOnly = false) {
    const catalog = readJson(catalogPath), plan = readJson(planFile), files = new Map(), selected = new Map();
    const byKey = new Map(catalog.assets.map(asset => [asset.key, asset]));
    for (const record of selectionRecords(plan)) {
        const key = record.key || `${record.catalog_id}/${record.variant || record.catalog_variant}`;
        const asset = byKey.get(key);
        assert(asset, `Plan references unknown catalog variant: ${key}`);
        assert.equal(asset.source_ready.ledger_status, 'verified_isolated', `Unready source: ${key}`);
        const finish = record.finish || defaultFinish(asset);
        assert(finish === 'embedded' || asset.material_overrides[finish], `Unknown finish ${key}/${finish}`);
        if (!selected.has(key)) selected.set(key, {asset, finishes: new Set([defaultFinish(asset)])});
        selected.get(key).finishes.add(finish);
    }

    function addFile(source, resPath, bytes = null) {
        const destination = inside(projectRoot, path.join(projectRoot, resPath.slice(6)));
        assert(resPath.startsWith(`res://${targetPrefix}`) || resPath.startsWith('res://Scene/Props/TownKit/Catalog/'), `Destination outside owned scope: ${resPath}`);
        let existingParent = path.dirname(destination);
        while (!fs.existsSync(existingParent)) existingParent = path.dirname(existingParent);
        const realRoot = fs.realpathSync(projectRoot), realParent = fs.realpathSync(existingParent);
        if (realParent !== realRoot) inside(realRoot, realParent);
        assert(/\.(glb|bin|png|jpg|jpeg|webp|tres|tscn)$/i.test(destination), `Unsupported delivery extension: ${resPath}`);
        const data = bytes || fs.readFileSync(source), sha256 = hash(data);
        if (files.has(destination)) {
            assert.equal(files.get(destination).sha256, sha256, `Conflicting delivery content: ${resPath}`);
            return false;
        }
        if (fs.existsSync(destination)) {
            assert(fs.statSync(destination).isFile() && !fs.lstatSync(destination).isSymbolicLink(), `Unsafe existing target: ${destination}`);
            assert.equal(hash(fs.readFileSync(destination)), sha256, `Refusing to overwrite changed file: ${destination}`);
        }
        files.set(destination, {source, res_path: resPath, destination, sha256, bytes: data, status: fs.existsSync(destination) ? 'identical' : 'new'});
        return true;
    }

    function addResource(asset, resPath) {
        const source = resourceSource(asset, resPath);
        if (!addFile(source, resPath)) return;
        if (source.endsWith('.tres')) {
            const text = fs.readFileSync(source, 'utf8');
            for (const match of text.matchAll(/\[ext_resource\b[^\]]*\bpath="([^"]+)"[^\]]*\]/g)) addResource(asset, match[1]);
        }
    }

    const wrappers = [];
    for (const {asset, finishes} of selected.values()) {
        assert.equal(hash(fs.readFileSync(asset.source_glb)), asset.source_glb_sha256, `Source changed since catalogue: ${asset.key}`);
        addResource(asset, asset.glb_res_path);
        const {json} = readGlb(asset.source_glb);
        for (const entry of [...(json.images || []), ...(json.buffers || [])]) {
            if (!entry.uri) continue;
            const dependency = relativeDependency(asset, asset.source_glb, asset.glb_res_path, entry.uri);
            if (dependency) addResource(asset, dependency.resPath);
        }
        for (const finish of finishes) for (const visualOnly of [false, true]) {
            const resPath = wrapperPath(asset, finish, visualOnly), text = wrapperText(asset, finish, visualOnly);
            const material = asset.material_overrides[finish];
            if (material && text.includes('id="2_finish"')) addResource(asset, material);
            addFile(null, resPath, Buffer.from(text));
            wrappers.push({key: asset.key, finish, collision_policy: visualOnly ? 'visual_only' : 'native', res_path: resPath});
        }
    }

    // Preflight every dependency and existing target before the first write.
    for (const file of files.values()) if (!checkOnly && file.status === 'new') {
        fs.mkdirSync(path.dirname(file.destination), {recursive: true});
        fs.writeFileSync(file.destination, file.bytes, {flag: 'wx'});
        assert.equal(hash(fs.readFileSync(file.destination)), file.sha256, `Target verification failed: ${file.destination}`);
    }
    const report = {
        schema_version: 1, mode: checkOnly ? 'check_only' : 'copy', selected_plan: slash(path.resolve(planFile)), plan_sha256: hash(fs.readFileSync(planFile)), catalog_sha256: hash(fs.readFileSync(catalogPath)),
        selected_types: new Set([...selected.values()].map(({asset}) => asset.catalog_id)).size, selected_geometry_variants: selected.size,
        files_total: files.size, new_files: [...files.values()].filter(file => file.status === 'new').length, identical_files: [...files.values()].filter(file => file.status === 'identical').length,
        bytes_total: [...files.values()].reduce((sum, file) => sum + file.bytes.length, 0),
        source_to_target_sha256_verified: !checkOnly, native_town_verified: false,
        limits: ['No Godot editor/runtime operation performed by importer.', 'Visual-only wrappers use inherited PROCESS_MODE_DISABLED and default CollisionObject3D DISABLE_MODE_REMOVE; verify native import removes helper collision.', 'Only matching opaque atlas surfaces receive finish overrides; embedded glass/lenses and unmatched surfaces retain source materials.'],
        wrappers, files: [...files.values()].map(({bytes, destination, ...file}) => ({...file, target: slash(destination)})),
    };
    if (!checkOnly) fs.writeFileSync(path.join(__dirname, 'asset-import-report.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(`IMPORT_${checkOnly ? 'CHECK' : 'COPY'}_OK ${selected.size} variants; ${files.size} files; ${report.new_files} new; ${report.bytes_total} bytes`);
    return report;
}

function selfCheck() {
    assert.throws(() => inside(projectRoot, path.join(projectRoot, '../escape')), /escapes root/);
    assert.throws(() => inside(projectRoot, projectRoot), /escapes root/);
    assert.equal(inside(projectRoot, path.join(projectRoot, 'Assets/a.glb')), path.join(projectRoot, 'Assets/a.glb'));
    const fake = {key: 'test/a', catalog_id: 'test', variant: 'a', source_prop_folder: 'test', glb_res_path: 'res://Assets/Blender/TownKit/props/test/assets/test.glb', wrapper_res_path: 'res://Scene/Props/TownKit/Catalog/test__a.tscn', material_overrides: {used: 'res://Assets/Blender/TownKit/props/test/materials/atlas_used.tres', clean: 'res://Assets/Blender/TownKit/props/test/materials/atlas_clean.tres'}, visual_meshes: [{path: 'Root/Body', surfaces: [{name: 'atlas_used', alpha_mode: 'OPAQUE'}, {name: 'glass', alpha_mode: 'BLEND'}, {name: 'lens', alpha_mode: 'OPAQUE'}]}]};
    const text = wrapperText(fake, 'clean', true);
    assert(text.includes('process_mode = 4') && text.includes('surface_material_override/0'));
    assert(!text.includes('surface_material_override/1') && !text.includes('surface_material_override/2'));
    assert.equal(wrapperPath(fake, 'clean', true), 'res://Scene/Props/TownKit/Catalog/test__a__clean__visual.tscn');
    assert.throws(() => resourceSource(fake, 'res://Assets/Blender/TownKit/props/test/materials/../../escape.tres'), /Unsafe resource/);
    assert.throws(() => relativeDependency(fake, '/not/read', fake.glb_res_path, 'https://example.com/a.png'), /Unsafe external/);
    assert.throws(() => relativeDependency(fake, '/not/read', fake.glb_res_path, '%2fetc/passwd'), /Unsafe external/);
    assert.equal(relativeDependency(fake, '/not/read', fake.glb_res_path, 'data:image/png;base64,AAAA'), null);
    assert.throws(() => selectionRecords({placements: []}), /Plan needs/);
    const binary = Buffer.alloc(36);
    [0, 0, 0, 1, 0, 0, 0, 1, 0].forEach((value, index) => binary.writeFloatLE(value, index * 4));
    const json = {scene: 0, scenes: [{nodes: [0]}], nodes: [{name: 'Mesh', mesh: 0, translation: [10, 2, -5], rotation: [0, Math.SQRT1_2, 0, Math.SQRT1_2]}], meshes: [{primitives: [{attributes: {POSITION: 0}}]}], accessors: [{bufferView: 0, componentType: 5126, type: 'VEC3', count: 3}], bufferViews: [{buffer: 0, byteLength: 36}]};
    const facts = geometryFacts(json, binary);
    assert.deepEqual(facts.visual_bounds_godot_m, [[10, 2, -6], [10, 3, -5]]);
    assert.equal(facts.visual_triangles, 1);
    console.log('IMPORTER_SELF_CHECK_OK traversal, external URI rejection, embedded URI, finish surface preservation, wrapper policy, transformed vertex bounds');
}

if (require.main === module) {
    if (process.argv.includes('--catalog')) buildCatalog();
    else if (process.argv.includes('--self-check')) selfCheck();
    else {
        const planFile = process.argv.find((argument, index) => index > 1 && !argument.startsWith('--'));
        assert(planFile, 'Usage: node import-assets.cjs <placement-plan.json> [--check-only] | --catalog | --self-check');
        importSelected(planFile, process.argv.includes('--check-only'));
    }
}

module.exports = {buildCatalog, readGlb, geometryFacts, inside, projectRoot, sourceRoot, targetPrefix, importSelected, wrapperText, wrapperPath, resourceSource, relativeDependency};
