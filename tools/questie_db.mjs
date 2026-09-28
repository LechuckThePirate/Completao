// Reader of Questie's baked Forever database (AddOns/QuestieDB/QuestieDB_Forever.toc): the data lives in the
// TOC's metadata lines as base64 CBOR (QuestieDB/src/read/baked.lua describes the format). Point QUESTIEDB_TOC
// at the .toc if Questie is installed somewhere else. Exposes quest(id), npc(id), item(id), object(id) as
// { fieldIndex: value } (indexes as in QuestieDB/src/meta/*Meta.lua), allIds(kind) and tocDir.
import { readFileSync } from "node:fs";
import { inflateSync } from "node:zlib";

const TOC = process.env.QUESTIEDB_TOC
    || "D:/Games/World of Warcraft/_classic_beta_/Interface/AddOns/QuestieDB/QuestieDB_Forever.toc";
const store = new Map();
for (const line of readFileSync(TOC, "utf8").split(/\r?\n/)) {
    const m = line.match(/^## (X-[^:]+): (.*)$/);
    if (m) store.set(m[1], m[2]);
}

// reassembles "~N~" chunked values (X-key holds "~N~", X-key-1..N the parts)
function stored(key) {
    const v = store.get(key);
    if (v === undefined) return undefined;
    const c = v.match(/^~(\d+)~$/);
    if (!c) return v;
    let out = "";
    for (let i = 1; i <= Number(c[1]); i++) out += store.get(`${key}-${i}`) ?? "";
    return out;
}

function cbor(buf) {
    let p = 0;
    const read = () => {
        const b = buf[p++], major = b >> 5, info = b & 31;
        let n = info;
        if (info === 24) n = buf[p++];
        else if (info === 25) { n = buf.readUInt16BE(p); p += 2; }
        else if (info === 26) { n = buf.readUInt32BE(p); p += 4; }
        else if (info === 27) { n = Number(buf.readBigUInt64BE(p)); p += 8; }
        switch (major) {
            case 0: return n;
            case 1: return -1 - n;
            case 2: { const s = buf.toString("utf8", p, p + n); p += n; return s; }
            case 3: { const s = buf.toString("utf8", p, p + n); p += n; return s; }
            case 4: { const a = []; for (let i = 0; i < n; i++) a.push(read()); return a; }
            case 5: { const o = {}; for (let i = 0; i < n; i++) { const k = read(); o[k] = read(); } return o; }
            case 6: return read();
            default:
                if (info === 20) return false;
                if (info === 21) return true;
                if (info === 22 || info === 23) return null;
                if (info === 25) { // half-precision float (16 bits): sign, 5-bit exponent, 10-bit mantissa
                    const sign = n & 0x8000 ? -1 : 1, exp = (n >> 10) & 31, mant = n & 1023;
                    if (exp === 0) return sign * 2 ** -14 * (mant / 1024);
                    if (exp === 31) return mant ? NaN : sign * Infinity;
                    return sign * 2 ** (exp - 15) * (1 + mant / 1024);
                }
                if (info === 26) return buf.readFloatBE(p - 4);
                if (info === 27) return buf.readDoubleBE(p - 8);
                return null;
        }
    };
    return read();
}
const decode = (b64) => cbor(Buffer.from(b64, "base64"));

const KINDS = {
    Quest: { prefix: "Quest-", fields: 36 },
    Npc: { prefix: "Npc-", fields: 15 },
    Item: { prefix: "Item-", fields: 16 },
    Object: { prefix: "Object-", fields: 7 },
};

export function allIds(kind) {
    const b64 = stored(`X-${KINDS[kind].prefix}IDS`);
    // the ID header is deflate-compressed CBOR
    return cbor(inflateSync(Buffer.from(b64, "base64")));
}

// one entity as { fieldIndex: value } (scalars from the row, tables from their own keys); cached
const cache = new Map();
export function entity(kind, id) {
    const ck = `${kind}:${id}`;
    if (cache.has(ck)) return cache.get(ck);
    const k = KINDS[kind];
    const rowB64 = stored(`X-${k.prefix}${id}-S`);
    let out = null;
    if (rowB64 !== undefined) {
        out = { ...decode(rowB64) };
        for (let f = 1; f <= k.fields; f++) {
            const t = stored(`X-${k.prefix}${id}-${f}`);
            if (t !== undefined) out[f] = decode(t);
        }
    }
    cache.set(ck, out);
    return out;
}
export const tocDir = TOC.replace(/[\\/][^\\/]+$/, "");

// A Lua table keyed by numbers that happen to be 1, 2, 3... is stored as a CBOR array, so a zone map like
// { [1] = {...} } (Dun Morogh) arrives as [ {...} ]. Returns a { key: value } map with Lua's 1-based keys.
export function keyed(x) {
    if (!x) return {};
    if (!Array.isArray(x)) return x;
    const out = {};
    x.forEach((v, i) => { if (v != null) out[i + 1] = v; });
    return out;
}
export const quest = (id) => entity("Quest", id);
export const npc = (id) => entity("Npc", id);
export const item = (id) => entity("Item", id);
export const object = (id) => entity("Object", id);
export { store, stored };
