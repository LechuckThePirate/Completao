// Builds the window's textures (Media/Textures/*.tga) from the art sheet in images/originals/ui_art_sheet.jpg:
// the obsidian background, the compass medallion and the ornate title plate are cut from it; the header banner is
// made from its stone and griffins; the gold 9-slice border and the status icons are drawn here.
// Needs ffmpeg on the PATH (it decodes and scales the sheet). Usage: node tools/ui_textures.mjs [sheet.jpg]
import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const sheet = process.argv[2] || join(root, "images", "originals", "ui_art_sheet.jpg");
const out = join(root, "Media", "Textures");
mkdirSync(out, { recursive: true });

// ---------------------------------------------------------------------------------------------- image helpers

// A region of the sheet, scaled to w x h, as RGBA bytes.
function cut(x, y, cw, ch, w, h) {
    const r = spawnSync("ffmpeg", ["-loglevel", "error", "-i", sheet, "-vf",
        `crop=${cw}:${ch}:${x}:${y},scale=${w}:${h}:flags=lanczos`, "-f", "rawvideo", "-pix_fmt", "rgba", "-"],
        { maxBuffer: 1 << 28 });
    if (r.status !== 0) throw new Error(`ffmpeg failed: ${r.stderr}`);
    return { w, h, px: new Float32Array(r.stdout) };
}

function blank(w, h) {
    return { w, h, px: new Float32Array(w * h * 4) };
}

// Uncompressed 32-bit TGA (no RLE), bottom-left origin: what every client reads.
function writeTGA(name, img) {
    const { w, h, px } = img;
    const buf = Buffer.alloc(18 + w * h * 4);
    buf[2] = 2; // uncompressed true color
    buf.writeUInt16LE(w, 12);
    buf.writeUInt16LE(h, 14);
    buf[16] = 32;
    buf[17] = 8; // 8 alpha bits, bottom-left origin
    let o = 18;
    for (let y = h - 1; y >= 0; y--) {
        for (let x = 0; x < w; x++) {
            const i = (y * w + x) * 4;
            const c = (k) => Math.max(0, Math.min(255, Math.round(px[i + k])));
            buf[o++] = c(2); buf[o++] = c(1); buf[o++] = c(0); buf[o++] = c(3);
        }
    }
    writeFileSync(join(out, name), buf);
    console.log(`${name}  ${w}x${h}`);
}

// Source-over of a straight-alpha color onto the image.
function blendPx(img, x, y, r, g, b, a) {
    if (x < 0 || y < 0 || x >= img.w || y >= img.h || a <= 0) return;
    const i = (y * img.w + x) * 4, p = img.px;
    const da = p[i + 3] / 255, sa = Math.min(1, a);
    const oa = sa + da * (1 - sa);
    if (oa <= 0) return;
    p[i] = (r * sa + p[i] * da * (1 - sa)) / oa;
    p[i + 1] = (g * sa + p[i + 1] * da * (1 - sa)) / oa;
    p[i + 2] = (b * sa + p[i + 2] * da * (1 - sa)) / oa;
    p[i + 3] = oa * 255;
}

const smooth = (e0, e1, v) => {
    const t = Math.max(0, Math.min(1, (v - e0) / (e1 - e0)));
    return t * t * (3 - 2 * t);
};

// Paints a shape given as a signed distance function (negative inside), antialiased by 4x4 supersampling.
// color(x, y) returns [r, g, b]; outline adds a dark ring of that width around it.
// glow: a soft halo of glowColor that far outside the shape.
function paintSDF(img, sdf, color, { outline = 0, outlineColor = [12, 10, 8], shadow = 0, ox = 0, oy = 0, size = 64, w, h,
    glow = 0, glowColor = [255, 255, 255], glowAlpha = 0.7 } = {}) {
    const S = 4;
    for (let y = 0; y < (h || size); y++) {
        for (let x = 0; x < (w || size); x++) {
            if (glow) {
                const d = sdf(x + 0.5, y + 0.5) - outline;
                if (d > 0 && d < glow) blendPx(img, ox + x, oy + y, glowColor[0], glowColor[1], glowColor[2], glowAlpha * (1 - d / glow) ** 2);
            }
            let cover = 0, ring = 0, shade = 0;
            for (let sy = 0; sy < S; sy++) {
                for (let sx = 0; sx < S; sx++) {
                    const fx = x + (sx + 0.5) / S, fy = y + (sy + 0.5) / S;
                    const d = sdf(fx, fy);
                    if (d < 0) cover++;
                    else if (d < outline) ring++;
                    if (shadow && sdf(fx - 1.5, fy - 2) < outline) shade++;
                }
            }
            const n = S * S;
            if (shade) blendPx(img, ox + x, oy + y, 0, 0, 0, (shade / n) * shadow);
            if (ring) blendPx(img, ox + x, oy + y, outlineColor[0], outlineColor[1], outlineColor[2], (ring + cover) / n);
            if (cover) {
                const [r, g, b] = color(x, y);
                blendPx(img, ox + x, oy + y, r, g, b, cover / n);
            }
        }
    }
}

