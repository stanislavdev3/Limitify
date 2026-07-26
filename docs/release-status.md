# Release status

Version: 0.1.0  
Build: 1  
Date: 2026-07-26

## Completed

- Native macOS 14 menu bar-only SwiftUI application.
- Compact remaining-allowance bar and percentage using the same value.
- Most-constrained-window selection.
- Popover with all Codex limit buckets/windows, reset times, plan, refresh time,
  stale warning, and manual refresh.
- Loading, unavailable, provider-not-installed, missing-directory, no-event,
  malformed-data, unsupported-data, access-denied, and transient error states.
- Preferred Codex app-server source with bounded stdio protocol handling.
- Bounded local JSONL fallback that reads only projected rate-limit fields.
- Automatic refresh, concurrent refresh coalescing, last-success retention,
  popover refresh, and wake/clock-change refresh.
- Refresh/stale/provider/path settings and launch-at-login integration.
- Accessibility labels and keyboard shortcuts for refresh and quit.
- Synthetic fixtures only; no copied session or credential data.
- Universal `x86_64` + `arm64` application bundle.
- Multi-resolution application icon, app bundle, and compressed DMG pipeline.
- Installation, privacy, troubleshooting, signing, and notarization instructions.

## Verification

- 28 automated tests pass on macOS.
- Release app passes `codesign --verify --deep --strict`.
- Release executable is a universal Mach-O containing `x86_64` and `arm64`.
- `Info.plist` passes `plutil -lint`.
- Final app launches and remains running in a process smoke test.
- DMG passes `hdiutil verify`.

Current local artifact:

```text
dist/Limitify-0.1.0.dmg
SHA-256 17b9896ff29071704873873553d2ab560c7f0e8c75011e6d84e3c335ce65b459
```

## External release requirement

The local artifact is ad-hoc signed and suitable for development/install smoke
testing. Public distribution still requires a Developer ID Application identity
and an Apple notary credential. This machine currently reports zero valid code
signing identities, so a Developer ID signature and notarization cannot be
produced here without external credentials.

Once credentials are installed:

```sh
SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" make dmg
NOTARY_PROFILE="limitify-notary" make notarize
```

The notarization target submits, waits, staples, and validates the DMG.
