# Beneos i18n Translation Matrix, Runbook

Self-contained guide for a future context (human or AI) that needs to understand, use, or extend the Beneos controlled-vocabulary translation system. You do NOT need the rest of the project to work with this; everything required is here.

## What this is

`common/beneos_i18n.json` is a single translation matrix for the **controlled vocabulary** used across the Beneos asset databases: the short, repeated tag values such as biomes, spell schools, creature types, item rarities, casting times, and so on. It does NOT translate per-asset names or descriptions (those are thousands of unique strings and are out of scope here).

It is consumed by all three Beneos surfaces that read the public database at `https://www.beneos-database.com/data/`:
- the Foundry module search,
- the Shopify webshop theme,
- any future search/UI.

One file, one fetch, shared truth. Public URL once uploaded: `https://www.beneos-database.com/data/common/beneos_i18n.json` (CORS is open, `Access-Control-Allow-Origin: *`).

## Structure

```jsonc
{
  "id": "beneos_i18n",
  "version": "1.0.0",
  "locales": [ ...13 Beneos languages... ],   // full target set
  "filled":  ["en","de","fr","pt-BR"],          // locales actually populated today (launch tier)
  "field_map": { "<domain>.<dbField>": "<matrixDomain>.<category>", ... },
  "domains": {
    "<matrixDomain>": {
      "<category>": {
        "<CANONICAL ENGLISH VALUE>": { "en": "...", "de": "...", "fr": "...", "pt-BR": "..." },
        ...
      }
    }
  }
}
```

- **Keys are the canonical English DB values after consolidation** (see "Consolidation" below). For lowercase DB values (creature types like `beast`, item origins like `occult`) the key stays the raw lowercase value and `en` carries the proper display form (`Beast`, `Occult`).
- **`field_map`** tells a consumer which matrix category a given DB property maps to. Note two DB fields share one matrix category: `battlemap.biom` and `token.biom` both resolve to `common.biome` (biomes mean the same in both domains).
- **Fallback order** for a lookup: requested locale, then `en`, then the raw key itself. Never show an empty string.

### Lookup contract (pseudocode)
```
function localizeLabel(domainField, value, locale):
    catPath = field_map[domainField]            // e.g. "token.type" -> "token.creature_type"
    term = domains[catPath.domain][catPath.cat][value]
    return term?[locale] ?? term?["en"] ?? capitalize(value)
```

## Sources (which DB fields feed which category)

| DB file | property | matrix category |
|---|---|---|
| battlemaps | `biom[]` | common.biome |
| battlemaps | `type` | battlemap.type |
| battlemaps | `brightness` | battlemap.brightness |
| battlemaps | `adventure[]` | battlemap.adventure |
| tokens | `biom[]` | common.biome |
| tokens | `type[]` | token.creature_type |
| tokens | `fightingstyle[]` | token.fighting_style |
| tokens | `purpose[]` | token.purpose |
| tokens | `movement[]` | token.movement |
| tokens | `size` | token.size |
| tokens | `source` | token.source |
| spells | `school` | spell.school |
| spells | `spell_type` | spell.spell_type |
| spells | `casting_time` | spell.casting_time |
| spells | `classes[]` | spell.class |
| items | `rarity` | item.rarity |
| items | `item_type` | item.item_type |
| items | `origin` | item.origin |

Excluded on purpose: numeric fields (level, cr, tier, price, stats, grid), `components` (V/S/M), `concentration`/`ritual`/`attunement` booleans, proper-name fields (`pack`, `faction`, `campaign`), and `hidden_tags` (freeform search keywords, see "Open follow-ups").

## Translation rules (must follow when extending)

1. **Official D&D 5e terminology** for rules terms, per language, NOT literal translation. This applies to: `spell.school`, `spell.casting_time`, `spell.class`, `token.size`, `token.creature_type` (the standard types), `item.rarity`, and `battlemap.adventure` (use the official localized module titles). Examples already in the file: Conjuration -> de "Beschwörung" / fr "Invocation" / pt-BR "Conjuração"; Bonus Action -> de "Bonusaktion"; Sorcerer -> de "Zauberer" / fr "Ensorceleur" / pt-BR "Feiticeiro"; Very Rare -> de "Sehr selten". Beneos-coined terms (fighting styles, purposes, spell types, item origins, the `Musclemancy` school) get sensible descriptive translations.
2. **No em-dashes or en-dashes** (`—` `–`) anywhere, in any language. Ordinary hyphens for compounds are fine.
3. **Plural forms / locale grammar**: keep terms as the natural singular noun/label per language.
4. Every term object should carry `en` plus all locales listed in `filled`. Locales not in `filled` are omitted and resolved by fallback.

