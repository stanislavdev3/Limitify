# Claude Code usage integration

## Source decision

Limitify uses Claude Code's documented custom status-line payload. Anthropic
documents two subscription windows:

- `rate_limits.five_hour.used_percentage` and `resets_at`;
- `rate_limits.seven_day.used_percentage` and `resets_at`.

The parser additionally understands the model-specific weekly windows that Max
plans report (`seven_day_opus`, `seven_day_sonnet`), pre-names a
`seven_day_fable` window following the same convention (not yet reported by
the status line as of July 2026 — Fable 5 usage counts against the shared
`five_hour`/`seven_day` windows), and keeps any future window-shaped
`rate_limits` entry (an object with `used_percentage` and `resets_at`) under a
humanized name instead of dropping it. Non-window entries are ignored;
malformed values in known windows are still rejected as malformed data.

The fields appear for Claude.ai Pro/Max subscribers after the first API response
in a session. Status-line execution is local and does not consume API tokens.
Reference: <https://code.claude.com/docs/en/statusline>.

Limitify does not invoke `/usage`, send a synthetic prompt, read Claude
credentials, or depend on a private HTTP endpoint. The official status-line
contract is preferable because it exposes the required percentages and reset
times without an extra request.

## Data flow

```text
Claude Code status-line JSON (one per profile/account)
    -> LimitifyClaudeStatusLine.sh
    -> rate_limits-only local cache (claude-usage[-<profile>].json)
    -> ClaudeUsageProvider (one instance per profile)
    -> common ServiceUsage model
    -> popover card per account and selected menu-bar label
```

Multiple Claude accounts are supported through per-config-directory profiles;
see [claude-multi-account.md](claude-multi-account.md). The account email shown
on each card comes from the profile's local `.claude.json` state file.

The collector uses macOS `plutil` to project only the `rate_limits` object. It
passes the unmodified JSON to a pre-existing status-line command and relays that
command's output. The installer keeps unrelated Claude settings intact and the
disconnect action restores the previous command.

## Freshness and limitations

The cache modification time is the observation time. Claude triggers status-line
updates after interactions and can also rerun it on the configured refresh
interval, but rate-limit fields can be absent before the first response. Limitify
therefore retains the last valid snapshot and applies the same stale-data policy
used for Codex.

This implementation was validated with synthetic fixtures because Claude Code
is not installed on the development machine. The parser, installer preservation,
collector privacy projection, and previous-command passthrough are automated or
script-tested; a live authenticated Claude account remains a distribution smoke
test.
