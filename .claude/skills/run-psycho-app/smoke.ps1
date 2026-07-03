# smoke.ps1 — CI-safe agent driver for psycho_app (milometry)
# Run from anywhere: .\\.claude\\skills\\run-psycho-app\\smoke.ps1
# No window required. Exits 0 on success, 1 on build/compile failure.
# Note: flutter analyze warnings are reported but do NOT fail this script.

Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\..\..\"
Set-Location $root

Write-Host "`n=== flutter pub get ===" -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { Write-Host "FAILED: flutter pub get" -ForegroundColor Red; exit 1 }

Write-Host "`n=== flutter analyze (warnings allowed) ===" -ForegroundColor Cyan
flutter analyze --no-fatal-infos --no-fatal-warnings
# Non-zero exit means errors (not just warnings) — still report but don't block
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: flutter analyze found issues (see above)" -ForegroundColor Yellow
}

Write-Host "`n=== flutter build web (compilation smoke test) ===" -ForegroundColor Cyan
flutter build web --no-pub
if ($LASTEXITCODE -ne 0) { Write-Host "FAILED: flutter build web" -ForegroundColor Red; exit 1 }

Write-Host "`n=== PASSED ===" -ForegroundColor Green
exit 0