## Consolidation (why the DB was cleaned first)

The raw DB had inconsistent tags (plurals, casing, misspellings, one structural bug) that would have produced split/duplicate translation keys. Before building the matrix, a cleanup pass canonicalized the source DB JSONs. Highlights of the 2026-05-29 pass:
- battlemaps `biom`: `Exteriour` -> `Exterior` (911x), `Interiour` -> `Interior` (613x); `brightness` `dark` -> `Dark`.
- tokens: ~15 biome case/plural fixes, fighting-style/purpose/movement casing, sizes `medium/large/...` -> `Medium/Large/...`.
- spells `classes`: comma-joined compound strings (one array element holding a whole class list) were split into individual class values; `Sorcer` -> `Sorcerer`; casting_time `Minute` -> `1 Minute`.
- items: `Veryrare` -> `Very Rare` (73x), `Spellfocus` -> `Spell Focus`, origin `techno_arcane` -> `technoarcane`, `dwarven_forged` -> `dwarvenforged` (matches the Codex origin slugs).

The matrix keys are the POST-consolidation canonical values. If you re-run consolidation, the matrix keys must track the new canonical values.

## Tools in this repo

- `collect_vocab.cjs` (repo root): scans the four DB files, prints distinct values + counts per category, and a duplicate-suspicion heuristic (normalized-key collisions + Levenshtein-near pairs). Use it to discover what needs consolidating and to list the canonical vocabulary. Run: `node collect_vocab.cjs`.
- `apply_i18n_consolidation.cjs` (repo root): applies a hardcoded rename map (and the spells `classes` split) to the four DB JSONs via surgical, formatting-preserving string replacement. Idempotent. Backs each file up to `*.pre_i18n_<date>.json` once. Run: `node apply_i18n_consolidation.cjs <YYYY-MM-DD>`.

Both are plain Node (`.cjs`), chosen over PowerShell because the tokens DB is non-standard-formatted (`:  ` double-space) and a full JSON reparse would reformat the whole file; surgical text replacement keeps diffs to the changed values only.

## How to re-run when NEW tags are added (the important part)

Whenever new releases add new tag values (new biomes, a new creature type, a new item_type, etc.), do this:

1. **Collect**: `node collect_vocab.cjs`. Read the per-category lists and the `!! norm-collisions` / `?? near` hints.
2. **Decide consolidation**: for any new value that is a plural/case/spelling variant of an existing canonical value, add a `raw -> canonical` entry to the `RENAMES` map in `apply_i18n_consolidation.cjs` (under the right file). For new structural bugs (e.g. comma-joined lists) extend the special-case logic. Do NOT merge values that are genuinely distinct.
3. **Apply**: `node apply_i18n_consolidation.cjs <today>`. Confirm the printed report and that the four JSONs still parse.
4. **Translate**: add a matrix entry for every NEW canonical value to `common/beneos_i18n.json`, under the category given by `field_map`. Follow the translation rules above (official D&D terms; no em-dashes; en + all `filled` locales). Bump `version`.
5. **Verify coverage**: re-run a coverage check (every distinct DB value in a translated field must have a matrix entry). The check used on 2026-05-29 confirmed 380 pairs, 0 missing.
6. **Upload together**: FTP the corrected DB JSON files AND the updated `beneos_i18n.json` to `…/data/` in the SAME deploy, so the live DB values and the matrix keys stay consistent. Uploading only one of them breaks the lookup.

## Open follow-ups (not done yet, by design)

- `hidden_tags` (freeform search keywords, e.g. items has 229 distinct) are NOT in the matrix yet. They still contain dupes like `dreams`/`dream`. Translating/consolidating them is a future pass.
- `battlemap.biom` is effectively a 127-value tag cloud mixing true biomes with descriptors (Day, Night, Horror, Gore, Holy...). All are translated, but a future content pass could split it into a clean biome taxonomy plus a separate descriptor facet.
- `item.item_type` still contains specific weapon names (Longsword, Rapier, Maul...) alongside true type categories. All are translated; reclassifying the specific items is a content decision for later.
- The 9 non-launch locales (es, it, pt-PT, pl, cs, ca, ja, ko, zh-TW) are not yet populated; lookups fall back to en. Add them by filling each term object and extending `filled`.
- Item origins map to the module's Codex Origins, which are independently translated in the module `lang/*.json` under `BENEOS.Codex.Origins.<slug>.Name`. Keep the two in sync when possible.

## Consumers (where the lookup is implemented)

- Webshop theme: `assets/beneos-db.js` (function `localizeLabel`) in the `beneos_shopify_theme` repo.
- Foundry module: currently uses `#capitalize` on raw values; wiring it to this matrix is a planned follow-up.
