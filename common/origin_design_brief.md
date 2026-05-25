# Design Brief: Origin Set-Bonus Info Window

**Audience:** Claude Design (handover document — designer comes in cold, does not know the Beneos ecosystem).
**Status:** Data complete. Layout open.
**Companion file:** [`origins.json`](./origins.json) — all data structured for direct consumption.
**Sample asset:** [`origin_design_brief_assets/vampiric.webp`](./origin_design_brief_assets/vampiric.webp) — one representative origin icon (see §6).

---

## 1. Product Context

The window lives inside the **Beneos Cloud search engine** (a browser-based search UI used by tabletop RPG game masters to find and import Beneos animated tokens, items, spells and battlemaps). The overall visual language of the cloud was defined in a previous design pass under "Beneos Cloud.html" — the same look & feel applies here.

Inside the search engine there is (or will be) an **info button** that opens this window. Its purpose is to introduce players and game masters to the **Origin mechanic** behind Beneos Loot — a system unique to Beneos that does not exist in standard Dungeons & Dragons. Users opening this window may be:

- experienced D&D players who have never heard of "Origins"
- existing Beneos customers who want a reference for the set-bonus rules
- prospective customers being onboarded to the loot system for the first time

The window therefore needs to do two jobs at once: **sell the concept** (this is cool, this is collectible) and **serve as a reference** (here are the actual rules for all 19 Origins).

---

## 2. The Origin Mechanic — Concept

Every magic item in the Beneos Loot library belongs to one of **19 Origins** — flavour-and-mechanic categories such as *Vampiric*, *Dwarvenforged*, *Awoken*, *Feywoven*, *Mutation*, *Technoarcane*. An Origin is more than a flavour tag: it describes where the item's power comes from (vampiric blood-magic, dwarven craftsmanship, fey weaving, occult pacts, …) and it ties the item into a **collectible set-bonus system**.

When a player is attuned to **two or more items sharing the same Origin**, the items begin to **resonate with each other**. Each Origin has three escalating set-bonus tiers:

| Tier | Required | Vibe |
|---|---|---|
| **Echo of Origin** | granted by a single attuned item of that Origin | a flavorful baseline ability |
| **Resonance** | active when 2+ attuned items share the Origin | a stronger, signature ability |
| **Perfect Harmony** | active when 3+ attuned items share the Origin | a powerful, defining capstone |

Several Origins also have **Special** entries (e.g. *Vampiric: Ritual of Ascension* or *Vampiric: Sanguine Rites*) — additional rule cards that extend the basic three tiers (see [`origins.json`](./origins.json) → `origins.<slug>.tiers.specials`).

This is the central pitch: **the more themed loot a player collects, the more their character becomes shaped by that theme**.

---

## 3. The Tier System — Detail

The complete canonical rule text is in [`origins.json`](./origins.json) → `mechanic_rules` (verbatim from the rulebook). The most important rules to surface in the UI:

### 3.1 Generic vs Named items
> *Items whose name consists only of their Origin and base item (for example, "Vampiric Longsword +1") are considered **Generic Items**. Generic items always grant the Echo of Origin feature of their respective Origin. Items with a unique name (such as "Griefplate") are considered **Named Items**. Named items possess an Origin but do not grant the Echo of Origin feature on their own.*

→ Important UX implication: even a "boring" +1 magic item with an Origin still pulls its weight in the set-bonus economy. Named items carry their own item-specific abilities instead, but still count as Origin items for the purpose of unlocking Resonance and Harmony.

### 3.2 Set Bonus definition
> *A Set Bonus is any benefit gained from being attuned to two or more items of the same Origin at the same time. Dormant items still count toward determining whether a Set Bonus is active, as long as you remain attuned to them.*

### 3.3 Rarity Modifier
Many Origin rules scale by item rarity. Rarity Modifier: Common 1, Uncommon 2, Rare 3, Very Rare 4, Legendary 5.

