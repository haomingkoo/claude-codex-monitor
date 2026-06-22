#!/bin/bash

# <xbar.title>Claude Code Usage</xbar.title>
# <xbar.version>v12.0</xbar.version>
# <xbar.author>koohaoming</xbar.author>
# <xbar.desc>Menu-bar usage for Claude Code and OpenAI Codex — rotates between providers; shows 5h, weekly, per-model sub-limits, and credits. Works with either or both.</xbar.desc>

# ============================================================
# CONFIG
# ============================================================
CACHE_DIR="$HOME/.cache/claude-usage"
CACHE_FILE="$CACHE_DIR/usage.json"
LOG_FILE="$CACHE_DIR/plugin.log"
NOTIFY_STATE="$CACHE_DIR/notify_state"

# Codex (OpenAI) — optional second provider. Auto-detected; absent = Claude-only, unchanged.
CODEX_AUTH="$HOME/.codex/auth.json"
CODEX_CACHE="$CACHE_DIR/codex_usage.json"
CODEX_USAGE_URL="https://chatgpt.com/backend-api/wham/usage"
CODEX_TOKEN_URL="https://auth.openai.com/oauth/token"
CODEX_CLIENT_ID="app_EMoamEEZ73f0CkXaXp7hrann"

# Language: saved in config file, changeable from dropdown menu
LANG_FILE="$CACHE_DIR/language"
if [ -f "$LANG_FILE" ]; then
  LANGUAGE=$(cat "$LANG_FILE")
else
  LANGUAGE="${LANGUAGE:-en}"
fi

# Refresh rate: saved in config file, changeable from dropdown menu
RATE_FILE="$CACHE_DIR/refresh_rate"
if [ -f "$RATE_FILE" ]; then
  REFRESH_RATE=$(cat "$RATE_FILE")
else
  REFRESH_RATE="2m"
fi

# Set CACHE_TTL based on refresh rate
# Note: SwiftBar runs this script every 2m (.2m.sh), so rates faster than 2m are not possible.
case "$REFRESH_RATE" in
  2m)  CACHE_TTL=120 ;;
  5m)  CACHE_TTL=300 ;;
  10m) CACHE_TTL=600 ;;
  *)   CACHE_TTL=120 ;;
esac

# Notification thresholds (remaining %) — alerts when crossing below these
NOTIFY_THRESHOLDS="50 25 10"

# Reset reminders — notify before a window resets (desktop + phone)
REMIND_BEFORE_FILE="$CACHE_DIR/remind_before"
if [ -f "$REMIND_BEFORE_FILE" ]; then
  REMIND_BEFORE=$(cat "$REMIND_BEFORE_FILE")
else
  REMIND_BEFORE="60 30 10"  # minutes before reset
fi

# ntfy push notifications — phone alerts with no API keys needed
# Users pick a topic name (like a channel), subscribe in the ntfy app
NTFY_TOPIC_FILE="$CACHE_DIR/ntfy_topic"
NTFY_ENABLED_FILE="$CACHE_DIR/ntfy_enabled"
NTFY_STATUS_INTERVAL_FILE="$CACHE_DIR/ntfy_status_interval"
NTFY_STATUS_STATE="$CACHE_DIR/ntfy_last_status"
NTFY_SERVER="https://ntfy.sh"

if [ -f "$NTFY_TOPIC_FILE" ]; then
  NTFY_TOPIC=$(cat "$NTFY_TOPIC_FILE")
else
  NTFY_TOPIC=""
fi

if [ -f "$NTFY_ENABLED_FILE" ]; then
  NTFY_ENABLED=$(cat "$NTFY_ENABLED_FILE")
else
  NTFY_ENABLED="false"
fi

# Status push interval in minutes (silent updates viewable in ntfy app)
if [ -f "$NTFY_STATUS_INTERVAL_FILE" ]; then
  NTFY_STATUS_INTERVAL=$(cat "$NTFY_STATUS_INTERVAL_FILE")
else
  NTFY_STATUS_INTERVAL=30
fi

mkdir -p "$CACHE_DIR"

# ============================================================
# HELPER SCRIPTS (auto-created on first run)
# ============================================================
SCRIPT_DIR="$CACHE_DIR/scripts"
mkdir -p "$SCRIPT_DIR"

for lang in en zh ja ko ta ms; do
  f="$SCRIPT_DIR/set-lang-${lang}.sh"
  if [ ! -f "$f" ]; then
    printf '#!/bin/bash\necho "%s" > "$HOME/.cache/claude-usage/language"\n' "$lang" > "$f"
    chmod +x "$f"
  fi
done

for rate in 2m 5m 10m; do
  f="$SCRIPT_DIR/set-rate-${rate}.sh"
  if [ ! -f "$f" ]; then
    printf '#!/bin/bash\necho "%s" > "$HOME/.cache/claude-usage/refresh_rate"\n' "$rate" > "$f"
    chmod +x "$f"
  fi
done

# Reset reminder presets
for preset in "60 30 10" "30 10" "60" "off"; do
  safe=$(echo "$preset" | tr ' ' '-')
  f="$SCRIPT_DIR/set-remind-${safe}.sh"
  if [ ! -f "$f" ]; then
    if [ "$preset" = "off" ]; then
      printf '#!/bin/bash\necho "" > "$HOME/.cache/claude-usage/remind_before"\n' > "$f"
    else
      printf '#!/bin/bash\necho "%s" > "$HOME/.cache/claude-usage/remind_before"\n' "$preset" > "$f"
    fi
    chmod +x "$f"
  fi
done

# ntfy helper scripts
f="$SCRIPT_DIR/set-ntfy-topic.sh"
if [ ! -f "$f" ]; then
  cat > "$f" << 'NTFY_TOPIC_SCRIPT'
#!/bin/bash
RAND=$(openssl rand -hex 4)
TOPIC=$(osascript -e "text returned of (display dialog \"Enter your ntfy topic name.\nThis is like a channel — subscribe to it in the ntfy app on your phone.\n\nA random default is provided:\" default answer \"claude-monitor-${RAND}\" with title \"Claude Code Monitor\")" 2>/dev/null)
if [ -n "$TOPIC" ]; then
  echo "$TOPIC" > "$HOME/.cache/claude-usage/ntfy_topic"
  echo "true" > "$HOME/.cache/claude-usage/ntfy_enabled"
  osascript -e "display notification \"Topic set: $TOPIC — now subscribe to this topic in the ntfy app on your phone.\" with title \"Claude Code Monitor\" sound name \"Glass\"" 2>/dev/null
fi
NTFY_TOPIC_SCRIPT
  chmod +x "$f"
fi

f="$SCRIPT_DIR/copy-ntfy-topic.sh"
if [ ! -f "$f" ]; then
  cat > "$f" << 'NTFY_COPY_SCRIPT'
#!/bin/bash
TOPIC=$(cat "$HOME/.cache/claude-usage/ntfy_topic" 2>/dev/null)
if [ -n "$TOPIC" ]; then
  echo -n "$TOPIC" | pbcopy
  osascript -e "display notification \"Copied: $TOPIC\" with title \"Claude Code Monitor\"" 2>/dev/null
fi
NTFY_COPY_SCRIPT
  chmod +x "$f"
fi

f="$SCRIPT_DIR/ntfy-enable.sh"
if [ ! -f "$f" ]; then
  printf '#!/bin/bash\necho "true" > "$HOME/.cache/claude-usage/ntfy_enabled"\n' > "$f"
  chmod +x "$f"
fi

f="$SCRIPT_DIR/ntfy-disable.sh"
if [ ! -f "$f" ]; then
  printf '#!/bin/bash\necho "false" > "$HOME/.cache/claude-usage/ntfy_enabled"\n' > "$f"
  chmod +x "$f"
fi

# ntfy status push interval presets
for interval in 10 30 60 120 off; do
  f="$SCRIPT_DIR/set-status-${interval}.sh"
  if [ ! -f "$f" ]; then
    if [ "$interval" = "off" ]; then
      printf '#!/bin/bash\necho "0" > "$HOME/.cache/claude-usage/ntfy_status_interval"\n' > "$f"
    else
      printf '#!/bin/bash\necho "%s" > "$HOME/.cache/claude-usage/ntfy_status_interval"\n' "$interval" > "$f"
    fi
    chmod +x "$f"
  fi
done

# Force-refresh helper — drops a sentinel so the next run skips the cache TTL and hits the API
f="$SCRIPT_DIR/force-refresh.sh"
if [ ! -f "$f" ]; then
  printf '#!/bin/bash\ntouch "$HOME/.cache/claude-usage/force_refresh"\n' > "$f"
  chmod +x "$f"
