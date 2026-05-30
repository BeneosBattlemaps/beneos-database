/* ============================================================
   Beneos Database : tag consolidation pass (pre-i18n cleanup)
   Surgical, value-scoped, formatting-preserving replacements on
   the raw JSON text (no reparse -> no reformat). Idempotent.
   Run: node apply_i18n_consolidation.cjs <YYYY-MM-DD>
   See common/BENEOS_I18N_README.md for the why + how-to-rerun.
   ============================================================ */
const fs = require('fs');
const date = process.argv[2] || 'nodate';
const base = 'J:/Beneos_Webservice/Online_Search/beneos-database/';

// Per-file simple value renames (exact quoted JSON string token "raw" -> "canonical").
// Only coined misspellings, plural and case dupes. NO taxonomy restructuring.
const RENAMES = {
  'battlemaps/beneos_battlemaps_database.json': {
    'Exteriour': 'Exterior',
    'Interiour': 'Interior',
    'dark': 'Dark'
  },
  'tokens/beneos_tokens_database_v2.json': {
    // biom case + plural
    'urban': 'Urban', 'dungeon': 'Dungeon', 'sacral': 'Sacral', 'civilized': 'Civilized',
    'mountain': 'Mountain', 'volcano': 'Volcano', 'lair': 'Lair', 'sky': 'Sky',
    'wasteland': 'Wasteland', 'castle': 'Castle', 'coast': 'Coast', 'forest': 'Forest',
    'ruins': 'Ruin', 'swamp': 'Swamp', 'wilderness': 'Wilderness',
    // fightingstyle case
    'tactical': 'Tactical', 'shock': 'Shock', 'charge': 'Charge', 'mobile': 'Mobile',
    'pack': 'Pack', 'ambush': 'Ambush', 'predator': 'Predator',
    // purpose case (only where a Capitalized canonical already exists)
    'damage': 'Damage', 'debuff': 'Debuff', 'leader': 'Leader', 'support': 'Support',
    // movement case
    'walk': 'Walk', 'fly': 'Fly', 'climb': 'Climb',
    // size case
    'medium': 'Medium', 'large': 'Large', 'huge': 'Huge', 'small': 'Small',
    'tiny': 'Tiny', 'gargantuan': 'Gargantuan'
  },
  'spells/beneos_spells_database.json': {
    'Sorcer': 'Sorcerer',
    'Minute': '1 Minute'
  },
  'items/beneos_items_database.json': {
    'Veryrare': 'Very Rare',
    'Spellfocus': 'Spell Focus',
    'techno_arcane': 'technoarcane',
    'dwarven_forged': 'dwarvenforged'
  }
};

// spells classes: comma-joined compound elements -> split + Capitalize.
// Exact compound strings observed in the data (each replaced by a quoted, comma-separated list).
const CLASS_COMPOUNDS = [
  'bard,druid,ranger,sorcerer,warlock,wizard',
  'bard,cleric,druid,paladin,ranger,sorcerer,warlock',
  'bard, druid, ranger, sorcerer, warlock, wizard',
  'bard, cleric, druid, paladin, ranger, sorcerer, warlock, wizard',
  'bard, cleric, druid, paladin, sorcerer, warlock, wizard',
  'bard, cleric, paladin'
];
function cap(s) { s = s.trim(); return s.charAt(0).toUpperCase() + s.slice(1); }
function reEsc(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }

const report = { date: date, files: {} };
for (const [rel, map] of Object.entries(RENAMES)) {
  const path = base + rel;
  let txt = fs.readFileSync(path, 'utf8');
  // backup once
  const bak = path.replace(/\.json$/, '.pre_i18n_' + date + '.json');
  if (!fs.existsSync(bak)) fs.writeFileSync(bak, txt);
  const fileRep = {};
  // classes compound split (spells only)
  if (rel.indexOf('spells') !== -1) {
    for (const comp of CLASS_COMPOUNDS) {
      const parts = comp.split(',').map(cap);
      const replacement = parts.map(p => '"' + p + '"').join(', ');
      const reC = new RegExp('"' + reEsc(comp) + '"', 'g');
      const n = (txt.match(reC) || []).length;
      if (n) { txt = txt.replace(reC, replacement); fileRep['[split] ' + comp] = n; }
    }
  }
  // simple quoted-token renames
  for (const [raw, canon] of Object.entries(map)) {
    const re = new RegExp('"' + reEsc(raw) + '"', 'g');
    const n = (txt.match(re) || []).length;
    if (n) { txt = txt.replace(re, '"' + canon + '"'); fileRep[raw + ' -> ' + canon] = n; }
  }
  fs.writeFileSync(path, txt);
  report.files[rel] = fileRep;
}
fs.writeFileSync(base + '.consolidation-report.json', JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
