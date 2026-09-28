// Uso: node tools/wowhead.mjs            -> genera Completao!!/Data/Generated/Forever.lua
// Descarga (con cache en tools/cache/ y pausa entre peticiones) las quests de las instancias
// nuevas de Forever desde Wowhead: lista de la zona + ficha de cada quest (nivel, requisito,
// facción, NPC que la da, serie/cadena).
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const CACHE = join(here, "cache");
const OUT = join(here, "..", "Completao!!", "Data", "Generated", "Forever.lua");
const DELAY_MS = 1500;
const UA = "Mozilla/5.0 (Completao addon data tool; personal use)";

// id de entrada del addon -> zona de Wowhead + quests extra que no estan en la categoria de la zona
const INSTANCES = JSON.parse(readFileSync(join(here, "forever_instances.json"), "utf8"));

mkdirSync(CACHE, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function get(kind, id) {
    const file = join(CACHE, `${kind}${id}.html`);
    if (existsSync(file)) return readFileSync(file, "utf8");
    await sleep(DELAY_MS);
    const res = await fetch(`https://www.wowhead.com/forever/${kind}=${id}`, { headers: { "User-Agent": UA } });
    if (!res.ok) throw new Error(`${kind}=${id}: HTTP ${res.status}`);
    const html = await res.text();
    writeFileSync(file, html);
    return html;
}

function extractArray(text, startIdx) {
    let depth = 0, inStr = false, esc = false;
    for (let i = startIdx; i < text.length; i++) {
        const c = text[i];
        if (inStr) {
            if (esc) esc = false;
            else if (c === "\\") esc = true;
            else if (c === '"') inStr = false;
        } else if (c === '"') inStr = true;
        else if (c === "[") depth++;
        else if (c === "]" && --depth === 0) return text.slice(startIdx, i + 1);
    }
    throw new Error("array sin cerrar");
}

function zoneQuests(html) {
    const at = html.indexOf("id: 'quests'");
    if (at < 0) return [];
    const dataAt = html.indexOf("data: [", at);
    return JSON.parse(extractArray(html, dataAt + "data: ".length));
}

function parseQuestPage(html, id) {
    const info = html.match(/WH\.markup\.printHtml\("(\[ul\].*?)", "infobox-contents-0"/s)?.[1] ?? "";
    const num = (re) => Number(info.match(re)?.[1]) || undefined;
    const side = info.includes("icon-alliance") && info.includes("icon-horde") ? undefined
        : info.includes("icon-alliance") ? "Alliance" : info.includes("icon-horde") ? "Horde" : undefined;
    const start = info.match(/Start: \[url=\\?\/forever\\?\/npc=\d+[^\]]*\]([^\[]+)\[/)?.[1];
    const name = html.match(/g_pageInfo = \{[^}]*"name":"((?:[^"\\]|\\.)*)"/)?.[1];
    const series = [];
    const table = html.match(/<table class="series">(.*?)<\/table>/s)?.[1];
    if (table) {
        for (const row of table.split("</tr>")) {
            const link = row.match(/quest=(\d+)\//);
            series.push(link ? Number(link[1]) : row.includes("<b>") ? id : null);
        }
    }
    // texto: objetivo (entre </h1> y la lista de iconos) y descripcion (seccion "Description")
    const clean = (s) => s
        .replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]+>/g, "")
        .replace(/&nbsp;/g, " ").replace(/&quot;/g, '"').replace(/&#0?39;/g, "'")
        .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
        .replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
    let objective = html.match(/<\/h1>(.*?)(?:<table class="icon-list">|<h2)/s)?.[1];
    if (objective && objective.length > 800) objective = undefined;
    const desc = html.match(/<h2 class="heading-size-3">Description<\/h2>(.*?)<h2/s)?.[1];

    // ubicaciones: bloque "new Mapper({...})" con los puntos de inicio/fin (por id de area)
    const locs = {};
    const mapperAt = html.indexOf("new Mapper(");
    if (mapperAt >= 0) {
        try {
            const from = html.indexOf("{", mapperAt);
            let depth = 0, inStr = false, esc = false, end = from;
            for (; end < html.length; end++) {
                const c = html[end];
                if (inStr) { if (esc) esc = false; else if (c === "\\") esc = true; else if (c === '"') inStr = false; }
                else if (c === '"') inStr = true;
                else if (c === "{") depth++;
                else if (c === "}" && --depth === 0) break;
            }
            const mapper = JSON.parse(html.slice(from, end + 1));
            for (const [area, z] of Object.entries(mapper.objectives ?? {})) {
                for (const p of (z.levels ?? []).flat()) {
                    if ((p.point === "start" || p.point === "end") && !locs[p.point] && p.coord) {
                        locs[p.point] = { npc: p.name, area: Number(area), x: p.coord[0], y: p.coord[1] };
                    }
                }
            }
        } catch { /* sin ubicacion */ }
    }

    return {
        objective: objective && clean(objective) || undefined,
        desc: desc && clean(desc) || undefined,
        start: locs.start,
        finish: locs.end,
        name: name && JSON.parse(`"${name}"`),
        level: num(/Level: (\d+)/),
        minLevel: num(/Requires level (\d+)/),
        type: info.match(/Type: ([A-Za-z ]+)\[/)?.[1],
        faction: side,
        giver: start?.trim(),
        series: series.filter((x) => x !== null),
    };
}

const luaStr = (s) => `"${String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n")}"`;

const out = ['local _, ns = ...', "", "-- GENERADO por tools/wowhead.mjs. No editar a mano: usar Data/Overrides.lua.", ""];

for (const [entryId, cfg] of Object.entries(INSTANCES)) {
    const listed = [];
    for (const zone of cfg.zones) listed.push(...zoneQuests(await get("zone", zone)));
    const ids = new Set([...listed.map((q) => q.id), ...(cfg.extra ?? [])]);
    const sideOf = { 1: "Alliance", 2: "Horde" };
    const fromList = new Map(listed.map((q) => [q.id, q]));

    // La serie de una quest puede incluir quests que no estan en la zona: se anaden.
    const details = new Map();
    const queue = [...ids];
    while (queue.length) {
        const id = queue.shift();
        if (details.has(id)) continue;
        const d = parseQuestPage(await get("quest", id), id);
        details.set(id, d);
        for (const s of d.series) if (!ids.has(s)) { ids.add(s); queue.push(s); }
    }

    // Cadenas cuyos pasos se llaman igual: se numeran ("Unending Torment (2/5)") para distinguirlos.
    const original = new Map([...details].map(([id, d]) => [id, d.name]));
    for (const [id, d] of details) {
        const names = d.series.map((s) => original.get(s));
        const idx = d.series.indexOf(id);
        if (d.series.length > 1 && idx >= 0 && new Set(names).size < names.length && d.name) {
            d.name = `${original.get(id)} (${idx + 1}/${d.series.length})`;
        }
    }

    out.push(`ns.AddQuests(${luaStr(entryId)}, {`);
    for (const id of [...ids].sort((a, b) => a - b)) {
        const d = details.get(id), l = fromList.get(id);
        const idx = d.series.indexOf(id);
        const prev = idx > 0 ? d.series[idx - 1] : undefined;
        const f = [`id = ${id}`, `name = ${luaStr(d.name ?? l?.name ?? "Quest " + id)}`];
        const level = d.level ?? l?.level, minLevel = d.minLevel ?? l?.reqlevel;
        if (level) f.push(`level = ${level}`);
        if (minLevel) f.push(`minLevel = ${minLevel}`);
        if (prev) f.push(`requires = { ${prev} }`);
        const faction = d.faction ?? sideOf[l?.side];
        if (faction) f.push(`faction = ${luaStr(faction)}`);
        const giver = d.giver ?? d.start?.npc;
        if (giver) f.push(`giver = ${luaStr(giver)}`);
        const loc = (l) => `{ npc = ${luaStr(l.npc)}, area = ${l.area}, x = ${l.x}, y = ${l.y} }`;
        if (d.start) f.push(`start = ${loc(d.start)}`);
        if (d.finish) f.push(`finish = ${loc(d.finish)}`);
        if (d.objective) f.push(`objective = ${luaStr(d.objective)}`);
        if (d.desc) f.push(`desc = ${luaStr(d.desc)}`);
        out.push(`    { ${f.join(", ")} }, -- ${d.type ?? "?"}${l ? "" : " (extra/serie)"}`);
    }
    out.push("})", "");
    console.log(`${entryId}: ${ids.size} quests (${listed.length} en la zona de Wowhead)`);
}

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, out.join("\n"));
console.log("escrito", OUT);