fi

# ============================================================
# TRANSLATIONS
# ============================================================
case "$LANGUAGE" in
  zh)
    L_SESSION_5H="5小时会话"; L_WINDOW_7D="7天窗口"; L_WINDOW_7D_OPUS="7天 Opus"
    L_REMAINING="剩余"; L_REFILLS="重置于"; L_BURNS="预计耗尽"
    L_RESETS_AT="重置时间"; L_PACE="速率"
    L_SOURCE="数据来源"; L_REFRESH="刷新"; L_OPEN_LOG="打开日志"
    L_NOT_AVAIL="暂无数据 — 使用后更新"; L_RATE_LIMITED="请求受限 — 请稍后再试"
    L_NO_AUTH="未登录 Claude Code"; L_NO_TOKEN="无法解析 OAuth 令牌"
    L_BAD_DATA="API 返回数据无效"; L_API_ERROR="API 错误"
    L_NEED_JQ="需要安装 jq"; L_INSTALL_JQ="安装 jq"
    L_NOTIFY_TITLE="Claude Code 用量警告"; L_REFRESH_RATE="刷新频率"
    L_REMIND_RESET="⏰ 重置前提醒"; L_RESETS_SOON="重置提醒"
    L_PHONE_ALERTS="📱 手机提醒 (ntfy)"; L_NTFY_SET_TOPIC="设置主题…"
    L_NTFY_COPY_TOPIC="复制主题"; L_NTFY_NOT_SET="未配置 — 点击设置主题"
    L_STATUS_PUSH="状态推送"; L_NTFY_EVERY="每"; L_NTFY_OFF="关闭"
    fmt_remaining() { echo "${1}% $L_REMAINING"; }
    fmt_refills() { echo "$L_REFILLS ${1}"; }
    fmt_burns() { echo "$L_BURNS ~${1}"; }
    fmt_resets_at() { echo "$L_RESETS_AT: ${1}"; }
    fmt_pace() { echo "$L_PACE: ${1}x"; }
    fmt_notify() { echo "${1}: ${2}% $L_REMAINING"; }
    fmt_reset_remind() { echo "${1} 将在 ~${2}分钟后重置 (${3})"; }
    ;;
  ja)
    L_SESSION_5H="5時間セッション"; L_WINDOW_7D="7日間ウィンドウ"; L_WINDOW_7D_OPUS="7日間 Opus"
    L_REMAINING="残り"; L_REFILLS="リセットまで"; L_BURNS="消費予測"
    L_RESETS_AT="リセット時刻"; L_PACE="ペース"
    L_SOURCE="ソース"; L_REFRESH="更新"; L_OPEN_LOG="ログを開く"
    L_NOT_AVAIL="データなし — 使用後に更新されます"; L_RATE_LIMITED="レート制限中"
    L_NO_AUTH="Claude Code 未ログイン"; L_NO_TOKEN="OAuthトークン解析失敗"
    L_BAD_DATA="APIレスポンスが無効"; L_API_ERROR="APIエラー"
    L_NEED_JQ="jqが必要です"; L_INSTALL_JQ="jqをインストール"
    L_NOTIFY_TITLE="Claude Code 使用量警告"; L_REFRESH_RATE="更新頻度"
    L_REMIND_RESET="⏰ リセット前リマインド"; L_RESETS_SOON="リセットリマインド"
    L_PHONE_ALERTS="📱 スマホ通知 (ntfy)"; L_NTFY_SET_TOPIC="トピック設定…"
    L_NTFY_COPY_TOPIC="トピックをコピー"; L_NTFY_NOT_SET="未設定 — トピック設定をクリック"
    L_STATUS_PUSH="ステータス通知"; L_NTFY_EVERY="毎"; L_NTFY_OFF="オフ"
    fmt_remaining() { echo "$L_REMAINING ${1}%"; }
    fmt_refills() { echo "$L_REFILLS ${1}"; }
    fmt_burns() { echo "$L_BURNS ~${1}"; }
    fmt_resets_at() { echo "$L_RESETS_AT: ${1}"; }
    fmt_pace() { echo "$L_PACE: ${1}x"; }
    fmt_notify() { echo "${1}: $L_REMAINING ${2}%"; }
    fmt_reset_remind() { echo "${1} ~${2}分後にリセット (${3})"; }
    ;;
  ko)
    L_SESSION_5H="5시간 세션"; L_WINDOW_7D="7일 윈도우"; L_WINDOW_7D_OPUS="7일 Opus"
    L_REMAINING="남음"; L_REFILLS="리셋까지"; L_BURNS="소진 예상"
    L_RESETS_AT="리셋 시각"; L_PACE="속도"
    L_SOURCE="소스"; L_REFRESH="새로고침"; L_OPEN_LOG="로그 열기"
    L_NOT_AVAIL="데이터 없음 — 사용 후 업데이트됩니다"; L_RATE_LIMITED="요청 제한 — 잠시 후 다시 시도"
    L_NO_AUTH="Claude Code 미로그인"; L_NO_TOKEN="OAuth 토큰 파싱 실패"
    L_BAD_DATA="API 응답 오류"; L_API_ERROR="API 오류"
    L_NEED_JQ="jq 필요"; L_INSTALL_JQ="jq 설치"
    L_NOTIFY_TITLE="Claude Code 사용량 경고"; L_REFRESH_RATE="새로고침 주기"
    L_REMIND_RESET="⏰ 리셋 전 알림"; L_RESETS_SOON="리셋 알림"
    L_PHONE_ALERTS="📱 휴대폰 알림 (ntfy)"; L_NTFY_SET_TOPIC="토픽 설정…"
    L_NTFY_COPY_TOPIC="토픽 복사"; L_NTFY_NOT_SET="미설정 — 토픽 설정을 클릭하세요"
    L_STATUS_PUSH="상태 알림"; L_NTFY_EVERY="매"; L_NTFY_OFF="끄기"
    fmt_remaining() { echo "${1}% $L_REMAINING"; }
    fmt_refills() { echo "$L_REFILLS ${1}"; }
    fmt_burns() { echo "$L_BURNS ~${1}"; }
    fmt_resets_at() { echo "$L_RESETS_AT: ${1}"; }
    fmt_pace() { echo "$L_PACE: ${1}x"; }
    fmt_notify() { echo "${1}: ${2}% $L_REMAINING"; }
    fmt_reset_remind() { echo "${1} ~${2}분 후 리셋 (${3})"; }
    ;;
  ta)
    L_SESSION_5H="5-மணி அமர்வு"; L_WINDOW_7D="7-நாள் சாளரம்"; L_WINDOW_7D_OPUS="7-நாள் Opus"
    L_REMAINING="மீதம்"; L_REFILLS="மீட்டமைப்பு"; L_BURNS="தீர்ந்துவிடும்"
    L_RESETS_AT="மீட்டமைப்பு நேரம்"; L_PACE="வேகம்"
    L_SOURCE="மூலம்"; L_REFRESH="புதுப்பி"; L_OPEN_LOG="பதிவைத் திற"
    L_NOT_AVAIL="தரவு இல்லை — பயன்பாட்டிற்குப் பின் புதுப்பிக்கப்படும்"; L_RATE_LIMITED="வரம்பு — பின்னர் முயற்சிக்கவும்"
    L_NO_AUTH="Claude Code உள்நுழையவில்லை"; L_NO_TOKEN="OAuth டோக்கன் பிழை"
    L_BAD_DATA="API பதில் தவறானது"; L_API_ERROR="API பிழை"
    L_NEED_JQ="jq தேவை"; L_INSTALL_JQ="jq நிறுவு"
    L_NOTIFY_TITLE="Claude Code பயன்பாட்டு எச்சரிக்கை"; L_REFRESH_RATE="புதுப்பிப்பு வீதம்"
    L_REMIND_RESET="⏰ மீட்டமைப்பு நினைவூட்டல்"; L_RESETS_SOON="மீட்டமைப்பு நினைவூட்டல்"
    L_PHONE_ALERTS="📱 தொலைபேசி விழிப்பூட்டல் (ntfy)"; L_NTFY_SET_TOPIC="தலைப்பு அமை…"
    L_NTFY_COPY_TOPIC="தலைப்பை நகலெடு"; L_NTFY_NOT_SET="அமைக்கவில்லை — தலைப்பை அமைக்கவும்"
    L_STATUS_PUSH="நிலை அறிவிப்பு"; L_NTFY_EVERY="ஒவ்வொரு"; L_NTFY_OFF="நிறுத்து"
    fmt_remaining() { echo "${1}% $L_REMAINING"; }
    fmt_refills() { echo "$L_REFILLS ${1}"; }
    fmt_burns() { echo "$L_BURNS ~${1}"; }
    fmt_resets_at() { echo "$L_RESETS_AT: ${1}"; }
    fmt_pace() { echo "$L_PACE: ${1}x"; }
    fmt_notify() { echo "${1}: ${2}% $L_REMAINING"; }
    fmt_reset_remind() { echo "${1} ~${2} நிமிடத்தில் மீட்டமைப்பு (${3})"; }
    ;;
  ms)
    L_SESSION_5H="Sesi 5-Jam"; L_WINDOW_7D="Tetingkap 7-Hari"; L_WINDOW_7D_OPUS="7-Hari Opus"
    L_REMAINING="baki"; L_REFILLS="Ditetapkan dalam"; L_BURNS="Habis dalam"
    L_RESETS_AT="Masa tetapan"; L_PACE="Kadar"
    L_SOURCE="Sumber"; L_REFRESH="Muat semula"; L_OPEN_LOG="Buka log"
    L_NOT_AVAIL="Belum tersedia — dikemas kini selepas penggunaan"; L_RATE_LIMITED="Had kadar — cuba lagi nanti"
    L_NO_AUTH="Belum log masuk Claude Code"; L_NO_TOKEN="Tidak dapat menghurai token OAuth"
    L_BAD_DATA="Respons API tidak sah"; L_API_ERROR="Ralat API"
    L_NEED_JQ="Perlu jq"; L_INSTALL_JQ="Pasang jq"
    L_NOTIFY_TITLE="Amaran Penggunaan Claude Code"; L_REFRESH_RATE="Kadar muat semula"
    L_REMIND_RESET="⏰ Peringatan Sebelum Set Semula"; L_RESETS_SOON="Peringatan Set Semula"
    L_PHONE_ALERTS="📱 Amaran Telefon (ntfy)"; L_NTFY_SET_TOPIC="Tetapkan Topik…"
    L_NTFY_COPY_TOPIC="Salin Topik"; L_NTFY_NOT_SET="Belum dikonfigurasi — klik Tetapkan Topik"
    L_STATUS_PUSH="Status Tolak"; L_NTFY_EVERY="setiap"; L_NTFY_OFF="Matikan"
    fmt_remaining() { echo "${1}% $L_REMAINING"; }
    fmt_refills() { echo "$L_REFILLS ${1}"; }
    fmt_burns() { echo "$L_BURNS ~${1}"; }
    fmt_resets_at() { echo "$L_RESETS_AT: ${1}"; }
    fmt_pace() { echo "$L_PACE: ${1}x"; }
    fmt_notify() { echo "${1}: ${2}% $L_REMAINING"; }
    fmt_reset_remind() { echo "${1} set semula dalam ~${2}m (${3})"; }
    ;;
  *)
    L_SESSION_5H="5-Hour Session"; L_WINDOW_7D="7-Day Window"; L_WINDOW_7D_OPUS="7-Day Opus"
    L_REMAINING="remaining"; L_REFILLS="Refills in"; L_BURNS="Burns out in"
    L_RESETS_AT="Resets at"; L_PACE="Pace"
    L_SOURCE="Source"; L_REFRESH="Refresh"; L_OPEN_LOG="Open log"
    L_NOT_AVAIL="Not available yet — updates after usage"; L_RATE_LIMITED="Rate limited — try again later"
    L_NO_AUTH="Not logged into Claude Code"; L_NO_TOKEN="Could not parse OAuth token"
    L_BAD_DATA="Invalid response from API"; L_API_ERROR="API error"
    L_NEED_JQ="Need jq"; L_INSTALL_JQ="Install jq"
    L_NOTIFY_TITLE="Claude Code Usage Warning"; L_REFRESH_RATE="Refresh Rate"
    L_REMIND_RESET="⏰ Remind Before Reset"; L_RESETS_SOON="Reset Reminder"
    L_PHONE_ALERTS="📱 Phone Alerts (ntfy)"; L_NTFY_SET_TOPIC="Set Topic…"
    L_NTFY_COPY_TOPIC="Copy Topic"; L_NTFY_NOT_SET="Not configured — click Set Topic"
    L_STATUS_PUSH="Status Push"; L_NTFY_EVERY="every"; L_NTFY_OFF="Off"
    fmt_remaining() { echo "${1}% $L_REMAINING"; }
    fmt_refills() { echo "$L_REFILLS ${1}"; }
    fmt_burns() { echo "$L_BURNS ~${1}"; }
    fmt_resets_at() { echo "$L_RESETS_AT ${1}"; }
    fmt_pace() { echo "$L_PACE: ${1}x"; }
    fmt_notify() { echo "${1}: ${2}% $L_REMAINING"; }
    fmt_reset_remind() { echo "${1} resets in ~${2}m (${3})"; }
    ;;