// SDF primitives
const circle = (cx, cy, r) => (x, y) => Math.hypot(x - cx, y - cy) - r;
const box = (cx, cy, hw, hh, rad = 0) => (x, y) => {
    const qx = Math.abs(x - cx) - hw + rad, qy = Math.abs(y - cy) - hh + rad;
    return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - rad;
};
const segment = (ax, ay, bx, by, r) => (x, y) => {
    const pax = x - ax, pay = y - ay, bax = bx - ax, bay = by - ay;
    const h = Math.max(0, Math.min(1, (pax * bax + pay * bay) / (bax * bax + bay * bay)));
    return Math.hypot(pax - bax * h, pay - bay * h) - r;
};
const union = (...f) => (x, y) => Math.min(...f.map((g) => g(x, y)));
const subtract = (a, b) => (x, y) => Math.max(a(x, y), -b(x, y));
// arc of a ring centered at (cx, cy): angles in radians, 0 = right, growing clockwise (screen y down)
const arc = (cx, cy, r, thick, from, to) => (x, y) => {
    let ang = Math.atan2(y - cy, x - cx);
    if (ang < from) ang += Math.PI * 2;
    if (ang >= from && ang <= to) return Math.abs(Math.hypot(x - cx, y - cy) - r) - thick;
    const end = (a) => [cx + Math.cos(a) * r, cy + Math.sin(a) * r];
    const [ax, ay] = end(from), [bx, by] = end(to);
    return Math.min(Math.hypot(x - ax, y - ay), Math.hypot(x - bx, y - by)) - thick;
};
const star = (cx, cy, rOut, rIn) => {
    const pts = [];
    for (let i = 0; i < 10; i++) {
        const a = -Math.PI / 2 + (i * Math.PI) / 5, r = i % 2 ? rIn : rOut;
        pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]);
    }
    return (x, y) => { // polygon SDF
        let d = Infinity, s = 1;
        for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
            const [ax, ay] = pts[j], [bx, by] = pts[i];
            const ex = bx - ax, ey = by - ay, wx = x - ax, wy = y - ay;
            const t = Math.max(0, Math.min(1, (wx * ex + wy * ey) / (ex * ex + ey * ey)));
            d = Math.min(d, Math.hypot(wx - ex * t, wy - ey * t));
            const c1 = y >= ay, c2 = y < by, c3 = ex * wy > ey * wx;
            if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s = -s;
        }
        return s * d;
    };
};

// vertical gradient between two colors over [y0, y1]
const vgrad = (top, bottom, y0, y1) => (_, y) => {
    const t = Math.max(0, Math.min(1, (y - y0) / (y1 - y0)));
    return top.map((c, k) => c + (bottom[k] - c) * t);
};

// Makes the sheet's flat dark backdrop transparent: a flood fill from the borders through pixels close to the
// backdrop's color, with a soft edge.
function knockOutBackdrop(img, tolerance = 22) {
    const { w, h, px } = img;
    const bg = [0, 1, 2].map((k) => px[k]); // the corner's color
    const dist = (i) => Math.max(...[0, 1, 2].map((k) => Math.abs(px[i * 4 + k] - bg[k])));
    const seen = new Uint8Array(w * h), stack = [];
    for (let x = 0; x < w; x++) stack.push(x, (h - 1) * w + x);
    for (let y = 0; y < h; y++) stack.push(y * w, y * w + w - 1);
    while (stack.length) {
        const i = stack.pop();
        if (seen[i] || dist(i) > tolerance) continue;
        seen[i] = 1;
        const x = i % w, y = (i - x) / w;
        if (x > 0) stack.push(i - 1);
        if (x < w - 1) stack.push(i + 1);
        if (y > 0) stack.push(i - w);
        if (y < h - 1) stack.push(i + w);
    }
    for (let i = 0; i < w * h; i++) {
        if (seen[i]) px[i * 4 + 3] = 0;
        else {
            // the outer ring of the shape fades: neighbours that are backdrop soften it
            const x = i % w, y = (i - x) / w;
            let n = 0;
            for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
                const nx = x + dx, ny = y + dy;
                if (nx >= 0 && ny >= 0 && nx < w && ny < h && seen[ny * w + nx]) n++;
            }
            if (n) px[i * 4 + 3] = 255 * (1 - n * 0.2);
        }
    }
}

