# Limitify

Limitify is a native macOS menu bar application that shows usage limits for AI developer tools. The first integrations are Codex and Claude Code; the architecture allows other services to be added without redesigning the application.

This document is the initial product and technical specification. Decisions that are not settled yet are explicitly marked as open questions.

## Product goal

Answer one question at a glance: **how much usage is left, and when does it reset?**

Limitify should be:

- quick to read from the menu bar;
- local-first and respectful of credentials;
- useful even when only one provider is configured;
- extensible to multiple services and multiple limit windows;
- explicit when data is stale or unavailable.

## MVP scope

The first release supports Codex and Claude Code and displays:

- remaining or used percentage in the menu bar;
- every available limit window, such as a five-hour or weekly window;
- reset time for each window;
- Codex plan type when available;
- last successful refresh time;
- loading, unavailable, stale, and error states;
- manual refresh;
- configurable automatic refresh interval.

The first release does not include:

- cloud synchronization;
- accounts shared between Macs;
- historical charts or usage forecasting;
- payments or subscription management;
- automatic updates;
- integrations other than Codex and Claude Code.

## Proposed interface

### Menu bar

Default presentation:

```text
[███████░░░] 73%
```

The percentage and the compact bar both represent the remaining allowance. Keeping both indicators aligned avoids a confusing state where the bar shows used capacity while the number shows what remains. If multiple windows exist, the menu bar shows the most constrained window.

The bar should be compact enough to coexist with other menu bar items. The initial visual target is approximately 28–36 points wide with a thin rounded track. Its appearance must remain legible in light and dark mode and when macOS renders the status item using a monochrome style.

### Popover

```text
Limitify

Codex                                      Plus

5-hour limit                        73% left
███████████████░░░░░
Resets in 2h 18m

Weekly limit                        41% left
████████░░░░░░░░░░░░
Resets Tuesday at 14:30

Updated just now                    Refresh

Settings…                              Quit
```

When data is stale, the previous value remains visible with a warning instead of being replaced by an empty state.

## Data source strategy

Providers are read-only. Limitify must not copy, display, log, or transmit authentication tokens.

For Codex, implementation should follow this priority:

1. Use a supported local Codex/app-server capability for rate-limit information if one is available and stable.
2. Fall back to structured `rate_limits` events in local Codex JSONL session files.
3. Never depend on reading credentials from `~/.codex/auth.json` or on undocumented private HTTP endpoints.

The local Codex session data has been observed to contain:

- `used_percent`;
- `window_minutes`;
- `resets_at`;
- plan type;
- credits state;
- primary and optional secondary limit windows.

The JSONL fallback may be stale until Codex writes a new event. The provider must therefore return both the usage snapshot and its observation time.

## Architecture

Limitify uses native Swift and SwiftUI with `MenuBarExtra`. The initial target is macOS 14 or newer unless support for macOS 13 becomes a requirement.

No third-party dependencies should be introduced for the MVP unless they remove substantial complexity.

### Layers

```text
SwiftUI views
    ↓
Usage store / refresh coordinator
    ↓
UsageProvider protocol
    ├── Codex provider
    ├── Claude provider (future)
    ├── Cursor provider (future)
    └── OpenAI API provider (future)
```

### Provider contract

Every integration maps its native data to a common model:

```text
ServiceUsage
├── provider identifier
├── display name
├── account or plan label (optional)
├── limits[]
│   ├── identifier
│   ├── display name
│   ├── used fraction
│   ├── window duration (optional)
│   └── reset date (optional)
├── observedAt
└── source status
```

Provider errors are isolated: one failed provider must not prevent other providers from updating.

### Suggested project structure

```text
Limitify/
├── PROJECT.md
├── Limitify.xcodeproj/
├── Limitify/
│   ├── App/
│   ├── Models/
│   ├── Providers/
│   │   └── Codex/
│   ├── Services/
│   ├── Views/
│   └── Resources/
└── LimitifyTests/
```

## Refresh behavior

- Refresh automatically every 60 seconds by default.
- Refresh when the popover opens if the current snapshot is old.
- Allow manual refresh.
- Coalesce concurrent refresh requests.
- Keep the last successful snapshot after a transient failure.
- Mark data stale after a configurable threshold; the initial proposal is 10 minutes.
- Avoid continuously scanning every Codex session file. Inspect recently modified candidates and read only the required tail of each file.

## Settings

Initial settings:

