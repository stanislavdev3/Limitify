# Milestone 0: Codex usage data spike

Status: initial spike complete  
Observed on: 2026-07-26  
Codex build examined: `codex-cli 0.145.0` on macOS/arm64

## Scope and safety rules

This spike evaluates local, read-only ways for Limitify to obtain Codex rate-limit
data. It does not establish a UI and does not implement a provider.

The investigation did not read `~/.codex/auth.json`, did not call a private HTTP
endpoint, and did not print or copy raw session lines. JSONL inspection selected
only the `rate_limits` object and its enclosing record type/timestamp. Synthetic
examples below do not contain copied account or session data.

## Decision

Use the Codex app-server method `account/rateLimits/read` as the preferred source
when a compatible local `codex` executable is available. Keep local session JSONL
parsing as a mandatory fallback.

This is a capability-based decision, not a hard dependency on Codex 0.145.0:

1. Discover the executable without invoking a shell.
2. Start `codex app-server --stdio` with a short startup/read timeout.
3. Complete the `initialize` / `initialized` handshake.
4. Call `account/rateLimits/read` with `params: null`.
5. If the executable, handshake, method, response, or refresh is unavailable,
   read the newest valid local JSONL event instead.

The rate-limit method is present in the schema generated **without**
`--experimental`, and a live read succeeded. However, the enclosing
`codex app-server` CLI command is still labelled experimental. The app-server is
therefore suitable as the preferred adapter but not stable enough to be the only
MVP source. The JSONL fallback is also required for offline/stale behavior and for
older Codex installations.

Limitify itself should not open a network connection. The separately installed
Codex process owns its authentication and may refresh account data using its own
implementation. Limitify communicates with that local process over stdio and
never receives credentials. Whether product language should distinguish this
from a strictly offline source should be clarified in privacy documentation.

## Source 1: Codex app-server

### Evidence

The installed CLI exposes:

```text
codex app-server [experimental]
codex app-server generate-json-schema --out <directory>
```

The non-experimental generated protocol schema includes:

- request `account/rateLimits/read`;
- notification `account/rateLimits/updated`;
- response `GetAccountRateLimitsResponse`;
- `RateLimitSnapshot`, `RateLimitWindow`, `CreditsSnapshot`, and `PlanType`.

A successful minimal exchange is:

```json
{"id":1,"method":"initialize","params":{"clientInfo":{"name":"limitify","version":"0.0.0"},"capabilities":{"experimentalApi":false}}}
{"method":"initialized"}
{"id":2,"method":"account/rateLimits/read","params":null}
```

The initialize response also reports `codexHome`, which can aid diagnostics. It
must not be treated as permission to inspect unrelated files.

### Response shape

`GetAccountRateLimitsResponse` contains:

- required `rateLimits`: a backward-compatible single-bucket snapshot;
- optional `rateLimitsByLimitId`: snapshots keyed by metered limit identifier;
- optional `rateLimitResetCredits`.

Each snapshot can contain:

- `limitId` and `limitName`;
- `primary` and optional `secondary` windows;
- `planType`;
- `credits`;
- `individualLimit`, `spendControlReached`, and `rateLimitReachedType`.

A window contains integer `usedPercent`, nullable `windowDurationMins`, and
nullable Unix-seconds `resetsAt`. The implementation should prefer a non-empty
`rateLimitsByLimitId`, then fall back to `rateLimits` to avoid duplicating the
same bucket.

The response has no observation timestamp. Limitify should set `observedAt` to
the instant a valid response is received and mark the source as a live local
adapter. This is a receipt time, not a server-authored timestamp.

`account/rateLimits/updated` is explicitly a sparse rolling update. A future
long-lived connection must merge it into the last full read or perform another
`account/rateLimits/read`; nullable values in the notification do not erase prior
metadata. The first implementation should use one-shot reads and avoid sparse
merge complexity.

### Operational risks

- The app-server entry point is experimental even though the method is in the
  default schema.
- Startup initializes Codex-owned state under its own home directory and can
  fail because of permissions.
- The process needs explicit lifecycle, timeout, cancellation, stdout framing,
  and sanitized stderr handling.
- Another Codex version may omit or change the method. Probe the method and
  decode defensively rather than relying only on a version number.
- Unknown response fields and unknown plan values must not invalidate otherwise
  usable windows.

## Source 2: local session JSONL

### Location and discovery

The default observed layout is:

```text
~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
```

