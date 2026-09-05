# Plays a real two-instance match over the loopback interface, headless, and checks
# that both sides finished on the same state hash.
#   powershell -File tools\run_net_test.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Find-Godot {
    if ($env:GODOT_BIN -and (Test-Path $env:GODOT_BIN)) { return $env:GODOT_BIN }
    $onPath = Get-Command godot -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $wingetDir = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    $found = Get-ChildItem $wingetDir -Recurse -Filter "Godot_v*_console.exe" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($found) { return $found.FullName }
    throw "Godot not found. Install it, or set GODOT_BIN to the executable."
}

$godot = Find-Godot
$hostLog = Join-Path $env:TEMP "regions_host.log"
$joinLog = Join-Path $env:TEMP "regions_join.log"

$hostProc = Start-Process -FilePath $godot -PassThru -NoNewWindow -RedirectStandardOutput $hostLog `
    -ArgumentList @("--headless", "--path", $root, "++", "--autoplay-host")
Start-Sleep -Milliseconds 1500
$joinProc = Start-Process -FilePath $godot -PassThru -NoNewWindow -RedirectStandardOutput $joinLog `
    -ArgumentList @("--headless", "--path", $root, "++", "--autoplay-join")

$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline -and (-not $hostProc.HasExited -or -not $joinProc.HasExited)) {
    Start-Sleep -Milliseconds 500
}
foreach ($p in @($hostProc, $joinProc)) { if (-not $p.HasExited) { $p.Kill() } }

$hostLine = (Get-Content $hostLog -ErrorAction SilentlyContinue | Select-String "^AUTOPLAY").Line
$joinLine = (Get-Content $joinLog -ErrorAction SilentlyContinue | Select-String "^AUTOPLAY").Line
Write-Output "host: $hostLine"
Write-Output "join: $joinLine"

function Field($line, $name) {
    if (-not $line) { return $null }
    $m = [regex]::Match($line, "$name=(-?\d+)")
    if ($m.Success) { return $m.Groups[1].Value } else { return $null }
}

$hostHash = Field $hostLine "hash"
$joinHash = Field $joinLine "hash"
if (-not $hostHash -or -not $joinHash) {
    Write-Output "FAIL: a side never reported. Logs: $hostLog / $joinLog"
    exit 1
}
if ($hostHash -ne $joinHash) {
    Write-Output "FAIL: desync. host=$hostHash join=$joinHash"
    exit 1
}
Write-Output "ok: both sides agree at hash $hostHash"
exit 0