### 3.4 Two special keywords
- **Dormant** — a magically inert item that still counts toward set bonuses but cannot be actively used as a focus.
- **Grandeur** — an effect that only activates when every attuned item of that Origin is Very Rare or Legendary.

### 3.5 Ritual of Ascension
A meta-mechanic: sacrificing three Very-Rare+ items of one Origin transforms the player's character into a creature matching that Origin (e.g. Feywoven → Fey, Occult → Undead) and permanently grants the Echo/Resonance/Harmony as inherent abilities. Heavy stuff — only some Origins have a Ritual of Ascension variant (Vampiric, Feywoven, Infernal, Occult — see `tiers.specials` per origin).

### 3.6 Sensing Items
A passive "treasure radar" tied to the same Echo/Resonance/Harmony tiers: the more items of an Origin you wear, the further and more precisely you can sense other items of that Origin. Useful flavour beat worth surfacing.

→ All five rule blocks above are available verbatim in `origins.json` → `mechanic_rules` (`i`, `keywords`, `ritual_of_ascension`, `sensing_items`). The designer should choose which to display front-and-center vs hide behind a disclosure.

---

## 4. How players collect & combine — narrative beat

The emotional arc the window should support:

1. **Discovery** — "Oh, this longsword is *Vampiric*. What does that mean?"
2. **Awareness** — "Wait, the boots I already have are also Vampiric…"
3. **Reward** — "I just unlocked the Resonance tier."
4. **Pursuit** — "What would happen if I got a third Vampiric item to harmony? And what *are* the other Origins?"

The window is the bridge between step 1 and step 4. It should make a player **want** to go hunt for matching items, not just inform them about a rules system.

---

## 5. Open Requirements for the Designer

Stated as **goals**, not as layout. The designer has full freedom on form (grid, list, tabs, accordion, modal-in-modal, card-flip, scrollable codex, side-panel, …).

**Must:**
- Convey the Origin concept to a first-time visitor in the first screen they see (no required scrolling to understand "what is an Origin").
- Present an **overview of all 19 Origins** with at minimum: icon, display name, short lore blurb.
- Allow **drill-down to each Origin's tiers** — Echo, Resonance, Harmony, plus any Specials. All texts must be reachable; the designer picks the disclosure pattern (click-to-expand, hover-preview, side-panel, dedicated detail view, etc.).
- Surface the **Generic-vs-Named rule** somewhere clearly — it is the most common source of player confusion.
- Use **English** for all user-facing copy. Quoted texts in `origins.json` are already English and should be used verbatim.
- Visually match the **Beneos Cloud** design language established in the previous design pass (same palette, typography, button language, panel chrome, glow accents — the designer knows this look).

**Should:**
- Feel **gamified and collectible** — closer in tone to a Diablo / Destiny / Genshin set-bonus codex than to a sterile rules wiki.
- Communicate **escalation** between Echo → Resonance → Harmony (e.g. via colour, intensity, badge tier, or unlock metaphor).
- Acknowledge that some Origins have **bonus content** (Specials) without making them feel like footnotes.

**Out of scope (do not design):**
- The Beneos search engine itself (already designed).
- Per-Item presentation (Named items each have their own bonus — that is a separate item-card design, not part of this window).
- In-game tracking of "what items has the player collected so far?" — that lives in the Foundry VTT module and is not part of this UI.
- Translations into the 13 Beneos languages — happens after UI strings are finalised.

---

## 6. Visual Assets

Every Origin has a dedicated **illustrated icon** rendered in the same painted, slightly grungy fantasy-emblem style. Two variants exist per Origin:

- **Color version** — primary, used in active/selected states.
- **Black-and-white version** — for inactive, locked, or unfocused states (the source files exist; the designer may alternatively rely on CSS desaturation if preferred).

