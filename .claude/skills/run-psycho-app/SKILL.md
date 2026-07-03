---
name: run-psycho-app
description: run, build, launch, start, test, screenshot the milometry / psycho_app Flutter project
---

milometry (package name `psycho_app`) is a Hebrew/English vocabulary Flutter app. On this Windows machine it can be driven without a window via the PowerShell smoke script, or launched interactively as a Windows desktop or Chrome web app. iOS/Android require a device or Codemagic CI.

All paths below are relative to the project root: `c:\My games\Mobile\psycho_app\`.

---

## Agent path (no window required)

Run the smoke script — it verifies deps, static analysis, and a full web compilation:

```powershell
cd "c:\My games\Mobile\psycho_app"
.\.claude\skills\run-psycho-app\smoke.ps1
```

Exits 0 on success. Output lands in `build\web\`. Takes ~50 s on first run.

Verified output (2026-07-03):
```
=== flutter pub get ===        ← OK
=== flutter analyze ===        ← 57 warnings (infos only, no errors)
=== flutter build web ===      ← Built build\web  ✓
=== PASSED ===
```

---

## Human path — Windows desktop

```powershell
flutter run -d windows
```

Opens a native Windows window. Ctrl-C to stop.

## Human path — Chrome web

```powershell
flutter run -d chrome
```

Opens Chrome on `localhost:<random port>`. Hot-reload works.

---

## Gotchas

- **`flutter analyze` exits 1** even for warnings (infos). The smoke script passes `--no-fatal-infos --no-fatal-warnings` to avoid false failures. Raw `flutter analyze` will report exit 1 with "57 issues found" — all are deprecation warnings, not errors.
- **TTS is a no-op on web/Windows.** The `_NativeTts` method channel targets `AppDelegate.swift` (iOS only). It silently catches all errors, so the app won't crash — word pronunciation just does nothing.
- **`in_app_purchase` is a no-op on web/Windows.** The paywall screen is informational only (no buttons), so this causes no visible issue.
- **`flutter build web` prints a Wasm dry-run warning.** Not an error — add `--no-wasm-dry-run` to suppress it.
- **`flutter pub get` is required before any build** if packages aren't fetched (e.g. after a fresh clone or adding a dependency).

---

## Build artifacts

| Command | Output |
|---|---|
| `flutter build web` | `build\web\` |
| `flutter build windows` | `build\windows\x64\runner\Release\` |
| `flutter build ipa` | Codemagic only (requires macOS + Xcode) |
| `flutter build appbundle` | Requires Android SDK + keystore |
