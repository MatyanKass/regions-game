# Copyright (c) 2026 MatyanKass. All rights reserved.
# Runs the game on this PC, straight from source. No build step.
#   powershell -File tools\run.ps1              the lobby, same as on a phone
#   powershell -File tools\run.ps1 -Practice    straight into a match against the bot
param([switch]$Practice)
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

$args = @("--path", $root, "--resolution", "1280x720")
if ($Practice) { $args += @("++", "--practice") }
& (Find-Godot) @args