The data directory remains configurable. Limitify should never infer that all of
`~/.codex` is in scope: the fallback needs only the `sessions` subtree selected
or detected for the configured Codex home.

Candidate selection should enumerate recently modified `.jsonl` files, newest
first, and stop as soon as a sufficiently recent valid event is found. File
modification time is only a discovery hint; the top-level event `timestamp` is
the authoritative `observedAt`.

### Observed envelope and fields

All sampled usage records had this envelope:

```text
type = "event_msg"
payload.type = "token_count"
payload.rate_limits = { ... }
timestamp = ISO-8601 string
```

Observed window fields are:

- `used_percent`: JSON number and therefore decoded as `Double`, even when the
  app-server schema uses an integer;
- `window_minutes`: integer in observed records, but treated as optional;
- `resets_at`: Unix timestamp in seconds, treated as optional.

Observed rate-limit object fields are:

- `limit_id`, `limit_name`;
- `primary`, nullable `secondary`;
- nullable `credits`;
- nullable `plan_type`;
- `individual_limit` and `rate_limit_reached_type`;
- in newer records, `spend_control_reached`.

The parser should decode only this small projection. It must not decode, retain,
or log token details, prompts, messages, or other event payloads.

### Observed structural variants

The local sample contained these distinct shapes. “Present” includes a nullable
field that exists in the JSON object.

| Shape | Windows | Credits | Plan | Extra observation |
| --- | --- | --- | --- | --- |
| A | primary + secondary | null | string | older multi-window form |
| B | primary only | object | string | standard form |
| C | primary only | null | string | credits unavailable |
| D | primary only | object | null | plan unavailable |
| E | primary only | object | string | includes `spend_control_reached` |

The following JSONL records are synthetic fixtures for those observed shapes.
Timestamps, percentages, reset times, and metadata are invented.

```jsonl
{"timestamp":"2026-01-10T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":27.5,"window_minutes":300,"resets_at":1768046400},"secondary":{"used_percent":58.0,"window_minutes":10080,"resets_at":1768651200},"credits":null,"plan_type":"plus","rate_limit_reached_type":null}}}
{"timestamp":"2026-01-10T10:01:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":31.0,"window_minutes":10080,"resets_at":1768651200},"secondary":null,"credits":{"has_credits":false,"unlimited":false,"balance":"0"},"individual_limit":null,"plan_type":"plus","rate_limit_reached_type":null}}}
{"timestamp":"2026-01-10T10:02:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":32.0,"window_minutes":10080,"resets_at":1768651200},"secondary":null,"credits":null,"individual_limit":null,"plan_type":"plus","rate_limit_reached_type":null}}}
{"timestamp":"2026-01-10T10:03:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":33.0,"window_minutes":10080,"resets_at":1768651200},"secondary":null,"credits":{"has_credits":true,"unlimited":false,"balance":"5"},"individual_limit":null,"plan_type":null,"rate_limit_reached_type":null}}}
{"timestamp":"2026-01-10T10:04:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":34.0,"window_minutes":10080,"resets_at":1768651200},"secondary":null,"credits":{"has_credits":false,"unlimited":false,"balance":"0"},"individual_limit":null,"spend_control_reached":false,"plan_type":"plus","rate_limit_reached_type":null}}}
```

Additional synthetic fixtures are required for a truncated final line, malformed
JSON between valid events, missing reset/duration, an out-of-range percentage,
and two files whose modification order differs from their event timestamps.

### Incremental read strategy

The first fallback implementation should optimize for correctness before adding
persistent cursors:

1. Sort a small bounded set of candidate files by modification time descending.
2. Read a bounded tail chunk from each candidate.
3. Discard bytes before the first newline because the chunk may begin mid-record.
4. Split into lines and scan from newest to oldest.
5. Ignore an incomplete final line and malformed/non-matching records.
6. Decode only matching `event_msg` / `token_count` records with `rate_limits`.
7. Compare valid event timestamps across candidates and return the newest.

If no valid event is present in the initial tail, the reader may expand the tail
up to a documented cap. It must not continuously rescan every complete session
file. Persistent byte offsets can be considered after correctness tests show a
need for them.

## Rejected local candidates

- `~/.codex/auth.json`: prohibited; it contains credentials and is unnecessary.
- Private HTTP endpoints: prohibited and unnecessary.
- `~/.codex/history.jsonl`: conversation/history data with no need-to-read
  justification for usage limits.
