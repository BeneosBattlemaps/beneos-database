# Combined run:
#   1) Re-apply tokens cleanup (delete 25 orphans, fix 13 nb_variants)
#   2) Add free_content field (default false, true for user-specified keys) to all 4 DBs:
#      tokens, items, spells, battlemaps
# Each DB is backed up to *.pre_free_content_<date>.json before write.
# Indent is detected per file (2-space or 4-space) and preserved on re-serialize.

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $MyInvocation.MyCommand.Path
$today = Get-Date -Format 'yyyy-MM-dd'

# --- True-Listen (per User) ---
$tokensTrue = @(
    '044-amygdalyan','154-awakened_armor','182-barmaid','215-beast_of_soot_and_sulphur',
    '171-blazing_skull','000-month_16_cathedral_knight','177-cult_possessed',
    '000-month_16_deathrite_bellringer','000-month_24_elder_lindwurm',
    '145-ghoul_bonegnawer','193-grave_golem','193-gravestones','122-gutterfist',
    '213-hellracer_boarding_imp','158-infernal_immolator','194-knight_unmounted',
    '224-krampus','169-mummy_tomb_vizier','196-orc_chieftain','184-rot_cerf',
    '161-sodden_cavalier','144-tactician','129-undead_archer','212-uvargandr',
    '211-uvargandr_stormscalecluster'
)
$spellsTrue = @(
    '0024_rats','0026_detonate','0032_profane_parrot','0035_relive','0038_grand_entrance',
    '0046_fist_of_iron','0051_predatory_adaptation','0059_festering_truth',
    '0063_burning_zeal','0064_hope_devourer','0075_dying_breath','0085_chosen_thrall',
    '0094_curse_mark','0115_background_music','0119_illgotten_gains','0100_stormspear'
)
$itemsTrue = @(
    '0055_awoken_huskblade','0058_bascinet_of_ancient_tactica','0059_bottlesnatcher_imp',
    '0091_dark_promise','0049_foremans_flask','0068_magmatic_molasses',
    '0097_potion_of_healing','0097_potion_of_superior_healing',
    '0097_potion_of_supreme_healing','0084_reefs_splendour','0003_shamblevault_coffin',
    '0054_slumbering_huskblade','0098_sphinx_key','0062_three_feather_tricorne',
    '0094_trench_digger'
)

# --- Tokens Cleanup-Listen (aus Audit) ---
$tokensOrphansToDel = @(
    '000-srd_airship','000-srd_arcane_eye','000-srd_arcane_hand','000-srd_arcane_sword',
    '000-srd_dancing_lights_medium','000-srd_dancing_lights_tiny','000-srd_flaming_sphere',
    '000-srd_floating_disk','000-srd_floating_whip','000-srd_guardian_of_faith',
    '000-srd_huge_animated_object','000-srd_illusory_creature','000-srd_illusory_object',
    '000-srd_illusory_phenomenon','000-srd_invisible_sensor','000-srd_keelboat',
    '000-srd_large_animated_object','000-srd_longship','000-srd_medium_animated_object',
    '000-srd_rowboat','000-srd_sailing_ship','000-srd_secret_chest',
    '000-srd_small_animated_object','000-srd_unseen_servant','000-srd_warship'
)
$tokensVariantFixes = @(
    @{ key='000-month_20_shade_tyrant';     actual=2 }
    @{ key='000-month_26_cloud_zone';       actual=3 }
    @{ key='000-srd_kraken';                actual=1 }
    @{ key='000-srd_zombie';                actual=1 }
    @{ key='159-vampire_chiropterror';      actual=1 }
    @{ key='181-frost_wretch';              actual=2 }
    @{ key='198-gnoll_fleshtaker';          actual=1 }
    @{ key='206-unhinged_mimic';            actual=3 }
    @{ key='220-corrupted_champion';        actual=3 }
    @{ key='222-vampire_Roadstalker';       actual=2 }
    @{ key='226-swarm_of_stirges';          actual=1 }
    @{ key='228-greater_earth_elemental';   actual=2 }
    @{ key='229-gravegrasper';              actual=2 }
)

# --- DB-Definitionen ---
$dbDefs = @(
    @{ name='tokens';     path=(Join-Path $root 'tokens\beneos_tokens_database_v2.json'); trueList=$tokensTrue;  doCleanup=$true  }
    @{ name='items';      path=(Join-Path $root 'items\beneos_items_database.json');      trueList=$itemsTrue;   doCleanup=$false }
    @{ name='spells';     path=(Join-Path $root 'spells\beneos_spells_database.json');    trueList=$spellsTrue;  doCleanup=$false }
    @{ name='battlemaps'; path=(Join-Path $root 'beneos_battlemaps_database.json');       trueList=@();          doCleanup=$false }
)

