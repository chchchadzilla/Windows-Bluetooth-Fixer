<#
.SYNOPSIS
    Builds BluetoothFixer.exe (elevating launcher) with the .NET Framework C# compiler that ships in Windows.
    Also draws the application icon. Output: ..\BluetoothFixer.exe
#>
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw 'csc.exe (.NET Framework 4) not found.' }

# ---- icon: Bluetooth rune on a blue rounded tile, PNG-packed ICO ----------
Add-Type -AssemblyName System.Drawing
function New-BtPng([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.Clear([System.Drawing.Color]::Transparent)
    $r = [int]($size * 0.22)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $rect = New-Object System.Drawing.Rectangle 0, 0, ($size - 1), ($size - 1)
    $path.AddArc($rect.X, $rect.Y, $r, $r, 180, 90); $path.AddArc($rect.Right - $r, $rect.Y, $r, $r, 270, 90); $path.AddArc($rect.Right - $r, $rect.Bottom - $r, $r, $r, 0, 90); $path.AddArc($rect.X, $rect.Bottom - $r, $r, $r, 90, 90); $path.CloseFigure()
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Point 0, 0), (New-Object System.Drawing.Point $size, $size), ([System.Drawing.Color]::FromArgb(0, 120, 215)), ([System.Drawing.Color]::FromArgb(0, 60, 140))
    $g.FillPath($brush, $path)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), ([Math]::Max(1.5, $size * 0.085))
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
    $s = $size
    $pts = @(
        (New-Object System.Drawing.PointF ($s * 0.30), ($s * 0.32)),
        (New-Object System.Drawing.PointF ($s * 0.68), ($s * 0.66)),
        (New-Object System.Drawing.PointF ($s * 0.50), ($s * 0.84)),
        (New-Object System.Drawing.PointF ($s * 0.50), ($s * 0.16)),
        (New-Object System.Drawing.PointF ($s * 0.68), ($s * 0.34)),
        (New-Object System.Drawing.PointF ($s * 0.30), ($s * 0.68))
    )
    $g.DrawLines($pen, $pts)
    # small wrench-ish tick at bottom-right to say "fixer"
    $pen2 = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 255, 200, 40)), ([Math]::Max(1.2, $size * 0.07))
    $pen2.StartCap = 'Round'; $pen2.EndCap = 'Round'
    $g.DrawLine($pen2, ($s * 0.70), ($s * 0.86), ($s * 0.78), ($s * 0.92)); $g.DrawLine($pen2, ($s * 0.78), ($s * 0.92), ($s * 0.92), ($s * 0.76))
    $g.Dispose()
    # Classic DIB icon entry (BITMAPINFOHEADER + BGRA bottom-up + 1bpp AND mask). csc's resource
    # writer does not accept PNG-compressed entries, so we write the old format for every size.
    $ms = New-Object System.IO.MemoryStream
    $w = New-Object System.IO.BinaryWriter $ms
    $w.Write([uint32]40); $w.Write([int32]$size); $w.Write([int32]($size * 2)); $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]0)
    $w.Write([uint32]($size * $size * 4)); $w.Write([int32]0); $w.Write([int32]0); $w.Write([uint32]0); $w.Write([uint32]0)
    $rect = New-Object System.Drawing.Rectangle 0, 0, $size, $size
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $stride = $data.Stride
    $row = New-Object byte[] ($size * 4)
    for ($y = $size - 1; $y -ge 0; $y--) {
        [System.Runtime.InteropServices.Marshal]::Copy([IntPtr]($data.Scan0.ToInt64() + $y * $stride), $row, 0, $size * 4)
        $w.Write($row)
    }
    $bmp.UnlockBits($data)
    $maskStride = [int]([Math]::Ceiling($size / 32.0) * 4)
    $mask = New-Object byte[] ($maskStride * $size)   # all zero = fully opaque per mask; alpha channel does the real work
    $w.Write($mask)
    $w.Flush()
    $bmp.Dispose()
    return $ms.ToArray()
}
function Write-Ico([int[]]$sizes, [string]$path) {
    $pngs = @{}; foreach ($s in $sizes) { $pngs[$s] = New-BtPng $s }
    $ico = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter $ico
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    foreach ($s in $sizes) {
        $b = $pngs[$s]
        $bw.Write([byte]$(if ($s -ge 256) { 0 } else { $s })); $bw.Write([byte]$(if ($s -ge 256) { 0 } else { $s }))
        $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$b.Length); $bw.Write([uint32]$offset)
        $offset += $b.Length
    }
    foreach ($s in $sizes) { $bw.Write($pngs[$s]) }
    $bw.Flush()
    [System.IO.File]::WriteAllBytes($path, $ico.ToArray())
}
$icoPath = Join-Path $here 'BluetoothFixer.ico'
$out = Join-Path $root 'BluetoothFixer.exe'
$src = Join-Path $here 'BluetoothFixer.Launcher.cs'
$manifest = Join-Path $here 'app.manifest'

# The in-box (pre-Roslyn) csc has a picky icon reader. Try progressively simpler icons, then no icon.
$attempts = @(
    @{ Name = 'multi-size DIB (128..16)'; Sizes = @(128, 64, 48, 32, 24, 16) },
    @{ Name = 'classic sizes (48/32/16)';  Sizes = @(48, 32, 16) },
    @{ Name = 'GDI Icon.Save (32)';        Sizes = @() }
)
$built = $false
foreach ($a in $attempts) {
    if ($a.Sizes.Count) { Write-Ico -sizes $a.Sizes -path $icoPath }
    else {
        $bmp = New-Object System.Drawing.Bitmap 32, 32
        $g = [System.Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'; $g.Clear([System.Drawing.Color]::FromArgb(0, 103, 192))
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 3; $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
        $g.DrawLines($pen, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF 10, 10), (New-Object System.Drawing.PointF 22, 21), (New-Object System.Drawing.PointF 16, 27), (New-Object System.Drawing.PointF 16, 5), (New-Object System.Drawing.PointF 22, 11), (New-Object System.Drawing.PointF 10, 22)))
        $g.Dispose()
        $icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
        $fs = [System.IO.File]::Create($icoPath); $icon.Save($fs); $fs.Close(); $bmp.Dispose()
    }
    Write-Host "Icon attempt: $($a.Name)"
    & $csc /nologo /target:winexe /optimize+ /platform:anycpu "/out:$out" "/win32manifest:$manifest" "/win32icon:$icoPath" /reference:System.Windows.Forms.dll $src 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -eq 0) { $built = $true; break }
}
if (-not $built) {
    Write-Host 'Compiling without an icon.'
    & $csc /nologo /target:winexe /optimize+ /platform:anycpu "/out:$out" "/win32manifest:$manifest" /reference:System.Windows.Forms.dll $src
    if ($LASTEXITCODE -ne 0) { throw "csc failed with $LASTEXITCODE" }
}
Write-Host "Built: $out ($([math]::Round((Get-Item $out).Length / 1KB)) KB)"
