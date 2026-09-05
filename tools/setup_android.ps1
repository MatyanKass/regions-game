# One-time machine setup for building the APK: Android SDK packages and a debug
# keystore. Godot's own export templates are installed separately, from the editor
# (Editor > Manage Export Templates) or by unpacking the .tpz for the matching version
# into %APPDATA%\Godot\export_templates\<version>\.
$ErrorActionPreference = "Stop"
$sdk = "C:\Android\sdk"
$sdkmanager = "$sdk\cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $sdkmanager)) {
    throw "Android command line tools missing. Unpack them into $sdk\cmdline-tools\latest."
}

$jdk = (Get-ChildItem "C:\Program Files\Microsoft" -Filter "jdk-*" -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1)
if ($jdk) { $env:JAVA_HOME = $jdk.FullName }
if (-not $env:JAVA_HOME) { throw "No JDK found. Install one and set JAVA_HOME." }

# sdkmanager --licenses is interactive and does not read a piped stream reliably from
# PowerShell, so the accepted-licence hashes are written directly. These are the public
# hashes Google ships; this is the same thing CI images do.
$licenses = @{
    "android-sdk-license" = @(
        "8933bad161af4178b1185d1a37fbf41ea5269c55",
        "d56f5187479451eabf01fb78af6dfcb131a6481e",
        "24333f8a63b6825ea9c5514f83c2829b004d1fee")
    "android-sdk-preview-license" = @("84831b9409646a918e30573bab4c9c91346d8abd")
    "android-sdk-arm-dbt-license" = @("859f317696f67ef3d7f30a50a5560e7834b43903")
}
New-Item -ItemType Directory -Force -Path "$sdk\licenses" | Out-Null
foreach ($name in $licenses.Keys) {
    Set-Content -Path "$sdk\licenses\$name" -Value ($licenses[$name] -join "`n") -Encoding ascii -NoNewline
}
& $sdkmanager --sdk_root=$sdk "platform-tools" "build-tools;34.0.0" "platforms;android-34"

$keystore = "C:\Android\debug.keystore"
if (-not (Test-Path $keystore)) {
    & "$env:JAVA_HOME\bin\keytool.exe" -keyalg RSA -genkeypair -alias androiddebugkey `
        -keypass android -keystore $keystore -storepass android `
        -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
}
"SDK ready at $sdk"
"Debug keystore: $keystore"
