# Copyright (c) 2026 MatyanKass. All rights reserved.
# Builds the Android APK.
#   powershell -File tools\build_apk.ps1            debug build, build\Regions.apk
#   powershell -File tools\build_apk.ps1 -Release   release build (needs a real keystore)
#
# Expects: Godot 4.7 with its export templates installed, a JDK, and the Android SDK
# command line tools. tools\setup_android.ps1 installs the last two.
param([switch]$Release)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "C:\Android\sdk" }
$keystore = "C:\Android\debug.keystore"

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

$godot = Find-Godot

# Godot reads the SDK location and the debug keystore from editor settings, not from
# the project, so the settings file has to exist and carry both before exporting.
$settings = Get-ChildItem (Join-Path $env:APPDATA "Godot") -Filter "editor_settings-*.tres" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if (-not $settings) {
    & $godot --headless --editor --quit --path $root | Out-Null
    $settings = Get-ChildItem (Join-Path $env:APPDATA "Godot") -Filter "editor_settings-*.tres" |
        Sort-Object Name -Descending | Select-Object -First 1
}
if (-not $settings) { throw "Godot never wrote an editor settings file." }

$text = Get-Content $settings.FullName -Raw
foreach ($pair in @(
        @("export/android/android_sdk_path", $sdk),
        @("export/android/debug_keystore", $keystore),
        @("export/android/debug_keystore_user", "androiddebugkey"),
        @("export/android/debug_keystore_pass", "android"))) {
    $line = '{0} = "{1}"' -f $pair[0], ($pair[1] -replace '\\', '/')
    if ($text -match [regex]::Escape($pair[0])) {
        $text = [regex]::Replace($text, [regex]::Escape($pair[0]) + ' = "[^"]*"', $line)
    } else {
        $text = $text -replace '(?m)^\[resource\]$', "[resource]`n$line"
    }
}
Set-Content -Path $settings.FullName -Value $text -Encoding utf8

New-Item -ItemType Directory -Force -Path (Join-Path $root "build") | Out-Null
$out = Join-Path $root "build\Regions.apk"
$mode = if ($Release) { "--export-release" } else { "--export-debug" }
& $godot --headless --path $root $mode "Android" $out
if ($LASTEXITCODE -ne 0) { throw "Export failed with code $LASTEXITCODE" }
"APK: $out ({0:N1} MB)" -f ((Get-Item $out).Length / 1MB)
