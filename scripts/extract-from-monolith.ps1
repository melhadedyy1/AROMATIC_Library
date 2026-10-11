# Extracts PDFs, covers, pdf-worker, pdfjsLib and the manifest JSON
# out of the monolithic AROMATIC_Learning_Library_V1.3 HTML file,
# and writes a slim index.html that loads them as external assets.
#
# Usage:
#   .\extract-from-monolith.ps1 -SourceHtml "D:\MH\AROMATIC_Learning_Library_V1.3_REVIEW_READ_ONLY (1).html"
#                               -OutDir "D:\AROMATIC_Library"

param(
    [Parameter(Mandatory=$true)][string]$SourceHtml,
    [Parameter(Mandatory=$true)][string]$OutDir
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SourceHtml)) { throw "Source HTML not found: $SourceHtml" }

Write-Host "Reading source HTML..."
$content = [IO.File]::ReadAllText($SourceHtml, [Text.Encoding]::UTF8)
Write-Host ("  size: {0:N0} bytes" -f $content.Length)

New-Item -ItemType Directory -Force -Path "$OutDir\pdfs"   | Out-Null
New-Item -ItemType Directory -Force -Path "$OutDir\covers" | Out-Null
New-Item -ItemType Directory -Force -Path "$OutDir\vendor" | Out-Null
New-Item -ItemType Directory -Force -Path "$OutDir\data"   | Out-Null

# ----- Extract every <script type="application/octet-stream" id="asset:X">BASE64</script> -----
$assetPattern = '<script\s+type="application/octet-stream"\s+id="asset:([^"]+)">([^<]*)</script>'
$assetMatches = [regex]::Matches($content, $assetPattern)
Write-Host ("Found {0} embedded assets." -f $assetMatches.Count)

$written = 0
foreach ($m in $assetMatches) {
    $id  = $m.Groups[1].Value
    $b64 = $m.Groups[2].Value.Trim()
    try {
        $bytes = [Convert]::FromBase64String($b64)
    } catch {
        Write-Warning "Base64 decode failed for asset '$id': $_"
        continue
    }

    if ($id -eq 'pdf-worker') {
        $outFile = Join-Path $OutDir 'vendor\pdf.worker.min.js'
    } else {
        # id looks like 'pdfs/01.pdf' or 'covers/01.png' — matches our target layout
        $outFile = Join-Path $OutDir ($id -replace '/', '\')
    }

    $parent = Split-Path $outFile -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllBytes($outFile, $bytes)
    Write-Host ("  wrote {0,-40} {1,10:N0} bytes" -f $id, $bytes.Length)
    $written++
}
Write-Host ("Extracted {0} asset files." -f $written)

# ----- Extract manifest JSON -----
$metaPattern = '<script\s+type="application/json"\s+id="embedded-metadata">([\s\S]*?)</script>'
$metaMatch = [regex]::Match($content, $metaPattern)
if (-not $metaMatch.Success) { throw "embedded-metadata JSON block not found" }
$manifestJson = $metaMatch.Groups[1].Value.Trim()
# Pretty-print by round-tripping through ConvertFrom-Json
try {
    $obj = $manifestJson | ConvertFrom-Json
    $pretty = $obj | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText("$OutDir\data\manifest.json", $pretty, [Text.UTF8Encoding]::new($false))
} catch {
    # Fallback: write as-is
    [IO.File]::WriteAllText("$OutDir\data\manifest.json", $manifestJson, [Text.UTF8Encoding]::new($false))
}
Write-Host "Wrote data\manifest.json"

# ----- Extract pdfjsLib (line 646 — the webpackUniversalModuleDefinition block) -----
# We take everything between the manifest closing tag's trailing </script> and the first
# user-defined function (`function embeddedURL`). The pdf.js payload sits in there as
# minified JS. To be robust, we grab the big <script> that contains "webpackUniversalModuleDefinition".
$pdfjsScriptPattern = '<script[^>]*>((?:[^<]|<(?!/script))*?webpackUniversalModuleDefinition(?:[^<]|<(?!/script))*?)</script>'
$pdfjsMatch = [regex]::Match($content, $pdfjsScriptPattern)
if ($pdfjsMatch.Success) {
    $pdfjsCode = $pdfjsMatch.Groups[1].Value
    [IO.File]::WriteAllText("$OutDir\vendor\pdf.min.js", $pdfjsCode, [Text.UTF8Encoding]::new($false))
    Write-Host ("Wrote vendor\pdf.min.js ({0:N0} bytes)" -f $pdfjsCode.Length)
} else {
    Write-Warning "Could not isolate pdfjsLib script block automatically."
}

Write-Host ""
Write-Host "Done. Next: generate a slim index.html with build-index.ps1"
