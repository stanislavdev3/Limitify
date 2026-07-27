# Claude multi-account support

## Concept

A Claude "profile" is one Claude Code config directory, which is how multiple
accounts coexist on one machine (`CLAUDE_CONFIG_DIR`). Every profile gets its
own status-line hook, its own local usage cache, its own popover card, and its
own menu-bar selection entry.

## Profile discovery

`ClaudeProfileDiscovery.discover(homeDirectory:additionalDirectories:)`:

- `~/.claude` is always included as the `default` profile, even before Claude
  Code is installed (the card then shows the install/connect hint). Its state
  file is `~/.claude.json` — in the home directory, not inside the config
  directory.
- Every `~/.claude-<name>` sibling directory that contains a `.claude.json`
  (i.e. an account has completed a login there) becomes profile `<name>`.
- Any other `CLAUDE_CONFIG_DIR` location cannot be guessed and is added by the
  user via *Settings → Claude → Add Account Directory…*. Added paths persist in
  `UserDefaults` (`claudeProfileDirectories`), are deduplicated against
  discovered profiles, and can be removed again (files are never touched).
  Their slug is the sanitized directory name plus a short path digest
  (`Claude Work (Team)` → `claude-work-team-a1b2c3`), so it depends only on
  the path itself — a later-discovered `~/.claude-*` with the same name can
  never remap a manual account's cache, selection, or customization.
- Automatic slugs are uniqued with the `default` slug reserved: a
  `~/.claude-default` directory becomes `default-2` instead of shadowing the
  default profile's provider ID.

The account label is read from the profile's `.claude.json` →
`oauthAccount.emailAddress`. This file contains no credentials; Limitify still
never reads keychain items, `auth.json`, or any network endpoint.

## Per-profile artifacts

| Artifact | `default` profile | other profiles |
| --- | --- | --- |
| Usage cache | `claude-usage.json` (historical name, keeps old hooks working) | `claude-usage-<slug>.json` |
| Status-line hook | `~/.claude/settings.json` | `<dir>/settings.json` |
| Previous-command backup keys | historical `claudePreviousStatusLine*` names | same names suffixed with `.<slug>` |
| Provider ID | `claude` (stored menu-bar selections stay valid) | `claude:<slug>` |

`ClaudeInstallerHub` owns one `ClaudeStatusLineInstaller` per profile and
republishes their status changes to SwiftUI.

## Customization

Per-profile, stored in `UserDefaults` (`claudeProfileCustomizations`, JSON):

- **Label** — optional display name override ("Work", "Личный"); shown in the
  popover card, settings row, and the usage model's `displayName`.
- **Tint** — optional card color from a fixed muted palette
  (blue/purple/cyan/green/orange/pink/graphite; the cyan option keeps its
  historical `teal` raw value in storage). Rendered as a whisper-light fill
  (system color at 0.08 opacity) plus a small saturated stripe on the card's
  leading edge; the stripe carries the hue distinction, because at such low
  fill opacities neighboring hues look identical. Picker swatches stay fully
  saturated for the same reason.

The label is stored exactly as typed (a transforming TextField binding breaks
cursor placement); whitespace-only labels are normalized away at display time
via `normalizedLabel`.

Empty customizations are removed from storage.

## Selection and fallback

The menu bar shows one provider, persisted as its raw provider ID under the
historical `displayProvider` defaults key ("codex" and "claude" remain valid).
If the selected provider is disabled or its profile disappears, the selection
falls back to the first enabled provider. Disabled providers are hidden from
the popover entirely.
