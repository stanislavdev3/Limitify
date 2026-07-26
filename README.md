# Limitify

Limitify is a native macOS menu bar application that shows how much Codex usage
is left and when each limit resets.

## Requirements

- macOS 14 Sonoma or newer;
- Codex installed locally, or an existing local Codex sessions directory;
- Swift 6 toolchain only when building from source.

## Build from source

```sh
make test
make bundle
open dist/Limitify.app
```

`make dmg` creates `dist/Limitify-0.1.0.dmg`.

For Developer ID distribution, provide a signing identity:

```sh
SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" make dmg
NOTARY_PROFILE="limitify-notary" make notarize
```

See [installation and troubleshooting](docs/installation.md) and
[privacy](docs/privacy.md). Current implementation and distribution status is in
[release status](docs/release-status.md).
