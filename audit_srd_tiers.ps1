# Phase A — Read-Only audit of SRD-item Tier assignments.
# Reads items\beneos_items_database.json and computes a proposed re-tiering
# for all SRD-prefixed items (0000_srd_*) based on rarity + gp price.
# Writes srd_tier_audit_<date>.csv. Writes NOTHING into the JSON itself.
#
# Workflow: run this first, review the CSV, then run apply_srd_tier_rebalance.ps1 -Apply.
#
# Plan reference: C:\Users\Beneos\.claude\plans\beneos-items-database-json-dies-ist-die-quirky-eagle.md

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $MyInvocation.MyCommand.Path
$today = Get-Date -Format 'yyyy-MM-dd'
$dbPath  = Join-Path $root 'items\beneos_items_database.json'
$csvPath = Join-Path $root "srd_tier_audit_$today.csv"

# --- Mundane item types: rarity stays as-is (price is independent of magic-rarity) ---
$mundaneTypes = @(
    'Heavy Armor','Medium Armor','Light Armor','Shield',
    'Simple Melee Weapon','Martial Melee Weapon','Simple Ranged Weapon','Martial Ranged Weapon',
    'Weapon','Natural Weapon','Ammo','Poison','Food','Tool','Gear','Equipment','Consumable'
)

# --- D&D 2024 DMG rarity-price brackets (used for auto-correct on magic items) ---
$rarityBrackets = @(
    @{ name='common';    min=0;     max=100    }
    @{ name='uncommon';  min=101;   max=500    }
    @{ name='rare';      min=501;   max=5000   }
    @{ name='veryrare';  min=5001;  max=50000  }
    @{ name='legendary'; min=50001; max=[double]::MaxValue }
)

function Get-RarityForPrice {
    param([double]$Price)
    foreach ($b in $rarityBrackets) {
        if ($Price -ge $b.min -and $Price -le $b.max) { return $b.name }
    }
    return 'common'
}

function Get-RarityMax {
    param([string]$RarityNorm)
    $b = $rarityBrackets | Where-Object name -eq $RarityNorm
    if ($b) { return $b.max } else { return 0 }
}

function Compute-Tier {
    param([string]$RarityNorm, [double]$Price)
    if ($RarityNorm -in @('legendary','artifact')) { return 4 }
    $floor = @{ common=1; uncommon=1; rare=2; veryrare=3 }[$RarityNorm]
    $ceil  = @{ common=1; uncommon=2; rare=3; veryrare=4 }[$RarityNorm]
    if ($null -eq $floor) { $floor = 1 }
    if ($null -eq $ceil)  { $ceil  = 1 }
    if ($Price -gt 0) {
        $byPrice =
            if     ($Price -le 3000)  { 1 }
            elseif ($Price -le 15000) { 2 }
            elseif ($Price -le 50000) { 3 }
            else                      { 4 }
        $t = [Math]::Min($ceil, [Math]::Max($floor, $byPrice))
        return $t
    }
    return $floor
}

# --- Load DB ---
Write-Host "Reading $dbPath ..."
$json = Get-Content -LiteralPath $dbPath -Raw | ConvertFrom-Json
$keys = $json.content.PSObject.Properties.Name
$srdKeys = $keys | Where-Object { $_ -like '0000_srd_*' }
Write-Host ("Found {0} SRD items (of {1} total)" -f $srdKeys.Count, $keys.Count)

# --- Build audit rows ---
$rows = New-Object System.Collections.Generic.List[object]
foreach ($key in $srdKeys) {
    $item = $json.content.$key
    $p    = $item.properties
    $oldRarity = if ($p.rarity) { [string]$p.rarity } else { '' }
    $oldRarityNorm = $oldRarity.ToLower() -replace '\s',''
    $oldTier  = [int]$p.tier
    $itemType = if ($p.item_type) { [string]$p.item_type } else { '' }
    $price    = 0.0
    if ($p.price) { [double]::TryParse([string]$p.price, [ref]$price) | Out-Null }

    # Step 1: rarity auto-correct (magic-only)
    $newRarity     = $oldRarity
    $newRarityNorm = $oldRarityNorm
    $anomalies = @()
    $isMagicLike = ($itemType -notin $mundaneTypes)

    if ($price -gt 0 -and $oldRarityNorm -in @('common','uncommon','rare','veryrare')) {
        $rarityMax = Get-RarityMax $oldRarityNorm
        if ($rarityMax -gt 0 -and $price -gt ($rarityMax * 3)) {
            if ($isMagicLike) {
                $proposed = Get-RarityForPrice $price
                if ($proposed -ne $oldRarityNorm) {
                    $newRarityNorm = $proposed
                    # Preserve original capitalization style for veryrare → "Veryrare"
                    $newRarity = (Get-Culture).TextInfo.ToTitleCase($proposed)
                    $anomalies += "RARITY_AUTOCORRECTED:$oldRarityNorm->$proposed"
                }
            } else {
                $anomalies += "RARITY_PRICE_MISMATCH_NOAUTO:mundane_type=$itemType"
            }
        }
    }

    # Step 2: compute new tier from (corrected) rarity + price
    $newTier = Compute-Tier -RarityNorm $newRarityNorm -Price $price

    if ($oldTier -eq 5) { $anomalies += "TIER_5_COLLAPSED" }
    if ($price -le 0 -and $oldRarityNorm -in @('veryrare','legendary')) {
        $anomalies += "ZERO_PRICE_HIGH_RARITY"
    }

    $delta = $newTier - $oldTier
    $row = [PSCustomObject]@{
        key           = $key
        name          = [string]$item.name
        item_type     = $itemType
        price         = $price
        old_rarity    = $oldRarity
        new_rarity    = $newRarity
        rarity_changed= ($oldRarityNorm -ne $newRarityNorm)
        old_tier      = $oldTier
        new_tier      = $newTier
        tier_delta    = $delta
        anomaly_flags = ($anomalies -join ';')
    }
    $rows.Add($row) | Out-Null
}

# --- Write CSV (UTF-8 with BOM so Excel handles umlauts) ---
Write-Host "Writing $csvPath ..."
$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

# --- Summary statistics ---
Write-Host ""
Write-Host "=== Summary ==="
Write-Host ("Total SRD items audited: {0}" -f $rows.Count)
Write-Host ""
Write-Host "Tier distribution (old -> new):"
$old = $rows | Group-Object old_tier | Sort-Object Name
$new = $rows | Group-Object new_tier | Sort-Object Name
foreach ($t in 1..5) {
    $o = ($old | Where-Object Name -eq "$t" | Select-Object -ExpandProperty Count)
    $n = ($new | Where-Object Name -eq "$t" | Select-Object -ExpandProperty Count)
    if (-not $o) { $o = 0 }
    if (-not $n) { $n = 0 }
    Write-Host ("  Tier {0}: old={1,3}  new={2,3}" -f $t, $o, $n)
}
Write-Host ""
Write-Host "Items where tier will change:"
("  " + ($rows | Where-Object tier_delta -ne 0).Count + " of " + $rows.Count) | Write-Host
Write-Host ""
Write-Host "Anomaly summary:"
$rows | Where-Object anomaly_flags | ForEach-Object { ($_.anomaly_flags -split ';') } | Group-Object | Sort-Object Count -Descending | ForEach-Object {
    Write-Host ("  {0,-50} {1,3}" -f $_.Name, $_.Count)
}
Write-Host ""
Write-Host ("CSV written to: {0}" -f $csvPath)
Write-Host "No JSON modified. Run apply_srd_tier_rebalance.ps1 -Apply when ready."
