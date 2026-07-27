# Limitify

Limitify is a native macOS menu bar application that shows how much Codex or
Claude Code usage is left and when each limit resets.

## Requirements

- macOS 14 Sonoma or newer;
- Codex and/or Claude Code installed locally;
- Swift 6 toolchain only when building from source.

## Build from source

```sh
make test
make bundle
open dist/Limitify.app
```

`make dmg` creates `dist/Limitify-0.1.0.dmg`.

Codex and every Claude account appear as separate blocks in the popover
(disabled services are hidden). Select the radio button beside a provider to
control which logo, compact bar, and percentage are shown in the macOS menu
bar. Each Claude account must be connected once; Limitify preserves any
existing Claude status-line command.

Multiple Claude accounts are detected automatically (`~/.claude` plus any
logged-in `~/.claude-*` config directory); other `CLAUDE_CONFIG_DIR` locations
can be added in Settings. Every account card can get a custom label and a
muted background tint — see `docs/claude-multi-account.md`.

To rebuild the release app, stop any running Limitify process, and launch the
fresh bundle:

```sh
make restart
```

For Developer ID distribution, provide a signing identity:

```sh
SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" make dmg
NOTARY_PROFILE="limitify-notary" make notarize
```

See [installation and troubleshooting](docs/installation.md) and
[privacy](docs/privacy.md). Current implementation and distribution status is in
[release status](docs/release-status.md).
