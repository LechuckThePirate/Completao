// Usage: node tools/cmangos_rewards.mjs --flavor vanilla|tbc <dump.sql>
// Generates Data/<Flavor>/Generated/Rewards.lua (ns.REWARDS) for the quests of that client's data. Questie's databases
// carry no item rewards, so they come from the open cmangos databases (github.com/cmangos/classic-db and tbc-db, GPL-3.0;
// the dump in Full_DB, gunzipped): items, choices, money and experience. The reputation comes from Questie's database of
// the client, as the quests themselves (set QUESTIEDB_TOC to its QuestieDB_<Flavor>.toc, see questie_db.mjs). Run
// questie_gen.mjs first: only the quests already in Data/ get a row.
import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { quest } from "./questie_db.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const CHOICES = 6, ITEMS = 4;
// the client's name in the files and the folders that hold its quests
const FLAVORS = {
    vanilla: { name: "Vanilla", label: "Classic", questDirs: ["Data/Classic", "Data/Vanilla/Generated"] },
    tbc: { name: "TBC", label: "TBC", questDirs: ["Data/Classic", "Data/TBC", "Data/TBC/Generated"] },
};
const flagAt = process.argv.indexOf("--flavor");
const FLAVOR = FLAVORS[process.argv[flagAt + 1]];
const dump = process.argv[flagAt + 2];
if (flagAt < 0 || !FLAVOR || !dump) throw new Error("usage: node tools/cmangos_rewards.mjs --flavor vanilla|tbc <dump.sql>");

// the rows of a table of a mysqldump, as { column: value }
function tableRows(sql, table) {
    const start = sql.indexOf(`CREATE TABLE \`${table}\``);
    if (start < 0) throw new Error(`no table ${table} in the dump`);
    const cols = [...sql.slice(start, sql.indexOf(") ENGINE", start)).matchAll(/^\s*`(\w+)`/gm)].map((m) => m[1]);
    const rows = [];
    const tag = `INSERT INTO \`${table}\` VALUES `;
    let pos = 0;
    while ((pos = sql.indexOf(tag, pos)) >= 0) {
        let p = pos + tag.length;
        for (;;) {
            while (sql[p] === "," || sql[p] === "\n" || sql[p] === "\r" || sql[p] === " ") p++;
            if (sql[p] !== "(") break;
            p++;
            const row = {};
            for (let c = 0; ; c++) {
                if (sql[p] === "'") {
                    let s = "";
                    p++;
                    while (sql[p] !== "'") {
                        if (sql[p] === "\\") p++;
                        s += sql[p++];
                    }
                    p++;
                    row[cols[c]] = s;
                } else {
                    let q = p;
                    while (sql[q] !== "," && sql[q] !== ")") q++;
                    const t = sql.slice(p, q);
                    row[cols[c]] = t === "NULL" ? null : Number(t);
                    p = q;
                }
                if (sql[p] === ",") p++;
                else { p++; break; }
            }
            rows.push(row);
        }
        pos = p;
    }
    return rows;
}

// the ids of the quests in the addon's data of the client
function questIds() {
    const ids = new Set();
    for (const dir of FLAVOR.questDirs) {
        for (const f of readdirSync(join(ROOT, dir))) {
            if (!f.endsWith(".lua") || f === "Rewards.lua") continue;
            for (const m of readFileSync(join(ROOT, dir, f), "utf8").matchAll(/\{ id = (\d+), name = /g)) ids.add(Number(m[1]));
        }
    }
    return ids;
}

// The dump has no experience column: the server derives it from the money a quest gives at the top level instead
// (0.6 copper per point up to level 60: it matches the experience the web lists for the classic quests).
const MONEY_PER_XP = { 61: 1.2, 62: 2.4, 63: 3.6, 64: 4.8 };
function xpOf(row) {
    if (row.RewMoneyMaxLevel <= 0) return 0;
    const level = row.QuestLevel;
    const rate = level >= 65 ? 6 : MONEY_PER_XP[level] ?? 0.6;
    return Math.ceil(row.RewMoneyMaxLevel / rate);
}

function itemList(row, idCol, countCol, n) {
    const list = [];
    for (let i = 1; i <= n; i++) {
        const id = row[idCol + i];
        if (id > 0) list.push(row[countCol + i] > 1 ? `{ ${id}, ${row[countCol + i]} }` : `${id}`);
    }
    return list;
}

function rewardLine(row) {
    const parts = [];
    const items = itemList(row, "RewItemId", "RewItemCount", ITEMS);
    const choice = itemList(row, "RewChoiceItemId", "RewChoiceItemCount", CHOICES);
    if (items.length) parts.push(`items = { ${items.join(", ")} }`);
    if (choice.length) parts.push(`choice = { ${choice.join(", ")} }`);
    // a negative amount is money the quest asks for, not a reward
    if (row.RewOrReqMoney > 0) parts.push(`money = ${row.RewOrReqMoney}`);
    const xp = xpOf(row);
    if (xp > 0) parts.push(`xp = ${xp}`);
    const rep = (quest(row.entry)?.[26] ?? []).filter((r) => r[1]);
    if (rep.length) parts.push(`rep = { ${rep.map((r) => `{ ${r[0]}, ${r[1]} }`).join(", ")} }`);
    return parts.length ? `    [${row.entry}] = { ${parts.join(", ")} },` : null;
}

const known = questIds();
const lines = tableRows(readFileSync(dump, "utf8"), "quest_template")
    .filter((row) => known.has(row.entry))
    .sort((a, b) => a.entry - b.entry)
    .map(rewardLine)
    .filter(Boolean);

const out = `local _, ns = ...

-- GENERATED by tools/cmangos_rewards.mjs from the cmangos ${FLAVOR.label} database and Questie's ${FLAVOR.name} database. Do not edit by hand.
-- [questID] = { items = fixed, choice = to choose from ({ id, count } when more than 1), money = copper,
--               xp = experience, rep = { { faction, value } } }
ns.REWARDS = {
${lines.join("\n")}
}
`;
writeFileSync(join(ROOT, `Data/${FLAVOR.name}/Generated/Rewards.lua`), out);
console.log(`${lines.length} rewards of ${known.size} quests`);
