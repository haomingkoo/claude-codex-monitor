# Development Notes & Troubleshooting

Lessons learned while building and debugging the Claude Code Monitor. Useful for future contributors and for picking up Windows work.

## Rate Limit Death Spiral (Fixed in v9.0)

### The bug
In v8.0 and earlier, when the API returned 429, the plugin logged it and fell back to cached data — but **never updated the cache file's modification time**. Since the cache-TTL check uses the file's mtime to decide "is this cache fresh?", it always saw the cache as expired and made another API call on the next run.

With a 1-minute refresh interval, this meant **60 API calls per hour, all returning 429**, each one extending the rate limit. The plugin could never recover.

### The fix
Added `touch "$CACHE_FILE"` in the 429/error handler so the cache mtime gets refreshed. Subsequent runs see "cache is fresh" and skip the API call, giving the rate limit time to recover.

In v12.1 the Windows tray got the same fix: stale-cache fallback updates the cache mtime, and refresh interval changes now update the cache TTL too.

### If a user is stuck
1. Update to v9.0+ (the fix is in the main script)
2. If the token's rate limit is permanently exhausted, re-authenticate:
   ```bash
   claude auth logout && claude auth login
   ```
3. Reduce refresh rate via the ⏱ Refresh Rate submenu (5m or 10m recommended)

---

## SwiftBar (macOS) — Hard-Won Gotchas

### 1. `param1` does NOT work reliably
SwiftBar does not pass `param1`, `param2` to bash scripts. `$1` arrives empty.

**Fix:** Use individual scripts per action (e.g., `set-lang-en.sh`, `set-lang-zh.sh`), no parameters.

### 2. Submenu items (`--` prefix) — bash DOES work in SwiftBar
~~Items with `--` prefix render as native macOS submenus — `bash=` is silently ignored.~~ This was an old xbar bug (fixed April 2021). In current SwiftBar, `--` submenu items fully support `bash=`, `refresh=true`, and all other parameters. Used in v9.0 for Language and Refresh Rate flyout menus.

**Note:** Do NOT rename the plugin file to change refresh rate — SwiftBar loses track of renamed files. Use config files instead.

### 3. Helper scripts must live OUTSIDE the plugins directory
Scripts in `~/SwiftBarPlugins/` get treated as plugins even with `.swiftbarignore`.

**Fix:** Place helper scripts in `~/.cache/claude-usage/scripts/`.

### 4. `refresh=true` races with `bash=`
The refresh fires before the bash command completes, so the plugin re-runs with stale data.

**Fix:** For simple writes, the race is minimal. For complex ops, use a separate script that writes → sleeps → triggers `open -g "swiftbar://refreshplugin?name=..."`.

### 5. Non-actionable text is faint (macOS vibrancy)
macOS reduces opacity on non-clickable menu items regardless of `color=`.

**Fix:** Add `bash='true' terminal=false` to ALL display lines. This tricks SwiftBar into rendering at full opacity.

### 6. Repo structure — SwiftBar only scans root
After reorganizing into `macos/` and `windows/` subdirs, the plugin disappeared. SwiftBar only reads the root of its plugin folder.

**Fix:** Keep a root-level copy + add `macos/` and `windows/` to `.swiftbarignore`.

---

## Windows (PowerShell) — Known Issues

### Status: Reported broken (2026-03-12)
A user reported the Windows system tray version doesn't work. No specific error captured yet.

### Things to check
- Does `~/.claude/.credentials.json` exist? (Requires Claude Code login via `claude`)
- Does PowerShell execution policy allow the script? (`Set-ExecutionPolicy Bypass -Scope CurrentUser`)
- Is .NET Framework available for `System.Windows.Forms`?
- Try running directly: `powershell -File windows\claude-code-monitor.ps1` to see error output

### Architecture
- `windows/claude-code-monitor.ps1` — main PowerShell script
- `windows/launch-monitor.bat` — convenience launcher (hides console window)
- Uses `System.Windows.Forms.NotifyIcon` for system tray
- Reads OAuth token from `~/.claude/.credentials.json`
- Same API endpoint as macOS: `GET https://api.anthropic.com/api/oauth/usage`