# --- Helper ---
function Get-IndentSize {
    param([string]$Path)
    foreach ($line in Get-Content -LiteralPath $Path -TotalCount 8) {
        if ($line -match '^( +)\S') { return $Matches[1].Length }
    }
    return 2
}
function Get-CaseInsensitiveKey {
    param($Container, [string]$Wanted)
    $Container.PSObject.Properties.Name |
        Where-Object { $_.ToLowerInvariant() -eq $Wanted.ToLowerInvariant() } |
        Select-Object -First 1
}

# --- Pro DB ---
$summary = @()
foreach ($d in $dbDefs) {
    Write-Host ""
    Write-Host "=== $($d.name.ToUpper()) ===" -ForegroundColor Cyan

    $indent  = Get-IndentSize -Path $d.path
    $backup  = $d.path -replace '\.json$', ".pre_free_content_$today.json"
    if (-not (Test-Path $backup)) {
        Copy-Item -LiteralPath $d.path -Destination $backup
        Write-Host "  Backup: $backup"
    } else {
        Write-Warning "  Backup already exists, kept as-is: $backup"
    }

    $db = Get-Content -LiteralPath $d.path -Raw -Encoding UTF8 | ConvertFrom-Json
    $beforeCount = $db.content.PSObject.Properties.Name.Count
    Write-Host "  Indent: ${indent}-space, entries (before): $beforeCount"

    # 1. Tokens-Cleanup
    if ($d.doCleanup) {
        $delHits = 0; $fixHits = 0
        foreach ($k in $tokensOrphansToDel) {
            $real = Get-CaseInsensitiveKey -Container $db.content -Wanted $k
            if ($real) {
                [void]$db.content.PSObject.Properties.Remove($real)
                $delHits++
            }
        }
        foreach ($f in $tokensVariantFixes) {
            $real = Get-CaseInsensitiveKey -Container $db.content -Wanted $f.key
            if ($real) {
                $db.content.$real.properties.nb_variants = [int]$f.actual
                $fixHits++
            }
        }
        Write-Host "  Cleanup: deleted=$delHits, nb_variants_fixed=$fixHits"
    }

    # 2. free_content
    $trueSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($d.trueList), [System.StringComparer]::OrdinalIgnoreCase)

    $entryProps = @($db.content.PSObject.Properties)
    $missingTrue = @()
    $trueAppliedCount = 0
    foreach ($prop in $entryProps) {
        $entry = $prop.Value
        if (-not $entry.properties) { continue }
        $isTrue = $trueSet.Contains($prop.Name)
        if ($entry.properties.PSObject.Properties.Name -contains 'free_content') {
            $entry.properties.free_content = $isTrue
        } else {
            Add-Member -InputObject $entry.properties -NotePropertyName 'free_content' -NotePropertyValue $isTrue -Force
        }
        if ($isTrue) { $trueAppliedCount++ }
    }
    foreach ($k in $d.trueList) {
        if (-not (Get-CaseInsensitiveKey -Container $db.content -Wanted $k)) {
            $missingTrue += $k
        }
    }
    if ($missingTrue.Count -gt 0) {
        Write-Warning "  [$($d.name)] true-keys nicht in DB (übersprungen): $($missingTrue -join ', ')"
    }
    Write-Host "  free_content=true applied: $trueAppliedCount of $($d.trueList.Count) requested"

    # 3. Re-Serialize (indent-aware)
    $out = $db | ConvertTo-Json -Depth 100
    if ($indent -gt 2) {
        $factor = $indent / 2
        $out = [regex]::Replace($out, '(?m)^( +)', { param($m) ' ' * ($m.Groups[1].Length * $factor) })
    }

    # 4. Atomic Write
    $tmp = "$($d.path).tmp"
    Set-Content -LiteralPath $tmp -Value $out -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $d.path -Force

    # 5. Validate
    $check = Get-Content -LiteralPath $d.path -Raw -Encoding UTF8 | ConvertFrom-Json
    $entries = @($check.content.PSObject.Properties.Name)
    $withField = 0; $trueCount = 0
    foreach ($k in $entries) {
        $props = $check.content.$k.properties
        if (-not $props) { continue }
        if ($props.PSObject.Properties.Name -contains 'free_content') {
            $withField++
            if ([bool]$props.free_content) { $trueCount++ }
        }
    }
    if ($withField -ne $entries.Count) {
        throw "[$($d.name)] free_content nicht überall gesetzt: $withField / $($entries.Count)"
    }
    Write-Host "  After-write: entries=$($entries.Count), with-free_content=$withField, true=$trueCount" -ForegroundColor Green

    $summary += [pscustomobject]@{
        DB = $d.name
        EntriesBefore = $beforeCount
        EntriesAfter = $entries.Count
        FreeContentTrue = $trueCount
        SkippedTrueKeys = ($missingTrue -join ',')
    }
}

Write-Host ""
Write-Host "=== SUMMARY ===" -ForegroundColor Yellow
$summary | Format-Table -AutoSize

Write-Host ""
Write-Host "Running reality_check.ps1 to verify cleanup state..." -ForegroundColor Cyan
& (Join-Path $root 'reality_check.ps1')
