$ErrorActionPreference = "SilentlyContinue"
$src = "C:\My games\Mobile\psycho_app"
$dst = "C:\psycho_build"
$aab = Join-Path $dst "build\app\outputs\bundle\release\app-release.aab"

Write-Host "=== Killing leftover build processes ==="
Stop-Process -Name "java" -Force
Stop-Process -Name "adb" -Force
Start-Sleep -Seconds 2

Write-Host "=== Copying project to $dst (excluding heavy/regenerable dirs) ==="
# robocopy: /E all subdirs, /XD exclude dirs, /NFL /NDL quiet
robocopy $src $dst /E /XD "$src\build" "$src\.dart_tool" "$src\.gradle" "$src\.git" "$src\output" "$src\Screenshots" "$src\android\.gradle" "$src\android\app\build" /NFL /NDL /NJH /NJS /NP | Out-Null

Write-Host "=== Verifying keystore present in copy ==="
$ks = Join-Path $dst "android\upload-keystore.jks"
Write-Host ("keystore exists: " + (Test-Path $ks))

Set-Location $dst
Write-Host "=== flutter pub get ==="
& flutter pub get 2>&1 | Out-Null

Write-Host "=== Building release appbundle in unwatched location (few minutes) ==="
& flutter build appbundle --release 2>&1 | Out-Null

if (Test-Path $aab) {
    $f = Get-Item $aab
    Write-Host ("BUILD SUCCEEDED - {0:N2} MB" -f ($f.Length/1MB))
    Write-Host ("AAB: " + $aab)
} else {
    Write-Host "BUILD FAILED - no AAB produced even in unwatched location."
}
