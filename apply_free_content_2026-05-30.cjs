/* ============================================================
   Beneos Database : free_content flag + tokens cleanup
   Surgical, format-preserving raw-text edits (no reparse -> no
   reformat), in the spirit of apply_i18n_consolidation.cjs.
   - Inserts properties.free_content (true for curated free list,
     else false) into items / spells / tokens.
   - Tokens also: delete 25 orphan SRD tokens, fix 13 nb_variants.
   Each file is backed up to *.pre_free_content_<date>.json first.
   Run:  node apply_free_content_2026-05-30.cjs [YYYY-MM-DD]
   ============================================================ */
'use strict';
const fs = require('fs');

const date = process.argv[2] || '2026-05-30';
const base = 'J:/Beneos_Webservice/Online_Search/beneos-database/';

// ---- curated free lists (true); everything else -> false ----
const TOKENS_TRUE = [
  '044-amygdalyan', '154-awakened_armor', '182-barmaid', '215-beast_of_soot_and_sulphur',
  '171-blazing_skull', '000-month_16_cathedral_knight', '177-cult_possessed',
  '000-month_16_deathrite_bellringer', '000-month_24_elder_lindwurm', '145-ghoul_bonegnawer',
  '193-grave_golem', '193-gravestones', '122-gutterfist', '213-hellracer_boarding_imp',
  '158-infernal_immolator', '194-knight_unmounted', '224-krampus', '169-mummy_tomb_vizier',
  '196-orc_chieftain', '184-rot_cerf', '161-sodden_cavalier', '144-tactician',
  '129-undead_archer', '212-uvargandr', '211-uvargandr_stormscalecluster'
];
// NOTE: list has '0051_predatory_adaptation' but the live key is
// '0051_predatory_adaption' (DB spelling). Mapped to the live key here.
const SPELLS_TRUE = [
  '0024_rats', '0026_detonate', '0032_profane_parrot', '0035_relive', '0038_grand_entrance',
  '0046_fist_of_iron', '0051_predatory_adaption', '0059_festering_truth', '0063_burning_zeal',
  '0064_hope_devourer', '0075_dying_breath', '0085_chosen_thrall', '0094_curse_mark',
  '0115_background_music', '0119_illgotten_gains', '0100_stormspear'
];
const ITEMS_TRUE = [
  '0055_awoken_huskblade', '0058_bascinet_of_ancient_tactica', '0059_bottlesnatcher_imp',
  '0091_dark_promise', '0049_foremans_flask', '0068_magmatic_molasses', '0097_potion_of_healing',
  '0097_potion_of_superior_healing', '0097_potion_of_supreme_healing', '0084_reefs_splendour',
  '0003_shamblevault_coffin', '0054_slumbering_huskblade', '0098_sphinx_key',
  '0062_three_feather_tricorne', '0094_trench_digger'
];

// ---- tokens cleanup lists (from apply_cleanup_and_free_content.ps1) ----
const TOKENS_ORPHANS = [
  '000-srd_airship', '000-srd_arcane_eye', '000-srd_arcane_hand', '000-srd_arcane_sword',
  '000-srd_dancing_lights_medium', '000-srd_dancing_lights_tiny', '000-srd_flaming_sphere',
  '000-srd_floating_disk', '000-srd_floating_whip', '000-srd_guardian_of_faith',
  '000-srd_huge_animated_object', '000-srd_illusory_creature', '000-srd_illusory_object',
  '000-srd_illusory_phenomenon', '000-srd_invisible_sensor', '000-srd_keelboat',
  '000-srd_large_animated_object', '000-srd_longship', '000-srd_medium_animated_object',
  '000-srd_rowboat', '000-srd_sailing_ship', '000-srd_secret_chest',
  '000-srd_small_animated_object', '000-srd_unseen_servant', '000-srd_warship'
];
const TOKENS_VARIANT_FIXES = [
  { key: '000-month_20_shade_tyrant', actual: 2 },
  { key: '000-month_26_cloud_zone', actual: 3 },
  { key: '000-srd_kraken', actual: 1 },
  { key: '000-srd_zombie', actual: 1 },
  { key: '159-vampire_chiropterror', actual: 1 },
  { key: '181-frost_wretch', actual: 2 },
  { key: '198-gnoll_fleshtaker', actual: 1 },
  { key: '206-unhinged_mimic', actual: 3 },
  { key: '220-corrupted_champion', actual: 3 },
  { key: '222-vampire_Roadstalker', actual: 2 },
  { key: '226-swarm_of_stirges', actual: 1 },
  { key: '228-greater_earth_elemental', actual: 2 },
  { key: '229-gravegrasper', actual: 2 }
];

// ---- helpers ----
function esc(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }

function backup(path) {
  const bak = path.replace(/\.json$/, '.pre_free_content_' + date + '.json');
  if (!fs.existsSync(bak)) { fs.copyFileSync(path, bak); console.log('  backup: ' + bak); }
  else console.log('  backup exists, kept: ' + bak);
}

// Find the offset of the matching close brace for the '{' at openIdx,
// respecting JSON string literals (so braces inside strings are ignored).
function matchBrace(text, openIdx) {
  let depth = 0, inStr = false;
  for (let i = openIdx; i < text.length; i++) {
    const c = text[i];
    if (inStr) {
      if (c === '\\') { i++; continue; }
      if (c === '"') inStr = false;
    } else {
      if (c === '"') inStr = true;
      else if (c === '{') depth++;
      else if (c === '}') { depth--; if (depth === 0) return i; }
    }
  }
  throw new Error('unbalanced braces from ' + openIdx);
}

