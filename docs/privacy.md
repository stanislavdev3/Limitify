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

## Claude Code status-line source

Claude Code's documented status-line JSON includes `rate_limits.five_hour` and
`rate_limits.seven_day`. When the user chooses **Connect Claude Code**, Limitify:

- installs a small collector at
  `~/Library/Application Support/Limitify/LimitifyClaudeStatusLine.sh`;
- updates `~/.claude/settings.json` to call it;
- preserves and forwards the complete input to any previous status-line command;
- writes only the `rate_limits` object to
  `~/Library/Application Support/Limitify/claude-usage.json`.

The cache contains usage percentages and reset timestamps only. It does not
contain prompts, responses, transcript paths, working directories, tokens, or
credentials. Disconnecting Claude in Limitify restores the prior command. The
source is documented by Anthropic at
<https://code.claude.com/docs/en/statusline>.

## Logs and preferences

Limitify does not log raw JSONL lines or app-server payloads. Preferences contain
only refresh settings, provider enablement, the selected menu-bar provider, the
configured sessions path, and the previous Claude status-line command needed for
restoration. They are stored in `UserDefaults`. No credentials are stored by
Limitify.
