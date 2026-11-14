// Draws the addon's kill-on-sight mark, addon/FantasyForce/Media/Kos.tga: a bone-white skull on a blood-red
// badge with a dark rim and crosshair ticks. 64x64, 32-bit TGA (what the game reads), drawn from shapes with
// 4x4 supersampling, so it stays crisp at the 20-28 px the addon shows it. The same mark at 256x256 as a PNG,
// public/discord/kos.png, is what the Discord bot's kill-on-sight posts and the site's KOS page show.
//   node tools/make-kos-icon.mjs
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateSync } from 'node:zlib';

const SIZE = 64; // the shapes below are drawn on a 64x64 grid
const SS = 4;
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = join(root, 'addon', 'FantasyForce', 'Media', 'Kos.tga');
const outPng = join(root, 'public', 'discord', 'kos.png');

const C = 32; // centre
const len = (x, y) => Math.hypot(x, y);
const ellipse = (x, y, cx, cy, rx, ry) => ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1;
const roundRect = (x, y, x0, y0, x1, y1, r) => {
  const qx = Math.max(x0 + r - x, 0, x - (x1 - r));
  const qy = Math.max(y0 + r - y, 0, y - (y1 - r));
  return x >= x0 && x <= x1 && y >= y0 && y <= y1 && len(qx, qy) <= r;
};
const tri = (x, y, [ax, ay], [bx, by], [cx, cy]) => {
  const s = (px, py, qx, qy, rx, ry) => (px - rx) * (qy - ry) - (qx - rx) * (py - ry);
  const d1 = s(x, y, ax, ay, bx, by), d2 = s(x, y, bx, by, cx, cy), d3 = s(x, y, cx, cy, ax, ay);
  return !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0));
};

// The colour (r, g, b, a in 0..1) at one sample point, top-left origin.
function sample(x, y) {
  const d = len(x - C, y - C);
  // crosshair ticks over the rim, top/bottom/left/right
  const tick = (Math.abs(x - C) <= 1.6 && d >= 22 && d <= 31.5) || (Math.abs(y - C) <= 1.6 && d >= 22 && d <= 31.5);
  if (tick) return [0.08, 0.02, 0.02, 1];
  if (d > 30) return [0, 0, 0, 0];
  if (d > 27.5) return [0.08, 0.02, 0.02, 1]; // dark rim
  if (d > 26) return [0.85, 0.62, 0.25, 1]; // thin gold ring, like the addon's portrait badge
  // skull (bone white, a little warm), shaded towards the bottom
  const cranium = ellipse(x, y, C, 27, 14.5, 13.5);
  const jaw = roundRect(x, y, C - 9, 33, C + 9, 46, 4);
  const cheek = roundRect(x, y, C - 12, 30, C + 12, 38, 5);
  if (cranium || jaw || cheek) {
    const eye = ellipse(x, y, C - 6, 29.5, 4.4, 4.9) || ellipse(x, y, C + 6, 29.5, 4.4, 4.9);
    const nose = tri(x, y, [C, 33.5], [C - 2.6, 38.5], [C + 2.6, 38.5]);
    const teethGap = y >= 41 && y <= 46 && [C - 4.5, C, C + 4.5].some((tx) => Math.abs(x - tx) <= 0.7);
    const mouth = y >= 40.4 && y <= 41.3 && Math.abs(x - C) <= 7;
    if (eye || nose) return [0.12, 0.02, 0.02, 1];
    if (teethGap || mouth) return [0.35, 0.18, 0.12, 1];
    const shade = 1 - Math.max(0, (y - 22) / 60);
    return [0.97 * shade, 0.93 * shade, 0.84 * shade, 1];
  }
  // blood-red badge, brighter at the top-left
  const light = 1 - len(x - 22, y - 18) / 55;
  return [0.45 + 0.4 * light, 0.03 + 0.05 * light, 0.03 + 0.04 * light, 1];
}

// The mark at `size` px: straight-alpha RGBA, rows top-down.
function render(size) {
  const k = SIZE / size;
  const px = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let sy = 0; sy < SS; sy++) {
        for (let sx = 0; sx < SS; sx++) {
          const [cr, cg, cb, ca] = sample((x + (sx + 0.5) / SS) * k, (y + (sy + 0.5) / SS) * k);
          r += cr * ca; g += cg * ca; b += cb * ca; a += ca;
        }
      }
      const i = (y * size + x) * 4;
      px[i] = a ? Math.round((r / a) * 255) : 0;
      px[i + 1] = a ? Math.round((g / a) * 255) : 0;
      px[i + 2] = a ? Math.round((b / a) * 255) : 0;
      px[i + 3] = Math.round((a / (SS * SS)) * 255);
    }
  }
  return px;
}

// TGA: BGRA, rows bottom-up, as the addon's other TGAs.
const rgba = render(SIZE);
const px = Buffer.alloc(SIZE * SIZE * 4);
for (let y = 0; y < SIZE; y++) {
  for (let x = 0; x < SIZE; x++) {
    const from = (y * SIZE + x) * 4;
    const to = ((SIZE - 1 - y) * SIZE + x) * 4;
    px[to] = rgba[from + 2]; px[to + 1] = rgba[from + 1]; px[to + 2] = rgba[from]; px[to + 3] = rgba[from + 3];
  }
}

const header = Buffer.alloc(18);
header[2] = 2; // uncompressed true colour
header.writeUInt16LE(SIZE, 12);
header.writeUInt16LE(SIZE, 14);
header[16] = 32;
header[17] = 8; // 8 alpha bits, bottom-left origin (like Icon.tga)
writeFileSync(out, Buffer.concat([header, px]));
console.log('wrote', out);

// PNG: 8-bit RGBA, no filtering, one IDAT.
const CRC = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let j = 0; j < 8; j++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
const crc32 = (buf) => {
  let c = 0xffffffff;
  for (const byte of buf) c = CRC[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};
const chunk = (type, data) => {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
};
function png(size, pixels) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; ihdr[9] = 6; // 8 bits, RGBA
  const raw = Buffer.alloc(size * (size * 4 + 1));
  for (let y = 0; y < size; y++) pixels.copy(raw, y * (size * 4 + 1) + 1, y * size * 4, (y + 1) * size * 4);
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}
mkdirSync(dirname(outPng), { recursive: true });
writeFileSync(outPng, png(256, render(256)));
console.log('wrote', outPng);