// Fills the masked pixels from their neighbours (repeated averaging), so the plate's baked-in title disappears.
function inpaint(img, mask, rounds = 400) {
    const { w, px } = img;
    const idx = [];
    for (let i = 0; i < mask.length; i++) if (mask[i]) idx.push(i);
    for (const i of idx) for (let k = 0; k < 3; k++) px[i * 4 + k] = 0;
    for (let r = 0; r < rounds; r++) {
        for (const i of idx) {
            for (let k = 0; k < 3; k++) {
                px[i * 4 + k] = (px[(i - 1) * 4 + k] + px[(i + 1) * 4 + k] + px[(i - w) * 4 + k] + px[(i + w) * 4 + k]) / 4;
            }
        }
    }
}

// ---------------------------------------------------------------------------------------------- the textures

// 1. Obsidian background, 1024 x 512: the sheet's map of cracked stone, with a soft vignette at the edges.
{
    const img = cut(76, 1060, 1800, 900, 1024, 512);
    for (let y = 0; y < img.h; y++) {
        for (let x = 0; x < img.w; x++) {
            const nx = (x / (img.w - 1)) * 2 - 1, ny = (y / (img.h - 1)) * 2 - 1;
            const v = 1 - 0.45 * smooth(0.55, 1.25, Math.hypot(nx * 0.9, ny));
            const i = (y * img.w + x) * 4;
            for (let k = 0; k < 3; k++) img.px[i + k] *= v;
            img.px[i + 3] = 255;
        }
    }
    writeTGA("BgMain.tga", img);
}

// 2. Compass medallion, 128 x 128: the sheet's compass, cut round (without the parchment behind it).
{
    const R = 197, cx = 349, cy = 460; // the ring on the sheet
    const pad = 6, side = (R + pad) * 2;
    const img = cut(cx - R - pad, cy - R - pad, side, side, 128, 128);
    const r = (R / side) * 128, c = 64;
    for (let y = 0; y < 128; y++) {
        for (let x = 0; x < 128; x++) {
            const d = Math.hypot(x + 0.5 - c, y + 0.5 - c);
            img.px[(y * 128 + x) * 4 + 3] = 255 * (1 - smooth(r - 1.2, r + 0.4, d));
        }
    }
    writeTGA("LogoMedallion.tga", img);
}

// 3. Ornate title plate, 512 x 128 (the plate is 512 x 106 at the top; the rest is transparent): the sheet's bronze
// plate with griffins, its baked-in title wiped so the addon writes its own.
let plate;
{
    const cw = 1180, ch = 244, w = 512, h = Math.round((ch / cw) * w);
    plate = cut(700, 230, cw, ch, w, h);
    knockOutBackdrop(plate);
    const sx = w / cw, sy = h / ch;
    // the "Consolidate alts" pill hangs under the plate's middle on the sheet: cut away
    for (let y = Math.round(222 * sy); y < h; y++) {
        for (let x = Math.round(380 * sx); x <= Math.round(800 * sx); x++) plate.px[(y * w + x) * 4 + 3] = 0;
    }
    // the stone is cold (blue over red): anything warm inside the title's box is the lettering or its glow
    const mask = new Uint8Array(w * h);
    const [x0, x1, y0, y1] = [318 * sx, 862 * sx, 84 * sy, 170 * sy].map(Math.round);
    for (let y = y0; y <= y1; y++) {
        for (let x = x0; x <= x1; x++) {
            const i = (y * w + x) * 4;
            if (plate.px[i] - plate.px[i + 2] > 4) mask[y * w + x] = 1;
        }
    }
    const grown = new Uint8Array(mask);
    for (let y = y0; y <= y1; y++) {
        for (let x = x0; x <= x1; x++) {
            if (!mask[y * w + x]) continue;
            for (let dy = -3; dy <= 3; dy++) for (let dx = -3; dx <= 3; dx++) grown[(y + dy) * w + x + dx] = 1;
        }
    }
    inpaint(plate, grown, 900);
    const img = blank(512, 128);
    img.px.set(plate.px, 0);
    writeTGA("TitlePlate.tga", img);
}

