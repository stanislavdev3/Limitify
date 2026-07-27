# Limitify

Native macOS menu-bar app (SwiftUI, Swift 6, SwiftPM) showing remaining
Codex/Claude Code usage. Two targets: `LimitifyCore` (models, providers,
no UI) and `LimitifyApp` (SwiftUI, settings, installers).

## Commands

- `make test` — build + full test suite (Swift Testing, not XCTest).
- `make restart` — rebuild `dist/Limitify.app` and relaunch it (local dev loop).
- `make dmg` — signed DMG (`SIGN_IDENTITY` for Developer ID, ad-hoc otherwise).

## Architecture invariants

- **Local-only**: providers read local files or spawn local CLIs. No network
  calls, no credentials (keychain, `auth.json`) are ever read.
- Provider identity is `ProviderID` (string struct): `codex`, `claude`
  (default profile), `claude:<slug>` for extra Claude profiles.
- Claude usage comes from a status-line hook writing a per-profile cache
  (`claude-usage[-<slug>].json` in Application Support); see
  `docs/claude-usage-integration.md` and `docs/claude-multi-account.md`.
- Claude profiles = config directories: `~/.claude` always, `~/.claude-*`
  with a `.claude.json` auto-discovered, arbitrary dirs added by the user in
  Settings. Account labels come from `.claude.json` → `oauthAccount`.
- Codex is only spawned after `CodexLaunchGate` confirms Gatekeeper would
  allow it — launching a quarantined binary from a background app makes
  macOS delete it as malware. Never bypass this gate.
- Historical names are load-bearing compatibility: the `default` profile's
  cache file (`claude-usage.json`), its `claudePreviousStatusLine*` defaults
  keys, and the `displayProvider` defaults values `codex`/`claude`.

## Conventions

- Tests use Swift Testing (`@Suite`/`@Test`/`#expect`) with synthetic fixtures
  and temp directories; nothing touches the real home directory or defaults
  (isolated `UserDefaults` suites).
- Every behavior change ships with tests and an update to the relevant doc in
  `docs/`.
- UI copy is English; keep failure messages actionable (what the user should
  do next), matching `UsagePopoverView.failureMessage`.