- automatic refresh interval;
- stale-data threshold;
- Codex data directory with automatic detection;
- launch at login;
- enable or disable configured providers.

Use `UserDefaults` for preferences. Future provider secrets must be stored in Keychain, never in `UserDefaults` or project files.

## Error states

The UI must distinguish:

- Codex is not installed;
- the Codex data directory does not exist;
- no usage event has been observed yet;
- the latest data is stale;
- a session file is incomplete or malformed;
- the data format is unsupported;
- access to the data directory is denied.

Malformed and partially written JSONL lines should be ignored safely. Parsing should continue with earlier valid events.

## Privacy and security

- Read only the minimum local files required for usage information.
- Do not read `auth.json` for the JSONL implementation.
- Do not log raw session lines because they can contain conversation content.
- Parse usage records in memory and log only non-sensitive diagnostics.
- Do not add analytics or network requests in the MVP.
- Document every filesystem location accessed by the app.

## Testing strategy

Unit tests should cover:

- primary and secondary limit windows;
- conversion from used to remaining percentage;
- malformed and truncated JSONL lines;
- selection of the newest valid event;
- multiple session files ordered by modification time;
- missing reset time and plan type;
- stale-data calculation;
- provider error isolation;
- menu bar selection of the most constrained window.
- menu bar bar and percentage using the same remaining value.

Fixtures must contain synthetic usage records only, never copied user sessions.

Manual verification should cover:

- first launch with and without Codex installed;
- live refresh while Codex is running;
- appearance in light and dark mode;
- menu bar layouts with limited space;
- launch at login;
- behavior after sleep and wake.

## Implementation milestones

### Milestone 0 — Decisions and data spike

- Verify the preferred Codex source and document its stability.
- Capture synthetic examples for every observed rate-limit shape.

Spike notes and the no-UI implementation plan are recorded in
[`docs/milestone-0-codex-usage-spike.md`](docs/milestone-0-codex-usage-spike.md).

Exit criterion: the Codex provider contract and data source are understood without accessing credentials.

### Milestone 1 — Application shell

- Create the Xcode project and menu bar-only SwiftUI application.
- Add the common usage models and provider protocol.
- Implement the popover using preview data.
- Add loading, empty, stale, and error presentations.

Exit criterion: the complete MVP interface works with deterministic mock data.

### Milestone 2 — Codex integration

- Implement the selected supported source if available.
- Implement the local JSONL fallback.
- Add safe incremental file reading and timestamp handling.
- Connect provider refreshes to the UI.
- Add parser and provider tests.

Exit criterion: Limitify displays real Codex usage and handles absent or malformed data safely.

### Milestone 3 — Preferences and system integration

- Add settings.
- Add launch at login.
- Add refresh lifecycle behavior for sleep, wake, and popover opening.
- Add accessibility labels and keyboard navigation.

Exit criterion: the application is comfortable to run continuously.

### Milestone 4 — Distribution

- Add app icon and final visual polish.
- Configure signing and entitlements.
- Produce a notarized application bundle or DMG.
- Write installation, privacy, and troubleshooting documentation.

Exit criterion: another Mac can install and run Limitify without development tools.

## Product decisions

The following decisions are fixed for the MVP:

1. The menu bar shows the remaining percentage.
2. A compact usage bar appears next to the percentage and visualizes the same remaining value.
3. The minimum supported system is macOS 14 Sonoma.
4. Limitify is menu bar-only and does not show a Dock icon.
5. When several limits exist, the menu bar shows the most constrained window: the one with the lowest remaining percentage.
6. The MVP uses local Codex data. It does not promise live usage while Codex is not producing local updates.
7. Data older than 10 minutes remains visible but is marked as stale.
8. The popover selects whether the Codex or Claude logo and usage appear in the menu bar.
9. Initial distribution is direct using a signed and notarized DMG, not the Mac App Store.

## First development task

Complete Milestone 0 as a short technical spike. The first code should be a synthetic fixture plus a parser test, followed by the common model and provider contract. This keeps the data boundary testable before UI or packaging decisions become expensive.

## Implementation status

As of 2026-07-26, Milestones 0–3, the Claude Code integration, and the implementation/build portion of
Milestone 4 are complete. A universal ad-hoc signed app and verified DMG are
produced locally. Developer ID signing and Apple notarization remain pending
because no signing identity or notary credential is installed on the development
machine. Detailed evidence is recorded in
[`docs/release-status.md`](docs/release-status.md).