// 4. Header banner, 1024 x 64: the stone in a dark bronze tone, bronze edges, and the griffin of the plate faint at
// the right end.
{
    const img = cut(76, 1500, 1800, 112, 1024, 64);
    for (let y = 0; y < 64; y++) {
        for (let x = 0; x < 1024; x++) {
            const i = (y * 1024 + x) * 4;
            const v = 0.62 + 0.25 * (1 - y / 63); // lighter at the top
            img.px[i] = img.px[i] * 1.18 * v + 8;
            img.px[i + 1] = img.px[i + 1] * 1.0 * v + 5;
            img.px[i + 2] = img.px[i + 2] * 0.78 * v + 2;
            img.px[i + 3] = 255;
        }
    }
    // griffin: the plate's right end, scaled to the banner's height, at 30 %
    const gw = Math.round(plate.w * (215 / 1180)), scale = 60 / plate.h;
    for (let y = 0; y < 60; y++) {
        for (let x = 0; x < Math.round(gw * scale); x++) {
            const sx = Math.min(plate.w - 1, plate.w - gw + Math.floor(x / scale)), sy = Math.min(plate.h - 1, Math.floor(y / scale));
            const i = (sy * plate.w + sx) * 4;
            const a = (plate.px[i + 3] / 255) * 0.3;
            blendPx(img, 1024 - Math.round(gw * scale) - 4 + x, y + 2, plate.px[i], plate.px[i + 1], plate.px[i + 2], a);
        }
    }
    const line = (y, c, a) => { for (let x = 0; x < 1024; x++) blendPx(img, x, y, c[0], c[1], c[2], a); };
    line(0, [212, 175, 55], 0.55);
    line(61, [40, 32, 18], 1);
    line(62, [212, 175, 55], 0.9);
    line(63, [92, 77, 46], 1);
    writeTGA("HeaderBanner.tga", img);
}

// 5. Gold 9-slice border, 64 x 64 (16 px corners): a fine 2 px burnished gold frame with discreet rivets.
{
    const img = blank(64, 64);
    const gold = (x, y) => {
        const t = (x + y) / 126; // light from the top-left
        const hi = [246, 222, 140], mid = [212, 175, 55], lo = [128, 98, 30];
        return t < 0.5 ? hi.map((c, k) => c + (mid[k] - c) * t * 2) : mid.map((c, k) => c + (lo[k] - c) * (t - 0.5) * 2);
    };
    const frame = subtract(box(32, 32, 28, 28, 2), box(32, 32, 26, 26, 1));
    paintSDF(img, frame, gold, { outline: 1, outlineColor: [20, 16, 8] });
    for (const [cx, cy] of [[8, 8], [56, 8], [8, 56], [56, 56]]) {
        paintSDF(img, circle(cx, cy, 2.2), gold, { outline: 0.8, outlineColor: [30, 22, 8] });
        blendPx(img, cx - 1, cy - 1, 255, 244, 200, 0.8);
    }
    writeTGA("BorderGold9Slice.tga", img);
}

// 6. Status icons, 256 x 64 (four 64 x 64): yellow exclamation, green question mark (turn in), grey lock, gold star.
{
    const img = blank(256, 64);
    const opts = (ox) => ({ ox, outline: 3, shadow: 0.45 });
    // exclamation
    paintSDF(img, union(segment(32, 12, 32, 38, 6), circle(32, 50, 5.5)),
        vgrad([255, 236, 110], [232, 160, 10], 8, 56), opts(0));
    // question mark
    paintSDF(img, union(arc(32, 22, 11, 4.5, Math.PI * 0.95, Math.PI * 2.45), segment(37.5, 31.5, 32, 37, 4.5), circle(32, 50, 5.5)),
        vgrad([140, 245, 150], [34, 160, 70], 8, 56), opts(64));
    // lock
    paintSDF(img, union(box(32, 42, 16, 13, 3), arc(32, 28, 10, 3.5, Math.PI, Math.PI * 2)),
        vgrad([200, 208, 220], [100, 116, 139], 16, 56), opts(128));
    paintSDF(img, union(circle(32, 39, 3.5), segment(32, 40, 32, 47, 2)), () => [30, 34, 44], { ox: 128 });
    // star
    paintSDF(img, star(32, 34, 25, 11), vgrad([255, 236, 140], [212, 150, 30], 9, 58), opts(192));
    writeTGA("StatusIcons.tga", img);
}

// ---------------------------------------------------------------------------------------------- drawn materials

