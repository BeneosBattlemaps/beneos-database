# Recovery: restore spells DB from 2026-05-05 backup (480 entries incl. 340 SRD)
# and re-apply the free_content field on the restored content.
# The current live spells DB (146 entries) was already shrunk before any of our
# scripts ran — we just snapshot it for reversibility, then overwrite from backup.

$ErrorActionPreference = 'Stop'

$root        = Split-Path -Parent $MyInvocation.MyCommand.Path
$today       = Get-Date -Format 'yyyy-MM-dd'
$dbPath      = Join-Path $root 'spells\beneos_spells_database.json'
$srcBackup   = Join-Path $root 'spells\beneos_spells_database.backup-2026-05-05.json'
$preRestore  = Join-Path $root "spells\beneos_spells_database.pre_restore_$today.json"

$spellsTrue = @(
    '0024_rats','0026_detonate','0032_profane_parrot','0035_relive','0038_grand_entrance',
    '0046_fist_of_iron','0051_predatory_adaptation','0059_festering_truth',
    '0063_burning_zeal','0064_hope_devourer','0075_dying_breath','0085_chosen_thrall',
    '0094_curse_mark','0115_background_music','0119_illgotten_gains','0100_stormspear'
)

# --- 1. Pre-Flight ---
if (-not (Test-Path $srcBackup)) { throw "Restore source missing: $srcBackup" }
if (-not (Test-Path $dbPath))    { throw "Live DB missing: $dbPath" }

$srcDb    = Get-Content -LiteralPath $srcBackup -Raw -Encoding UTF8 | ConvertFrom-Json
$srcCount = $srcDb.content.PSObject.Properties.Name.Count
$srcSrd   = ($srcDb.content.PSObject.Properties.Name | Where-Object { $_ -like '0000_srd*' }).Count
if ($srcCount -lt 480 -or $srcSrd -lt 300) {
    throw "Source backup looks degraded: entries=$srcCount srd=$srcSrd (expected >=480, >=300 SRD)"
}
Write-Host "Source OK: $srcCount entries with $srcSrd SRD spells" -ForegroundColor Green

$liveDb     = Get-Content -LiteralPath $dbPath -Raw -Encoding UTF8 | ConvertFrom-Json
$liveCount  = $liveDb.content.PSObject.Properties.Name.Count
Write-Host "Live DB before restore: $liveCount entries"

# --- 2. Snapshot current state ---
if (-not (Test-Path $preRestore)) {
    Copy-Item -LiteralPath $dbPath -Destination $preRestore
    Write-Host "Pre-restore snapshot: $preRestore"
} else {
    Write-Warning "Pre-restore snapshot already exists, kept as-is: $preRestore"
}

# --- 3. Restore ---
Copy-Item -LiteralPath $srcBackup -Destination $dbPath -Force
Write-Host "Restored from: $srcBackup"

# --- 4. Re-apply free_content ---
$db = Get-Content -LiteralPath $dbPath -Raw -Encoding UTF8 | ConvertFrom-Json
$trueSet = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@($spellsTrue), [System.StringComparer]::OrdinalIgnoreCase)

$missing = @()
$applied = 0
foreach ($prop in @($db.content.PSObject.Properties)) {
    $entry = $prop.Value
    if (-not $entry.properties) { continue }
    $isTrue = $trueSet.Contains($prop.Name)
    if ($entry.properties.PSObject.Properties.Name -contains 'free_content') {
        $entry.properties.free_content = $isTrue
    } else {
        Add-Member -InputObject $entry.properties -NotePropertyName 'free_content' -NotePropertyValue $isTrue -Force
    }
    if ($isTrue) { $applied++ }
}
foreach ($k in $spellsTrue) {
    $found = $db.content.PSObject.Properties.Name | Where-Object { $_.ToLowerInvariant() -eq $k.ToLowerInvariant() } | Select-Object -First 1
    if (-not $found) { $missing += $k }
}
if ($missing.Count -gt 0) {
    Write-Warning "true-keys nicht in restaurierter DB (übersprungen): $($missing -join ', ')"
}
Write-Host "free_content=true applied: $applied of $($spellsTrue.Count) requested"

# Source backup uses 2-space indent → no doubling needed
$out = $db | ConvertTo-Json -Depth 100
$tmp = "$dbPath.tmp"
Set-Content -LiteralPath $tmp -Value $out -Encoding UTF8
Move-Item -LiteralPath $tmp -Destination $dbPath -Force

# --- 5. Validate ---
$check = Get-Content -LiteralPath $dbPath -Raw -Encoding UTF8 | ConvertFrom-Json
$entries  = @($check.content.PSObject.Properties.Name)
$srdCount = ($entries | Where-Object { $_ -like '0000_srd*' }).Count
$withField = 0
$trueCount = 0
foreach ($k in $entries) {
    $props = $check.content.$k.properties
    if (-not $props) { continue }
    if ($props.PSObject.Properties.Name -contains 'free_content') {
        $withField++
        if ([bool]$props.free_content) { $trueCount++ }
    }
}

Write-Host ""
Write-Host "=== POST-RESTORE STATE ===" -ForegroundColor Yellow
Write-Host ("Entries: {0}  SRD: {1}  with-free_content: {2}  true: {3}" -f $entries.Count, $srdCount, $withField, $trueCount)

if ($entries.Count -lt 480) { throw "Entries below threshold: $($entries.Count) (expected >=480)" }
if ($srdCount  -lt 300)     { throw "SRD count below threshold: $srdCount (expected >=300)" }
if ($withField -ne $entries.Count) { throw "free_content nicht überall gesetzt: $withField / $($entries.Count)" }

# Spot checks
$rats = $check.content.'0024_rats'.properties.free_content
$cactus = $check.content.'0001_needleburst_cactus'.properties.free_content
Write-Host "Spot: 0024_rats.free_content=$rats (expect True), 0001_needleburst_cactus.free_content=$cactus (expect False)"
if (-not $rats)  { throw "Spot fail: 0024_rats should be true" }
if ($cactus)     { throw "Spot fail: 0001_needleburst_cactus should be false" }

$srdSample = $entries | Where-Object { $_ -like '0000_srd*' } | Select-Object -First 1
Write-Host ("Spot: SRD sample '{0}' free_content={1} (expect False)" -f $srdSample, $check.content.$srdSample.properties.free_content)
if ([bool]$check.content.$srdSample.properties.free_content) { throw "Spot fail: SRD sample $srdSample should default to false" }

Write-Host "All validations passed." -ForegroundColor Green

# --- 6. Re-Audit ---
Write-Host ""
Write-Host "Running reality_check.ps1 to verify drift..." -ForegroundColor Cyan
& (Join-Path $root 'reality_check.ps1')
