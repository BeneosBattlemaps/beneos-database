# Phase B - Apply SRD-item Tier rebalance to items\beneos_items_database.json.
# Default = Dry-Run. Pass -Apply to actually write the file.
# Always creates a backup at items\beneos_items_database.pre_tier_rebalance_<date>.json
# before modifying.
#
# Plan reference: C:\Users\Beneos\.claude\plans\beneos-items-database-json-dies-ist-die-quirky-eagle.md
[CmdletBinding()]
param(
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $MyInvocation.MyCommand.Path
$today = Get-Date -Format 'yyyy-MM-dd'
$dbPath     = Join-Path $root 'items\beneos_items_database.json'
$backupPath = Join-Path $root ("items\beneos_items_database.pre_tier_rebalance_$today.json")

# --- Helper from apply_cleanup_and_free_content.ps1 (lines 74-80) ---
function Get-IndentSize {
    param([string]$Path)
    foreach ($line in Get-Content -LiteralPath $Path -TotalCount 8) {
        if ($line -match '^( +)\S') { return $Matches[1].Length }
    }
    return 2
}

# --- Re-tier algorithm (must match audit_srd_tiers.ps1) ---
$mundaneTypes = @(
    'Heavy Armor','Medium Armor','Light Armor','Shield',
    'Simple Melee Weapon','Martial Melee Weapon','Simple Ranged Weapon','Martial Ranged Weapon',
    'Weapon','Natural Weapon','Ammo','Poison','Food','Tool','Gear','Equipment','Consumable'
)
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
        return [Math]::Min($ceil, [Math]::Max($floor, $byPrice))
    }
    return $floor
}

# --- Capitalization map: keep DB convention (e.g. "Veryrare" not "Very Rare") ---
$rarityDisplay = @{
    common    = 'Common'
    uncommon  = 'Uncommon'
    rare      = 'Rare'
    veryrare  = 'Veryrare'
    legendary = 'Legendary'
    artifact  = 'Artifact'
}

# --- Load DB ---
Write-Host "Reading $dbPath ..."
$indent = Get-IndentSize -Path $dbPath
Write-Host ("Detected indent: {0} spaces" -f $indent)
$json = Get-Content -LiteralPath $dbPath -Raw | ConvertFrom-Json
$keys = $json.content.PSObject.Properties.Name
$srdKeys = $keys | Where-Object { $_ -like '0000_srd_*' }
Write-Host ("SRD items: {0} (of {1} total)" -f $srdKeys.Count, $keys.Count)

# --- Apply algorithm in-memory ---
$tierChanges   = 0
$rarityChanges = 0
$changeLog = New-Object System.Collections.Generic.List[string]

foreach ($key in $srdKeys) {
    $p = $json.content.$key.properties
    $oldRarity = if ($p.rarity) { [string]$p.rarity } else { '' }
    $oldRarityNorm = $oldRarity.ToLower() -replace '\s',''
    $oldTier  = [int]$p.tier
    $itemType = if ($p.item_type) { [string]$p.item_type } else { '' }
    $price    = 0.0
    if ($p.price) { [double]::TryParse([string]$p.price, [ref]$price) | Out-Null }

    $newRarityNorm = $oldRarityNorm
    $isMagicLike = ($itemType -notin $mundaneTypes)
    if ($price -gt 0 -and $oldRarityNorm -in @('common','uncommon','rare','veryrare')) {
        $rarityMax = Get-RarityMax $oldRarityNorm
        if ($isMagicLike -and $rarityMax -gt 0 -and $price -gt ($rarityMax * 3)) {
            $proposed = Get-RarityForPrice $price
            if ($proposed -ne $oldRarityNorm) {
                $newRarityNorm = $proposed
            }
        }
    }
    $newRarityDisplay = if ($rarityDisplay.ContainsKey($newRarityNorm)) { $rarityDisplay[$newRarityNorm] } else { $oldRarity }
    $newTier = Compute-Tier -RarityNorm $newRarityNorm -Price $price

    $rarityChanged = ($oldRarityNorm -ne $newRarityNorm)
    $tierChanged   = ($oldTier -ne $newTier)

    if ($rarityChanged) {
        $p.rarity = $newRarityDisplay
        $rarityChanges++
    }
    if ($tierChanged) {
        $p.tier = $newTier
        $tierChanges++
    }
    if ($rarityChanged -or $tierChanged) {
        $changeLog.Add(("  {0,-50} rarity:{1,-10}->{2,-10} tier:{3}->{4}" -f $key, $oldRarity, $newRarityDisplay, $oldTier, $newTier)) | Out-Null
    }
}

Write-Host ""
Write-Host "=== Proposed changes ==="
Write-Host ("Tier changes:   {0}" -f $tierChanges)
Write-Host ("Rarity changes: {0}" -f $rarityChanges)
Write-Host ""
if ($changeLog.Count -gt 0) {
    Write-Host "First 10 changes (of $($changeLog.Count)):"
    $changeLog | Select-Object -First 10 | ForEach-Object { Write-Host $_ }
    if ($changeLog.Count -gt 10) { Write-Host ("  ... and {0} more" -f ($changeLog.Count - 10)) }
}

if (-not $Apply) {
    Write-Host ""
    Write-Host "DRY RUN. Re-run with -Apply to write the file." -ForegroundColor Yellow
    return
}

# --- Apply: backup + write ---
Write-Host ""
Write-Host ("Creating backup: {0}" -f $backupPath)
Copy-Item -LiteralPath $dbPath -Destination $backupPath -Force

$indentStr = ' ' * $indent
Write-Host ("Writing {0} (indent={1}) ..." -f $dbPath, $indent)
$out = $json | ConvertTo-Json -Depth 64
# PowerShell ConvertTo-Json default uses 2-space indent. If the file uses something else,
# rewrite the leading whitespace per line. Most Beneos JSON files are 2-space indent.
if ($indent -ne 2) {
    $out = ($out -split "`n") | ForEach-Object {
        if ($_ -match '^(\s+)(.*)$') {
            # Convert 2-space groups to $indent-space groups
            $leading = $Matches[1]
            $rest    = $Matches[2]
            $level   = [Math]::Floor($leading.Length / 2)
            ($indentStr * $level) + $rest
        } else { $_ }
    } | ForEach-Object { $_ } | Out-String
}
[System.IO.File]::WriteAllText($dbPath, $out, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
Write-Host ("File written: {0}" -f $dbPath)
Write-Host ("Backup:       {0}" -f $backupPath)
Write-Host ("Tier changes:   {0}" -f $tierChanges)
Write-Host ("Rarity changes: {0}" -f $rarityChanges)
