# Beneos Reality-Check
# Read-only audit between release folders, search-engine DBs, and thumbnail folders.
# Produces Markdown + JSON reports. Writes nothing back to DBs or release folders.

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Today     = Get-Date -Format 'yyyy-MM-dd'

$RELEASES = @{
    tokens = 'D:\PNP_Game\FoundryVTT_Assets\Data\beneos_assets\beneos_tokens'
    items  = 'D:\PNP_Game\FoundryVTT_Assets\Data\beneos_assets\beneos_items'
    spells = 'D:\PNP_Game\FoundryVTT_Assets\Data\beneos_assets\beneos_spells'
}
$DBS = @{
    tokens = Join-Path $ScriptDir 'tokens\beneos_tokens_database_v2.json'
    items  = Join-Path $ScriptDir 'items\beneos_items_database.json'
    spells = Join-Path $ScriptDir 'spells\beneos_spells_database.json'
}
$THUMBS = @{
    tokens = Join-Path $ScriptDir 'tokens\thumbnails_v2'
    items  = Join-Path $ScriptDir 'items\thumbnails'
    spells = Join-Path $ScriptDir 'spells\thumbnails'
}

# Utility / pipeline / scratch folders that live next to the asset folders but
# are NOT release assets. Filtered out before any DB comparison so they don't
# pollute the missing-entries list.
$UTILITY_FOLDERS = @{
    tokens = @('_img_update','_legacy','_srd_pipeline','beneos_journal_v2','beneos_topdown','c')
    items  = @('_backup_2026-05-08','_backup_2026-05-05','_0000_printer_friendly_cards')
    spells = @('_backup_2026-05-08','_backup_2026-05-05','_0000_printer_friendly_cards')
}

function Test-IsUtilityFolder {
    param([string]$Type, [string]$Name)
    if ($UTILITY_FOLDERS[$Type] -contains $Name) { return $true }
    if ($Name.StartsWith('_'))                   { return $true }   # all _-prefixed = utility
    return $false
}

function Get-EffectiveReleaseFolders {
    param([string]$Type)
    $all = Get-ChildItem -LiteralPath $RELEASES[$Type] -Directory -ErrorAction Stop |
           Select-Object -ExpandProperty Name
    $filtered = $all | Where-Object {
        if (Test-IsUtilityFolder -Type $Type -Name $_) { return $false }
        if ($Type -eq 'tokens') { return $true }
        # items + spells: ignore 0000_* unless 0000_srd*
        if ($_ -like '0000_srd*') { return $true }
        if ($_ -like '0000_*')    { return $false }
        return $true
    }
    return ,@($filtered)
}

function Get-IgnoredFolders {
    param([string]$Type)
    $all = Get-ChildItem -LiteralPath $RELEASES[$Type] -Directory |
           Select-Object -ExpandProperty Name
    $utility = @($all | Where-Object { Test-IsUtilityFolder -Type $Type -Name $_ })
    if ($Type -eq 'tokens') {
        return [pscustomobject]@{ utility = $utility; stub_0000 = @() }
    }
    $stub = @($all | Where-Object { $_ -like '0000_*' -and -not ($_ -like '0000_srd*') -and -not (Test-IsUtilityFolder -Type $Type -Name $_) })
    return [pscustomobject]@{ utility = $utility; stub_0000 = $stub }
}

function Test-IsStubThumbnail {
    param([string]$Type, [string]$ThumbName)
    # Items/spells: <key>-icon.webp. Stub if key starts with 0000_ but not 0000_srd_
    if ($Type -eq 'tokens') { return $false }
    if ($ThumbName -match '^(0000_)(.+)-icon\.webp$') {
        $key = '0000_' + $Matches[2]
        if ($key -like '0000_srd*') { return $false }
        return $true
    }
    return $false
}

function Get-TokenActualVariants {
    param([string]$Key)
    $folder = Join-Path $RELEASES.tokens $Key
    $files  = Get-ChildItem -LiteralPath $folder -Filter "$Key-*-token.webp" -File -ErrorAction SilentlyContinue
    if (-not $files) { return 0 }
    $max = 0
    foreach ($f in $files) {
        if ($f.BaseName -match "^$([regex]::Escape($Key))-(\d+)-token$") {
            $n = [int]$Matches[1]
            if ($n -gt $max) { $max = $n }
        }
    }
    return $max
}

function Load-DbContent {
    param([string]$Path)
    $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    return $json.content
}