This brief ships with **one sample only** — [`origin_design_brief_assets/vampiric.webp`](./origin_design_brief_assets/vampiric.webp) — as a stylistic reference. **Assume the remaining 18 icons exist in the exact same style** (they do; their filenames are listed per-origin in `origins.json` → `icon_filename` and `icon_filename_bw`). The full icon set lives at `J:\Beneos_Adventures\Publishing\Item_Cards\beneos_card_creator_v1\source\icons_origin\` and will be wired in at build time.

---

## 7. Data Reference

All data lives in [`origins.json`](./origins.json), schema:

```jsonc
{
  "mechanic_rules": {
    "i":                    { "title", "rules", "source_key" },  // Generic/Named, Set Bonus, Rarity Mod
    "keywords":             { ... },                              // Dormant, Grandeur
    "ritual_of_ascension":  { ... },                              // meta-mechanic
    "sensing_items":        { ... }                               // treasure-radar mechanic
  },
  "origins": {
    "<slug>": {
      "slug":             "vampiric",
      "display_name":     "Vampiric",
      "icon_filename":    "vampiric.webp",
      "icon_filename_bw": "vampiric_blackwhite.webp",
      "lore":             "...short concept blurb (one sentence)...",
      "tiers": {
        "echo":      { "title", "lore", "rules", "rarity", "source_key" } | null,
        "resonance": [ { ...same shape... } ],   // ARRAY — some origins have I + II
        "harmony":   { ...same shape... } | null,
        "specials":  [ { "type", "title", "lore", "rules", "rarity", "source_key" } ]
      }
    }
  },
  "anomalies": [ "ancient: missing Echo tier" ]   // see §7.2
}
```

### 7.1 Field semantics

| Field | What it is | How to use it |
|---|---|---|
| `display_name` | Human-readable origin name | Headline / tab label |
| `lore` | One-sentence concept blurb (English) | Tooltip / overview-card description |
| `icon_filename` / `icon_filename_bw` | Filename only, no path | The build system resolves the path; designer just references the filename |
| `tiers.<tier>.title` | E.g. "Vampiric: Echo of Origin" | Section heading inside the detail view |
| `tiers.<tier>.lore` | Flavour text for the tier | Italic intro under the heading |
| `tiers.<tier>.rules` | The actual gameplay rules text | Main body of the tier card — uses `**bold**` and `__italic__` markdown |
| `tiers.<tier>.rarity` | Common / Uncommon / Rare / Very Rare | Render as a rarity chip (matches the rest of Beneos rarity styling) |
| `tiers.specials[].type` | e.g. `ritual_of_ascension`, `sanguine_rites`, `dark_bond` | Special badge / sub-section label |

### 7.2 Known data anomalies (callouts for the designer)

- **`ancient`** has no Echo tier in the source (only Resonance + Harmony). The UI must either hide the Echo slot for this Origin or display a graceful placeholder.
- **`awoken`** has two Resonance entries (`Resonance I` and `Resonance II`). Schema models `tiers.resonance` as an array specifically to accommodate this.
- **Slug ↔ icon filename overrides** (already resolved in JSON, no action needed — just be aware): `dwarvenforged → dwarven_forged.webp`, `giantforged → giant_forged.webp`, `technoarcane → techno_arcane.webp`.
- **`crystalline`** B/W variant is misspelled in the source as `crystaline_blackwhite.webp` (single L). The JSON points at the correct existing file; cosmetic source-side typo.

### 7.3 The 19 Origins (for quick orientation)

`ancient`, `arcane`, `awoken`, `beastforged`, `blessed`, `crystalline`, `druidic`, `dwarvenforged`, `elemental`, `feywoven`, `giantforged`, `infernal`, `mutation`, `occult`, `primordial`, `relic`, `sanctified`, `technoarcane`, `vampiric`.

---

## 8. Regenerating the dataset

`origins.json` was built by [`_build_origins_json.ps1`](./_build_origins_json.ps1) (lives next to this brief). Re-running it merges the two upstream sources again — useful if either source changes:

- `J:\Beneos_Webservice\Online_Search\beneos-database\common\beneos_common_database.json` (origin lore)
- `J:\Beneos_Adventures\Publishing\Item_Cards\beneos_card_creator_v1\items.json` (tier rules)

Designer does not need to run it; engineering will keep it fresh.