// Value noise and its fractal sum, for parchment, wood and stone.
function hash(x, y, seed) {
    let h = (Math.imul(x, 374761393) + Math.imul(y, 668265263) + Math.imul(seed, 1442695041)) | 0;
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    h ^= h >>> 16;
    return (h >>> 0) / 4294967295;
}
function vnoise(x, y, seed) {
    const xi = Math.floor(x), yi = Math.floor(y), u = smooth(0, 1, x - xi), v = smooth(0, 1, y - yi);
    const a = hash(xi, yi, seed), b = hash(xi + 1, yi, seed), c = hash(xi, yi + 1, seed), d = hash(xi + 1, yi + 1, seed);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}
function fbm(x, y, seed, octaves = 5) {
    let sum = 0, amp = 0.5, freq = 1, norm = 0;
    for (let i = 0; i < octaves; i++) {
        sum += amp * vnoise(x * freq, y * freq, seed + i * 17);
        norm += amp;
        amp *= 0.5;
        freq *= 2;
    }
    return sum / norm;
}
const mix = (a, b, t) => a.map((c, k) => c + (b[k] - c) * t);
const rgb = (s) => [0, 2, 4].map((k) => parseInt(s.slice(k, k + 2), 16));
function setPx(img, x, y, c, a = 255) {
    const i = (y * img.w + x) * 4;
    img.px[i] = c[0]; img.px[i + 1] = c[1]; img.px[i + 2] = c[2]; img.px[i + 3] = a;
}

// Aged parchment with mottled stains and grain (the colors of the maintainer's mockup); `burn` gives it torn, burnt
// edges (irregular, a dark rim with an ember line inside), transparent beyond them. `page`: lighter and calmer, with
// a thinner rim, for a sheet that is read (the quest details).
function parchment(w, h, seed, burn, page) {
    const img = blank(w, h);
    const light = rgb(page ? "F4DDB0" : "E8BF86"), mid = rgb(page ? "EBCF9C" : "D6A46C"), dark = rgb(page ? "DDBB84" : "BE8A50");
    const edge = rgb(page ? "B98A55" : "9A6234");
    const ember = rgb("B5581E"), char = rgb("3A1E0E"), soot = rgb("160B05");
    for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
            const mott = fbm(x / 70, y / 70, seed);
            const stain = fbm(x / 25, y / 25, seed + 5);
            const grain = fbm(x / 3, y / 3, seed + 9, 3) - 0.5;
            let c = mix(dark, mix(mid, light, smooth(0.45, 0.75, mott)), smooth(0.25, 0.6, mott));
            c = mix(c, edge, smooth(0.62, 0.8, stain) * (page ? 0.18 : 0.35)); // tea stains
            c = c.map((v) => v + grain * (page ? 12 : 22));
            let alpha = 255;
            if (burn) {
                // distance to the nearest edge, made ragged by noise
                let d = Math.min(x, w - 1 - x, y, h - 1 - y);
                d += (fbm(x / 26, y / 26, seed + 3) - 0.5) * (page ? 14 : 22) + (fbm(x / 6, y / 6, seed + 4) - 0.5) * 6 - (page ? 3 : 6);
                c = mix(edge, c, smooth(4, page ? 26 : 46, d)); // darker towards the edge
                if (d < 13) c = mix(c, ember, smooth(13, 8, d) * 0.55);
                if (d < 8) c = mix(c, char, smooth(8, 3, d));
                if (d < 3) c = mix(c, soot, smooth(3, 0, d));
                alpha = 255 * smooth(-1.5, 0.5, d);
            } else {
                const d = Math.min(y, h - 1 - y);
                c = mix(edge, c, smooth(0, 6, d));
            }
            setPx(img, x, y, c, alpha);
        }
    }
    return img;
}

// 7. Parchment, 256 x 512: the side panel and the quest drawer's page.
writeTGA("Parchment.tga", parchment(256, 512, 11, true));
writeTGA("ParchmentPage.tga", parchment(256, 512, 13, true, true));
writeTGA("ParchmentPageWide.tga", parchment(1024, 512, 17, true, true)); // the same, for a wide sheet

// 8. Parchment band, 512 x 32: the table's header.
{
    const img = parchment(512, 32, 23, false);
    for (let x = 0; x < 512; x++) setPx(img, x, 31, rgb("5C4D2E"));
    writeTGA("ParchmentBar.tga", img);
}

