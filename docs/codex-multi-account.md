# Codex multi-account support

## Concept

A Codex "profile" is one Codex `CODEX_HOME` directory, which is how multiple
accounts coexist on one machine (`CODEX_HOME`). Every profile gets its own
live app-server source (pinned to its own `CODEX_HOME`), its own session
fallback directory, its own popover card, and its own menu-bar selection
entry.

## Profile discovery

`CodexProfileDiscovery.discover(environment:homeDirectory:additionalDirectories:)`:

- The default profile is always included, resolved exactly as before
  (`CODEX_HOME` environment variable if set, else `~/.codex`), even before
  Codex is installed.
- Every `~/.codex-<name>` sibling directory that contains an `auth.json` (i.e.
  an account has completed a login there) becomes profile `<name>`. Only the
  file's existence is checked — its contents, which hold credentials, are
  never read.
- Any other `CODEX_HOME` location cannot be guessed and is added by the user
  via *Settings → Codex → Add Account Directory…*. Added paths persist in
  `UserDefaults` (`codexProfileDirectories`), are deduplicated against
  discovered profiles, and can be removed again (files are never touched).
  Their slug is the sanitized directory name plus a short path digest, so it
  depends only on the path itself — a later-discovered `~/.codex-*` with the
  same name can never remap a manual account's selection or customization.
- Automatic slugs are also path-stable, using the same scheme as Claude
  profiles: a clean `~/.codex-<name>` keeps `<name>` verbatim; a name
  sanitization would alter, or the reserved `default`, gets a path-digest
  suffix instead.

Codex has no account email to read (unlike Claude's `.claude.json`); the
popover badge shows the live usage event's plan type instead, and the user
names additional accounts by hand (see Customization below).

## Per-profile behavior

Every profile, default included, is treated the same way — symmetric with
how Claude profiles already work:

| Behavior | every profile |
| --- | --- |
| Session fallback directory | `<CODEX_HOME>/sessions`, not user-configurable |
| Live app-server process environment | spawned with `CODEX_HOME` pinned to the profile's directory |
| Provider ID | `codex` for the default profile (stored menu-bar selections stay valid), `codex:<slug>` for others |

Earlier versions of this feature special-cased the default profile (reusing
a pre-existing, user-configurable "Sessions directory" setting and leaving
`CODEX_HOME` unset on its spawned process) to stay byte-for-byte compatible
with the single-account behavior that predated multi-account support. That
asymmetry was removed once the per-profile UI existed, since pinning
`CODEX_HOME` explicitly resolves to the same directory the default profile
already used — there was nothing left for the override to actually change.

## Customization

Per-profile, stored in `UserDefaults` (`codexProfileCustomizations`, JSON) —
the same `ProfileCustomization` type Claude profiles use, in its own
dictionary so a Codex slug and a Claude slug can never collide:

- **Label** — optional display name override ("Work", "Personal"); shown in
  the popover card, settings row, and the usage model's `displayName`.
- **Tint** — optional card color, same fixed muted palette as Claude cards.
- **Group** — optional Work/Personal bucket shared across providers; see
  [account-grouping.md](account-grouping.md).

## Selection and fallback

Codex profiles feed into the same `enabledDisplayProviders` list, selection,
and stale-provider fallback as Claude profiles; see
[claude-multi-account.md](claude-multi-account.md#selection-and-fallback).
