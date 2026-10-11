# AROMATIC Learning Library

Static training-library site for AROMATIC. One self-serving page (`index.html`) that lists every training kit and opens each PDF in a built-in reader (PDF.js).

The original V1.3 shipped as a single 160 MB HTML file with every PDF, cover, font and the PDF.js runtime inlined as base64. That made the first-byte wait painful and made weekly updates impossible without re-sending the whole monolith.

This repo splits that monolith into separate assets so the shell page is 2.8 MB and each PDF is only fetched when a user opens it, and so new programs can be added with a single commit per week.

## Layout

```
.
├── index.html              Slim shell: UI + CSS + Cairo font (2.8 MB)
├── data/
│   └── manifest.json       Source of truth: categories + kits metadata
├── pdfs/
│   ├── 01.pdf              One PDF per kit, loaded on demand
│   └── ...
├── covers/
│   ├── 01.png              One cover image per kit
│   └── ...
├── vendor/
│   ├── pdf.min.js          PDF.js 3.11.174 (viewer)
│   └── pdf.worker.min.js   PDF.js worker (loaded in a Web Worker)
└── scripts/
    ├── extract-from-monolith.ps1   One-off: splits the original 160 MB HTML
    ├── build-index.ps1             One-off: rebuilds the slim index.html
    ├── add-program.ps1             Weekly: adds a new kit (PDF + metadata)
    ├── serve.ps1                   Dev: tiny static server on localhost
    └── _loader-patch.js            Replacement loader (used by build-index.ps1)
```

## Hosting

The site is designed to be served over HTTP (GitHub Pages works out of the box). It will **not** work by double-clicking `index.html` because browsers block `fetch()` of local files under `file://`.

### Option A — GitHub Pages (recommended)

1. Push this repo to `github.com/<org>/AROMATIC_Library`.
2. In **Settings → Pages**, choose branch `main`, folder `/ (root)`.
3. The site goes live at `https://<org>.github.io/AROMATIC_Library/`.

### Option B — Local preview

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\serve.ps1 -Port 8765
```

Then open http://localhost:8765/.

## Weekly update workflow

Every week there's a new program. The steps:

```powershell
# 1. Add the new program (copies files into pdfs/ and covers/, updates manifest)
.\scripts\add-program.ps1 `
    -PdfPath   "C:\path\to\new-program.pdf" `
    -CoverPath "C:\path\to\cover.png" `
    -Title     "اسم الحقيبة" `
    -EnglishTitle "Program Name" `
    -CategoryId perfumes `
    -Description "وصف قصير" `
    -PageCount 24

# 2. Review the change
git status
git diff data/manifest.json

# 3. Commit & push
git add pdfs/NN.pdf covers/NN.png data/manifest.json
git commit -m "Add program: <title>"
git push
```

Within ~1 minute of the push, GitHub Pages has the new kit live.

Valid `CategoryId` values (match `data/manifest.json`):

| id            | title              |
|---------------|--------------------|
| perfumes      | العطور             |
| collections   | المجموعات والباقات |
| oils          | الزيوت العطرية     |
| devices       | الأجهزة            |
| fresheners    | المعطرات           |
| references    | الهرم العطري والمراجع |

To mark a kit as draft (not listed on the home page), set `status` to anything other than `"published"` in `data/manifest.json`.

## Updating an existing kit's PDF

Just replace the file at `pdfs/NN.pdf`, bump `updatedAt` and `sha256` in `data/manifest.json`, commit, push.

```powershell
# recompute sha256
(Get-FileHash .\pdfs\03.pdf -Algorithm SHA256).Hash.ToLower()
```

## Removing a kit

1. Delete the entry from `data/manifest.json`.
2. Delete `pdfs/NN.pdf` and `covers/NN.png`.
3. Commit, push.

(We keep sequential numbering only for new kits — gaps are fine.)

## Reproducing the split from the monolith

If a new monolithic `AROMATIC_Learning_Library_VX.html` is ever provided, re-run:

```powershell
.\scripts\extract-from-monolith.ps1 `
    -SourceHtml "C:\path\to\AROMATIC_Learning_Library_VX.html" `
    -OutDir .

.\scripts\build-index.ps1 `
    -SourceHtml "C:\path\to\AROMATIC_Learning_Library_VX.html" `
    -OutDir .
```

This rewrites `pdfs/`, `covers/`, `vendor/`, `data/manifest.json`, and `index.html`.

## Size & performance

| | Before (V1.3 monolith) | After (this repo) |
|---|---:|---:|
| First HTML byte → painted shell | 160 MB download | 2.8 MB download |
| Kit list render | after full HTML + base64 decode of 18 PDFs | after small `manifest.json` fetch |
| Opening one PDF | already in memory | ~2–24 MB fetch (varies by kit) |
| Updating one program | re-ship 160 MB | commit 1 PDF + manifest patch |
