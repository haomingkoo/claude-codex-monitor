# Claude Code Monitor

Know exactly how much Claude Code you have left — right from your menu bar.

A lightweight widget that tracks your **remaining** rate limits in real time, tells you when you're burning too fast, and alerts you before you run out. Available for **macOS** (SwiftBar) and **Windows** (system tray).

**New in v10.0:** Get alerts on your phone and smart "tokens refreshing soon" reminders — [see below](#-phone-alerts-optional--macos).

---

## What It Looks Like

**macOS (SwiftBar)**

```
  52% · 7d:81%                         <- menu bar

  Claude Code (max)
  ---------------------------------
  5-Hour Session
  ||||||||||||..........
  52.0% remaining
  Refills in 3h 42m (4:00 PM)
  Pace: 1.0x
  Burns out in ~5h 12m
  ---------------------------------
  7-Day Window
  ||||||||||||||||....
  81.0% remaining
  Refills in 4d 12h (Mar 16)
  Pace: 0.7x
  Burns out in ~6d 11h
  ---------------------------------
  Source: live
  ---------------------------------
  Refresh
  Open log
  ---------------------------------
  Refresh Rate                      >
  Language                          >
  ⏰ Remind Before Reset            >
  📱 Phone Alerts (ntfy)            >
```

**Windows (System Tray)** — two icons rotate in the tray (donut ring for 5h, bar for 7d). Click for the full dropdown:

```
  Claude Code (max)
  ---------------------------------
  5-Hour Session  [donut icon]
  ||||||||||||..........
  52% remaining
  Refills in 3h 42m (3:49 PM)
  Pace: 1.0x
  Burns out in ~5h 12m
  ---------------------------------
  7-Day Window  [bar icon]
  ||||||||||||||||....
  81% remaining
  Refills in 4d 12h (Mar 16)
  Pace: 0.7x
  Burns out in ~6d 11h
  ---------------------------------
  Refresh Now · Open Log
  Language / Settings / Exit
```

At a glance: 🟢 >50% left · 🟡 20–50% left · 🔴 <20% left

---

## Features

**See what's left** — 5-hour session, 7-day window, and Opus-specific quota (when applicable).

**Know when it resets** — countdown timer + local time, e.g., "Refills in 1h 49m (4:00 PM)". No timezone math needed.

**Know if you're going too fast**

| Icon | Pace | What it means |
|------|------|---------------|
| 🐢 | < 0.8x | Chill — plenty of headroom |
| ✅ | 0.8–1.3x | Sustainable — you'll make it to reset |
| ⚡ | 1.3–2.0x | Fast — you'll run out before reset at this rate |
| 🔥 | > 2.0x | Way too fast — slow down |

Plus a **burnout projection** — tells you when you'll hit 0% if you keep going at your current rate.

**Get alerted before you run out** — desktop notifications at 50%, 25%, and 10% remaining. Auto-resets when your window refills — no duplicate alerts.

**Get reminded when tokens refresh** (NEW · macOS) — notifies you before your window resets so you know when to get back to work. Smart enough to skip the reminder if you're actively coding. Configurable: 60, 30, and 10 minutes before reset (default).

**6 languages** — English, 中文, 日本語, 한국어, தமிழ், Bahasa Melayu. Switch from the dropdown menu.

---

## 📱 Phone Alerts (Optional · macOS)

Get the same alerts on your phone — away from your desk? You'll still know when tokens are low or about to refresh.

Uses [ntfy](https://ntfy.sh), a free and open-source notification service. **No accounts, no API keys, no tokens stored on your computer.**

> Currently macOS-only. Windows support may come in a future release.

**Setup takes 30 seconds:**

1. Install the **ntfy** app — [iOS](https://apps.apple.com/app/ntfy/id1625396347) · [Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy)
2. In the menu bar dropdown, click **📱 Phone Alerts → Set Topic…**
3. A dialog pops up with a random topic name (like a private channel) — click OK
4. On your phone, open ntfy → tap **+** → type the same topic name → Subscribe

Done. Your phone will now receive:

| What you'll get | How it alerts | When |
|----------------|---------------|------|
| Status check-in | Silent — just open the app to see it | Periodically (every 30m by default) |
| "Tokens resetting soon" | Normal notification | Before your window resets |
| 50% remaining | Normal notification | When you drop below 50% |
| 25% remaining | Louder notification | When you drop below 25% |
| 10% remaining | Urgent notification | When you're almost out |

**What's configurable:**

| Feature | Where to change it | Default |
|---------|-------------------|---------|
| Usage alerts (50/25/10%) | Always on when phone alerts are enabled | On |
| Reset reminders | ⏰ Remind Before Reset menu | 60 · 30 · 10 min |
| Status check-ins | 📱 Phone Alerts → Status Push | Every 30m (10m / 30m / 1h / 2h / Off) |

Desktop alerts work regardless of whether you set up phone alerts. Phone alerts just extend them to your pocket.

**Privacy:** Nothing sensitive is stored. The topic name is just a word you pick — not a password. Even if someone guessed it, all they'd see is "Claude Code at 25%." You can also [self-host ntfy](https://docs.ntfy.sh/install/) for full control.

**Fully optional** — skip this entirely and everything else works the same.

---

## Why the 7-Day Window Matters

The 5-hour session resets often, but the **7-day window is the real limit**. It resets once per week — burn through it early and you're locked out.

| What to know | |
|---|---|
| Resets all at once — not gradually | Plan around the reset date |
| Claude.ai web chat shares the same quota | Both count toward your weekly limit |
| 🔥 2.0x pace = burning a week's worth in ~3.5 days | Watch your pace indicator |

**Tip:** Keep the 7-day pace at ✅ 1.0x or below. If you see ⚡ or 🔥, ease off.

---

## Installation

**macOS** — requires [SwiftBar](https://github.com/swiftbar/SwiftBar), [jq](https://jqlang.github.io/jq/), python3, and [Claude Code](https://docs.anthropic.com/en/docs/claude-code). You must have logged into Claude Code at least once.

```bash
# 1. Install dependencies
brew install --cask swiftbar
brew install jq

# 2. Get the plugin (recommended)
mkdir -p ~/SwiftBarPlugins
curl -o ~/SwiftBarPlugins/claude-code-monitor.2m.sh \
  https://raw.githubusercontent.com/haomingkoo/claude-code-monitor/main/claude-code-monitor.2m.sh
chmod +x ~/SwiftBarPlugins/claude-code-monitor.2m.sh

# 3. Open SwiftBar → set plugin folder to ~/SwiftBarPlugins
open -a SwiftBar
```

> **If you `git clone` instead:** The repo includes Windows files in a `windows/` subfolder. SwiftBar may try to run `windows/launch-monitor.bat` and show errors — this is harmless but noisy. The `.swiftbarignore` file is included to suppress this. If you still see errors, the `curl` method above avoids the issue entirely.

You should see **🟢 XX% · 7d:XX%** in your menu bar. Everything else is created automatically.

**Windows** — requires Windows 10/11, PowerShell 5.1+, and [Claude Code](https://docs.anthropic.com/en/docs/claude-code). You must have logged into Claude Code at least once.

```powershell
# 1. Get the code
git clone https://github.com/haomingkoo/claude-code-monitor.git

# 2. Run it
.\windows\launch-monitor.bat
```

Two icons appear in your system tray. Click for the full dropdown.

**Auto-start on login:** Press **Win + R** → `shell:startup` → copy `launch-monitor.bat` into that folder.

---

## Configuration

All settings are accessible from the **dropdown menu** — no file editing needed. But if you prefer the terminal:

```bash
# Language
echo "zh" > ~/.cache/claude-usage/language

# Refresh rate (macOS) — how often the API is checked (2m / 5m / 10m)
echo "5m" > ~/.cache/claude-usage/refresh_rate

# Reset reminders (macOS) — minutes before reset to notify
echo "60 30 10" > ~/.cache/claude-usage/remind_before
echo "" > ~/.cache/claude-usage/remind_before            # turn off

# Phone alerts (macOS)
echo "my-topic-name" > ~/.cache/claude-usage/ntfy_topic
echo "true" > ~/.cache/claude-usage/ntfy_enabled
echo "30" > ~/.cache/claude-usage/ntfy_status_interval   # minutes (0 = off)

# Notification thresholds — edit in the script
NOTIFY_THRESHOLDS="50 25 10"
```

> **Note:** Don't rename the `.2m.sh` file — SwiftBar needs that exact filename.

---

## How It Works

1. Reads your Claude Code OAuth token from your system (macOS Keychain / Windows credentials file)
2. Checks Anthropic's usage API for your current utilization
3. Caches the response locally to avoid hitting rate limits
4. Calculates remaining %, pace, and burnout projection
5. Renders in the menu bar / system tray
6. Sends alerts when thresholds are crossed
7. Falls back to cached data if the API is unavailable

---

## Security

- Your OAuth token **never leaves your machine** — it's only sent to Anthropic's servers
- No tokens are written to disk or logged
- The cache only stores usage percentages and reset times
- Phone alerts (ntfy) don't involve any tokens — just a topic name

---

## Troubleshooting

**macOS**

| What you see | What's wrong | How to fix it |
|---|---|---|
| `CC: no auth` | Not logged into Claude Code | Run `claude` in terminal and log in |
| `CC: no token` | Keychain issue | Run `claude logout` then `claude` |
| `CC: error` | API error | Click **Open log** for details |
| `CC: 429` | Rate limited | Wait a few minutes — it backs off automatically |
| Widget not showing | SwiftBar not configured | Set folder to `~/SwiftBarPlugins` |

**Windows**

| What you see | What's wrong | How to fix it |
|---|---|---|
| CMD window stays open | Outdated launcher | Update to latest version |
| No tray icon | Script not running | Run `launch-monitor.bat` |
| "No data" | Not logged in | Run `claude` in terminal and log in |

**Stuck on 429?** Wait 5 minutes (it backs off automatically). Still stuck? Run `claude auth logout` → `claude auth login`. As a last resort: `rm -rf ~/.cache/claude-usage`, re-authenticate, and restart SwiftBar.

**Logs:** `tail -20 ~/.cache/claude-usage/plugin.log` (macOS) or `Get-Content ~\.cache\claude-usage\monitor.log -Tail 20` (Windows)

**Reset cache:** `rm -rf ~/.cache/claude-usage` — the plugin recreates everything on the next run.

---

## Version History

| Version | What changed |
|---------|-------------|
| **v10.0** | Phone alerts via ntfy (optional, no API keys). Smart reset reminders that only nudge when you're idle. Configurable from dropdown menu. |
| **v9.2** | Auto-create helper scripts. Add MIT LICENSE. Fix jq detection. |
| **v9.0** | Fix rate limit death spiral. Configurable refresh rate. Dynamic cache TTL. |
| **v8.1** | Windows: fix CMD window staying open on launch. |
| **v8.0** | Windows feature parity: dual icons, pace/burnout, 6 languages, notifications. |
| **v7.0** | Pace indicator, burnout projection, notifications, multi-language. |
| **v6.0** | Null-safe 7-day, robust timezone parsing, multi-language. |
| **v5.0** | Initial release. |

## License

MIT
