# Copyright (c) 2026 MatyanKass. All rights reserved.
# Builds a standalone Windows executable into build\Regions.exe.
#   powershell -File tools\build_windows.ps1
#   powershell -File tools\build_windows.ps1 -Share    build\share\Regions.exe + Regions.pck
# -Share is the build to hand to friends. An unsigned exe nobody has run before is held
# by Microsoft Defender for a cloud scan that a 100 MB file often does not finish, and
# the game never opens. So the share build leaves Godot's own release executable
# untouched - no embedded game, no icon or name written into it - which makes it byte for
# byte the file thousands of other Godot games ship, and puts the game beside it in
# Regions.pck. Keep the two files together.
param([switch]$Share)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Find-Godot {
    if ($env:GODOT_BIN -and (Test-Path $env:GODOT_BIN)) { return $env:GODOT_BIN }
    $onPath = Get-Command godot -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $found = Get-ChildItem (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages") -Recurse `
        -Filter "Godot_v*_console.exe" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($found) { return $found.FullName }
    throw "Godot not found. Install it, or set GODOT_BIN."
}

if ($Share) {
    $dir = Join-Path $root "build\share"
    if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $out = Join-Path $dir "Regions.exe"
    & (Find-Godot) --headless --path $root --export-release "Windows Share" $out
    if ($LASTEXITCODE -ne 0) { throw "Export failed with code $LASTEXITCODE" }
    $zip = Join-Path $root "build\Regions-windows.zip"
    Compress-Archive -Force -Path (Join-Path $dir "*") -DestinationPath $zip
    "ZIP: $zip ({0:N1} MB) - unpack both files into one folder" -f ((Get-Item $zip).Length / 1MB)
    exit 0
}

New-Item -ItemType Directory -Force -Path (Join-Path $root "build") | Out-Null
$out = Join-Path $root "build\Regions.exe"
& (Find-Godot) --headless --path $root --export-debug "Windows Desktop" $out
if ($LASTEXITCODE -ne 0) { throw "Export failed with code $LASTEXITCODE" }
"EXE: $out ({0:N1} MB)" -f ((Get-Item $out).Length / 1MB)
