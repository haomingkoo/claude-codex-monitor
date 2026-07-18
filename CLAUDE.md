# CLAUDE.md

## Purpose
Menu-bar / system-tray widget that shows remaining Claude Code and OpenAI Codex
rate limits in real time, with pace and burnout warnings, reset reminders, and
optional phone push alerts. macOS via SwiftBar, Windows via system tray.

## Tech Stack
- **macOS**: Bash (`claude-code-monitor.2m.sh`), runs as a [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin. Deps: `jq`, `python3`, `curl`, `osascript`.
- **Windows**: PowerShell (`windows/claude-code-monitor.ps1`), launched via `.bat`/`.vbs`, PowerShell 5.1+.
- No package manager or build step — this is a pair of standalone scripts, not a compiled app.

## Commands
There is no install or build tooling. To run manually:
```bash
# macOS — run the plugin directly (mirrors what SwiftBar does every 2 min)
./claude-code-monitor.2m.sh

# macOS — install into SwiftBar
mkdir -p ~/SwiftBarPlugins
cp claude-code-monitor.2m.sh ~/SwiftBarPlugins/
chmod +x ~/SwiftBarPlugins/claude-code-monitor.2m.sh
open -a SwiftBar
```
```powershell
# Windows — launch the tray monitor
.\windows\launch-monitor.bat
```
Run the focused shell check with `bash tests/codex-window-labels.sh`.

## Architecture
`claude-code-monitor.2m.sh` is a single-file script, organized top-to-bottom into
sections (grep `^# ====` to jump between them):
1. **CONFIG** — cache dir/file paths, Codex OAuth constants, refresh rate → cache TTL
2. **HELPER SCRIPTS** — auto-writes small `.sh` scripts under `~/.cache/claude-usage/scripts/` for dropdown menu actions (language, refresh rate, reminders, ntfy topic)
3. **TRANSLATIONS** — 6-language string table (en/zh/ja/ko/ta/ms)
4. **LOGGING**, **DEPENDENCIES**, **AUTH** — reads Claude token from macOS Keychain and Codex token from `~/.codex/auth.json`; both optional
5. **FETCH WITH CACHE** — hits Anthropic `oauth/usage` and ChatGPT `wham/usage`, caches to `~/.cache/claude-usage/`
6. **PARSE (Claude)**, **CODEX FETCH + PARSE** — turn API responses into remaining %, pace, burnout projection
7. **THEME**, **TIME HELPERS** — dark-mode detection, duration/countdown formatting
8. **NOTIFICATIONS** — desktop alerts at 50/25/10% thresholds and reset reminders; optional ntfy.sh phone push
9. **RENDER** — emits SwiftBar-format text (bitmap bar plugin protocol) to stdout

`windows/claude-code-monitor.ps1` reimplements the same flow (auth → fetch →
parse → render) natively for a Windows tray icon; `launch-monitor.bat`/`.vbs`
are thin launchers.

## Key Files
- `claude-code-monitor.2m.sh` — macOS/SwiftBar plugin (main script, ~1300 lines)
- `windows/claude-code-monitor.ps1` — Windows tray equivalent (~1170 lines)
- `windows/launch-monitor.bat`, `windows/launch-monitor.vbs` — Windows launchers
- `README.md` — user-facing install/config/feature docs (kept in sync with script behavior)
- `TROUBLESHOOTING.md` — common error states and fixes
- `.swiftbarignore` — tells SwiftBar to ignore non-plugin files (docs, `windows/`, `.bat`/`.vbs`/`.ps1`)
- Runtime state lives outside the repo at `~/.cache/claude-usage/` (cache, logs, per-user config, generated helper scripts) — never commit this
