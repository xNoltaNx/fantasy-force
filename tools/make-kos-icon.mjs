// Draws the addon's kill-on-sight mark, addon/FantasyForce/Media/Kos.tga: a bone-white skull on a blood-red
// badge with a dark rim and crosshair ticks. 64x64, 32-bit TGA (what the game reads), drawn from shapes with
// 4x4 supersampling, so it stays crisp at the 20-28 px the addon shows it.
//   node tools/make-kos-icon.mjs
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SIZE = 64;
const SS = 4;
const out = join(dirname(fileURLToPath(import.meta.url)), '..', 'addon', 'FantasyForce', 'Media', 'Kos.tga');

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

const px = Buffer.alloc(SIZE * SIZE * 4);
for (let y = 0; y < SIZE; y++) {
  for (let x = 0; x < SIZE; x++) {
    let r = 0, g = 0, b = 0, a = 0;
    for (let sy = 0; sy < SS; sy++) {
      for (let sx = 0; sx < SS; sx++) {
        const [cr, cg, cb, ca] = sample(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS);
        r += cr * ca; g += cg * ca; b += cb * ca; a += ca;
      }
    }
    const n = SS * SS;
    const i = ((SIZE - 1 - y) * SIZE + x) * 4; // rows bottom-up, as the addon's other TGAs
    // TGA stores BGRA, straight (not premultiplied) alpha
    px[i] = a ? Math.round((b / a) * 255) : 0;
    px[i + 1] = a ? Math.round((g / a) * 255) : 0;
    px[i + 2] = a ? Math.round((r / a) * 255) : 0;
    px[i + 3] = Math.round((a / n) * 255);
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
