<#
.SYNOPSIS
    Draws the repository banner / GitHub social-preview image (1280x640 PNG) with nothing but GDI+.
    Output: assets\banner.png  (also usable as the repo's Social preview image: Settings > General > Social preview)
#>
param([string]$OutPath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $OutPath) { $OutPath = Join-Path (Split-Path -Parent $here) 'assets\banner.png' }
New-Item -ItemType Directory -Path (Split-Path -Parent $OutPath) -Force | Out-Null

$W = 1280; $H = 640
$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.InterpolationMode = 'HighQualityBicubic'

function C([int]$a, [int]$r, [int]$gg, [int]$b) { [System.Drawing.Color]::FromArgb($a, $r, $gg, $b) }
function PF([double]$x, [double]$y) { New-Object System.Drawing.PointF ([single]$x), ([single]$y) }

# --- background: deep navy -> indigo diagonal gradient --------------------
$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Point 0, 0), (New-Object System.Drawing.Point $W, $H), (C 255 9 13 32), (C 255 24 34 88)
$g.FillRectangle($bg, 0, 0, $W, $H)

# subtle grid
$gridPen = New-Object System.Drawing.Pen (C 18 120 160 255), 1
for ($x = 0; $x -lt $W; $x += 40) { $g.DrawLine($gridPen, $x, 0, $x, $H) }
for ($y = 0; $y -lt $H; $y += 40) { $g.DrawLine($gridPen, 0, $y, $W, $y) }

# glow behind the rune (stacked translucent ellipses)
$cx = 300; $cy = 320
for ($i = 12; $i -ge 1; $i--) {
    $rad = 40 + $i * 22
    $glow = New-Object System.Drawing.SolidBrush (C ([int](10 + (12 - $i) * 1.2)) 40 140 255)
    $g.FillEllipse($glow, $cx - $rad, $cy - $rad, $rad * 2, $rad * 2)
}

# signal arcs to the right of the rune
for ($i = 1; $i -le 3; $i++) {
    $pen = New-Object System.Drawing.Pen (C ([int](150 - $i * 35)) 90 200 255), ([single](10 - $i * 2))
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    $r = 150 + $i * 48
    $g.DrawArc($pen, [single]($cx - $r), [single]($cy - $r), [single]($r * 2), [single]($r * 2), -38, 76)
}

# the Bluetooth rune
$runePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 26
$runePen.StartCap = 'Round'; $runePen.EndCap = 'Round'; $runePen.LineJoin = 'Round'
$s = 300
$pts = @((PF ($cx - $s * 0.20) ($cy - $s * 0.18)), (PF ($cx + $s * 0.18) ($cy + $s * 0.16)), (PF $cx ($cy + $s * 0.34)), (PF $cx ($cy - $s * 0.34)), (PF ($cx + $s * 0.18) ($cy - $s * 0.16)), (PF ($cx - $s * 0.20) ($cy + $s * 0.18)))
$shadowPen = New-Object System.Drawing.Pen (C 90 0 0 0), 34; $shadowPen.StartCap = 'Round'; $shadowPen.EndCap = 'Round'; $shadowPen.LineJoin = 'Round'
$g.DrawLines($shadowPen, [System.Drawing.PointF[]]($pts | ForEach-Object { PF ($_.X + 6) ($_.Y + 8) }))
$g.DrawLines($runePen, [System.Drawing.PointF[]]$pts)

# "fixed" badge: yellow ring with a bold check mark, bottom-right of the rune
$bx = $cx + 118; $by = $cy + 120
$g.FillEllipse((New-Object System.Drawing.SolidBrush (C 255 250 204 21)), $bx - 46, $by - 46, 92, 92)
$g.FillEllipse((New-Object System.Drawing.SolidBrush (C 255 9 13 32)), $bx - 38, $by - 38, 76, 76)
$wp = New-Object System.Drawing.Pen (C 255 250 204 21), 11; $wp.StartCap = 'Round'; $wp.EndCap = 'Round'; $wp.LineJoin = 'Round'
$g.DrawLines($wp, [System.Drawing.PointF[]]@((PF ($bx - 20) ($by + 2)), (PF ($bx - 6) ($by + 16)), (PF ($bx + 22) ($by - 14))))

# --- text -------------------------------------------------------------------
$titleFont = New-Object System.Drawing.Font 'Segoe UI', 66, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$subFont   = New-Object System.Drawing.Font 'Segoe UI', 30, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
$pillFont  = New-Object System.Drawing.Font 'Segoe UI', 21, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$footFont  = New-Object System.Drawing.Font 'Segoe UI', 19, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
$white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$grey  = New-Object System.Drawing.SolidBrush (C 255 190 200 225)
$dim   = New-Object System.Drawing.SolidBrush (C 255 130 145 185)

$tx = 560; $ty = 150
$g.DrawString('Windows', $titleFont, $white, $tx, $ty)
$g.DrawString('Bluetooth Fixer', $titleFont, $white, $tx, $ty + 74)
$g.DrawString('Finds out WHY Bluetooth is broken.', $subFont, $grey, $tx + 4, $ty + 172)
$g.DrawString('Then fixes it. For free.', $subFont, $grey, $tx + 4, $ty + 212)

# pills
$pills = @(
    @{ T = 'Free & open source'; C = (C 255 16 185 129) },
    @{ T = 'No telemetry';       C = (C 255 59 130 246) },
    @{ T = 'Windows 10 / 11';    C = (C 255 168 85 247) },
    @{ T = '21 repairs';         C = (C 255 245 158 11) }
)
$px = $tx + 4; $py = $ty + 290
foreach ($p in $pills) {
    $sz = $g.MeasureString($p.T, $pillFont)
    $wPill = [int]($sz.Width + 34); $hPill = 40
    if ($px + $wPill -gt $W - 40) { $px = $tx + 4; $py += 52 }
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $r = 20
    $path.AddArc($px, $py, $r * 2, $r * 2, 180, 90); $path.AddArc($px + $wPill - $r * 2, $py, $r * 2, $r * 2, 270, 90); $path.AddArc($px + $wPill - $r * 2, $py + $hPill - $r * 2, $r * 2, $r * 2, 0, 90); $path.AddArc($px, $py + $hPill - $r * 2, $r * 2, $r * 2, 90, 90); $path.CloseFigure()
    $g.FillPath((New-Object System.Drawing.SolidBrush (C 70 $p.C.R $p.C.G $p.C.B)), $path)
    $g.DrawPath((New-Object System.Drawing.Pen $p.C, 2), $path)
    $g.DrawString($p.T, $pillFont, (New-Object System.Drawing.SolidBrush $p.C), $px + 17, $py + 7)
    $px += $wPill + 12
}

# footer
$g.DrawString('Diagnoses the USB stack, drivers, services, policies and event logs.', $footFont, $dim, $tx + 4, $H - 100)
$g.DrawString('Repairs with backups. Verifies itself.   |   MIT licensed   |   by Chad Keith', $footFont, $dim, $tx + 4, $H - 70)

# thin accent line at the bottom
$accent = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Point 0, 0), (New-Object System.Drawing.Point $W, 0), (C 255 59 130 246), (C 255 168 85 247)
$g.FillRectangle($accent, 0, $H - 8, $W, 8)

$g.Dispose()
$bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "Banner written: $OutPath"