function Get-DbKeys {
    param($Content)
    return ,@($Content.PSObject.Properties.Name)
}

# ----- Per-type analysis -----

function Analyze-Tokens {
    Write-Host "Analyzing tokens..." -ForegroundColor Cyan
    $release = Get-EffectiveReleaseFolders -Type 'tokens'
    $content = Load-DbContent -Path $DBS.tokens
    $dbKeys  = Get-DbKeys -Content $content
    $thumbs  = Get-ChildItem -LiteralPath $THUMBS.tokens -File -Filter '*-db.webp' |
              Select-Object -ExpandProperty Name

    $releaseSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$release, [System.StringComparer]::OrdinalIgnoreCase)
    $dbSet      = [System.Collections.Generic.HashSet[string]]::new([string[]]$dbKeys, [System.StringComparer]::OrdinalIgnoreCase)
    $thumbSet   = [System.Collections.Generic.HashSet[string]]::new([string[]]$thumbs, [System.StringComparer]::OrdinalIgnoreCase)

    $orphans       = @($dbKeys  | Where-Object { -not $releaseSet.Contains($_) } | Sort-Object)
    $missingEntries = @($release | Where-Object { -not $dbSet.Contains($_) } | Sort-Object)

    $missingThumbs   = New-Object System.Collections.Generic.List[object]
    $variantMismatch = New-Object System.Collections.Generic.List[object]
    $expectedThumbs  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($key in $dbKeys) {
        $entry      = $content.$key
        $nbVariants = [int]$entry.properties.nb_variants
        if ($nbVariants -lt 1) { $nbVariants = 1 }

        # Variant mismatch only meaningful when a release folder exists
        if ($releaseSet.Contains($key)) {
            $actual = Get-TokenActualVariants -Key $key
            if ($actual -ne $nbVariants) {
                $variantMismatch.Add([pscustomobject]@{
                    key       = $key
                    db        = $nbVariants
                    actual    = $actual
                    direction = if ($actual -lt $nbVariants) { 'shrink' } else { 'grow' }
                }) | Out-Null
            }
        }

        # Missing thumbnails (1..nb_variants must each exist)
        $missingForKey = @()
        for ($i = 1; $i -le $nbVariants; $i++) {
            $expected = "$key-$i-db.webp"
            $expectedThumbs.Add($expected) | Out-Null
            if (-not $thumbSet.Contains($expected)) { $missingForKey += $i }
        }
        if ($missingForKey.Count -gt 0) {
            $missingThumbs.Add([pscustomobject]@{
                key             = $key
                missing_variants = $missingForKey
                nb_variants     = $nbVariants
            }) | Out-Null
        }
    }

    $orphanThumbs = @($thumbs | Where-Object { -not $expectedThumbs.Contains($_) } | Sort-Object)

    return [pscustomobject]@{
        type             = 'tokens'
        release_count    = $release.Count
        db_count         = $dbKeys.Count
        thumb_count      = $thumbs.Count
        orphans          = $orphans
        missing_entries  = $missingEntries
        missing_thumbs   = $missingThumbs.ToArray()
        orphan_thumbs    = $orphanThumbs
        variant_mismatch = $variantMismatch.ToArray()
    }
}

function Analyze-IconType {
    param([string]$Type) # items | spells
    Write-Host "Analyzing $Type..." -ForegroundColor Cyan
    $release = Get-EffectiveReleaseFolders -Type $Type
    $ignored = Get-IgnoredFolders -Type $Type
    $content = Load-DbContent -Path $DBS[$Type]
    $dbKeys  = Get-DbKeys -Content $content
    $allThumbs = Get-ChildItem -LiteralPath $THUMBS[$Type] -File -Filter '*-icon.webp' |
                 Select-Object -ExpandProperty Name
    # Split thumbnails: real (in scope) vs stub (0000_* non-srd)
    $thumbs     = @($allThumbs | Where-Object { -not (Test-IsStubThumbnail -Type $Type -ThumbName $_) })
    $stubThumbs = @($allThumbs | Where-Object {       Test-IsStubThumbnail -Type $Type -ThumbName $_  })

    $releaseSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$release, [System.StringComparer]::OrdinalIgnoreCase)
    $dbSet      = [System.Collections.Generic.HashSet[string]]::new([string[]]$dbKeys, [System.StringComparer]::OrdinalIgnoreCase)
    $thumbSet   = [System.Collections.Generic.HashSet[string]]::new([string[]]$thumbs, [System.StringComparer]::OrdinalIgnoreCase)

    $orphans        = @($dbKeys  | Where-Object { -not $releaseSet.Contains($_) } | Sort-Object)
    $missingEntries = @($release | Where-Object { -not $dbSet.Contains($_) } | Sort-Object)

    $missingThumbs  = New-Object System.Collections.Generic.List[object]
    $expectedThumbs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $dbKeys) {
        $expected = "$key-icon.webp"
        $expectedThumbs.Add($expected) | Out-Null
        if (-not $thumbSet.Contains($expected)) {
            $missingThumbs.Add([pscustomobject]@{ key = $key; expected = $expected }) | Out-Null
        }
    }
    $orphanThumbs = @($thumbs | Where-Object { -not $expectedThumbs.Contains($_) } | Sort-Object)

    return [pscustomobject]@{
        type             = $Type
        release_count    = $release.Count
        ignored_utility  = $ignored.utility
        ignored_stub     = $ignored.stub_0000
        db_count         = $dbKeys.Count
        thumb_count      = $thumbs.Count
        stub_thumb_count = $stubThumbs.Count
        orphans          = $orphans
        missing_entries  = $missingEntries
        missing_thumbs   = $missingThumbs.ToArray()
        orphan_thumbs    = $orphanThumbs
    }
}

