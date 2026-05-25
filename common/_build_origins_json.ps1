$ErrorActionPreference = 'Stop'

$commonDbPath = 'J:\Beneos_Webservice\Online_Search\beneos-database\common\beneos_common_database.json'
$itemsPath    = 'J:\Beneos_Adventures\Publishing\Item_Cards\beneos_card_creator_v1\items.json'
$iconsDir     = 'J:\Beneos_Adventures\Publishing\Item_Cards\beneos_card_creator_v1\source\icons_origin'
$outPath      = 'J:\Beneos_Webservice\Online_Search\beneos-database\common\origins.json'

$slugToIcon = @{
    'dwarvenforged' = 'dwarven_forged'
    'giantforged'   = 'giant_forged'
    'technoarcane'  = 'techno_arcane'
}

function Resolve-IconBase($slug) {
    if ($slugToIcon.ContainsKey($slug)) { return $slugToIcon[$slug] }
    return $slug
}

function Get-Title($slug) {
    $special = @{
        'dwarvenforged' = 'Dwarvenforged'
        'giantforged'   = 'Giantforged'
        'technoarcane'  = 'Technoarcane'
        'beastforged'   = 'Beastforged'
        'feywoven'      = 'Feywoven'
    }
    if ($special.ContainsKey($slug)) { return $special[$slug] }
    return (Get-Culture).TextInfo.ToTitleCase($slug)
}

# --- Load common_db -> origin lore ---
$commonRaw = Get-Content $commonDbPath -Raw -Encoding UTF8
$common    = $commonRaw | ConvertFrom-Json
$originLore = @{}
foreach ($p in $common.hover.origin.PSObject.Properties) {
    $slug = $p.Name.Trim()
    $msg  = $p.Value.message
    if ($msg) {
        # Strip leading "Origin: " or "Slug: " prefix from lore for cleanliness
        $clean = $msg -replace '^[A-Za-z]+:\s*',''
        $originLore[$slug] = $clean
    }
}
Write-Host "Loaded $($originLore.Count) origin lore entries from common_db"

# --- Load items.json -> filter 0000_* entries ---
$itemsRaw  = Get-Content $itemsPath -Raw -Encoding UTF8
$items     = $itemsRaw | ConvertFrom-Json
$zeroItems = $items | Where-Object { $_.releaseName -and $_.releaseName.StartsWith('0000_') }
Write-Host "Loaded $($zeroItems.Count) 0000_* tier entries from items.json"

# --- Bucket per origin / tier ---
$buckets = @{}
foreach ($slug in $originLore.Keys) {
    $buckets[$slug] = [ordered]@{
        echo      = $null
        resonance = New-Object System.Collections.ArrayList
        harmony   = $null
        specials  = New-Object System.Collections.ArrayList
    }
}

foreach ($it in $zeroItems) {
    $name = $it.releaseName -replace '^0000_',''
    # find which origin slug this entry belongs to (longest match wins to avoid e.g. 'arcane' eating 'technoarcane')
    $matchedSlug = $null
    foreach ($slug in ($originLore.Keys | Sort-Object -Property Length -Descending)) {
        if ($name.StartsWith($slug + '_') -or $name -eq $slug) {
            $matchedSlug = $slug
            break
        }
    }
    if (-not $matchedSlug) {
        Write-Warning "No origin matched for $($it.releaseName)"
        continue
    }
    $suffix = $name.Substring($matchedSlug.Length).TrimStart('_')

    $entry = [ordered]@{
        title       = $it.frontTitle
        lore        = $it.frontLore
        rules       = $it.frontDescription
        rarity      = $it.rarity
        source_key  = $it.releaseName
    }

    switch -Regex ($suffix) {
        '^echo_of_origin$'      { $buckets[$matchedSlug].echo = $entry }
        '^resonance(_i|_ii)?$'  { [void]$buckets[$matchedSlug].resonance.Add($entry) }
        '^perfect_harmony$'     { $buckets[$matchedSlug].harmony = $entry }
        default {
            $special = [ordered]@{
                type        = $suffix
                title       = $it.frontTitle
                lore        = $it.frontLore
                rules       = $it.frontDescription
                rarity      = $it.rarity
                source_key  = $it.releaseName
            }
            [void]$buckets[$matchedSlug].specials.Add($special)
        }
    }
}

# --- Assemble final structure ---
$origins = [ordered]@{}
foreach ($slug in $originLore.Keys) {
    $iconBase = Resolve-IconBase $slug
    $iconColor = Join-Path $iconsDir "$iconBase.webp"
    $bwName = if ($slug -eq 'crystalline') { 'crystaline_blackwhite' } else { "${iconBase}_blackwhite" }
    $iconBw = Join-Path $iconsDir "$bwName.webp"

    $iconExists   = Test-Path $iconColor
    $iconBwExists = Test-Path $iconBw

    $origins[$slug] = [ordered]@{
        slug             = $slug
        display_name     = Get-Title $slug
        icon_filename    = "$iconBase.webp"
        icon_filename_bw = "$bwName.webp"
        icon_exists      = $iconExists
        icon_bw_exists   = $iconBwExists
        lore             = $originLore[$slug]
        tiers            = [ordered]@{
            echo      = $buckets[$slug].echo
            resonance = @($buckets[$slug].resonance)
            harmony   = $buckets[$slug].harmony
            specials  = @($buckets[$slug].specials)
        }
    }
}

# --- Anomaly check ---
$anomalies = New-Object System.Collections.ArrayList
foreach ($slug in $origins.Keys) {
    $o = $origins[$slug]
    if (-not $o.tiers.echo)            { [void]$anomalies.Add("${slug}: missing Echo tier") }
    if ($o.tiers.resonance.Count -eq 0){ [void]$anomalies.Add("${slug}: missing Resonance tier") }
    if (-not $o.tiers.harmony)         { [void]$anomalies.Add("${slug}: missing Harmony tier") }
    if (-not $o.icon_exists)           { [void]$anomalies.Add("${slug}: color icon file not found ($($o.icon_filename))") }
    if (-not $o.icon_bw_exists)        { [void]$anomalies.Add("${slug}: b/w icon file not found ($($o.icon_filename_bw))") }
}

$root = [ordered]@{
    version       = '1.0'
    generated_at  = (Get-Date -Format 'yyyy-MM-dd')
    description   = 'Beneos Loot Origin set-bonus dataset. Merges origin lore (concept blurb) with Echo/Resonance/Harmony tier rules and Special-tier entries. Intended as handover for Claude Design.'
    source        = [ordered]@{
        lore   = 'beneos_common_database.json -> hover.origin.<slug>.message'
        tiers  = "items.json -> entries where releaseName starts with '0000_'"
        icons  = 'beneos_card_creator_v1/source/icons_origin/'
    }
    naming_notes  = [ordered]@{
        slug_to_icon_filename_overrides = $slugToIcon
        bw_filename_typo                = 'crystalline origin uses crystaline_blackwhite.webp (single L) -- source typo, not corrected here'
    }
    anomalies     = @($anomalies)
    origins       = $origins
}

$json = $root | ConvertTo-Json -Depth 12
# Force UTF-8 without BOM
[System.IO.File]::WriteAllText($outPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote $outPath"
Write-Host "Origins: $($origins.Count)"
Write-Host "Anomalies: $($anomalies.Count)"
if ($anomalies.Count -gt 0) {
    $anomalies | ForEach-Object { Write-Host "  - $_" }
}
