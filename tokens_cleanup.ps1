# Tokens-DB Cleanup
# Atomic: backup -> modify in-memory -> validate -> atomic write -> re-audit.
# Source of fixes: reality_check_<date>.json (variant_mismatch + orphans).
# Items / Spells DBs are NOT touched.

$ErrorActionPreference = 'Stop'

$root      = Split-Path -Parent $MyInvocation.MyCommand.Path
$dbPath    = Join-Path $root 'tokens\beneos_tokens_database_v2.json'
$today     = Get-Date -Format 'yyyy-MM-dd'
$backup    = Join-Path $root "tokens\beneos_tokens_database_v2.pre_cleanup_$today.json"
$auditJson = Join-Path $root "reality_check_$today.json"

if (-not (Test-Path $auditJson)) {
    throw "Audit JSON not found: $auditJson — run reality_check.ps1 first."
}
if (-not (Test-Path $dbPath)) {
    throw "Tokens DB not found: $dbPath"
}

$audit        = Get-Content -LiteralPath $auditJson -Raw -Encoding UTF8 | ConvertFrom-Json
$keepKey      = '154-awakened_armor'
$orphansToDel = @($audit.tokens.orphans | Where-Object { $_ -ne $keepKey })
$variantFixes = @($audit.tokens.variant_mismatch)

Write-Host "Audit input: $($audit.tokens.orphans.Count) orphans (keep '$keepKey' -> deleting $($orphansToDel.Count)), $($variantFixes.Count) variant mismatches"

# --- 1. Pre-flight presence check ---
$db = Get-Content -LiteralPath $dbPath -Raw -Encoding UTF8 | ConvertFrom-Json
$presentKeys = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@($db.content.PSObject.Properties.Name),
    [System.StringComparer]::OrdinalIgnoreCase)

$missing = @()
foreach ($k in $orphansToDel) { if (-not $presentKeys.Contains($k)) { $missing += "orphan:$k" } }
foreach ($f in $variantFixes) { if (-not $presentKeys.Contains($f.key)) { $missing += "fix:$($f.key)" } }
if ($missing.Count -gt 0) {
    throw "Pre-flight failed. Missing in DB: $($missing -join ', ')"
}
$beforeCount = $db.content.PSObject.Properties.Name.Count
Write-Host "Pre-flight OK. DB has $beforeCount entries."

# --- 2. Backup ---
if (-not (Test-Path $backup)) {
    Copy-Item -LiteralPath $dbPath -Destination $backup
    Write-Host "Backup created: $backup"
} else {
    Write-Warning "Backup already exists, kept as-is: $backup"
}

# --- 3. Modify in-memory ---
# Build case-insensitive key resolver (DB key may differ in case from audit key, e.g. 222-vampire_Roadstalker)
$keyByLower = @{}
$db.content.PSObject.Properties.Name | ForEach-Object { $keyByLower[$_.ToLowerInvariant()] = $_ }

foreach ($k in $orphansToDel) {
    $real = $keyByLower[$k.ToLowerInvariant()]
    [void]$db.content.PSObject.Properties.Remove($real)
}

foreach ($f in $variantFixes) {
    $real    = $keyByLower[$f.key.ToLowerInvariant()]
    $newVal  = [int]$f.actual
    $db.content.$real.properties.nb_variants = $newVal
    Write-Host ("  fix nb_variants: {0,-40} {1} -> {2}" -f $real, $f.db, $newVal)
}

$afterCount = $db.content.PSObject.Properties.Name.Count
if ($afterCount -ne ($beforeCount - $orphansToDel.Count)) {
    throw "In-memory entry count wrong: before=$beforeCount, after=$afterCount, expected=$($beforeCount - $orphansToDel.Count)"
}

# --- 4. Re-serialize (PowerShell ConvertTo-Json defaults to 2-space indent; original is 4-space) ---
$out = $db | ConvertTo-Json -Depth 100
# Double leading whitespace per line: 2-space indent -> 4-space indent
$out = [regex]::Replace($out, '(?m)^( +)', { param($m) ' ' * ($m.Groups[1].Length * 2) })

# --- 5. Atomic write ---
$tmp = "$dbPath.tmp"
Set-Content -LiteralPath $tmp -Value $out -Encoding UTF8
Move-Item -LiteralPath $tmp -Destination $dbPath -Force
Write-Host "DB written: $dbPath"

# --- 6. Post-validate ---
$check = Get-Content -LiteralPath $dbPath -Raw -Encoding UTF8 | ConvertFrom-Json
$nowKeys = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@($check.content.PSObject.Properties.Name),
    [System.StringComparer]::OrdinalIgnoreCase)

$failed = @()
if (-not $check.content.'154-awakened_armor') { $failed += "154-awakened_armor missing (must be preserved!)" }
if (-not $check.content.'000-srd_zombie')     { $failed += "000-srd_zombie missing (variant fix target, must remain)" }
foreach ($k in $orphansToDel) {
    if ($nowKeys.Contains($k)) { $failed += "orphan still present: $k" }
}
foreach ($f in $variantFixes) {
    $real = ($check.content.PSObject.Properties.Name | Where-Object { $_.ToLowerInvariant() -eq $f.key.ToLowerInvariant() } | Select-Object -First 1)
    if (-not $real) { $failed += "fix key gone: $($f.key)"; continue }
    $now = [int]$check.content.$real.properties.nb_variants
    if ($now -ne [int]$f.actual) { $failed += "$($f.key) nb_variants=$now expected=$($f.actual)" }
}
if ($failed.Count -gt 0) {
    throw "Post-validation FAILED:`n  - $($failed -join "`n  - ")"
}
Write-Host "Post-validation OK. New entry count: $($check.content.PSObject.Properties.Name.Count)"

# --- 7. Re-audit ---
Write-Host ""
Write-Host "Running reality_check.ps1 to verify drift cleared..." -ForegroundColor Cyan
& (Join-Path $root 'reality_check.ps1')