esac

# Labels for the per-model sub-limit and extra-usage rows (English fallback across all languages)
: "${L_WINDOW_7D_SONNET:=7-Day Sonnet}"
: "${L_EXTRA_USAGE:=Extra Usage}"
: "${L_EXTRA_OFF:=off}"

# ============================================================
# LOGGING
# ============================================================
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" >> "$LOG_FILE"
}

# Keep log file under 200 lines
if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 200 ]; then
  tail -100 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

log "INFO" "Plugin run started"

# ============================================================
# DEPENDENCIES
# ============================================================
if ! command -v /opt/homebrew/bin/jq &>/dev/null && ! command -v /usr/local/bin/jq &>/dev/null; then
  echo "CC: $L_NEED_JQ"
  echo "---"
  echo "$L_INSTALL_JQ: brew install jq | bash='brew install jq' terminal=true"
  log "ERROR" "jq not found"
  exit 0
fi
if [ -x /opt/homebrew/bin/jq ]; then
  JQ=/opt/homebrew/bin/jq
else
  JQ=/usr/local/bin/jq
fi

# ============================================================
# AUTH — both providers optional; show whatever is logged in
# ============================================================
HAS_CODEX=false
[ -f "$CODEX_AUTH" ] && HAS_CODEX=true

# Claude auth (Keychain). Missing auth is only fatal when Codex is also absent.
CLAUDE_OK=true
CREDS=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
TOKEN=""
if [ -z "$CREDS" ]; then
  CLAUDE_OK=false
  log "WARN" "No Claude credentials in Keychain"
