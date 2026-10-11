# Rebuilds a slim index.html from the monolithic source by:
#   - stripping embedded <script id="asset:*"> (PDFs/covers/pdf-worker)
#   - stripping the inline embedded-metadata JSON (served via fetch instead)
#   - replacing the inline pdfjsLib bundle with <script src="vendor/pdf.min.js">
#   - rewriting embeddedURL / coverSource / loader to use external file paths
#
# Run after extract-from-monolith.ps1 has populated pdfs/, covers/, vendor/, data/.

param(
    [Parameter(Mandatory=$true)][string]$SourceHtml,
    [Parameter(Mandatory=$true)][string]$OutDir
)

$ErrorActionPreference = 'Stop'

Write-Host "Loading source HTML..."
$c = [IO.File]::ReadAllText($SourceHtml, [Text.Encoding]::UTF8)
Write-Host ("  original: {0:N0} bytes" -f $c.Length)

# ----- 1. Remove all <script type="application/octet-stream" id="asset:X">BASE64</script> -----
$assetRe = [regex]'<script\s+type="application/octet-stream"\s+id="asset:[^"]+">[^<]*</script>'
$before = $c.Length
$c = $assetRe.Replace($c, '')
Write-Host ("  stripped asset blocks: -{0:N0} bytes" -f ($before - $c.Length))

# ----- 2. Remove the embedded manifest JSON (we'll fetch it instead) -----
$metaRe = [regex]::new('<script\s+type="application/json"\s+id="embedded-metadata">[\s\S]*?</script>', 'Singleline')
$before = $c.Length
$c = $metaRe.Replace($c, '')
Write-Host ("  stripped embedded-metadata: -{0:N0} bytes" -f ($before - $c.Length))

# ----- 3. Replace the inline pdfjsLib bundle with an external <script src=...> -----
# The pdfjsLib script sits inside <script>/** ... */ !function webpackUniversalModuleDefinition ... </script>
$pdfjsRe = [regex]::new('<script>\s*/\*\*[\s\S]*?webpackUniversalModuleDefinition[\s\S]*?</script>', 'Singleline')
$before = $c.Length
$c = $pdfjsRe.Replace($c, '<script src="vendor/pdf.min.js"></script>', 1)
Write-Host ("  swapped pdfjsLib for external file: -{0:N0} bytes" -f ($before - $c.Length))

# ----- 4. Rewrite embeddedURL() so it returns a plain URL (not a base64 blob URL) -----
$oldEmbeddedURL = [regex]'function embeddedURL\(path\)\{[\s\S]*?embeddedURLs\.set\(path,url\);return url\}'
$newEmbeddedURL = "function embeddedURL(path){return path==='pdf-worker'?'vendor/pdf.worker.min.js':path}"
if (-not $oldEmbeddedURL.IsMatch($c)) { throw "embeddedURL function not found" }
$c = $oldEmbeddedURL.Replace($c, $newEmbeddedURL, 1)
Write-Host "  rewrote embeddedURL()"

# ----- 5. Rewrite coverSource() so it just returns the relative path -----
$oldCoverSource = [regex]"function coverSource\(path\)\{[^}]*?getElementById\('asset:'\+path\)[^}]*?\}"
$newCoverSource = "function coverSource(path){if(!path)return '';if(path.startsWith('data:'))return path;return path}"
if (-not $oldCoverSource.IsMatch($c)) { throw "coverSource function not found" }
$c = $oldCoverSource.Replace($c, $newCoverSource, 1)
Write-Host "  rewrote coverSource()"

# ----- 6. Rewrite the startup IIFE to fetch manifest.json instead of reading inline JSON -----
$oldLoader = [regex]@'
\(async\(\)=>\{try\{data=JSON\.parse\(document\.getElementById\('embedded-metadata'\)\.textContent\);[^}]*?render\(\)\}catch\(err\)\{[^}]*?\}\}\)\(\);
'@
$loaderFile = Join-Path $PSScriptRoot '_loader-patch.js'
if (-not (Test-Path $loaderFile)) { throw "Loader patch file not found: $loaderFile" }
$newLoader = [IO.File]::ReadAllText($loaderFile, [Text.UTF8Encoding]::new($false)).TrimEnd("`r","`n")
if (-not $oldLoader.IsMatch($c)) { throw "startup loader IIFE not found" }
$c = $oldLoader.Replace($c, $newLoader, 1)
Write-Host "  rewrote startup loader"

# ----- Write result -----
$outFile = Join-Path $OutDir 'index.html'
[IO.File]::WriteAllText($outFile, $c, [Text.UTF8Encoding]::new($false))
Write-Host ("Wrote {0} ({1:N0} bytes, {2:N1} MB)" -f $outFile, $c.Length, ($c.Length/1MB))
