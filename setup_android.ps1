$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TempRoot = Join-Path $env:TEMP "mesh_message_android_scaffold"

Write-Host "Generating Flutter Android scaffold..."
if (Test-Path $TempRoot) {
    Remove-Item $TempRoot -Recurse -Force
}

flutter create --platforms=android --org com.example --project-name mesh_message $TempRoot

$AndroidTarget = Join-Path $ProjectRoot "android"
if (Test-Path $AndroidTarget) {
    Remove-Item $AndroidTarget -Recurse -Force
}

Copy-Item (Join-Path $TempRoot "android") $AndroidTarget -Recurse

$ManifestTarget = Join-Path $AndroidTarget "app/src/main/AndroidManifest.xml"
Copy-Item (Join-Path $ProjectRoot "native/android/AndroidManifest.xml") $ManifestTarget -Force

$KotlinDir = Join-Path $AndroidTarget "app/src/main/kotlin/com/example/mesh_message"
New-Item -ItemType Directory -Force -Path $KotlinDir | Out-Null
Copy-Item (Join-Path $ProjectRoot "native/android/MainActivity.kt") (Join-Path $KotlinDir "MainActivity.kt") -Force

Write-Host ""
Write-Host "Android scaffold installed."
Write-Host "Next run:"
Write-Host "  flutter pub get"
Write-Host "  flutter run"
