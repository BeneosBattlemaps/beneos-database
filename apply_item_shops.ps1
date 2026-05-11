# Adds a new properties.shop array field to every item in
# items\beneos_items_database.json. Each shop value is one of 14 snake_case
# keys (healer, black_market, tavern, magic_shop, alchemist, weapon_shop,
# blacksmith, armorer, tailor, temple, traveling_merchant, gunsmith,
# crafting_guild, thieves_guild). Items can appear in multiple shops.
#
# Default = Dry-Run (writes nothing, prints distribution + samples).
# Pass -Apply to write the file (with backup).
#
# Plan: C:\Users\Beneos\.claude\plans\beneos-items-database-json-dies-ist-die-quirky-eagle.md

[CmdletBinding()]
param(
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $MyInvocation.MyCommand.Path
$today = Get-Date -Format 'yyyy-MM-dd'
$dbPath     = Join-Path $root 'items\beneos_items_database.json'
$backupPath = Join-Path $root ("items\beneos_items_database.pre_shop_field_$today.json")

# --- Helper from apply_cleanup_and_free_content.ps1 (lines 74-80) ---
function Get-IndentSize {
    param([string]$Path)
    foreach ($line in Get-Content -LiteralPath $Path -TotalCount 8) {
        if ($line -match '^( +)\S') { return $Matches[1].Length }
    }
    return 2
}

# --- All known shop keys (14) ---
$AllShops = @(
    'healer','black_market','tavern','magic_shop','alchemist',
    'weapon_shop','blacksmith','armorer','tailor','temple',
    'traveling_merchant','gunsmith','crafting_guild','thieves_guild'
)

# --- Build the shop[] array for one item ---
function Get-ShopsForItem {
    param(
        [string]$Key,
        [string]$Name,
        [string]$ItemType,
        [string]$Origin,
        [string]$Rarity,
        [double]$Price
    )

    $isSrd      = $Key.StartsWith('0000_srd_')
    $itLower    = $ItemType.ToLower()
    $nameLower  = $Name.ToLower()
    $rarityNorm = ($Rarity.ToLower() -replace '\s','')
    $orig       = $Origin.ToLower()
    $shops      = New-Object System.Collections.Generic.HashSet[string]

    # --- Originals are magical by definition ---
    if (-not $isSrd) {
        [void]$shops.Add('magic_shop')
    }

    # --- Step 1: item_type defaults ---
    # Firearm detection (priority over generic weapon)
    $isFirearm = ($itLower -match 'pistol|musket|firearm|flintlock') -or
                 ($nameLower -match '\b(pistol|musket|flintlock|firearm|gun|revolver)\b')

    if ($itLower -match 'armor') {
        [void]$shops.Add('armorer')
        if ($itLower -match 'heavy|plate|medium') { [void]$shops.Add('blacksmith') }
    }
    elseif ($itLower -eq 'shield') {
        [void]$shops.Add('armorer'); [void]$shops.Add('blacksmith')
    }
    elseif ($isFirearm) {
        [void]$shops.Add('gunsmith')
    }
    elseif ($itLower -match 'weapon|longsword|dagger|glaive|maul|rapier|scimitar|longbow|crossbow|warhammer|battleaxe|greataxe|greatsword|halberd|mace|morningstar|quarterstaff|spear|club|sickle|trident|whip|shortbow|sling|blowgun|war pick|handaxe|javelin|lance|pike|flail') {
        [void]$shops.Add('weapon_shop')
        [void]$shops.Add('blacksmith')
    }
    elseif ($itLower -eq 'ammo' -or $itLower -eq 'ammunition') {
        [void]$shops.Add('weapon_shop')
        if ($nameLower -match 'bullet|shot|gunpowder|cartridge') { [void]$shops.Add('gunsmith') }
    }
    elseif ($itLower -eq 'potion') {
        [void]$shops.Add('alchemist'); [void]$shops.Add('magic_shop')
        if ($nameLower -match 'heal|antitoxin|cure|vitality|restoration') { [void]$shops.Add('healer') }
    }
    elseif ($itLower -eq 'scroll') {
        [void]$shops.Add('magic_shop')
        if ($nameLower -match 'heal|cure|bless|restoration|sanctuary|protection from evil|prayer|revivify|raise dead') {
            [void]$shops.Add('temple')
        }
    }
    elseif ($itLower -eq 'poison') {
        if ($rarityNorm -eq 'common' -and $Price -gt 0 -and $Price -le 200) {
            [void]$shops.Add('alchemist'); [void]$shops.Add('thieves_guild')
        } else {
            [void]$shops.Add('thieves_guild'); [void]$shops.Add('black_market')
        }
    }
    elseif ($itLower -eq 'tool') {
        [void]$shops.Add('crafting_guild'); [void]$shops.Add('traveling_merchant')
        if ($nameLower -match "thieves|burglar|lockpick|disguise|forgery|poisoner") {
            [void]$shops.Add('thieves_guild')
        }
        if ($nameLower -match "smith|mason|carpenter|leatherwork|tinker") {
            [void]$shops.Add('blacksmith')
        }
        if ($nameLower -match "instrument|drum|flute|horn|lute|lyre|pan flute|viol|bagpipe") {
            [void]$shops.Add('tavern')
        }
    }
    elseif ($itLower -eq 'instrument') {
        [void]$shops.Add('crafting_guild'); [void]$shops.Add('tavern')
    }
    elseif ($itLower -in @('clothing','cloak','hat','tattoo')) {
        [void]$shops.Add('tailor')
    }
    elseif ($itLower -eq 'food') {
        [void]$shops.Add('tavern'); [void]$shops.Add('traveling_merchant')
    }
    elseif ($itLower -eq 'consumable') {
        [void]$shops.Add('alchemist')
        if ($nameLower -match 'oil|potion|elixir|salve|tincture') { [void]$shops.Add('healer') }
    }
    elseif ($itLower -eq 'container') {
        [void]$shops.Add('tailor'); [void]$shops.Add('crafting_guild'); [void]$shops.Add('traveling_merchant')
    }
    elseif ($itLower -in @('gear','adventuring gear','equipment')) {
        if ($rarityNorm -in @('uncommon','rare','veryrare','legendary','artifact')) {
            # SRD Equipment with non-Common rarity = wondrous magic item
            [void]$shops.Add('magic_shop')
            # Wearable hints by name keyword
            if ($nameLower -match '\b(boots|gloves|gauntlet|cloak|robe|belt|girdle|headband|circlet|sash|bracers|cape|mantle|vestments|garb)\b') {
                [void]$shops.Add('tailor')
            }
            if ($nameLower -match '\b(helm|helmet|crown|coif|mask)\b') {
                [void]$shops.Add('armorer')
            }
        } else {
            # Mundane adventuring gear (Common)
            [void]$shops.Add('traveling_merchant')
            [void]$shops.Add('crafting_guild')
            if ($Price -le 50) { [void]$shops.Add('tavern') }
        }
    }
    elseif ($itLower -eq 'trinket') {
        if ($isSrd -and $rarityNorm -eq 'common' -and $Price -le 100) {
            [void]$shops.Add('traveling_merchant'); [void]$shops.Add('tavern')
        } else {
            [void]$shops.Add('magic_shop')
        }
    }
    elseif ($itLower -in @('natural','natural weapon','spell focus','spellfocus','crown')) {
        [void]$shops.Add('magic_shop')
        if ($itLower -match 'weapon') { [void]$shops.Add('weapon_shop') }
    }
    # Originals weapon item_types with "+1" suffix etc.
    elseif ($itLower -match '\+\s*\d+') {
        # e.g. "Longsword +2", "Light Armor +1"
        if ($itLower -match 'armor') {
            [void]$shops.Add('armorer')
            if ($itLower -match 'heavy|plate|medium') { [void]$shops.Add('blacksmith') }
        } elseif ($itLower -match 'bow|crossbow') {
            [void]$shops.Add('weapon_shop')
        } else {
            [void]$shops.Add('weapon_shop'); [void]$shops.Add('blacksmith')
        }
    }
    elseif ($itLower -match 'impr' -or $itLower -match 'improvised') {
        [void]$shops.Add('tavern'); [void]$shops.Add('traveling_merchant')
    }

    # --- Step 2: Originals origin overrides ---
    if (-not $isSrd) {
        if ($orig -in @('occult','vampiric','infernal')) {
            [void]$shops.Add('black_market')
            if ($orig -eq 'occult' -and $rarityNorm -in @('rare','veryrare','legendary','artifact')) {
                [void]$shops.Add('thieves_guild')
            }
        }
        if ($orig -in @('blessed','sanctified','druidic')) {
            [void]$shops.Add('temple')
        }
        if ($orig -in @('dwarvenforged','dwarven_forged','giantforged','beastforged')) {
            [void]$shops.Add('blacksmith')
        }
    }

    # --- Step 3: Name keyword overrides ---
    if ($nameLower -match '\b(holy|sacred|divine|sanctified|prayer|blessed)\b' -or
        $nameLower -match 'holy water|holy symbol') {
        [void]$shops.Add('temple')
    }
    if ($nameLower -match '\b(wine|ale|mead|beer|tankard|rations|grog|cider)\b') {
        [void]$shops.Add('tavern')
    }
    if ($nameLower -match 'lockpick|thieves.+tool|burglar|disguise kit|forgery') {
        [void]$shops.Add('thieves_guild')
    }
    if ($nameLower -match 'bullet|firearm|gunpowder|cartridge|musket|pistol|flintlock') {
        [void]$shops.Add('gunsmith')
    }
    if ($nameLower -match '\b(book|tome|manual)\b') {
        if ($isSrd -and $rarityNorm -eq 'common') {
            [void]$shops.Add('crafting_guild')
        } else {
            [void]$shops.Add('magic_shop')
        }
    }
    # Classic D&D magic-item phrasing — force magic_shop and exclude mundane shops
    if ($nameLower -match '\b(wand|staff|rod|scroll|potion|ring|amulet|necklace|talisman|orb)\s+of\b') {
        [void]$shops.Add('magic_shop')
        [void]$shops.Remove('tavern')
        [void]$shops.Remove('traveling_merchant')
    }

    # --- Step 4: Rarity-based filtering ---
    if ($rarityNorm -in @('rare','veryrare','legendary','artifact')) {
        [void]$shops.Remove('tavern')
        [void]$shops.Remove('traveling_merchant')
    }

    # --- Step 5: Fallback ---
    if ($shops.Count -eq 0) {
        [void]$shops.Add('traveling_merchant')
    }

    # Return ordered by canonical shop list (stable output)
    $ordered = New-Object System.Collections.Generic.List[string]
    foreach ($s in $AllShops) {
        if ($shops.Contains($s)) { $ordered.Add($s) | Out-Null }
    }
    return ,$ordered.ToArray()
}

# --- Load DB ---
Write-Host "Reading $dbPath ..."
$indent = Get-IndentSize -Path $dbPath
Write-Host ("Detected indent: {0} spaces" -f $indent)
$json = Get-Content -LiteralPath $dbPath -Raw | ConvertFrom-Json
$keys = $json.content.PSObject.Properties.Name
Write-Host ("Total items: {0} (SRD: {1}, Originals: {2})" -f $keys.Count,
    ($keys | Where-Object { $_ -like '0000_srd_*' }).Count,
    ($keys | Where-Object { $_ -notlike '0000_srd_*' }).Count)

# --- Compute shop assignments in-memory ---
$assignments = @{}
$fallbackCount = 0
foreach ($key in $keys) {
    $p = $json.content.$key.properties
    $price = 0.0
    if ($p.price) { [double]::TryParse([string]$p.price, [ref]$price) | Out-Null }
    $shops = Get-ShopsForItem -Key $key `
                              -Name ([string]$json.content.$key.name) `
                              -ItemType ([string]$p.item_type) `
                              -Origin  ([string]$p.origin) `
                              -Rarity  ([string]$p.rarity) `
                              -Price   $price
    $assignments[$key] = $shops
    if ($shops.Count -eq 1 -and $shops[0] -eq 'traveling_merchant') {
        # Could be intended (gear) or pure fallback. Track only items where item_type was unrecognized.
        $itLower = ([string]$p.item_type).ToLower()
        if ($itLower -notin @('gear','adventuring gear','equipment','tool','container','consumable')) {
            $fallbackCount++
        }
    }
}

# --- Print distribution + samples ---
Write-Host ""
Write-Host "=== Shop distribution ==="
foreach ($shop in $AllShops) {
    $items = $keys | Where-Object { $assignments[$_] -contains $shop }
    Write-Host ("  {0,-20} {1,4} items" -f $shop, $items.Count)
}
Write-Host ""
Write-Host ("Fallback-only items (unrecognized item_type): {0}" -f $fallbackCount)

Write-Host ""
Write-Host "=== Sample items per shop (5 each) ==="
foreach ($shop in $AllShops) {
    Write-Host ("[{0}]" -f $shop) -ForegroundColor Cyan
    $sampleKeys = ($keys | Where-Object { $assignments[$_] -contains $shop } | Get-Random -Count ([Math]::Min(5, ($keys | Where-Object { $assignments[$_] -contains $shop }).Count)))
    foreach ($k in $sampleKeys) {
        $n = $json.content.$k.name
        $it = $json.content.$k.properties.item_type
        $r  = $json.content.$k.properties.rarity
        Write-Host ("    {0,-50} ({1} / {2})" -f $n, $it, $r)
    }
}

# --- Negative checks ---
Write-Host ""
Write-Host "=== Negative checks ==="

$tavernHighRarity = $keys | Where-Object {
    $assignments[$_] -contains 'tavern' -and
    (($json.content.$_.properties.rarity).ToLower() -replace '\s','') -in @('rare','veryrare','legendary','artifact')
}
Write-Host ("Tavern items with rarity Rare+: {0} (must be 0)" -f $tavernHighRarity.Count)
if ($tavernHighRarity.Count -gt 0) {
    $tavernHighRarity | Select-Object -First 5 | ForEach-Object {
        Write-Host ("    BAD: {0} ({1})" -f $json.content.$_.name, $json.content.$_.properties.rarity)
    }
}

$origNoMagic = $keys | Where-Object {
    $_ -notlike '0000_srd_*' -and ($assignments[$_] -notcontains 'magic_shop')
}
Write-Host ("Originals without magic_shop: {0} (must be 0)" -f $origNoMagic.Count)

$noShops = $keys | Where-Object { -not $assignments[$_] -or $assignments[$_].Count -eq 0 }
Write-Host ("Items with no shops: {0} (must be 0)" -f $noShops.Count)

# --- Apply or stop ---
if (-not $Apply) {
    Write-Host ""
    Write-Host "DRY RUN. Re-run with -Apply to write the file." -ForegroundColor Yellow
    return
}

Write-Host ""
Write-Host ("Creating backup: {0}" -f $backupPath)
Copy-Item -LiteralPath $dbPath -Destination $backupPath -Force

# --- Inject shop arrays into the in-memory model ---
foreach ($key in $keys) {
    $p = $json.content.$key.properties
    $shopsArr = $assignments[$key]
    if ($p.PSObject.Properties.Name -contains 'shop') {
        $p.shop = $shopsArr
    } else {
        $p | Add-Member -NotePropertyName 'shop' -NotePropertyValue $shopsArr -Force
    }
}

# --- Write JSON (preserve indent, ensure trailing newline) ---
$indentStr = ' ' * $indent
Write-Host ("Writing {0} (indent={1}) ..." -f $dbPath, $indent)
$out = $json | ConvertTo-Json -Depth 64
if ($indent -ne 2) {
    $out = ($out -split "`n") | ForEach-Object {
        if ($_ -match '^(\s+)(.*)$') {
            $leading = $Matches[1]; $rest = $Matches[2]
            $level = [Math]::Floor($leading.Length / 2)
            ($indentStr * $level) + $rest
        } else { $_ }
    } | Out-String
}
if (-not $out.EndsWith("`n")) { $out += "`n" }
[System.IO.File]::WriteAllText($dbPath, $out, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
Write-Host ("File written: {0}" -f $dbPath)
Write-Host ("Backup:       {0}" -f $backupPath)
Write-Host ("Items updated: {0}" -f $keys.Count)
