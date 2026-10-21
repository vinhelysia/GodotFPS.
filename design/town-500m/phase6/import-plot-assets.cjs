// Add the existing young birch variant without replacing the Phase5 import receipt.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const importer = require('../phase5/import-assets.cjs');
const root = path.resolve(__dirname, '../../..');
const catalog = JSON.parse(fs.readFileSync(path.join(__dirname, '../phase5/asset-catalog.json')));
const asset = catalog.assets.find(row => row.key === 'forest_birch_tree/A');
assert(asset && asset.source_ready.ledger_status === 'verified_isolated');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const files = new Map();
function add(resPath, bytes) {
    assert(resPath.startsWith('res://Assets/Blender/TownKit/props/forest_birch_tree/') || resPath.startsWith('res://Scene/Props/TownKit/Catalog/forest_birch_tree__A'));
    if (files.has(resPath)) return;
    const data = bytes || fs.readFileSync(importer.resourceSource(asset, resPath));
    files.set(resPath, data);
    if (resPath.endsWith('.tres')) {
        for (const match of data.toString().matchAll(/\[ext_resource[^\]]*path="([^"]+)"/g)) add(match[1]);
    }
}
const glb = importer.readGlb(asset.source_glb);
assert.equal(hash(glb.bytes), asset.source_glb_sha256);
add(asset.glb_res_path);
for (const entry of [...(glb.json.images || []), ...(glb.json.buffers || [])]) {
    if (entry.uri) {
        const dependency = importer.relativeDependency(asset, asset.source_glb, asset.glb_res_path, entry.uri);
        if (dependency) add(dependency.resPath);
    }
}
const finish = 'late_autumn';
assert(asset.material_overrides[finish]);
const wrapper = importer.wrapperPath(asset, finish, false);
add(asset.material_overrides[finish]);
add(wrapper, Buffer.from(importer.wrapperText(asset, finish, false)));
for (const [resPath, bytes] of files) {
    const destination = path.join(root, resPath.slice(6));
    if (fs.existsSync(destination)) assert.equal(hash(fs.readFileSync(destination)), hash(bytes), `Refusing changed target ${resPath}`);
}
for (const [resPath, bytes] of files) {
    const destination = path.join(root, resPath.slice(6));
    if (!fs.existsSync(destination)) {
        fs.mkdirSync(path.dirname(destination), {recursive: true});
        fs.writeFileSync(destination, bytes, {flag: 'wx'});
    }
}
const report = {status: 'SOURCE_HASH_VERIFIED_NATIVE_PENDING', wrapper, unit_scale: [1, 1, 1], files: [...files].map(([res_path, bytes]) => ({res_path, sha256: hash(bytes), bytes: bytes.length}))};
fs.writeFileSync(path.join(__dirname, 'plot-assets-import.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({wrapper, files: files.size, source_sha256: asset.source_glb_sha256}));