// 9. Chain node plate, 128 x 64 (9-slice, 16 px corners): dark stone in a beveled metal frame with cut corners.
// NodeGlow, the same outline as a soft white halo (tinted by status in the game).
const plateShape = (w, h, inset, cut) => (x, y) => {
    const qx = Math.abs(x - w / 2) - (w / 2 - inset), qy = Math.abs(y - h / 2) - (h / 2 - inset);
    const boxD = Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0);
    const chamfer = (qx + qy + cut) / Math.SQRT2; // the cut corners
    return Math.max(boxD, chamfer);
};
{
    const W = 128, H = 64, img = blank(W, H);
    const outer = plateShape(W, H, 3, 9), inner = plateShape(W, H, 8, 9);
    for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
            const dOut = outer(x + 0.5, y + 0.5), dIn = inner(x + 0.5, y + 0.5);
            if (dOut > 1) continue;
            const cover = smooth(1, -1, dOut);
            let c;
            if (dIn < 0) {
                const n = fbm(x / 14, y / 14, 41), vein = fbm(x / 5, y / 5, 43, 3);
                c = mix(rgb("1A1E25"), rgb("2A303A"), n);
                c = mix(c, rgb("0E1014"), smooth(0.55, 0.7, vein) * 0.5);
                c = mix(rgb("0B0D10"), c, smooth(0, 5, -dIn)); // inner shadow under the frame
            } else {
                // metal: lit from the top-left, a dark groove in the middle of the band
                const t = (x / W + y / H) / 2;
                c = mix(rgb("8C8F96"), rgb("3E4148"), t);
                const band = Math.min(-dOut, dIn);
                c = mix(c, rgb("23252A"), smooth(1.2, 0, Math.abs(band - 2.5)) * 0.5);
                c = c.map((v) => v + (fbm(x / 4, y / 4, 47, 3) - 0.5) * 30);
            }
            if (dOut > -1) c = mix(c, rgb("0A0A0C"), 0.6); // dark outline
            setPx(img, x, y, c, 255 * cover);
        }
    }
    writeTGA("NodeFrame.tga", img);

    const glow = blank(W, H), shape = plateShape(W, H, 14, 9);
    for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
            const d = shape(x + 0.5, y + 0.5);
            const a = d < 0 ? 0.9 : Math.max(0, 1 - d / 13) ** 2 * 0.9;
            setPx(glow, x, y, [255, 255, 255], 255 * a);
        }
    }
    writeTGA("NodeGlow.tga", glow);
}

// 10. Action buttons, 256 x 64 each (3-slice, 32 px caps): a wooden plate in a bronze frame (primary actions) and a
// dark stone one in an iron frame (the rest), both with four rivets.
function buttonPlate(name, fill, frame, rivet, seed, grainScale) {
    const W = 256, H = 64, img = blank(W, H);
    const outer = plateShape(W, H, 2, 6), inner = plateShape(W, H, 7, 5);
    for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
            const dOut = outer(x + 0.5, y + 0.5), dIn = inner(x + 0.5, y + 0.5);
            if (dOut > 1) continue;
            let c;
            if (dIn < 0) {
                const g = fbm(x / grainScale[0], y / grainScale[1], seed), n = fbm(x / 9, y / 9, seed + 2, 3);
                c = mix(fill[1], fill[0], g * 0.8 + n * 0.2);
                c = mix(c, fill[1], smooth(0.4, 1, y / H) * 0.45); // darker at the bottom
                c = mix(rgb("120C08"), c, smooth(0, 5, -dIn));
            } else {
                c = mix(frame[0], frame[1], y / H);
                if (Math.min(-dOut, dIn) < 1.2) c = mix(c, rgb("0C0A08"), 0.55);
            }
            setPx(img, x, y, c, 255 * smooth(1, -1, dOut));
        }
    }
    for (const [cx, cy] of [[12, 12], [W - 12, 12], [12, H - 12], [W - 12, H - 12]]) {
        paintSDF(img, circle(cx, cy, 3.4), (x, y) => mix(rivet[0], rivet[1], smooth(cy - 3, cy + 3, y)),
            { outline: 1, outlineColor: [20, 14, 10], w: W, h: H });
    }
    writeTGA(name, img);
}
buttonPlate("ButtonWood.tga", [rgb("7A5634"), rgb("3E2814")], [rgb("A07A48"), rgb("5A3E22")], [rgb("E0A878"), rgb("7A4A2A")], 61, [40, 3]);
buttonPlate("ButtonStone.tga", [rgb("2E3139"), rgb("17191E")], [rgb("5B5E66"), rgb("2A2C31")], [rgb("B0A090"), rgb("5A4E44")], 71, [12, 12]);

