# CLAUDE.md

Menu-bar widget showing remaining Claude Code and Codex rate limits. macOS: single Bash SwiftBar plugin `claude-code-monitor.2m.sh`. Windows: `windows/claude-code-monitor.ps1`, which reimplements the same flow; change both when behaviour changes. No build step.

## Commands

```bash
./claude-code-monitor.2m.sh          # one run, prints SwiftBar output
bash tests/codex-window-labels.sh    # the only test
```

Windows: `.\windows\launch-monitor.bat`.

## Gotchas

- SwiftBar runs the copy in `~/SwiftBarPlugins/`, a separate clone of this repo. Edits here do nothing until that copy is updated.
- Claude auth comes from the macOS Keychain item `Claude Code-credentials`; Codex from `~/.codex/auth.json`. Either may be missing; it's only fatal when both are.
- Runtime state (cache, logs, config, generated menu-action scripts) lives in `~/.cache/claude-usage/`. Never commit it.
- `.swiftbarignore` keeps docs and Windows files out of SwiftBar; update it when adding non-plugin files.
- Keep `README.md` in sync with script behaviour.