- Codex SQLite state/log stores: their inspected schemas exposed no dedicated
  rate-limit or usage table. Internal databases have higher compatibility and
  privacy risk than the protocol or whitelisted session events.
- Codex logs: unsuitable because formatting is diagnostic, unstable, and may
  contain sensitive context.

## Provider boundary

The first common model should remain source-neutral:

```text
ServiceUsage
├── providerID
├── displayName
├── accountLabel?          // plan for Codex
├── limits[]
│   ├── id                 // bucket id + primary/secondary role
│   ├── displayName
│   ├── usedFraction       // 0...1
│   ├── windowDuration?
│   └── resetAt?
├── observedAt
└── source                 // appServer or sessionJSONL
```

Source availability/errors should be separate from the snapshot so the store can
retain the last success. “Stale” is derived by the store from `observedAt` and the
configured threshold; it is not permanently encoded by the provider.

Mapping rules:

- Validate `usedPercent` as a finite value in `0...100`; an invalid newest event
  is skipped so an earlier valid event can still be used.
- `usedFraction = usedPercent / 100`.
- `remainingFraction = 1 - usedFraction` is derived consistently by presentation
  logic; providers do not store a second independent percentage.
- Map both primary and secondary windows when present.
- Preserve unknown durations with a generic label rather than assuming that the
  primary window is always five hours or weekly.
- Treat reset time, duration, plan, credits, limit name, and new fields as
  optional. Unknown fields are ignored.
- Use `rateLimitsByLimitId` when present and non-empty; otherwise use the
  backward-compatible `rateLimits` object.

Suggested provider contract:

```swift
protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetchUsage() async throws -> ServiceUsage
}
```

The Codex provider composes two internal adapters rather than exposing two
providers to the rest of the app:

```text
CodexUsageProvider
├── CodexAppServerSource
└── CodexSessionJSONLSource (fallback)
```

## First implementation plan (no UI)

1. **Create the testable core target.** Add a Foundation-only core module and
   test target. Do not create views, `MenuBarExtra`, app lifecycle code, settings,
   signing, or packaging yet.
2. **Commit synthetic JSONL fixtures first.** Add one fixture for each A–E shape
   plus malformed, truncated, missing-field, invalid-percent, and cross-file
   ordering cases. Keep fixtures free of session text and real identifiers.
3. **Write parser tests before the parser.** Assert primary/secondary mapping,
   fractional percentages, optional metadata, timestamp conversion, unknown-field
   tolerance, recovery to an earlier valid line, and newest-event selection.
4. **Implement the JSONL projection and tail reader.** Use private `Decodable`
   DTOs with only whitelisted fields. Keep filesystem discovery separate from
   line decoding so tests do not require a real Codex directory.
5. **Add the common model and `UsageProvider`.** Introduce validated model
   invariants and source metadata, then map the JSONL DTO into that model.
6. **Add app-server protocol fixtures and decoder tests.** Cover multi-bucket,
   backward-compatible single-bucket, missing secondary, unknown plan, unknown
   fields, and error responses without launching a real process in unit tests.
7. **Implement the bounded app-server client.** Use `Process` and pipes directly,
   perform the handshake/read, enforce startup and response timeouts, terminate
   the child on cancellation, and sanitize errors. Do not invoke through a shell.
8. **Compose fallback behavior.** Try app-server first and fall back only for
   source availability/compatibility/refresh failures. Return the JSONL event's
   actual age so the store can mark it stale later.
9. **Add focused integration tests.** Use temporary synthetic directories and a
   fake app-server executable/protocol peer. A real installed Codex smoke test is
   manual and opt-in because it depends on local account state.

The first reviewable slice should end after steps 1–5: fixture-driven JSONL
parsing, the common model, and the provider contract, with no UI. Steps 6–9 then
complete the Codex provider data boundary for Milestone 2.

### Implementation progress

Steps 1–5 were completed on 2026-07-26 as the `LimitifyCore` Swift package
target and its test target. The slice includes the synthetic fixtures, projected
JSONL decoder, bounded multi-file tail reader, validated common models, and
`UsageProvider`. Ten unit tests pass. No app target or UI code has been added.

## Milestone 0 exit assessment

- Preferred source verified: yes, with an explicit experimental-host caveat.
- JSONL fallback verified: yes.
- Credentials accessed by Limitify or this spike: no.
- Observed structural variants represented synthetically: yes, A–E above.
- Provider boundary understood: yes.
- Ready for the first fixture/parser/model slice: yes.
