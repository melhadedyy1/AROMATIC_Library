# Tiny static file server for local preview of the AROMATIC Library.
# Default:  .\serve.ps1              -> serves cwd on http://localhost:8765
# Options:  -Port 9000  -Root ..     -> different port / root

param(
    [int]$Port = 8765,
    [string]$Root = (Get-Location).Path
)

$Root = (Resolve-Path $Root).Path
$listener = [System.Net.HttpListener]::new()
$prefix = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)
$listener.Start()
Write-Host "Serving $Root at $prefix (Ctrl+C to stop)"

$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.htm'  = 'text/html; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.mjs'  = 'application/javascript; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.gif'  = 'image/gif'
    '.svg'  = 'image/svg+xml'
    '.webp' = 'image/webp'
    '.pdf'  = 'application/pdf'
    '.woff2'= 'font/woff2'
    '.woff' = 'font/woff'
    '.ttf'  = 'font/ttf'
    '.ico'  = 'image/x-icon'
    '.txt'  = 'text/plain; charset=utf-8'
    '.map'  = 'application/json; charset=utf-8'
}

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $res = $ctx.Response
        try {
            $rel = [Uri]::UnescapeDataString($req.Url.AbsolutePath.TrimStart('/'))
            if ([string]::IsNullOrEmpty($rel)) { $rel = 'index.html' }
            $safe = Join-Path $Root $rel
            $full = [IO.Path]::GetFullPath($safe)
            if (-not $full.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)) {
                $res.StatusCode = 403
            } elseif (Test-Path $full -PathType Container) {
                $idx = Join-Path $full 'index.html'
                if (Test-Path $idx) { $full = $idx } else { $res.StatusCode = 404 }
            }
            if ($res.StatusCode -eq 200 -and (Test-Path $full -PathType Leaf)) {
                $ext = [IO.Path]::GetExtension($full).ToLower()
                if ($mime.ContainsKey($ext)) { $res.ContentType = $mime[$ext] } else { $res.ContentType = 'application/octet-stream' }
                $res.Headers['Cache-Control'] = 'no-store'
                $bytes = [IO.File]::ReadAllBytes($full)
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            } elseif ($res.StatusCode -eq 200) {
                $res.StatusCode = 404
                $msg = [Text.Encoding]::UTF8.GetBytes("404 Not Found: $rel")
                $res.OutputStream.Write($msg, 0, $msg.Length)
            }
            Write-Host ("{0} {1} {2}" -f $res.StatusCode, $req.HttpMethod, $rel)
        } catch {
            Write-Host "Error: $_"
            try { $res.StatusCode = 500 } catch {}
        } finally {
            try { $res.OutputStream.Close() } catch {}
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
}
