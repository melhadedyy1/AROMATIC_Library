# Adds a new program (PDF + metadata) to the AROMATIC Library.
#
# Example:
#   .\add-program.ps1 `
#       -PdfPath "C:\path\to\new-program.pdf" `
#       -CoverPath "C:\path\to\new-cover.png" `
#       -Title "اسم الحقيبة" `
#       -EnglishTitle "Program Name" `
#       -CategoryId perfumes `
#       -Description "وصف الحقيبة" `
#       -PageCount 24
#
# The script:
#   1. Picks the next free kit number (02 digits).
#   2. Copies pdf + cover into pdfs/XX.pdf and covers/XX.png.
#   3. Computes sha256 of the PDF for integrity.
#   4. Appends a new entry to data/manifest.json (preserving existing content).
#
# After running, commit & push:
#   git add .
#   git commit -m "Add program: $Title"
#   git push

param(
    [Parameter(Mandatory=$true)][string]$PdfPath,
    [Parameter(Mandatory=$true)][string]$CoverPath,
    [Parameter(Mandatory=$true)][string]$Title,
    [Parameter(Mandatory=$true)][string]$EnglishTitle,
    [Parameter(Mandatory=$true)][string]$CategoryId,
    [string]$Description = "",
    [string]$Details = "",
    [int]$PageCount = 0,
    [string[]]$Tags = @(),
    [string]$Status = "published",
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $PdfPath))   { throw "PDF not found: $PdfPath" }
if (-not (Test-Path $CoverPath)) { throw "Cover not found: $CoverPath" }

$manifestPath = Join-Path $RepoRoot 'data\manifest.json'
if (-not (Test-Path $manifestPath)) { throw "Manifest not found: $manifestPath" }

$manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

# Validate category id against manifest
if (-not ($manifest.categories | Where-Object { $_.id -eq $CategoryId })) {
    $known = ($manifest.categories | ForEach-Object { $_.id }) -join ', '
    throw "Unknown categoryId '$CategoryId'. Known categories: $known"
}

# Pick next kit number
$existingNums = $manifest.kits | ForEach-Object {
    if ($_.id -match '^kit-(\d+)$') { [int]$Matches[1] } else { 0 }
}
$next = (($existingNums | Measure-Object -Maximum).Maximum) + 1
$numStr = '{0:D2}' -f $next
$kitId  = "kit-$numStr"

$pdfDst   = Join-Path $RepoRoot "pdfs\$numStr.pdf"
$coverDst = Join-Path $RepoRoot "covers\$numStr.png"

Copy-Item $PdfPath   $pdfDst   -Force
Copy-Item $CoverPath $coverDst -Force

$sha = (Get-FileHash $pdfDst -Algorithm SHA256).Hash.ToLower()
$today = Get-Date -Format 'yyyy-MM-dd'

if (-not $Tags -or $Tags.Count -eq 0) { $Tags = @($Title, $EnglishTitle) }

$newKit = [ordered]@{
    id               = $kitId
    title            = $Title
    englishTitle     = $EnglishTitle
    categoryId       = $CategoryId
    description      = $Description
    details          = $Details
    pdf              = "pdfs/$numStr.pdf"
    cover            = "covers/$numStr.png"
    pageCount        = $PageCount
    tags             = $Tags
    status           = $Status
    order            = $next
    createdAt        = $today
    updatedAt        = $today
    sha256           = $sha
    originalFilename = [IO.Path]::GetFileName($PdfPath)
}

$manifest.kits = @($manifest.kits) + [pscustomobject]$newKit

$json = $manifest | ConvertTo-Json -Depth 20
[IO.File]::WriteAllText($manifestPath, $json, [Text.UTF8Encoding]::new($false))

Write-Host "Added $kitId:"
Write-Host "  Title       : $Title"
Write-Host "  Category    : $CategoryId"
Write-Host "  PDF         : pdfs/$numStr.pdf  (sha256 $sha)"
Write-Host "  Cover       : covers/$numStr.png"
Write-Host "  Manifest    : $manifestPath"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  git add pdfs/$numStr.pdf covers/$numStr.png data/manifest.json"
Write-Host "  git commit -m `"Add program: $Title`""
Write-Host "  git push"
