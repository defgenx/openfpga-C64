<#
.SYNOPSIS
  Turn every .t64 on the Pocket card's Assets\c64\common into a .prg (Windows).

.DESCRIPTION
  Same conversion as tools/t64_to_prg.py, for Windows without Python; keep the two in sync.
  Each .prg is written next to its .t64; an existing .prg is never overwritten.
  Easiest: double-click convert-t64.bat. Or: .\convert-t64.ps1 [-Path E:\Assets\c64\common]
#>
[CmdletBinding()]
param([string]$Path = "")

$ErrorActionPreference = "Stop"
function Fail([string]$msg) { Write-Host "error: $msg" -ForegroundColor Red; exit 1 }

if (-not $Path) {
    $found = @()
    foreach ($d in Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in 2, 3 }) {
        $c = Join-Path "$($d.DeviceID)\" "Assets\c64\common"
        if (Test-Path -LiteralPath $c -PathType Container) { $found += $c }
    }
    if ($found.Count -eq 0) { Fail "no card with Assets\c64\common found - insert the Pocket SD card" }
    if ($found.Count -eq 1) { $Path = $found[0] } else {
        for ($i = 0; $i -lt $found.Count; $i++) { Write-Host "  $($i + 1)) $($found[$i])" }
        $n = Read-Host "Number of the card to convert"
        if ($n -notmatch '^\d+$' -or [int]$n -lt 1 -or [int]$n -gt $found.Count) { Fail "invalid choice" }
        $Path = $found[[int]$n - 1]
    }
    Write-Host "Pocket card: $Path"
}

function U16([byte[]]$b, [int]$o) { return [int]$b[$o] + 256 * [int]$b[$o + 1] }
function U32([byte[]]$b, [int]$o) { return [long](U16 $b $o) + 65536L * [long](U16 $b ($o + 2)) }

# (start address, offset, length) of each program in a T64 image
function Get-T64Entries([byte[]]$data) {
    if ($data.Length -lt 64 -or $data[0] -ne 0x43 -or $data[1] -ne 0x36 -or $data[2] -ne 0x34) { throw "not a T64 image" }
    $count = [Math]::Max([Math]::Max((U16 $data 0x22), (U16 $data 0x24)), 1)
    $dirs = @()
    for ($i = 0; $i -lt $count; $i++) {
        $o = 0x40 + 32 * $i
        if ($o + 32 -gt $data.Length) { break }
        $off = U32 $data ($o + 8)
        if ($data[$o] -eq 1 -and $off -gt 0 -and $off -lt $data.Length) {
            $dirs += [pscustomobject]@{ Offset = $off; Start = (U16 $data ($o + 2)); End = (U16 $data ($o + 4)) }
        }
    }
    $dirs = @($dirs | Sort-Object Offset)
    if ($dirs.Count -eq 0) { throw "no program in this T64" }
    for ($n = 0; $n -lt $dirs.Count; $n++) {
        # the end address is often wrong in T64s made by old tools: cap by the next entry or the file end
        $limit = if ($n + 1 -lt $dirs.Count) { $dirs[$n + 1].Offset } else { $data.Length }
        $len = ($dirs[$n].End - $dirs[$n].Start) -band 0xFFFF
        if ($len -eq 0 -or $dirs[$n].Offset + $len -gt $limit) { $len = $limit - $dirs[$n].Offset }
        [pscustomobject]@{ Start = $dirs[$n].Start; Offset = $dirs[$n].Offset; Length = [int]$len }
    }
}

$found = 0; $written = 0; $failed = 0
foreach ($f in Get-ChildItem -LiteralPath $Path -Recurse -File | Where-Object { $_.Extension -ieq ".t64" -and -not $_.Name.StartsWith("._") }) {
    $found++
    try {
        $data = [IO.File]::ReadAllBytes($f.FullName)
        $n = 0
        foreach ($e in Get-T64Entries $data) {
            $suffix = if ($n -eq 0) { "" } else { "_$($n + 1)" }
            $n++
            $dst = Join-Path $f.DirectoryName "$($f.BaseName)$suffix.prg"
            if (Test-Path -LiteralPath $dst) { continue }
            $out = New-Object byte[] ($e.Length + 2)
            $out[0] = $e.Start -band 0xFF; $out[1] = $e.Start -shr 8
            [Array]::Copy($data, $e.Offset, $out, 2, $e.Length)
            [IO.File]::WriteAllBytes($dst, $out)
            Write-Host "$($f.FullName) -> $(Split-Path -Leaf $dst) (`$$('{0:X4}' -f $e.Start), $($e.Length) bytes)"
            $written++
        }
    } catch {
        Write-Host "$($f.FullName): skipped ($($_.Exception.Message))" -ForegroundColor Yellow
        $failed++
    }
}
Write-Host "$found .t64 found, $written .prg written, $failed skipped"
