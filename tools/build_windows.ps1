# Builds a standalone Windows executable into build\Regions.exe.
#   powershell -File tools\build_windows.ps1
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

New-Item -ItemType Directory -Force -Path (Join-Path $root "build") | Out-Null
$out = Join-Path $root "build\Regions.exe"
& (Find-Godot) --headless --path $root --export-debug "Windows Desktop" $out
if ($LASTEXITCODE -ne 0) { throw "Export failed with code $LASTEXITCODE" }
"EXE: $out ({0:N1} MB)" -f ((Get-Item $out).Length / 1MB)