# ----- Run all three -----
$tokensResult = Analyze-Tokens
$itemsResult  = Analyze-IconType -Type 'items'
$spellsResult = Analyze-IconType -Type 'spells'

# ----- Write JSON -----
$jsonOut = [pscustomobject]@{
    generated_at = (Get-Date).ToString('o')
    tokens       = $tokensResult
    items        = $itemsResult
    spells       = $spellsResult
}
$jsonPath = Join-Path $ScriptDir "reality_check_$Today.json"
$jsonOut | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
Write-Host "JSON written: $jsonPath" -ForegroundColor Green

# ----- Write Markdown -----
$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# Beneos Reality-Check Report ($Today)")
[void]$md.AppendLine()
[void]$md.AppendLine("## Zusammenfassung")
[void]$md.AppendLine()
[void]$md.AppendLine("| Typ | Release (effektiv) | DB | Thumbs | Orphans | Missing | Bad Thumbs | Orphan Thumbs | Variant-Mismatch |")
[void]$md.AppendLine("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
[void]$md.AppendLine("| Tokens | $($tokensResult.release_count) | $($tokensResult.db_count) | $($tokensResult.thumb_count) | $($tokensResult.orphans.Count) | $($tokensResult.missing_entries.Count) | $($tokensResult.missing_thumbs.Count) | $($tokensResult.orphan_thumbs.Count) | $($tokensResult.variant_mismatch.Count) |")
[void]$md.AppendLine("| Items  | $($itemsResult.release_count) (stub: $($itemsResult.ignored_stub.Count), util: $($itemsResult.ignored_utility.Count)) | $($itemsResult.db_count) | $($itemsResult.thumb_count) | $($itemsResult.orphans.Count) | $($itemsResult.missing_entries.Count) | $($itemsResult.missing_thumbs.Count) | $($itemsResult.orphan_thumbs.Count) | — |")
[void]$md.AppendLine("| Spells | $($spellsResult.release_count) (stub: $($spellsResult.ignored_stub.Count), util: $($spellsResult.ignored_utility.Count)) | $($spellsResult.db_count) | $($spellsResult.thumb_count) | $($spellsResult.orphans.Count) | $($spellsResult.missing_entries.Count) | $($spellsResult.missing_thumbs.Count) | $($spellsResult.orphan_thumbs.Count) | — |")
[void]$md.AppendLine()

function Append-List {
    param($Builder, [string]$Header, [string[]]$Items, [int]$Limit = 0)
    [void]$Builder.AppendLine("### $Header ($($Items.Count))")
    if ($Items.Count -eq 0) {
        [void]$Builder.AppendLine("_keine_")
        [void]$Builder.AppendLine()
        return
    }
    $shown = if ($Limit -gt 0 -and $Items.Count -gt $Limit) { $Items[0..($Limit-1)] } else { $Items }
    foreach ($i in $shown) { [void]$Builder.AppendLine("- ``$i``") }
    if ($Limit -gt 0 -and $Items.Count -gt $Limit) {
        [void]$Builder.AppendLine("- _… $($Items.Count - $Limit) weitere — siehe JSON_")
    }
    [void]$Builder.AppendLine()
}

# Tokens section
[void]$md.AppendLine("## Tokens")
[void]$md.AppendLine()
Append-List -Builder $md -Header 'DB-Orphans (kein Release-Ordner)' -Items $tokensResult.orphans
Append-List -Builder $md -Header 'Missing-Entries (Release ohne DB)' -Items $tokensResult.missing_entries

[void]$md.AppendLine("### Missing-Thumbnails ($($tokensResult.missing_thumbs.Count))")
if ($tokensResult.missing_thumbs.Count -eq 0) {
    [void]$md.AppendLine("_keine_")
} else {
    foreach ($m in $tokensResult.missing_thumbs) {
        $vlist = ($m.missing_variants -join ', ')
        [void]$md.AppendLine("- ``$($m.key)`` — fehlende Varianten: $vlist (DB nb_variants=$($m.nb_variants))")
    }
}
[void]$md.AppendLine()

Append-List -Builder $md -Header 'Orphan-Thumbnails (in thumbnails_v2/, aber DB kennt sie nicht)' -Items $tokensResult.orphan_thumbs -Limit 200

[void]$md.AppendLine("### Variant-Mismatch ($($tokensResult.variant_mismatch.Count))")
if ($tokensResult.variant_mismatch.Count -eq 0) {
    [void]$md.AppendLine("_keine_")
} else {
    foreach ($v in $tokensResult.variant_mismatch) {
        [void]$md.AppendLine("- ``$($v.key)``: DB=$($v.db), real=$($v.actual) → DB korrigieren auf $($v.actual) [$($v.direction)]")
    }
}
[void]$md.AppendLine()

# Items + Spells sections
foreach ($r in @($itemsResult, $spellsResult)) {
    $title = (Get-Culture).TextInfo.ToTitleCase($r.type)
    [void]$md.AppendLine("## $title")
    [void]$md.AppendLine()
    $utilList = if ($r.ignored_utility.Count -gt 0) { ($r.ignored_utility | ForEach-Object { '`' + $_ + '`' }) -join ', ' } else { '-' }
    [void]$md.AppendLine("Ignorierte 0000_-Stub-Ordner: $($r.ignored_stub.Count) - Utility/Backup-Ordner: $($r.ignored_utility.Count) ($utilList)")
    $sample = @($r.ignored_stub | Select-Object -First 10)
    if ($sample.Count -gt 0) {
        $sampleList = ($sample | ForEach-Object { '`' + $_ + '`' }) -join ', '
        [void]$md.AppendLine("Stub-Beispiele: $sampleList")
    }
    [void]$md.AppendLine("Stub-Thumbnails (in Thumbnail-Ordner, aber 0000_-Stub): $($r.stub_thumb_count) - werden nicht als Orphans gewertet")
    [void]$md.AppendLine()
    Append-List -Builder $md -Header 'DB-Orphans (kein Release-Ordner)' -Items $r.orphans
    Append-List -Builder $md -Header 'Missing-Entries (Release ohne DB)' -Items $r.missing_entries

    [void]$md.AppendLine("### Missing-Thumbnails ($($r.missing_thumbs.Count))")
    if ($r.missing_thumbs.Count -eq 0) {
        [void]$md.AppendLine("_keine_")
    } else {
        foreach ($m in $r.missing_thumbs) {
            [void]$md.AppendLine("- ``$($m.key)`` → erwartet ``$($m.expected)``")
        }
    }
    [void]$md.AppendLine()

    Append-List -Builder $md -Header 'Orphan-Thumbnails' -Items $r.orphan_thumbs -Limit 200
}

$mdPath = Join-Path $ScriptDir "reality_check_report_$Today.md"
$md.ToString() | Set-Content -LiteralPath $mdPath -Encoding UTF8
Write-Host "Markdown written: $mdPath" -ForegroundColor Green

# Console summary
Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Yellow
foreach ($r in @($tokensResult, $itemsResult, $spellsResult)) {
    $vm = if ($r.PSObject.Properties.Name -contains 'variant_mismatch') { $r.variant_mismatch.Count } else { '-' }
    Write-Host ("{0,-7} release={1,5}  db={2,5}  thumbs={3,5}  orphans={4,4}  missing={5,4}  badThumbs={6,4}  orphanThumbs={7,5}  varMismatch={8}" -f `
        $r.type, $r.release_count, $r.db_count, $r.thumb_count, $r.orphans.Count, $r.missing_entries.Count, $r.missing_thumbs.Count, $r.orphan_thumbs.Count, $vm)
}
