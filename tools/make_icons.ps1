# Copyright (c) 2026 MatyanKass. All rights reserved.
# Renders the app icon from the game's own drawing code into assets/icon.
# A real window is opened for a moment: a headless renderer returns an empty texture.
#   powershell -File tools\make_icons.ps1
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

$out = Join-Path $root "assets\icon"
& (Find-Godot) --path $root --resolution 640x640 "++" "--icons=$out"
Get-ChildItem $out -Filter *.png | Select-Object Name, Length
