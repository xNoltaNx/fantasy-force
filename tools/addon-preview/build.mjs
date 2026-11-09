// Builds the addon preview into tools/addon-preview/dist/: index.html plus its scripts, opening straight from
// the folder (no server). The addon's Lua files (in .toc order), the pretend game's Lua, the Media TGAs and
// the stand-in font go into data.js, so nothing is fetched from disk at run time.
//   node tools/addon-preview/build.mjs      (or: npm run addon-preview)
import { readFileSync, writeFileSync, mkdirSync, readdirSync, copyFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const addon = join(root, 'addon', 'FantasyForce');
const dist = join(here, 'dist');
const read = (p) => readFileSync(p, 'utf8');

// the addon's files as the game loads them: the .toc's file lines, in order
const files = read(join(addon, 'FantasyForce.toc')).split(/\r?\n/).map((l) => l.trim())
  .filter((l) => l && !l.startsWith('#') && /\.lua$/i.test(l));

const tga = {};
const media = join(addon, 'Media');
for (const f of existsSync(media) ? readdirSync(media) : []) {
  if (/\.tga$/i.test(f)) tga[f.replace(/\.tga$/i, '')] = readFileSync(join(media, f)).toString('base64');
}

const fontFile = join(root, 'node_modules', '@fontsource', 'marcellus', 'files', 'marcellus-latin-400-normal.woff2');
const data = {
  files,
  sources: files.map((f) => read(join(addon, f))),
  lua: { fakegame: read(join(here, 'fakegame.lua')), world: read(join(here, 'world.lua')), preview: read(join(here, 'preview.lua')) },
  tga,
  font: existsSync(fontFile) ? readFileSync(fontFile).toString('base64') : '',
  built: new Date().toISOString(),
};

mkdirSync(dist, { recursive: true });
writeFileSync(join(dist, 'data.js'), `window.PREVIEW_DATA = ${JSON.stringify(data)};\n`);
for (const f of ['index.html', 'preview.js', 'preview.css']) copyFileSync(join(here, f), join(dist, f));
copyFileSync(join(root, 'node_modules', 'fengari-web', 'dist', 'fengari-web.js'), join(dist, 'fengari-web.js'));
console.log(`addon preview: ${join(dist, 'index.html')} (${files.join(', ')}; ${Object.keys(tga).join(', ') || 'no'} TGAs)`);
