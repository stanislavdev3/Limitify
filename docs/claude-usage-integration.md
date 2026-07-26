# Claude Code usage integration

## Source decision

Limitify uses Claude Code's documented custom status-line payload. Anthropic
documents two subscription windows:

- `rate_limits.five_hour.used_percentage` and `resets_at`;
- `rate_limits.seven_day.used_percentage` and `resets_at`.

The fields appear for Claude.ai Pro/Max subscribers after the first API response
in a session. Status-line execution is local and does not consume API tokens.
Reference: <https://code.claude.com/docs/en/statusline>.

Limitify does not invoke `/usage`, send a synthetic prompt, read Claude
credentials, or depend on a private HTTP endpoint. The official status-line
contract is preferable because it exposes the required percentages and reset
times without an extra request.

## Data flow

```text
Claude Code status-line JSON
    -> LimitifyClaudeStatusLine.sh
    -> rate_limits-only local cache
    -> ClaudeUsageProvider
    -> common ServiceUsage model
    -> popover and selected menu-bar label
```

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
