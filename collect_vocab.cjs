const fs = require('fs');
const base = 'J:/Beneos_Webservice/Online_Search/beneos-database/';
const files = {
  battlemap: 'battlemaps/beneos_battlemaps_database.json',
  token: 'tokens/beneos_tokens_database_v2.json',
  spell: 'spells/beneos_spells_database.json',
  item: 'items/beneos_items_database.json'
};
// which property fields are controlled vocabulary per domain
const FIELDS = {
  battlemap: ['biom', 'type', 'brightness', 'adventure', 'hidden_tags'],
  token: ['biom', 'type', 'fightingstyle', 'purpose', 'movement', 'size', 'source', 'faction', 'campaign', 'hidden_tags'],
  spell: ['school', 'spell_type', 'casting_time', 'classes', 'hidden_tags'],
  item: ['rarity', 'item_type', 'origin', 'hidden_tags']
};
const SKIP_VALUES = new Set(['None', 'none', '', null, undefined]);

// counts[domain][field][value] = n
const counts = {};
for (const [kind, rel] of Object.entries(files)) {
  const json = JSON.parse(fs.readFileSync(base + rel, 'utf8'));
  const content = json.content || {};
  counts[kind] = {};
  for (const f of FIELDS[kind]) counts[kind][f] = {};
  for (const key of Object.keys(content)) {
    const props = (content[key] && content[key].properties) || {};
    for (const f of FIELDS[kind]) {
      let v = props[f];
      if (v == null) continue;
      const arr = Array.isArray(v) ? v : [v];
      for (let val of arr) {
        if (typeof val !== 'string') val = String(val);
        val = val.trim();
        if (SKIP_VALUES.has(val)) continue;
        counts[kind][f][val] = (counts[kind][f][val] || 0) + 1;
      }
    }
  }
}

// normalization for duplicate detection
function norm(s) {
  return s.toLowerCase().replace(/\s+/g, ' ').trim()
    .replace(/iour\b/g, 'ior')   // exteriour->exterior
    .replace(/s\b/g, '');         // naive de-plural
}
function lev(a, b) {
  a = a.toLowerCase(); b = b.toLowerCase();
  const m = [];
  for (let i = 0; i <= b.length; i++) m[i] = [i];
  for (let j = 0; j <= a.length; j++) m[0][j] = j;
  for (let i = 1; i <= b.length; i++) for (let j = 1; j <= a.length; j++)
    m[i][j] = b[i-1] === a[j-1] ? m[i-1][j-1] : Math.min(m[i-1][j-1], m[i][j-1], m[i-1][j]) + 1;
  return m[b.length][a.length];
}

const out = {};
let summary = '';
for (const kind of Object.keys(counts)) {
  out[kind] = {};
  for (const f of Object.keys(counts[kind])) {
    const entries = Object.entries(counts[kind][f]).sort((a, b) => b[1] - a[1]);
    out[kind][f] = entries;
    if (!entries.length) continue;
    // suspected dupes within this field
    const vals = entries.map(e => e[0]);
    const groups = {};
    vals.forEach(v => { const n = norm(v); (groups[n] = groups[n] || []).push(v); });
    const normDupes = Object.values(groups).filter(g => g.length > 1);
    const levPairs = [];
    for (let i = 0; i < vals.length; i++) for (let j = i + 1; j < vals.length; j++) {
      const d = lev(vals[i], vals[j]);
      if (d > 0 && d <= 2 && Math.abs(vals[i].length - vals[j].length) <= 3) levPairs.push([vals[i], vals[j], d]);
    }
    const hideList = f === 'hidden_tags';
    summary += '\n[' + kind + '.' + f + ']  distinct=' + entries.length + '\n';
    if (!hideList) {
      summary += '  values: ' + entries.map(e => e[0] + '(' + e[1] + ')').join(', ') + '\n';
    } else {
      summary += '  (hidden_tags: ' + entries.length + ' distinct; top20: ' + entries.slice(0, 20).map(e => e[0] + '(' + e[1] + ')').join(', ') + ')\n';
    }
    if (normDupes.length) summary += '  !! norm-collisions: ' + JSON.stringify(normDupes) + '\n';
    if (levPairs.length) summary += '  ?? near (lev<=2): ' + levPairs.slice(0, 25).map(p => p[0] + '~' + p[1]).join(', ') + '\n';
  }
}
fs.writeFileSync(base + '.vocab.json', JSON.stringify(out, null, 0));
// merged biome view across battlemap+token
const bSet = {};
['battlemap', 'token'].forEach(k => Object.entries(counts[k].biom || {}).forEach(([v, n]) => bSet[v] = (bSet[v] || 0) + n));
summary += '\n[MERGED biome battlemap+token] distinct=' + Object.keys(bSet).length + '\n  ' + Object.entries(bSet).sort((a,b)=>b[1]-a[1]).map(e=>e[0]+'('+e[1]+')').join(', ') + '\n';
console.log(summary);
console.log('\n(raw distinct+counts written to .vocab.json)');
