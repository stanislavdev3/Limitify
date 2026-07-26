# Installation and troubleshooting

## Install

1. Open `Limitify-0.1.0.dmg`.
2. Drag Limitify to Applications.
3. Start Limitify. It appears only in the menu bar and has no Dock icon.
4. Use Codex once if Limitify reports that no usage event has been observed.
5. For Claude, open Settings, enable Claude, and choose **Connect Claude Code**.
   Send one Claude Code message so its status-line payload contains rate limits.

The locally produced development DMG is ad-hoc signed until Developer ID
credentials are supplied. If Gatekeeper blocks that build, Control-click the app
and choose Open. Do not disable Gatekeeper system-wide. A Developer ID signed and
notarized release opens normally.

The default automatic refresh interval is 60 seconds. Local snapshots older
than 10 minutes remain visible with a stale warning.

## Troubleshooting

### Codex is not installed

Install Codex, or open Limitify Settings and choose an existing Codex sessions
directory. Live app-server refresh requires a compatible local `codex`
executable; JSONL fallback does not.

### Codex data not found

The default path is `~/.codex/sessions`. If `CODEX_HOME` was customized, choose
its `sessions` subdirectory in Settings.

### No usage data yet

Run at least one Codex request, wait for Codex to write its local usage event,
then choose Refresh in Limitify.

### Access denied

Choose a readable sessions directory in Settings. Limitify is distributed
outside the Mac App Store and does not request Full Disk Access.

### Claude Code is not connected

Claude Code must be installed locally. Open Limitify Settings and choose
**Connect Claude Code**. Limitify adds a local collector to Claude's official
status-line configuration. If a custom status line already exists, its command
continues to receive the original input and its output is preserved.

Claude exposes subscription limits after the first API response in a session.
Restart any Claude Code session that was already open when Limitify connected,
send one message in the interactive CLI, then choose Refresh in Limitify.
Non-interactive `claude -p` does not render the status line. Disconnecting in
Settings restores the previous status-line command.

### Launch at login needs approval

Open System Settings → General → Login Items and allow Limitify. Launch at login
works only for an installed application bundle, not a raw SwiftPM executable.

### Data is stale

Limitify preserves the last valid local snapshot after transient failures. Use
Codex or choose Refresh. JSONL usage cannot become newer until Codex writes a new
rate-limit event.
