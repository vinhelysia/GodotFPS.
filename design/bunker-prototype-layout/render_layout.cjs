const fs = require('fs');
const path = require('path');
const sharp = require('C:/Users/Vinh/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const folder = __dirname;
(async () => {
  const svg = fs.readFileSync(path.join(folder, 'layout.svg'));
  await sharp(svg).png().toFile(path.join(folder, 'layout.png'));
  const meta = await sharp(path.join(folder, 'layout.png')).metadata();
  if (meta.width !== 1860 || meta.height !== 1850) throw new Error('Wrong preview dimensions');
  console.log(JSON.stringify({preview: 'layout.png', width: meta.width, height: meta.height}));
})().catch(error => { console.error(error.message); process.exitCode = 1; });
