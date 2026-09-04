# Runs the simulation tests headless - no editor, no window, no phone.
#   powershell -File tools\run_tests.ps1
# Exit code 0 means every test passed.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Find-Godot {
    if ($env:GODOT_BIN -and (Test-Path $env:GODOT_BIN)) { return $env:GODOT_BIN }
    $onPath = Get-Command godot -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $wingetDir = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path $wingetDir) {
        # The console build writes to stdout on Windows; the plain one does not.
        $found = Get-ChildItem $wingetDir -Recurse -Filter "Godot_v*_console.exe" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    throw "Godot not found. Install it, or set GODOT_BIN to the executable."
}

$godot = Find-Godot
& $godot --headless --path $root --script res://tests/run_tests.gd
exit $LASTEXITCODE