// 11. Action icons, 320 x 64 (five 64 x 64, glowing): green map pin (waypoint), green chain links, red open book,
// red magnifier (map), red cracked seal (abandon).
{
    const img = blank(320, 64);
    const green = { glow: 7, glowColor: [60, 230, 120], glowAlpha: 0.55, outline: 2, outlineColor: [10, 30, 14] };
    const red = { glow: 7, glowColor: [240, 60, 50], glowAlpha: 0.55, outline: 2, outlineColor: [40, 8, 6] };
    const gFill = vgrad([170, 255, 190], [40, 170, 80], 8, 58), rFill = vgrad([255, 150, 130], [190, 30, 25], 8, 58);
    // pin: a round head on a point, with a hole
    const poly = (pts) => (x, y) => {
        let d = Infinity, s = 1;
        for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
            const [ax, ay] = pts[j], [bx, by] = pts[i];
            const ex = bx - ax, ey = by - ay, wx = x - ax, wy = y - ay;
            const t = Math.max(0, Math.min(1, (wx * ex + wy * ey) / (ex * ex + ey * ey)));
            d = Math.min(d, Math.hypot(wx - ex * t, wy - ey * t));
            const c1 = y >= ay, c2 = y < by, c3 = ex * wy > ey * wx;
            if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s = -s;
        }
        return s * d;
    };
    paintSDF(img, subtract(union(circle(32, 23, 13), poly([[20.5, 29], [43.5, 29], [32, 56]])), circle(32, 23, 5)),
        gFill, { ...green, ox: 0 });
    // chain: two slanted links
    const link = (cx, cy) => subtract(box(cx, cy, 13, 7, 7), box(cx, cy, 7, 2.2, 2.2));
    const rot = (f, cx, cy, a) => (x, y) => {
        const dx = x - cx, dy = y - cy, c = Math.cos(a), s = Math.sin(a);
        return f(cx + dx * c - dy * s, cy + dx * s + dy * c);
    };
    paintSDF(img, union(rot(link(23, 38), 32, 32, -0.78), rot(link(41, 26), 32, 32, -0.78)), gFill, { ...green, ox: 64 });
    // book: two pages and a spine
    const page = (sx) => (x, y) => {
        const local = box(32 + sx * 11, 33, 10, 14, 1.5)(x, y + (sx * (x - 32) > 0 ? Math.abs(x - 32) * 0.12 : 0));
        return local;
    };
    paintSDF(img, subtract(union(page(-1), page(1)), segment(32, 18, 32, 48, 0.8)), rFill, { ...red, ox: 128 });
    // magnifier
    paintSDF(img, union(subtract(circle(27, 27, 14), circle(27, 27, 9)), segment(37, 37, 52, 52, 3.5)), rFill, { ...red, ox: 192 });
    // cracked seal: a ring with an X through it
    paintSDF(img, union(subtract(circle(32, 32, 20), circle(32, 32, 15)), segment(22, 22, 42, 42, 3.2), segment(42, 22, 22, 42, 3.2)),
        rFill, { ...red, ox: 256 });
    writeTGA("ActionIcons.tga", img);
}

// 12. The window's emblem, 256 x 256: the compass, quest icons and progress bar in the jeweled ring (images/originals/
// emblem.jpg), cut out of its black backdrop at 1024 px and brought down to 256 (premultiplied, so no dark fringe).
{
    const big = (() => {
        const r = spawnSync("ffmpeg", ["-loglevel", "error", "-i", join(root, "images", "originals", "emblem.jpg"), "-vf",
            "scale=1024:1024:flags=lanczos", "-f", "rawvideo", "-pix_fmt", "rgba", "-"], { maxBuffer: 1 << 28 });
        if (r.status !== 0) throw new Error(`ffmpeg failed: ${r.stderr}`);
        return { w: 1024, h: 1024, px: new Float32Array(r.stdout) };
    })();
    knockOutBackdrop(big, 26);
    const img = blank(256, 256), f = 4;
    for (let y = 0; y < 256; y++) {
        for (let x = 0; x < 256; x++) {
            let r = 0, g = 0, b = 0, a = 0;
            for (let dy = 0; dy < f; dy++) {
                for (let dx = 0; dx < f; dx++) {
                    const i = ((y * f + dy) * 1024 + x * f + dx) * 4, al = big.px[i + 3] / 255;
                    r += big.px[i] * al; g += big.px[i + 1] * al; b += big.px[i + 2] * al; a += al;
                }
            }
            const o = (y * 256 + x) * 4;
            if (a > 0) { img.px[o] = r / a; img.px[o + 1] = g / a; img.px[o + 2] = b / a; }
            img.px[o + 3] = (a / (f * f)) * 255;
        }
    }
    writeTGA("Emblem.tga", img);
}

