// Builds the addon preview into tools/addon-preview/dist/: index.html plus its scripts, opening straight from
// the folder (no server). The addon's Lua files (in .toc order), the pretend game's Lua, the Media TGAs and
// the game's icons go into data.js, and the stand-in font into preview.css, so nothing is fetched at run time
// (a page that may only show its own and data: images, like Proofer's capture, draws the same).
// The icons come from Wowhead's icon server once and are kept in node_modules/.cache/addon-preview-icons.
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
const sources = files.map((f) => read(join(addon, f)));
const lua = { fakegame: read(join(here, 'fakegame.lua')), world: read(join(here, 'world.lua')), preview: read(join(here, 'preview.lua')) };

const tga = {};
const media = join(addon, 'Media');
for (const f of existsSync(media) ? readdirSync(media) : []) {
  if (/\.tga$/i.test(f)) tga[f.replace(/\.tga$/i, '')] = readFileSync(join(media, f)).toString('base64');
}

// Every icon the addon and the pretend world name, plus the class icons and the question mark.
const names = new Set(['inv_misc_questionmark', 'trade_alchemy']);
for (const c of ['warrior', 'paladin', 'hunter', 'rogue', 'priest', 'shaman', 'mage', 'warlock', 'druid']) names.add('classicon_' + c);
const iconWord = /["\\]((?:inv|spell|trade|ability)_[A-Za-z0-9_]+)"/gi;
for (const text of [...sources, lua.world]) {
  for (const m of text.matchAll(iconWord)) if (m[1] !== m[1].toUpperCase()) names.add(m[1].toLowerCase()); // not EVENT_NAMES
}
const cache = join(root, 'node_modules', '.cache', 'addon-preview-icons');
mkdirSync(cache, { recursive: true });
const icons = {};
const failed = [];
await Promise.all([...names].map(async (name) => {
  const file = join(cache, name + '.jpg');
  if (!existsSync(file)) {
    try {
      const r = await fetch(`https://wow.zamimg.com/images/wow/icons/medium/${name}.jpg`);
      if (!r.ok) throw new Error(String(r.status));
      writeFileSync(file, Buffer.from(await r.arrayBuffer()));
    } catch (e) { failed.push(`${name} (${e.message})`); return; }
  }
  icons[name] = 'data:image/jpeg;base64,' + readFileSync(file).toString('base64');
}));

const fontFile = join(root, 'node_modules', '@fontsource', 'marcellus', 'files', 'marcellus-latin-400-normal.woff2');
const fontRule = existsSync(fontFile)
  ? `@font-face { font-family: "Marcellus"; src: url(data:font/woff2;base64,${readFileSync(fontFile).toString('base64')}) format("woff2"); }\n`
  : '';
const data = { files, sources, lua, tga, icons, built: new Date().toISOString() };

mkdirSync(dist, { recursive: true });
writeFileSync(join(dist, 'data.js'), `window.PREVIEW_DATA = ${JSON.stringify(data)};\n`);
for (const f of ['index.html', 'preview.js']) copyFileSync(join(here, f), join(dist, f));
writeFileSync(join(dist, 'preview.css'), fontRule + read(join(here, 'preview.css')));
copyFileSync(join(root, 'node_modules', 'fengari-web', 'dist', 'fengari-web.js'), join(dist, 'fengari-web.js'));
console.log(`addon preview: ${join(dist, 'index.html')} (${files.join(', ')}; ${Object.keys(tga).join(', ') || 'no'} TGAs; `
  + `${Object.keys(icons).length} icons${failed.length ? `, missing ${failed.join(', ')}` : ''})`);