else
  TOKEN=$(echo "$CREDS" | $JQ -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
  if [ -z "$TOKEN" ]; then
    CLAUDE_OK=false
    log "ERROR" "Failed to parse Claude accessToken"
  fi
fi

# Nothing to show at all → surface the auth error and stop
if [ "$CLAUDE_OK" = false ] && [ "$HAS_CODEX" = false ]; then
  echo "CC: no auth"
  echo "---"
  echo "$L_NO_AUTH | size=13"
  exit 0
fi

# ============================================================
# FETCH WITH CACHE
# ============================================================
# Force-refresh sentinel — shared by both providers, detected once per run
FORCE_REFRESH_FILE="$CACHE_DIR/force_refresh"
FORCE_REFRESH=false
if [ -f "$FORCE_REFRESH_FILE" ]; then
  FORCE_REFRESH=true
  rm -f "$FORCE_REFRESH_FILE"
  log "INFO" "Force refresh requested — bypassing cache"
fi

# Remaining-percent helper (used by both Claude and Codex)
calc_remaining() { echo "scale=1; 100 - $1" | bc; }

# ----- Claude usage (only when logged in) -----
if [ "$CLAUDE_OK" = true ]; then
USE_CACHE=false
if [ "$FORCE_REFRESH" = false ] && [ -f "$CACHE_FILE" ]; then
  cache_age=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE") ))
  if [ "$cache_age" -lt "$CACHE_TTL" ]; then
    USE_CACHE=true
    log "INFO" "Using cache (age: ${cache_age}s)"
  fi
fi

if [ "$USE_CACHE" = true ]; then
  USAGE=$(cat "$CACHE_FILE")
  FETCH_STATUS="cached (${cache_age}s ago)"
else
  HTTP_CODE=$(curl -s -o "$CACHE_FILE.tmp" -w "%{http_code}" --max-time 10 \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

  if [ "$HTTP_CODE" = "200" ]; then
    mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    chmod 600 "$CACHE_FILE" 2>/dev/null  # usage data is private — owner-only
    USAGE=$(cat "$CACHE_FILE")
    FETCH_STATUS="live"
    log "INFO" "API call success (HTTP $HTTP_CODE)"
  elif [ "$HTTP_CODE" = "429" ]; then
    log "WARN" "Rate limited (HTTP 429) — using stale cache"
    rm -f "$CACHE_FILE.tmp"
    if [ -f "$CACHE_FILE" ]; then
      touch "$CACHE_FILE"  # refresh mtime so CACHE_TTL prevents further API calls
      USAGE=$(cat "$CACHE_FILE")
      FETCH_STATUS="rate limited — showing stale data"
    elif [ "$HAS_CODEX" = false ]; then
      echo "CC: 429"
      echo "---"
      echo "$L_RATE_LIMITED | size=13 color=#CC7700"
      echo "---"
      echo "$L_REFRESH | bash='$SCRIPT_DIR/force-refresh.sh' terminal=false refresh=true size=13"
      exit 0
    else
      CLAUDE_OK=false  # Codex is present — skip Claude, show Codex
    fi
  else
    log "ERROR" "API call failed (HTTP $HTTP_CODE)"
    rm -f "$CACHE_FILE.tmp"
    if [ -f "$CACHE_FILE" ]; then
      touch "$CACHE_FILE"  # refresh mtime so CACHE_TTL prevents further API calls
      USAGE=$(cat "$CACHE_FILE")
      FETCH_STATUS="error (HTTP $HTTP_CODE) — showing stale data"
    elif [ "$HAS_CODEX" = false ]; then
      echo "CC: error"
      echo "---"
      echo "$L_API_ERROR (HTTP $HTTP_CODE) | size=13 color=#CC0000"
      echo "---"
      echo "$L_OPEN_LOG | bash='open' param1='$LOG_FILE' terminal=false size=13"
      echo "$L_REFRESH | bash='$SCRIPT_DIR/force-refresh.sh' terminal=false refresh=true size=13"
      exit 0
    else
      CLAUDE_OK=false
    fi
  fi
fi
fi  # end Claude fetch gate

# Validate + parse Claude data only if the fetch produced usable JSON
if [ "$CLAUDE_OK" = true ]; then
if ! echo "$USAGE" | $JQ -e '.five_hour.utilization // empty' &>/dev/null; then
  log "WARN" "Claude API returned null data — will retry next run"
  if [ "$HAS_CODEX" = false ]; then
    echo "CC: waiting"
    echo "---"
    echo "$L_NOT_AVAIL | size=13"
    echo "---"
    echo "$L_OPEN_LOG | bash='open' param1='$LOG_FILE' terminal=false size=13"
    echo "$L_REFRESH | bash='$SCRIPT_DIR/force-refresh.sh' terminal=false refresh=true size=13"
    exit 0
  fi
  CLAUDE_OK=false
fi
fi

# ============================================================
# PARSE (Claude)
# ============================================================
if [ "$CLAUDE_OK" = true ]; then
five_hr_used=$(echo "$USAGE" | $JQ -r 'if .five_hour then .five_hour.utilization // 0 else empty end')
five_hr_reset=$(echo "$USAGE" | $JQ -r 'if .five_hour then .five_hour.resets_at // empty else empty end')
seven_day_used=$(echo "$USAGE" | $JQ -r 'if .seven_day then .seven_day.utilization // 0 else empty end')
seven_day_reset=$(echo "$USAGE" | $JQ -r 'if .seven_day then .seven_day.resets_at // empty else empty end')
opus_used=$(echo "$USAGE" | $JQ -r 'if .seven_day_opus then .seven_day_opus.utilization // empty else empty end')
opus_reset=$(echo "$USAGE" | $JQ -r 'if .seven_day_opus then .seven_day_opus.resets_at // empty else empty end')
sonnet_used=$(echo "$USAGE" | $JQ -r 'if .seven_day_sonnet then .seven_day_sonnet.utilization // empty else empty end')
sonnet_reset=$(echo "$USAGE" | $JQ -r 'if .seven_day_sonnet then .seven_day_sonnet.resets_at // empty else empty end')

# Extra Usage (pay-as-you-go credits) — separate from the rate-limit windows
extra_enabled=$(echo "$USAGE" | $JQ -r '.spend.enabled // false')
extra_used_minor=$(echo "$USAGE" | $JQ -r '.spend.used.amount_minor // empty')
extra_limit_minor=$(echo "$USAGE" | $JQ -r '.spend.limit.amount_minor // empty')
extra_exponent=$(echo "$USAGE" | $JQ -r '.spend.limit.exponent // 2')
extra_currency=$(echo "$USAGE" | $JQ -r '.spend.limit.currency // empty')

five_hr_left=$(calc_remaining "${five_hr_used:-0}")

HAS_SEVEN_DAY=true
if [ -z "$seven_day_used" ]; then
  HAS_SEVEN_DAY=false
  seven_day_left=""
else
  seven_day_left=$(calc_remaining "$seven_day_used")
fi

log "INFO" "5h: ${five_hr_left}% left | 7d: ${seven_day_left:-N/A}% left | source: $FETCH_STATUS"
fi  # end Claude parse gate

# ============================================================
# THEME
# ============================================================
DARK_MODE=$(defaults read -g AppleInterfaceStyle 2>/dev/null)
if [ "$DARK_MODE" = "Dark" ]; then
  TEXT_PRIMARY="#EEEEEE"
  TEXT_SECONDARY="#BBBBBB"
  TEXT_MUTED="#888888"
  COLOR_GREEN="#2ECC71"
  COLOR_ORANGE="#E67E22"
  COLOR_RED="#E74C3C"
  BAR_FILLED_GREEN="#27AE60"
  BAR_FILLED_ORANGE="#D35400"
  BAR_FILLED_RED="#C0392B"
  BAR_EMPTY="#444444"
else
  TEXT_PRIMARY="#2a2a2a"
  TEXT_SECONDARY="#2a2a2a"
  TEXT_MUTED="#2a2a2a"
  COLOR_GREEN="#004D2C"
  COLOR_ORANGE="#8B4000"
  COLOR_RED="#8B0000"
  BAR_FILLED_GREEN="#004D2C"
  BAR_FILLED_ORANGE="#8B4000"
  BAR_FILLED_RED="#8B0000"
  BAR_EMPTY="#999999"
fi

# Helper: only emit "color=X" when X is non-empty; omitting lets macOS use native text color
c() { [ -n "$1" ] && echo "color=$1" || echo ""; }

color_for_remaining() {
  local r=${1%.*}
  if [ "$r" -le 20 ]; then
    echo "$COLOR_RED"
  elif [ "$r" -le 50 ]; then
    echo "$COLOR_ORANGE"
  else
    echo "$COLOR_GREEN"
  fi
}

bar_color_for_remaining() {
  local r=${1%.*}
  if [ "$r" -le 20 ]; then
    echo "$BAR_FILLED_RED"
  elif [ "$r" -le 50 ]; then
    echo "$BAR_FILLED_ORANGE"
  else
    echo "$BAR_FILLED_GREEN"
  fi
}

progress_bar() {
  local pct=${1%.*}
  local width=20
  local filled=$(( (pct * width) / 100 ))
  local empty=$((width - filled))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="■"; done
  for ((i=0; i<empty; i++)); do bar+="□"; done
  echo "$bar"
}

status_icon() {
  local r=${1%.*}
  if [ "$r" -le 20 ]; then
    echo "🔴"
  elif [ "$r" -le 50 ]; then
    echo "🟡"
  else
    echo "🟢"
  fi
}

# ============================================================
# TIME HELPERS
# ============================================================
format_duration() {
  local diff="$1"
  if [ "$diff" -le 0 ] 2>/dev/null; then
    echo ""
    return
  fi
  local days=$((diff / 86400))
  local hours=$(( (diff % 86400) / 3600 ))
  local mins=$(( (diff % 3600) / 60 ))
  if [ "$days" -gt 0 ]; then
    echo "${days}d ${hours}h"
  elif [ "$hours" -gt 0 ]; then
    echo "${hours}h ${mins}m"
  else
    echo "${mins}m"
  fi
}

parse_reset_epoch() {
  local reset_ts="$1"
  if [ -z "$reset_ts" ] || [ "$reset_ts" = "null" ]; then
    echo ""
    return
  fi
  # Try python3 first — handles any ISO 8601 timezone correctly
  if command -v python3 &>/dev/null; then
    local epoch=$(python3 -c "
from datetime import datetime, timezone
ts = '$reset_ts'
dt = datetime.fromisoformat(ts)
print(int(dt.astimezone(timezone.utc).timestamp()))
" 2>/dev/null)
    if [ -n "$epoch" ]; then
      echo "$epoch"
      return
    fi
  fi
  # macOS fallback: strip offset, parse as UTC (works if API returns +00:00/Z)
  local clean_ts=$(echo "$reset_ts" | sed 's/\.[0-9]*//; s/[+-][0-9][0-9]:[0-9][0-9]$//; s/Z$//')
  local epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$clean_ts" "+%s" 2>/dev/null)
  if [ -n "$epoch" ]; then
    echo "$epoch"
    return
  fi
  # Nothing worked
  log "WARN" "Could not parse timestamp: $reset_ts"
  echo ""
}

format_reset() {
  local reset_ts="$1"
  local epoch=$(parse_reset_epoch "$reset_ts")
  if [ -z "$epoch" ]; then
    echo ""
    return
  fi
  local now=$(date "+%s")
  local diff=$((epoch - now))
  format_duration "$diff"
}

# Convert reset timestamp to local time string (e.g., "3:49 PM" or "Mar 15 3:49 PM")
format_local_reset_time() {
  local reset_ts="$1"
  local epoch=$(parse_reset_epoch "$reset_ts")
  if [ -z "$epoch" ]; then
    echo ""
    return
  fi
  local now=$(date "+%s")
  local diff=$((epoch - now))
  if [ "$diff" -le 0 ]; then
    echo ""
    return
  fi
  # If reset is today, show just time; if another day, include date
  local reset_date=$(date -r "$epoch" "+%Y-%m-%d" 2>/dev/null)
  local today=$(date "+%Y-%m-%d")
  if [ "$reset_date" = "$today" ]; then
    date -r "$epoch" "+%I:%M %p" 2>/dev/null | sed 's/^0//'
  else
    date -r "$epoch" "+%b %d %I:%M %p" 2>/dev/null | sed 's/  / /g; s/ 0/ /g'
  fi
}

# Project when tokens will run out based on current burn rate
format_burnout() {
  local utilization="$1"
  local reset_ts="$2"
  local window_seconds="$3"

  local used_int=${utilization%.*}
  if [ "$used_int" -le 0 ] 2>/dev/null; then
    echo ""
    return
  fi

  local reset_epoch=$(parse_reset_epoch "$reset_ts")
  if [ -z "$reset_epoch" ]; then
    echo ""
    return
  fi

  local now=$(date "+%s")
  local secs_until_reset=$((reset_epoch - now))
  if [ "$secs_until_reset" -le 0 ]; then
    echo ""
    return
  fi

  local elapsed=$((window_seconds - secs_until_reset))
  if [ "$elapsed" -le 0 ]; then
    echo ""
    return
  fi

  # seconds until 100% = (100 - utilization) * elapsed / utilization
  local remaining=$(echo "scale=1; 100 - $utilization" | bc)
  local remaining_int=${remaining%.*}
  if [ "$remaining_int" -le 0 ] 2>/dev/null; then
    echo "now"
    return
  fi

  local secs_to_burnout=$(echo "scale=0; $remaining * $elapsed / $utilization" | bc)
  local burnout_str=$(format_duration "$secs_to_burnout")
  if [ -n "$burnout_str" ]; then
    echo "$burnout_str"
  fi
}

# Calculate pace: how fast you're burning vs sustainable linear rate
# Returns: multiplier (e.g., "1.5" means 1.5x faster than sustainable)
calc_pace() {
  local utilization="$1"
  local reset_ts="$2"
  local window_seconds="$3"

  local used_int=${utilization%.*}
  if [ "$used_int" -le 0 ] 2>/dev/null; then
    echo ""
    return
  fi

  local reset_epoch=$(parse_reset_epoch "$reset_ts")
  if [ -z "$reset_epoch" ]; then
    echo ""
    return
  fi

  local now=$(date "+%s")
  local secs_until_reset=$((reset_epoch - now))
  if [ "$secs_until_reset" -le 0 ]; then
    echo ""
    return
  fi

  local elapsed=$((window_seconds - secs_until_reset))
  if [ "$elapsed" -le 0 ]; then
    echo ""
    return
  fi

  # ideal usage at this point = (elapsed / window) * 100
  # pace = actual / ideal
  local pace=$(echo "scale=1; ($utilization * $window_seconds) / (100 * $elapsed)" | bc)
  # Ensure leading zero (bc outputs ".5" not "0.5")
  case "$pace" in
    .*) pace="0${pace}" ;;
  esac
  echo "$pace"
}

pace_icon() {
  local pace="$1"
  # Compare as integers (pace * 10) to avoid float issues in bash
  local pace_x10=$(echo "scale=0; $pace * 10 / 1" | bc)
  if [ "$pace_x10" -ge 20 ]; then
    echo "🔥"  # >2x — burning way too fast
  elif [ "$pace_x10" -ge 13 ]; then
    echo "⚡"  # >1.3x — faster than sustainable
  elif [ "$pace_x10" -ge 8 ]; then
    echo "✅"  # 0.8-1.3x — on pace
  else
    echo "🐢"  # <0.8x — conservative
  fi
}

# ============================================================
# NOTIFICATIONS
# ============================================================

# Send push notification via ntfy (no API keys — just a topic name)
ntfy_send() {
  local title="$1"
  local message="$2"
  local priority="${3:-default}"
  local tags="${4:-}"

  if [ "$NTFY_ENABLED" != "true" ] || [ -z "$NTFY_TOPIC" ]; then
    return
  fi

  local -a cmd=(curl -s --max-time 5
    -H "Title: $title"
    -H "Priority: $priority")
  [ -n "$tags" ] && cmd+=(-H "Tags: $tags")
  cmd+=(-d "$message" "${NTFY_SERVER}/${NTFY_TOPIC}")

  "${cmd[@]}" >/dev/null 2>&1 &
}

check_and_notify() {
  local label="$1"
  local remaining="$2"
  local key="$3"  # unique key for this window (e.g., "5h" or "7d")

  local remaining_int=${remaining%.*}
  local state_file="${NOTIFY_STATE}_${key}"

  # Read last notified threshold
  local last_threshold=100
  if [ -f "$state_file" ]; then
    last_threshold=$(cat "$state_file" 2>/dev/null)
    # Reset if usage has recovered above the last threshold (window reset)
    if [ "$remaining_int" -gt "$last_threshold" ] 2>/dev/null; then
      last_threshold=100
      echo "100" > "$state_file"
    fi
  fi

  for threshold in $NOTIFY_THRESHOLDS; do
    if [ "$remaining_int" -le "$threshold" ] && [ "$last_threshold" -gt "$threshold" ] 2>/dev/null; then
      # Crossed below this threshold — notify desktop
      local msg=$(fmt_notify "$label" "$remaining_int")
      osascript -e "display notification \"$msg\" with title \"$L_NOTIFY_TITLE\" sound name \"Funk\"" 2>/dev/null
      # Also push to phone via ntfy (escalating priority)
      local ntfy_priority="default"
      if [ "$threshold" -le 10 ]; then
        ntfy_priority="urgent"
      elif [ "$threshold" -le 25 ]; then
        ntfy_priority="high"
      fi
      ntfy_send "$L_NOTIFY_TITLE" "$msg" "$ntfy_priority" "warning"
      echo "$threshold" > "$state_file"
      log "INFO" "Notification sent: $label at ${remaining_int}% (threshold: ${threshold}%)"
      return
    fi
  done
}

# Remind before a window resets (desktop + phone)
check_reset_reminder() {
  local label="$1"
  local reset_ts="$2"
  local key="$3"
  local remaining="$4"

  if [ -z "$REMIND_BEFORE" ]; then return; fi

  local epoch=$(parse_reset_epoch "$reset_ts")
  if [ -z "$epoch" ]; then return; fi

  local now=$(date "+%s")
  local secs_until=$((epoch - now))
  local mins_until=$((secs_until / 60))

  if [ "$mins_until" -le 0 ]; then return; fi

  local state_file="${CACHE_DIR}/remind_state_${key}"
  local last_reminded=999
  if [ -f "$state_file" ]; then
    last_reminded=$(cat "$state_file" 2>/dev/null)
    [ -z "$last_reminded" ] && last_reminded=999
  fi

  # Only remind if usage is moderate — don't disturb someone actively burning tokens
  # (if pace > 1.3x they're clearly at the computer and don't need a reminder)
  local remaining_int=${remaining%.*}
  if [ "$key" = "5h" ]; then
    local pace=$(calc_pace "$five_hr_used" "$five_hr_reset" "18000")
  else
    local pace=$(calc_pace "$seven_day_used" "$seven_day_reset" "604800")
  fi
  if [ -n "$pace" ]; then
    local pace_x10=$(echo "scale=0; $pace * 10 / 1" | bc)
    if [ "$pace_x10" -ge 13 ]; then
      log "INFO" "Reset reminder skipped: $label pace ${pace}x (actively using)"
      return
    fi
  fi

  # Check thresholds (must be in descending order: e.g., "60 30 10")
  for mins in $REMIND_BEFORE; do
    if [ "$mins_until" -le "$mins" ] && [ "$last_reminded" -gt "$mins" ]; then
      local reset_time=$(format_local_reset_time "$reset_ts")
      local msg=$(fmt_reset_remind "$label" "$mins_until" "$reset_time")
      [ -n "$remaining" ] && msg="$msg — ${remaining_int}% remaining"
      osascript -e "display notification \"$msg\" with title \"$L_RESETS_SOON\" sound name \"Funk\"" 2>/dev/null
      ntfy_send "$L_RESETS_SOON" "$msg" "default" "clock,arrows_counterclockwise"
      echo "$mins" > "$state_file"
      log "INFO" "Reset reminder: $label in ${mins_until}m (threshold: ${mins}m)"
      return
    fi
  done

  # Reset state when far from next reset (new window started)
  local max_remind=$(echo "$REMIND_BEFORE" | tr ' ' '\n' | sort -rn | head -1)
  if [ "$mins_until" -gt "$max_remind" ] && [ "$last_reminded" -ne 999 ]; then
    echo "999" > "$state_file"
  fi
}

# Silent status push to ntfy (viewable in app without buzzing)
ntfy_status_push() {
  if [ "$NTFY_ENABLED" != "true" ] || [ -z "$NTFY_TOPIC" ]; then return; fi
  if [ "$NTFY_STATUS_INTERVAL" = "0" ] || [ -z "$NTFY_STATUS_INTERVAL" ]; then return; fi

  local now=$(date +%s)
  local last_sent=0
  if [ -f "$NTFY_STATUS_STATE" ]; then
    last_sent=$(cat "$NTFY_STATUS_STATE" 2>/dev/null)
    [ -z "$last_sent" ] && last_sent=0
  fi

  local interval_secs=$((NTFY_STATUS_INTERVAL * 60))
  if [ $((now - last_sent)) -lt "$interval_secs" ]; then return; fi

  # Build status message
  local msg="5h: ${five_hr_left}%"
  if [ "$HAS_SEVEN_DAY" = true ]; then
    msg="$msg | 7d: ${seven_day_left}%"
  fi

  local pace=$(calc_pace "$five_hr_used" "$five_hr_reset" "18000")
  if [ -n "$pace" ]; then
    local picon=$(pace_icon "$pace")
    msg="$msg | ${picon} ${pace}x"
  fi

  local reset_str=$(format_reset "$five_hr_reset")
  local local_time=$(format_local_reset_time "$five_hr_reset")
  if [ -n "$reset_str" ]; then
    msg="$msg | Resets in $reset_str"
    [ -n "$local_time" ] && msg="$msg ($local_time)"
  fi

  ntfy_send "Claude Code Status" "$msg" "min" "bar_chart"
  echo "$now" > "$NTFY_STATUS_STATE"
  log "INFO" "ntfy status push sent"
}

# ============================================================
# CODEX FETCH + PARSE (optional second provider; runs after helpers exist)
# Security: tokens are never logged or echoed; auth.json + caches stay mode 600.
# ============================================================
CODEX_OK=false
CODEX_STATUS=""
if [ "$HAS_CODEX" = true ]; then
  cx_access=$($JQ -r '.tokens.access_token // empty' "$CODEX_AUTH" 2>/dev/null)
  cx_acct=$($JQ -r '.tokens.account_id // empty' "$CODEX_AUTH" 2>/dev/null)

  cx_use_cache=false
  if [ "$FORCE_REFRESH" = false ] && [ -f "$CODEX_CACHE" ]; then
    cx_age=$(( $(date +%s) - $(stat -f %m "$CODEX_CACHE") ))
    [ "$cx_age" -lt "$CACHE_TTL" ] && cx_use_cache=true
  fi

  if [ "$cx_use_cache" = true ]; then
    CODEX_USAGE=$(cat "$CODEX_CACHE")
    CODEX_STATUS="cached (${cx_age}s ago)"
    CODEX_OK=true
  elif [ -n "$cx_access" ]; then
    cx_code=$(curl -s -o "$CODEX_CACHE.tmp" -w "%{http_code}" --max-time 10 \
      -H "Authorization: Bearer $cx_access" \
      -H "ChatGPT-Account-Id: $cx_acct" \
      -H "User-Agent: codex_cli_rs" \
      -H "originator: codex_cli_rs" \
      -H "Accept: application/json" \
      "$CODEX_USAGE_URL" 2>/dev/null)

    # Token expired → refresh via refresh_token, write back to auth.json (600), retry once
    if [ "$cx_code" = "401" ]; then
      cx_refresh=$($JQ -r '.tokens.refresh_token // empty' "$CODEX_AUTH" 2>/dev/null)
      if [ -n "$cx_refresh" ]; then
        log "INFO" "Codex token expired — refreshing"
        cx_new=$(curl -s --max-time 10 -X POST "$CODEX_TOKEN_URL" \
          -H "Content-Type: application/json" \
          -d "{\"client_id\":\"$CODEX_CLIENT_ID\",\"grant_type\":\"refresh_token\",\"refresh_token\":\"$cx_refresh\"}" 2>/dev/null)
        cx_new_access=$(echo "$cx_new" | $JQ -r '.access_token // empty' 2>/dev/null)
        if [ -n "$cx_new_access" ]; then
          cx_new_id=$(echo "$cx_new" | $JQ -r '.id_token // empty' 2>/dev/null)
          cx_new_refresh=$(echo "$cx_new" | $JQ -r '.refresh_token // empty' 2>/dev/null)
          cx_tmp_auth="$CODEX_AUTH.tmp.$$"
          $JQ --arg a "$cx_new_access" --arg i "$cx_new_id" --arg r "$cx_new_refresh" \
            '.tokens.access_token=$a
             | (if $i!="" then .tokens.id_token=$i else . end)
             | (if $r!="" then .tokens.refresh_token=$r else . end)
             | .last_refresh=(now|todate)' \
            "$CODEX_AUTH" > "$cx_tmp_auth" 2>/dev/null
          if [ -s "$cx_tmp_auth" ] && $JQ -e . "$cx_tmp_auth" >/dev/null 2>&1; then
            chmod 600 "$cx_tmp_auth" 2>/dev/null
            mv "$cx_tmp_auth" "$CODEX_AUTH"
            cx_access="$cx_new_access"
            cx_code=$(curl -s -o "$CODEX_CACHE.tmp" -w "%{http_code}" --max-time 10 \
              -H "Authorization: Bearer $cx_access" \
              -H "ChatGPT-Account-Id: $cx_acct" \
              -H "User-Agent: codex_cli_rs" -H "originator: codex_cli_rs" -H "Accept: application/json" \
              "$CODEX_USAGE_URL" 2>/dev/null)
          else
            rm -f "$cx_tmp_auth"
            log "ERROR" "Codex token refresh produced invalid auth.json — left untouched"
          fi
        fi
      fi
    fi

    if [ "$cx_code" = "200" ]; then
      mv "$CODEX_CACHE.tmp" "$CODEX_CACHE"
      chmod 600 "$CODEX_CACHE" 2>/dev/null
      CODEX_USAGE=$(cat "$CODEX_CACHE")
      CODEX_STATUS="live"
      CODEX_OK=true
    else
      rm -f "$CODEX_CACHE.tmp"
      if [ -f "$CODEX_CACHE" ]; then
        CODEX_USAGE=$(cat "$CODEX_CACHE")
        CODEX_STATUS="stale (HTTP $cx_code)"
        CODEX_OK=true
      fi
      log "WARN" "Codex usage fetch failed (HTTP $cx_code)"
    fi
  fi

  if [ "$CODEX_OK" = true ]; then
    cx_5h_used=$(echo "$CODEX_USAGE" | $JQ -r '.rate_limit.primary_window.used_percent // empty')
    cx_5h_reset=$(echo "$CODEX_USAGE" | $JQ -r '.rate_limit.primary_window.reset_at // empty')
    cx_wk_used=$(echo "$CODEX_USAGE" | $JQ -r '.rate_limit.secondary_window.used_percent // empty')
    cx_wk_reset=$(echo "$CODEX_USAGE" | $JQ -r '.rate_limit.secondary_window.reset_at // empty')
    cx_plan=$(echo "$CODEX_USAGE" | $JQ -r '.plan_type // "codex"')
    cx_credits_has=$(echo "$CODEX_USAGE" | $JQ -r '.credits.has_credits // empty')
    cx_credits_bal=$(echo "$CODEX_USAGE" | $JQ -r '.credits.balance // empty')
    cx_credits_unlimited=$(echo "$CODEX_USAGE" | $JQ -r '.credits.unlimited // empty')
    if [ -z "$cx_5h_used" ]; then
      CODEX_OK=false  # unexpected shape
      log "WARN" "Codex usage JSON missing rate_limit fields"
    else
      # epoch reset_at -> ISO so render_section's time helpers work
      cx_5h_iso=$(date -u -r "${cx_5h_reset:-0}" "+%Y-%m-%dT%H:%M:%S+00:00" 2>/dev/null)
      cx_wk_iso=$(date -u -r "${cx_wk_reset:-0}" "+%Y-%m-%dT%H:%M:%S+00:00" 2>/dev/null)
    fi
  fi
fi

# ============================================================
# RENDER
# ============================================================
S=14  # base font size

# --- Claude menu-bar bits ---
if [ "$CLAUDE_OK" = true ]; then
  five_hr_left_int=${five_hr_left%.*}
  five_color=$(color_for_remaining "$five_hr_left")
  # Did the 5h window reset while we're stuck on stale (rate-limited) data?
  five_hr_stale_expired=false
  if echo "$FETCH_STATUS" | grep -q "stale" && [ -n "$five_hr_reset" ] && [ "$five_hr_reset" != "null" ]; then
    _fh_e=$(parse_reset_epoch "$five_hr_reset")
    [ -n "$_fh_e" ] && [ "$_fh_e" -lt "$(date +%s)" ] && five_hr_stale_expired=true
  fi
  five_hr_bar_label="${five_hr_left_int}%"
  [ "$five_hr_stale_expired" = true ] && five_hr_bar_label="~0%"
  [ "$HAS_SEVEN_DAY" = true ] && seven_color=$(color_for_remaining "$seven_day_left")
fi

# --- Codex menu-bar bits ---
if [ "$CODEX_OK" = true ]; then
  cx_5h_left=$(calc_remaining "${cx_5h_used:-0}"); cx_5h_left_int=${cx_5h_left%.*}
  cx_wk_left=$(calc_remaining "${cx_wk_used:-0}"); cx_wk_left_int=${cx_wk_left%.*}
fi

# --- Menu bar: one line per available provider; SwiftBar rotates them ---
bar_emitted=0
if [ "$CLAUDE_OK" = true ]; then
  ci=$(status_icon "$five_hr_left_int")
  if [ "$HAS_SEVEN_DAY" = true ]; then
    echo "${ci} CC ${five_hr_bar_label}·7d:${seven_day_left%.*}% | size=13"
  else
    echo "${ci} CC ${five_hr_bar_label}·7d:N/A | size=13"
  fi
  bar_emitted=1
fi
if [ "$CODEX_OK" = true ]; then
  cx_min=$cx_5h_left_int
  [ "$cx_wk_left_int" -lt "$cx_min" ] 2>/dev/null && cx_min=$cx_wk_left_int
  cxi=$(status_icon "$cx_min")
  echo "${cxi} CX 5h:${cx_5h_left_int}%·wk:${cx_wk_left_int}% | size=13"
  bar_emitted=1
fi
if [ "$bar_emitted" = 0 ]; then
  echo "CC: unavailable | size=13 color=#CC0000"
fi
echo "---"

# Section renderer
render_section() {
  local label="$1"
  local left="$2"
  local color="$3"
  local reset_ts="$4"
  local window_secs="$5"
  local utilization="$6"
  local available="$7"  # "true" or "false"

  # bash='true' on info lines forces macOS to render at full opacity (not vibrancy-faded)
  local NOP="bash='true' terminal=false"

  if [ "$available" = "false" ]; then
    echo "⚪  ${label} | size=$S $(c "$TEXT_MUTED") $NOP"
    echo "$L_NOT_AVAIL | size=$S $(c "$TEXT_MUTED") $NOP"
    return
  fi

  local icon=$(status_icon "$left")
  local bar=$(progress_bar "$left")
  local reset_str=$(format_reset "$reset_ts")
  local local_time=$(format_local_reset_time "$reset_ts")
  local bar_col=$(bar_color_for_remaining "$left")

  echo "${icon}  ${label} | size=$S $(c "$TEXT_PRIMARY") $NOP"
  echo "${bar} | size=$S font=Menlo color=${bar_col} $NOP"
  echo "$(fmt_remaining "$left") | size=$S color=$color $NOP"

  # Refill countdown + local reset time
  if [ -n "$reset_str" ] && [ -n "$local_time" ]; then
    echo "$(fmt_refills "$reset_str") (${local_time}) | size=$S $(c "$TEXT_SECONDARY") $NOP"
  elif [ -n "$reset_str" ]; then
    echo "$(fmt_refills "$reset_str") | size=$S $(c "$TEXT_SECONDARY") $NOP"
  elif [ -n "$reset_ts" ] && [ "$reset_ts" != "null" ]; then
    local _re=$(parse_reset_epoch "$reset_ts")
    local _now=$(date +%s)
    [ -n "$_re" ] && [ "$_re" -lt "$_now" ] && echo "Window reset — awaiting fresh data | size=$S $(c "$TEXT_MUTED") $NOP"
  fi

  # Pace indicator + burnout projection
  if [ -n "$window_secs" ] && [ -n "$utilization" ]; then
    local pace=$(calc_pace "$utilization" "$reset_ts" "$window_secs")
    if [ -n "$pace" ]; then
      local picon=$(pace_icon "$pace")
      echo "${picon} $(fmt_pace "$pace") | size=$S $(c "$TEXT_SECONDARY") $NOP"
    fi

    local burnout=$(format_burnout "$utilization" "$reset_ts" "$window_secs")
    if [ -n "$burnout" ]; then
      echo "$(fmt_burns "$burnout") | size=$S $(c "$TEXT_SECONDARY") $NOP"
    fi
  fi
}

# ----- Claude sections -----
if [ "$CLAUDE_OK" = true ]; then
  SUB_TYPE=$(echo "$CREDS" | $JQ -r '.claudeAiOauth.subscriptionType // "unknown"' 2>/dev/null)
  echo "Claude Code (${SUB_TYPE}) | size=$S $(c "$TEXT_PRIMARY") bash='true' terminal=false"
  echo "---"
  render_section "$L_SESSION_5H" "$five_hr_left" "$five_color" "$five_hr_reset" "18000" "$five_hr_used" "true"
  echo "---"
  if [ "$HAS_SEVEN_DAY" = true ]; then
    render_section "$L_WINDOW_7D" "$seven_day_left" "$seven_color" "$seven_day_reset" "604800" "$seven_day_used" "true"
  else
    render_section "$L_WINDOW_7D" "" "" "" "" "" "false"
  fi

  # Per-model sub-limits: only when actually used (a 0% scoped limit is just noise)
  if [ -n "$opus_used" ] && [ "$opus_used" != "null" ] && [ "${opus_used%.*}" -gt 0 ] 2>/dev/null; then
    echo "---"
    opus_left=$(calc_remaining "$opus_used")
    render_section "$L_WINDOW_7D_OPUS" "$opus_left" "$(color_for_remaining "$opus_left")" "$opus_reset" "604800" "$opus_used" "true"
  fi
  if [ -n "$sonnet_used" ] && [ "$sonnet_used" != "null" ] && [ "${sonnet_used%.*}" -gt 0 ] 2>/dev/null; then
    echo "---"
    sonnet_left=$(calc_remaining "$sonnet_used")
    render_section "$L_WINDOW_7D_SONNET" "$sonnet_left" "$(color_for_remaining "$sonnet_left")" "$sonnet_reset" "604800" "$sonnet_used" "true"
  fi

  # Extra Usage (pay-as-you-go) — spend vs limit when enabled, otherwise "off"
  if [ -n "$extra_limit_minor" ]; then
    echo "---"
    NOP="bash='true' terminal=false"
    if [ "$extra_enabled" = "true" ]; then
      extra_used_disp=$(awk -v m="${extra_used_minor:-0}" -v e="${extra_exponent:-2}" 'BEGIN { printf "%.2f", m/(10^e) }')
      extra_limit_disp=$(awk -v m="$extra_limit_minor" -v e="${extra_exponent:-2}" 'BEGIN { printf "%.2f", m/(10^e) }')
      echo "💳  ${L_EXTRA_USAGE}: ${extra_used_disp} / ${extra_limit_disp} ${extra_currency} | size=$S $(c "$TEXT_PRIMARY") $NOP"
    else
      echo "💳  ${L_EXTRA_USAGE}: ${L_EXTRA_OFF} | size=$S $(c "$TEXT_MUTED") $NOP"
    fi
  fi

  echo "---"
  echo "$L_SOURCE: ${FETCH_STATUS} | size=$S $(c "$TEXT_SECONDARY") bash='true' terminal=false"
fi

# ----- Codex sections -----
if [ "$CODEX_OK" = true ]; then
  [ "$CLAUDE_OK" = true ] && echo "---"  # separator only when a Claude section precedes
  echo "Codex (${cx_plan}) | size=$S $(c "$TEXT_PRIMARY") bash='true' terminal=false"
  echo "---"
  render_section "Codex 5h" "$cx_5h_left" "$(color_for_remaining "$cx_5h_left")" "$cx_5h_iso" "18000" "$cx_5h_used" "true"
  echo "---"
  render_section "Codex Weekly" "$cx_wk_left" "$(color_for_remaining "$cx_wk_left")" "$cx_wk_iso" "604800" "$cx_wk_used" "true"
  NOP="bash='true' terminal=false"
  if [ "$cx_credits_unlimited" = "true" ]; then
    echo "💳  Codex credits: unlimited | size=$S $(c "$TEXT_SECONDARY") $NOP"
  elif [ -n "$cx_credits_bal" ] && [ "$cx_credits_bal" != "null" ]; then
    echo "💳  Codex credits: ${cx_credits_bal} | size=$S $(c "$TEXT_SECONDARY") $NOP"
  fi
  echo "---"
  echo "$L_SOURCE: Codex ${CODEX_STATUS} | size=$S $(c "$TEXT_SECONDARY") bash='true' terminal=false"
fi
echo "---"
echo "$L_REFRESH | bash='$SCRIPT_DIR/force-refresh.sh' terminal=false refresh=true $(c "$TEXT_SECONDARY") size=$S"
echo "$L_OPEN_LOG | bash='open' param1='$LOG_FILE' terminal=false $(c "$TEXT_SECONDARY") size=$S"
echo "---"
# Refresh rate — flyout submenu
RD="$HOME/.cache/claude-usage/scripts"
rate_mark() { [ "$REFRESH_RATE" = "$1" ] && echo "✓ " || echo ""; }
echo "⏱ $L_REFRESH_RATE: ${REFRESH_RATE} | size=$S $(c "$TEXT_SECONDARY")"
echo "--$(rate_mark 2m)2m | bash='$RD/set-rate-2m.sh' terminal=false refresh=true size=$S"
echo "--$(rate_mark 5m)5m | bash='$RD/set-rate-5m.sh' terminal=false refresh=true size=$S"
echo "--$(rate_mark 10m)10m | bash='$RD/set-rate-10m.sh' terminal=false refresh=true size=$S"
# Language — flyout submenu
lang_mark() { [ "$LANGUAGE" = "$1" ] && echo "✓ " || echo ""; }
LD="$HOME/.cache/claude-usage/scripts"
echo "🌐 Language | size=$S $(c "$TEXT_SECONDARY")"
echo "--$(lang_mark en)English | bash='$LD/set-lang-en.sh' terminal=false refresh=true size=$S"
echo "--$(lang_mark zh)中文 | bash='$LD/set-lang-zh.sh' terminal=false refresh=true size=$S"
echo "--$(lang_mark ja)日本語 | bash='$LD/set-lang-ja.sh' terminal=false refresh=true size=$S"
echo "--$(lang_mark ko)한국어 | bash='$LD/set-lang-ko.sh' terminal=false refresh=true size=$S"
echo "--$(lang_mark ta)தமிழ் | bash='$LD/set-lang-ta.sh' terminal=false refresh=true size=$S"
echo "--$(lang_mark ms)Bahasa Melayu | bash='$LD/set-lang-ms.sh' terminal=false refresh=true size=$S"
# Reset reminders — flyout submenu
SD="$HOME/.cache/claude-usage/scripts"
remind_mark() { [ "$REMIND_BEFORE" = "$1" ] && echo "✓ " || echo ""; }
echo "$L_REMIND_RESET: ${REMIND_BEFORE:-$L_NTFY_OFF} | size=$S $(c "$TEXT_SECONDARY")"
echo "--$(remind_mark "60 30 10")60 · 30 · 10m | bash='$SD/set-remind-60-30-10.sh' terminal=false refresh=true size=$S"
echo "--$(remind_mark "30 10")30 · 10m | bash='$SD/set-remind-30-10.sh' terminal=false refresh=true size=$S"
echo "--$(remind_mark "60")60m | bash='$SD/set-remind-60.sh' terminal=false refresh=true size=$S"
echo "--$(remind_mark "")$L_NTFY_OFF | bash='$SD/set-remind-off.sh' terminal=false refresh=true size=$S"
# ntfy phone alerts — flyout submenu
if [ "$NTFY_ENABLED" = "true" ] && [ -n "$NTFY_TOPIC" ]; then
  echo "$L_PHONE_ALERTS ✓ | size=$S $(c "$TEXT_SECONDARY")"
else
  echo "$L_PHONE_ALERTS | size=$S $(c "$TEXT_SECONDARY")"
fi
echo "--$L_NTFY_SET_TOPIC | bash='$SD/set-ntfy-topic.sh' terminal=false refresh=true size=$S"
if [ -n "$NTFY_TOPIC" ]; then
  echo "--📋 $L_NTFY_COPY_TOPIC: $NTFY_TOPIC | bash='$SD/copy-ntfy-topic.sh' terminal=false size=$S"
  ntfy_on_mark() { [ "$NTFY_ENABLED" = "true" ] && echo "✓ " || echo ""; }
  ntfy_off_mark() { [ "$NTFY_ENABLED" != "true" ] && echo "✓ " || echo ""; }
  echo "--$(ntfy_on_mark)On | bash='$SD/ntfy-enable.sh' terminal=false refresh=true size=$S"
  echo "--$(ntfy_off_mark)Off | bash='$SD/ntfy-disable.sh' terminal=false refresh=true size=$S"
  echo "-----"
  status_mark() { [ "$NTFY_STATUS_INTERVAL" = "$1" ] && echo "✓ " || echo ""; }
  echo "--$L_STATUS_PUSH | size=$S $(c "$TEXT_MUTED")"
  echo "----$(status_mark 10)${L_NTFY_EVERY} 10m | bash='$SD/set-status-10.sh' terminal=false refresh=true size=$S"
  echo "----$(status_mark 30)${L_NTFY_EVERY} 30m | bash='$SD/set-status-30.sh' terminal=false refresh=true size=$S"
  echo "----$(status_mark 60)${L_NTFY_EVERY} 60m | bash='$SD/set-status-60.sh' terminal=false refresh=true size=$S"
  echo "----$(status_mark 120)${L_NTFY_EVERY} 2h | bash='$SD/set-status-120.sh' terminal=false refresh=true size=$S"
  echo "----$(status_mark 0)$L_NTFY_OFF | bash='$SD/set-status-off.sh' terminal=false refresh=true size=$S"
else
  echo "--$L_NTFY_NOT_SET | size=$S $(c "$TEXT_MUTED")"
fi

# ============================================================
# NOTIFICATIONS (run after render so UI updates immediately) — Claude only
# ============================================================
if [ "$CLAUDE_OK" = true ]; then
  check_and_notify "$L_SESSION_5H" "$five_hr_left" "5h"
  if [ "$HAS_SEVEN_DAY" = true ]; then
    check_and_notify "$L_WINDOW_7D" "$seven_day_left" "7d"
  fi

  # Reset reminders (desktop + phone if ntfy enabled)
  check_reset_reminder "$L_SESSION_5H" "$five_hr_reset" "5h" "$five_hr_left"
  if [ "$HAS_SEVEN_DAY" = true ]; then
    check_reset_reminder "$L_WINDOW_7D" "$seven_day_reset" "7d" "$seven_day_left"
  fi

  # Silent status push to phone (ntfy only, throttled)
  ntfy_status_push
fi
