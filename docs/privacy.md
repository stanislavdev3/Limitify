# Privacy

Limitify is local-first and read-only.

## Files accessed

The Codex JSONL fallback accesses only the configured sessions directory, which
defaults to:

```text
~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
```

It enumerates recently modified `.jsonl` candidates and reads bounded tails. It
decodes only the event timestamp, record type, plan label, limit identifiers,
usage percentages, window durations, and reset timestamps.

Limitify does not read `~/.codex/auth.json`, `~/.codex/history.jsonl`, Codex
conversation content, or Codex SQLite/log stores.

## App-server source

When a compatible local Codex executable exists, Limitify starts
`codex app-server --stdio` and calls its supported `account/rateLimits/read`
method. The Codex process owns authentication. Limitify receives rate-limit
metadata only and never receives authentication tokens.

Limitify opens no network connection, includes no analytics, and transmits no
data. The separately installed Codex process may refresh its own account data
according to Codex behavior.

## Logs and preferences

Limitify does not log raw JSONL lines or app-server payloads. Preferences contain
only refresh settings, provider enablement, and the configured sessions path and
are stored in `UserDefaults`. No credentials are stored by Limitify.