// ---------------------------------------------------------------------------------------------- the quest tree's pieces
// From the maintainer's sheets in images/originals (tree_frames, tree_halo, tree_connectors, tree_sigil), all on black.

// A region of an image, fitted into w x h (aspect kept, centered, black around it; or stretched to it), as RGBA.
function fit(file, x, y, cw, ch, w, h, stretch) {
    const r = spawnSync("ffmpeg", ["-loglevel", "error", "-i", join(root, "images", "originals", file), "-vf",
        stretch ? `crop=${cw}:${ch}:${x}:${y},scale=${w}:${h}:flags=lanczos`
            : `crop=${cw}:${ch}:${x}:${y},scale=${w}:${h}:force_original_aspect_ratio=decrease:flags=lanczos,` +
            `pad=${w}:${h}:(ow-iw)/2:(oh-ih)/2:black`, "-f", "rawvideo", "-pix_fmt", "rgba", "-"], { maxBuffer: 1 << 28 });
    if (r.status !== 0) throw new Error(`ffmpeg failed: ${r.stderr}`);
    return { w, h, px: new Float32Array(r.stdout) };
}

// 13. Node frames, 256 x 256 each (9-slice, 56 px corners): iron (available / in the log), bronze (done), rusty iron
// in chains (locked), polished gold (selected). Their stone panel stays; the black around them goes.
for (const [name, box] of [["NodeIron", [42, 67, 430, 390]], ["NodeBronze", [555, 69, 423, 386]],
    ["NodeLocked", [30, 552, 456, 430]], ["NodeGold", [550, 564, 434, 405]]]) {
    const img = fit("tree_frames.png", box[0] - 2, box[1] - 2, box[2] + 4, box[3] + 4, 256, 256);
    knockOutBackdrop(img, 24);
    writeTGA(`${name}.tga`, img);
}

// 14. Node halo, 512 x 256 (9-slice, 64 px corners): a white glow around the frame's shape, drawn additively (black
// adds nothing) and tinted by status in the game.
{
    const img = fit("tree_halo.png", 97, 49, 830, 409, 512, 256);
    for (let i = 0; i < img.w * img.h; i++) {
        const v = Math.max(img.px[i * 4], img.px[i * 4 + 1], img.px[i * 4 + 2]);
        img.px[i * 4] = img.px[i * 4 + 1] = img.px[i * 4 + 2] = v;
        img.px[i * 4 + 3] = 255;
    }
    writeTGA("NodeHalo.tga", img);
}

// 15. Rails, 512 x 32, seamless left to right (the last 48 px fade into the first ones): iron with green runes (the
// path walked) and plain iron (what is ahead). Drawn tiled along each connection.
function rail(name, x, y, cw, ch) {
    const F = 48, W = 512;
    const src = fit("tree_connectors.png", x, y, cw, ch, W + F, 32, true); // the bar alone, filling the height
    const img = blank(W, 32);
    for (let yy = 0; yy < 32; yy++) {
        for (let xx = 0; xx < W; xx++) {
            const o = (yy * W + xx) * 4, a = (yy * (W + F) + xx) * 4;
            for (let k = 0; k < 3; k++) {
                const c = src.px[a + k];
                img.px[o + k] = xx < F ? c * (xx / F) + src.px[(yy * (W + F) + W + xx) * 4 + k] * (1 - xx / F) : c;
            }
            img.px[o + 3] = 255;
        }
    }
    writeTGA(name, img);
}
rail("RailRunes.tga", 70, 37, 880, 36);
rail("RailIron.tga", 70, 194, 880, 52);

// 16. The connections' gem (at their bends) and arrowhead (into a quest), 64 x 64, cut out of the black.
for (const [name, box] of [["RailGem", [71, 314, 120, 121]], ["RailArrow", [480, 343, 65, 103]]]) {
    const img = fit("tree_connectors.png", box[0] - 3, box[1] - 3, box[2] + 6, box[3] + 6, 64, 64);
    knockOutBackdrop(img, 24);
    writeTGA(`${name}.tga`, img);
}

// 17. The runic sigil behind the tree, 512 x 512, drawn additively (black adds nothing).
{
    const img = fit("tree_sigil.png", 0, 0, 1024, 1024, 512, 512);
    for (let i = 0; i < img.w * img.h; i++) img.px[i * 4 + 3] = 255;
    writeTGA("TreeSigil.tga", img);
}
