$ErrorActionPreference = "Continue"
$src = "C:\My games\Mobile\psycho_app"
$dst = "C:\psycho_build"
$adb = "C:\Users\erezp\AppData\Local\Android\sdk\platform-tools\adb.exe"
$apk = Join-Path $dst "build\app\outputs\flutter-apk\app-debug.apk"
$pkg = "com.pappostudios.milometry"

Write-Host "=== Syncing your code to the unwatched build folder ($dst) ==="
robocopy $src $dst /E /XD "$src\build" "$src\.dart_tool" "$src\.gradle" "$src\.git" "$src\output" "$src\Screenshots" "$src\android\.gradle" "$src\android\app\build" "$src\build\windows" /NFL /NDL /NJH /NJS /NP | Out-Null

Set-Location $dst
Write-Host "=== flutter pub get ==="
& flutter pub get 2>&1 | Out-Null

Write-Host "=== Building debug APK (no VS Code watcher here, so no lock) ==="
& flutter build apk --debug 2>&1 | Select-String -Pattern "Built|error|Error|FAILURE" | ForEach-Object { $_.Line }

if (-not (Test-Path $apk)) {
    Write-Host "BUILD FAILED - no APK produced. See above."
    exit 1
}

Write-Host "=== Installing on your phone ==="
$out = & $adb install -r $apk 2>&1 | Out-String
Write-Host $out

if ($out -match "INSTALL_FAILED_UPDATE_INCOMPATIBLE|signatures do not match") {
    Write-Host ""
    Write-Host "The Play Store version is installed and is signed with a different key,"
    Write-Host "so it must be removed first. Uninstalling (this clears local progress)..."
    & $adb uninstall $pkg | Out-Null
    Write-Host "Reinstalling the test build..."
    & $adb install $apk 2>&1 | Write-Host
}

Write-Host ""
Write-Host "DONE. Open Milometry on your phone to see the latest changes."
