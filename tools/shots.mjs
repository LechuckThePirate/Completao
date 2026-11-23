// Cuts the CurseForge page's screenshots out of the ones /completao shots took in game.
//
//   1. In game:   /completao shots [entry id]      (don't touch anything until it says it is done)
//   2. In game:   /reload                          (writes the list of what each screenshot shows into the saved variables)
//   3. Here:      node tools/shots.mjs
//
// It reads the list ("name|time|left|top|right|bottom": which part of the screen each view covers, as fractions) from
// WTF/Account/<account>/SavedVariables/Completao.lua, matches each line to the screenshot the game wrote right after
// it (the first one not used, taken at that time or later), crops it with ffmpeg and saves it as
// images/screencaps/<name>.png.
//
// Options:  --wow "<folder of the client>"   (default D:\Games\World of Warcraft\_forever_)
//           --out <folder>                   (default images/screencaps)
//           --only a,b                       (just those names)
//           --keep                           (leave the client's screenshots alone; by default they are not deleted either)
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const option = (name, fallback) => {
    const i = args.indexOf(name);
    return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};
const wow = option("--wow", "D:\\Games\\World of Warcraft\\_forever_");
const out = option("--out", join(root, "images", "screencaps"));
const only = option("--only", "") ? option("--only", "").split(",") : null;

// the saved variables of any account
const accounts = join(wow, "WTF", "Account");
let saved;
for (const account of existsSync(accounts) ? readdirSync(accounts) : []) {
    const file = join(accounts, account, "SavedVariables", "Completao.lua");
    if (existsSync(file) && (!saved || statSync(file).mtimeMs > statSync(saved).mtimeMs)) saved = file;
}
if (!saved) throw new Error(`No Completao.lua in ${accounts}: run /completao shots in game, then /reload`);
const shots = [...readFileSync(saved, "utf8").matchAll(/"([a-z_0-9]+)\|(\d+)\|([\d.]+)\|([\d.]+)\|([\d.]+)\|([\d.]+)"/g)]
    .map((m) => ({ name: m[1], time: Number(m[2]), rect: m.slice(3, 7).map(Number) }));
if (!shots.length) throw new Error("The saved variables hold no shots: run /completao shots in game, then /reload");

// the client's screenshots, oldest first
const folder = join(wow, "Screenshots");
const files = readdirSync(folder)
    .filter((f) => /\.(png|jpe?g|tga)$/i.test(f))
    .map((f) => ({ path: join(folder, f), mtime: Math.floor(statSync(join(folder, f)).mtimeMs / 1000) }))
    .sort((a, b) => a.mtime - b.mtime);

mkdirSync(out, { recursive: true });
const used = new Set();
let done = 0;
for (const shot of shots) {
    if (only && !only.includes(shot.name)) continue;
    const file = files.find((f) => !used.has(f.path) && f.mtime >= shot.time - 1);
    if (!file) {
        console.log(`${shot.name}: no screenshot found after it was taken`);
        continue;
    }
    used.add(file.path);
    const probe = spawnSync("ffprobe", ["-v", "error", "-show_entries", "stream=width,height", "-of", "csv=p=0", file.path]);
    const [width, height] = probe.stdout.toString().trim().split(",").map(Number);
    const [l, t, r, b] = shot.rect;
    const x = Math.floor(l * width), y = Math.floor(t * height);
    const w = Math.max(2, Math.ceil(r * width) - x), h = Math.max(2, Math.ceil(b * height) - y);
    const target = join(out, `${shot.name}.png`);
    const run = spawnSync("ffmpeg", ["-loglevel", "error", "-y", "-i", file.path, "-vf", `crop=${w}:${h}:${x}:${y}`, "-frames:v", "1", target]);
    if (run.status !== 0) {
        console.log(`${shot.name}: ffmpeg failed: ${run.stderr}`);
        continue;
    }
    console.log(`${shot.name}.png  ${w}x${h}  (from ${file.path.split(/[\\/]/).pop()})`);
    done++;
}
console.log(`${done} of ${shots.length} done -> ${out}`);