// Delete a full entry block. Handles both a middle entry (drop its line +
// trailing comma) and the last entry in its container (drop the preceding
// comma instead, so no trailing comma remains). Idempotent: missing -> no-op.
function deleteEntry(text, key) {
  const m = new RegExp('"' + esc(key) + '"\\s*:\\s*\\{').exec(text);
  if (!m) { console.log('  (skip, already gone: ' + key + ')'); return text; }
  const lineStart = text.lastIndexOf('\n', m.index) + 1; // start of the dict-key line
  const braceOpen = text.indexOf('{', m.index);
  const braceClose = matchBrace(text, braceOpen);
  // look at the first non-whitespace char after the close brace
  let n = braceClose + 1;
  while (n < text.length && /\s/.test(text[n])) n++;
  if (text[n] === ',') {
    // middle entry: remove [line .. trailing comma + newline]
    let end = n + 1;
    if (text[end] === '\r') end++;
    if (text[end] === '\n') end++;
    return text.slice(0, lineStart) + text.slice(end);
  }
  // last entry: remove [preceding comma .. close brace]
  let p = lineStart - 1;
  while (p >= 0 && /\s/.test(text[p])) p--;
  if (text[p] !== ',') throw new Error('expected preceding comma before last entry ' + key);
  return text.slice(0, p) + text.slice(braceClose + 1);
}

// Fix a scalar property value scoped to one entry. Idempotent: missing -> no-op.
function fixScalar(text, key, prop, value) {
  const re = new RegExp('("' + esc(key) + '"\\s*:\\s*\\{[\\s\\S]*?"' + esc(prop) + '"\\s*:\\s*)\\d+');
  if (!re.test(text)) { console.log('  (skip fix, not found: ' + key + '.' + prop + ')'); return text; }
  return text.replace(re, '$1' + value);
}

// Insert properties.free_content as the FIRST property, in document order,
// in a single forward pass (O(n)). keys must be in document order.
function insertFreeContent(text, keys, trueSet) {
  const propRe = /"properties"\s*:([ \t]*)\{(\r?\n)([ \t]*)/g;
  let out = '';
  let cursor = 0;
  let skipped = 0;
  for (const key of keys) {
    const keyRe = new RegExp('"' + esc(key) + '"\\s*:\\s*\\{', 'g');
    keyRe.lastIndex = cursor;
    const km = keyRe.exec(text);
    if (!km) throw new Error('entry not found in order: ' + key);
    propRe.lastIndex = km.index;
    const pm = propRe.exec(text);
    if (!pm) throw new Error('properties block not found: ' + key);
    const insertAt = pm.index + pm[0].length; // right before first child
    // idempotency: skip if free_content is already the first property
    if (text.startsWith('"free_content"', insertAt)) { skipped++; continue; }
    const colonSp = pm[1], nl = pm[2], indent = pm[3];
    const bool = trueSet.has(key.toLowerCase()) ? 'true' : 'false';
    const ins = '"free_content":' + colonSp + bool + ',' + nl + indent;
    out += text.slice(cursor, insertAt) + ins;
    cursor = insertAt;
  }
  out += text.slice(cursor);
  if (skipped) console.log('  (skipped ' + skipped + ' entries already having free_content)');
  return out;
}

function processFile(rel, opts) {
  const path = base + rel;
  console.log('\n=== ' + rel + ' ===');
  backup(path);
  let text = fs.readFileSync(path, 'utf8');
  const original = text;

  // case-insensitive key resolver against the live DB keys
  const liveKeys = Object.keys(JSON.parse(text).content);
  const lcMap = new Map(liveKeys.map(k => [k.toLowerCase(), k]));
  const resolve = k => lcMap.get(k.toLowerCase()) || k;

  // structural cleanup (tokens only)
  if (opts.orphans) {
    for (const k of opts.orphans) text = deleteEntry(text, resolve(k));
    console.log('  deleted orphans: ' + opts.orphans.length);
  }
  if (opts.variantFixes) {
    for (const f of opts.variantFixes) text = fixScalar(text, resolve(f.key), 'nb_variants', f.actual);
    console.log('  nb_variants fixed: ' + opts.variantFixes.length);
  }

  // free_content insertion
  const data = JSON.parse(text); // post-cleanup structure, for doc-order keys
  const allKeys = Object.keys(data.content);
  const onlySet = opts.onlyKeys ? new Set(opts.onlyKeys.map(k => k.toLowerCase())) : null;
  const targetKeys = onlySet ? allKeys.filter(k => onlySet.has(k.toLowerCase())) : allKeys;
  const trueSet = new Set(opts.trueList.map(k => k.toLowerCase()));
  text = insertFreeContent(text, targetKeys, trueSet);
  console.log('  free_content inserted into ' + targetKeys.length + ' entries');

  // atomic write (preserve LF + trailing newline already in `text`)
  if (text === original) { console.log('  no change'); return; }
  const tmp = path + '.tmp';
  fs.writeFileSync(tmp, text);
  fs.renameSync(tmp, path);
  console.log('  written.');
}

// ---- run ----
// 1) Items: only the 4 entries currently missing the field (all false).
processFile('items/beneos_items_database.json', {
  trueList: ITEMS_TRUE,
  onlyKeys: ['0138_false_idol', '0136_spear_of_truth', '0135_scryepatch', '0134_defiance_injector']
});
// 2) Spells: all entries.
processFile('spells/beneos_spells_database.json', { trueList: SPELLS_TRUE });
// 3) Tokens: cleanup + all surviving entries.
processFile('tokens/beneos_tokens_database_v2.json', {
  trueList: TOKENS_TRUE,
  orphans: TOKENS_ORPHANS,
  variantFixes: TOKENS_VARIANT_FIXES
});

console.log('\nDone.');
