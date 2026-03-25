# ============================================================
# Claude Code Usage Monitor - Windows System Tray  (v8.0)
# ============================================================
# A lightweight system tray app that shows Claude Code rate
# limits in real time. No dependencies beyond PowerShell 5.1+
# and .NET Framework (both ship with Windows 10/11).
#
# Features:
#   - Dual rotating icons (donut for 5h, bar for 7d)
#   - Pace calculation & burnout projection
#   - 6-language UI (en, zh, ja, ko, ta, ms)
#   - Toast notifications at 50%, 25%, 10% thresholds
#
# Usage: Double-click launch-monitor.bat
#        Or: powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File claude-code-monitor.ps1
# ============================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ============================================================
# CONFIG
# ============================================================
$script:CacheDir    = Join-Path $env:USERPROFILE ".cache\claude-usage"
$script:CacheFile   = Join-Path $script:CacheDir "usage.json"
$script:LogFile     = Join-Path $script:CacheDir "monitor.log"
$script:LangFile    = Join-Path $script:CacheDir "language"
$script:CacheTTL    = 120          # seconds
$script:PollInterval = 60          # seconds between data refresh
$script:IconRotateInterval = 4     # seconds between icon shape toggle
$script:NotifyThresholds = @(50, 25, 10)

# 5-hour = 18000s, 7-day = 604800s
$script:Window5h = 18000
$script:Window7d = 604800

if (-not (Test-Path $script:CacheDir)) {
    New-Item -ItemType Directory -Path $script:CacheDir -Force | Out-Null
}

# ============================================================
# LOGGING
# ============================================================
function Write-Log {
    param([string]$Level, [string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts [$Level] $Message"
    Add-Content -Path $script:LogFile -Value $line -ErrorAction SilentlyContinue

    # Trim log to 200 lines
    if (Test-Path $script:LogFile) {
        $lines = Get-Content $script:LogFile -ErrorAction SilentlyContinue
        if ($lines -and $lines.Count -gt 200) {
            $lines[-100..-1] | Set-Content $script:LogFile -ErrorAction SilentlyContinue
        }
    }
}

Write-Log "INFO" "Monitor started (v8.0)"

# ============================================================
# TRANSLATIONS
# ============================================================
function Get-Language {
    if (Test-Path $script:LangFile) {
        $lang = (Get-Content $script:LangFile -Raw -ErrorAction SilentlyContinue).Trim()
        if ($lang) { return $lang }
    }
    return "en"
}

function Set-Language {
    param([string]$Lang)
    $Lang | Set-Content $script:LangFile -Force
    $script:CurrentLang = $Lang
    $script:L = Get-Translations $Lang
    Write-Log "INFO" "Language changed to $Lang"
}

function Get-Translations {
    param([string]$Lang)
    switch ($Lang) {
        "zh" { return @{
            Session5h    = "5$([char]0x5C0F)$([char]0x65F6)$([char]0x4F1A)$([char]0x8BDD)"
            Window7d     = "7$([char]0x5929)$([char]0x7A97)$([char]0x53E3)"
            Window7dOpus = "7$([char]0x5929) Opus"
            Remaining    = "$([char]0x5269)$([char]0x4F59)"
            Refills      = "$([char]0x91CD)$([char]0x7F6E)$([char]0x4E8E)"
            Burns        = "$([char]0x9884)$([char]0x8BA1)$([char]0x8017)$([char]0x5C3D)"
            ResetsAt     = "$([char]0x91CD)$([char]0x7F6E)$([char]0x65F6)$([char]0x95F4)"
            Pace         = "$([char]0x901F)$([char]0x7387)"
            Source       = "$([char]0x6570)$([char]0x636E)$([char]0x6765)$([char]0x6E90)"
            Refresh      = "$([char]0x5237)$([char]0x65B0)"
            OpenLog      = "$([char]0x6253)$([char]0x5F00)$([char]0x65E5)$([char]0x5FD7)"
            Language     = "$([char]0x8BED)$([char]0x8A00)"
            Exit         = "$([char]0x9000)$([char]0x51FA)"
            NotifyTitle  = "Claude Code $([char]0x7528)$([char]0x91CF)$([char]0x8B66)$([char]0x544A)"
            NoData       = "$([char]0x6682)$([char]0x65E0)$([char]0x6570)$([char]0x636E)"
            FmtRemaining = "{0}% $([char]0x5269)$([char]0x4F59)"
            FmtRefills   = "$([char]0x91CD)$([char]0x7F6E)$([char]0x4E8E) {0}"
            FmtBurns     = "$([char]0x9884)$([char]0x8BA1)$([char]0x8017)$([char]0x5C3D) ~{0}"
            FmtPace      = "$([char]0x901F)$([char]0x7387): {0}x"
            FmtNotify    = "{0}: {1}% $([char]0x5269)$([char]0x4F59)"
        }}
        "ja" { return @{
            Session5h    = "5$([char]0x6642)$([char]0x9593)$([char]0x30BB)$([char]0x30C3)$([char]0x30B7)$([char]0x30E7)$([char]0x30F3)"
            Window7d     = "7$([char]0x65E5)$([char]0x9593)$([char]0x30A6)$([char]0x30A3)$([char]0x30F3)$([char]0x30C9)$([char]0x30A6)"
            Window7dOpus = "7$([char]0x65E5)$([char]0x9593) Opus"
            Remaining    = "$([char]0x6B8B)$([char]0x308A)"
            Refills      = "$([char]0x30EA)$([char]0x30BB)$([char]0x30C3)$([char]0x30C8)$([char]0x307E)$([char]0x3067)"
            Burns        = "$([char]0x6D88)$([char]0x8CBB)$([char]0x4E88)$([char]0x6E2C)"
            ResetsAt     = "$([char]0x30EA)$([char]0x30BB)$([char]0x30C3)$([char]0x30C8)$([char]0x6642)$([char]0x523B)"
            Pace         = "$([char]0x30DA)$([char]0x30FC)$([char]0x30B9)"
            Source       = "$([char]0x30BD)$([char]0x30FC)$([char]0x30B9)"
            Refresh      = "$([char]0x66F4)$([char]0x65B0)"
            OpenLog      = "$([char]0x30ED)$([char]0x30B0)$([char]0x3092)$([char]0x958B)$([char]0x304F)"
            Language     = "$([char]0x8A00)$([char]0x8A9E)"
            Exit         = "$([char]0x7D42)$([char]0x4E86)"
            NotifyTitle  = "Claude Code $([char]0x4F7F)$([char]0x7528)$([char]0x91CF)$([char]0x8B66)$([char]0x544A)"
            NoData       = "$([char]0x30C7)$([char]0x30FC)$([char]0x30BF)$([char]0x306A)$([char]0x3057)"
            FmtRemaining = "$([char]0x6B8B)$([char]0x308A) {0}%"
            FmtRefills   = "$([char]0x30EA)$([char]0x30BB)$([char]0x30C3)$([char]0x30C8)$([char]0x307E)$([char]0x3067) {0}"
            FmtBurns     = "$([char]0x6D88)$([char]0x8CBB)$([char]0x4E88)$([char]0x6E2C) ~{0}"
            FmtPace      = "$([char]0x30DA)$([char]0x30FC)$([char]0x30B9): {0}x"
            FmtNotify    = "{0}: $([char]0x6B8B)$([char]0x308A) {1}%"
        }}
        "ko" { return @{
            Session5h    = "5$([char]0xC2DC)$([char]0xAC04) $([char]0xC138)$([char]0xC158)"
            Window7d     = "7$([char]0xC77C) $([char]0xC708)$([char]0xB3C4)$([char]0xC6B0)"
            Window7dOpus = "7$([char]0xC77C) Opus"
            Remaining    = "$([char]0xB0A8)$([char]0xC74C)"
            Refills      = "$([char]0xB9AC)$([char]0xC14B)$([char]0xAE4C)$([char]0xC9C0)"
            Burns        = "$([char]0xC18C)$([char]0xC9C4) $([char]0xC608)$([char]0xC0C1)"
            ResetsAt     = "$([char]0xB9AC)$([char]0xC14B) $([char]0xC2DC)$([char]0xAC01)"
            Pace         = "$([char]0xC18D)$([char]0xB3C4)"
            Source       = "$([char]0xC18C)$([char]0xC2A4)"
            Refresh      = "$([char]0xC0C8)$([char]0xB85C)$([char]0xACE0)$([char]0xCE68)"
            OpenLog      = "$([char]0xB85C)$([char]0xADF8) $([char]0xC5F4)$([char]0xAE30)"
            Language     = "$([char]0xC5B8)$([char]0xC5B4)"
            Exit         = "$([char]0xC885)$([char]0xB8CC)"
            NotifyTitle  = "Claude Code $([char]0xC0AC)$([char]0xC6A9)$([char]0xB7C9) $([char]0xACBD)$([char]0xACE0)"
            NoData       = "$([char]0xB370)$([char]0xC774)$([char]0xD130) $([char]0xC5C6)$([char]0xC74C)"
            FmtRemaining = "{0}% $([char]0xB0A8)$([char]0xC74C)"
            FmtRefills   = "$([char]0xB9AC)$([char]0xC14B)$([char]0xAE4C)$([char]0xC9C0) {0}"
            FmtBurns     = "$([char]0xC18C)$([char]0xC9C4) $([char]0xC608)$([char]0xC0C1) ~{0}"
            FmtPace      = "$([char]0xC18D)$([char]0xB3C4): {0}x"
            FmtNotify    = "{0}: {1}% $([char]0xB0A8)$([char]0xC74C)"
        }}
        "ta" { return @{
            Session5h    = "5-$([char]0x0BAE)$([char]0x0BA3)$([char]0x0BBF) $([char]0x0B85)$([char]0x0BAE)$([char]0x0BB0)$([char]0x0BCD)$([char]0x0BB5)$([char]0x0BC1)"
            Window7d     = "7-$([char]0x0BA8)$([char]0x0BBE)$([char]0x0BB3)$([char]0x0BCD) $([char]0x0B9A)$([char]0x0BBE)$([char]0x0BB3)$([char]0x0BB0)$([char]0x0BAE)$([char]0x0BCD)"
            Window7dOpus = "7-$([char]0x0BA8)$([char]0x0BBE)$([char]0x0BB3)$([char]0x0BCD) Opus"
            Remaining    = "$([char]0x0BAE)$([char]0x0BC0)$([char]0x0BA4)$([char]0x0BAE)$([char]0x0BCD)"
            Refills      = "$([char]0x0BAE)$([char]0x0BC0)$([char]0x0B9F)$([char]0x0BCD)$([char]0x0B9F)$([char]0x0BAE)$([char]0x0BC8)$([char]0x0BAA)$([char]0x0BCD)$([char]0x0BAA)$([char]0x0BC1)"
            Burns        = "$([char]0x0BA4)$([char]0x0BC0)$([char]0x0BB0)$([char]0x0BCD)$([char]0x0BA8)$([char]0x0BCD)$([char]0x0BA4)$([char]0x0BC1)$([char]0x0BB5)$([char]0x0BBF)$([char]0x0B9F)$([char]0x0BC1)$([char]0x0BAE)$([char]0x0BCD)"
            ResetsAt     = "$([char]0x0BAE)$([char]0x0BC0)$([char]0x0B9F)$([char]0x0BCD)$([char]0x0B9F)$([char]0x0BAE)$([char]0x0BC8)$([char]0x0BAA)$([char]0x0BCD)$([char]0x0BAA)$([char]0x0BC1) $([char]0x0BA8)$([char]0x0BC7)$([char]0x0BB0)$([char]0x0BAE)$([char]0x0BCD)"
            Pace         = "$([char]0x0BB5)$([char]0x0BC7)$([char]0x0B95)$([char]0x0BAE)$([char]0x0BCD)"
            Source       = "$([char]0x0BAE)$([char]0x0BC2)$([char]0x0BB2)$([char]0x0BAE)$([char]0x0BCD)"
            Refresh      = "$([char]0x0BAA)$([char]0x0BC1)$([char]0x0BA4)$([char]0x0BC1)$([char]0x0BAA)$([char]0x0BCD)$([char]0x0BAA)$([char]0x0BBF)"
            OpenLog      = "$([char]0x0BAA)$([char]0x0BA4)$([char]0x0BBF)$([char]0x0BB5)$([char]0x0BC8)$([char]0x0BA4)$([char]0x0BCD) $([char]0x0BA4)$([char]0x0BBF)$([char]0x0BB1)"
            Language     = "$([char]0x0BAE)$([char]0x0BCA)$([char]0x0BB4)$([char]0x0BBF)"
            Exit         = "$([char]0x0BB5)$([char]0x0BC6)$([char]0x0BB3)$([char]0x0BBF)$([char]0x0BAF)$([char]0x0BC7)$([char]0x0BB1)$([char]0x0BC1)"
            NotifyTitle  = "Claude Code $([char]0x0B8E)$([char]0x0B9A)$([char]0x0BCD)$([char]0x0B9A)$([char]0x0BB0)$([char]0x0BBF)$([char]0x0B95)$([char]0x0BCD)$([char]0x0B95)$([char]0x0BC8)"
            NoData       = "$([char]0x0BA4)$([char]0x0BB0)$([char]0x0BB5)$([char]0x0BC1) $([char]0x0B87)$([char]0x0BB2)$([char]0x0BCD)$([char]0x0BB2)$([char]0x0BC8)"
            FmtRemaining = "{0}% $([char]0x0BAE)$([char]0x0BC0)$([char]0x0BA4)$([char]0x0BAE)$([char]0x0BCD)"
            FmtRefills   = "$([char]0x0BAE)$([char]0x0BC0)$([char]0x0B9F)$([char]0x0BCD)$([char]0x0B9F)$([char]0x0BAE)$([char]0x0BC8)$([char]0x0BAA)$([char]0x0BCD)$([char]0x0BAA)$([char]0x0BC1) {0}"
            FmtBurns     = "$([char]0x0BA4)$([char]0x0BC0)$([char]0x0BB0)$([char]0x0BCD)$([char]0x0BA8)$([char]0x0BCD)$([char]0x0BA4)$([char]0x0BC1)$([char]0x0BB5)$([char]0x0BBF)$([char]0x0B9F)$([char]0x0BC1)$([char]0x0BAE)$([char]0x0BCD) ~{0}"
            FmtPace      = "$([char]0x0BB5)$([char]0x0BC7)$([char]0x0B95)$([char]0x0BAE)$([char]0x0BCD): {0}x"
            FmtNotify    = "{0}: {1}% $([char]0x0BAE)$([char]0x0BC0)$([char]0x0BA4)$([char]0x0BAE)$([char]0x0BCD)"
        }}
        "ms" { return @{
            Session5h    = "Sesi 5-Jam"
            Window7d     = "Tetingkap 7-Hari"
            Window7dOpus = "7-Hari Opus"
            Remaining    = "baki"
            Refills      = "Ditetapkan dalam"
            Burns        = "Habis dalam"
            ResetsAt     = "Masa tetapan"
            Pace         = "Kadar"
            Source       = "Sumber"
            Refresh      = "Muat semula"
            OpenLog      = "Buka log"
            Language     = "Bahasa"
            Exit         = "Keluar"
            NotifyTitle  = "Amaran Penggunaan Claude Code"
            NoData       = "Belum tersedia"
            FmtRemaining = "{0}% baki"
            FmtRefills   = "Ditetapkan dalam {0}"
            FmtBurns     = "Habis dalam ~{0}"
            FmtPace      = "Kadar: {0}x"
            FmtNotify    = "{0}: {1}% baki"
        }}
        default { return @{
            Session5h    = "5-Hour Session"
            Window7d     = "7-Day Window"
            Window7dOpus = "7-Day Opus"
            Remaining    = "remaining"
            Refills      = "Refills in"
            Burns        = "Burns out in"
            ResetsAt     = "Resets at"
            Pace         = "Pace"
            Source       = "Source"
            Refresh      = "Refresh Now"
            OpenLog      = "Open Log"
            Language     = "Language"
            Exit         = "Exit"
            NotifyTitle  = "Claude Code Usage Warning"
            NoData       = "No data"
            FmtRemaining = "{0}% remaining"
            FmtRefills   = "Refills in {0}"
            FmtBurns     = "Burns out in ~{0}"
            FmtPace      = "Pace: {0}x"
            FmtNotify    = "{0}: {1}% remaining"
        }}
    }
}

$script:CurrentLang = Get-Language
$script:L = Get-Translations $script:CurrentLang

# ============================================================
# AUTH
# ============================================================
function Get-OAuthToken {
    $credFile = Join-Path $env:USERPROFILE ".claude\.credentials.json"
    if (-not (Test-Path $credFile)) {
        Write-Log "ERROR" "Credentials file not found: $credFile"
        return $null
    }
    try {
        $creds = Get-Content $credFile -Raw | ConvertFrom-Json
        $token = $creds.claudeAiOauth.accessToken
        if ([string]::IsNullOrEmpty($token)) {
            Write-Log "ERROR" "accessToken is empty"
            return $null
        }
        $script:SubscriptionType = $creds.claudeAiOauth.subscriptionType
        return $token
    } catch {
        Write-Log "ERROR" "Failed to parse credentials: $_"
        return $null
    }
}

# ============================================================
# FETCH USAGE (WITH CACHE)
# ============================================================
function Get-Usage {
    # Check cache freshness
    if (Test-Path $script:CacheFile) {
        $cacheAge = ((Get-Date) - (Get-Item $script:CacheFile).LastWriteTime).TotalSeconds
        if ($cacheAge -lt $script:CacheTTL) {
            Write-Log "INFO" "Using cache (age: $([int]$cacheAge)s)"
            $script:FetchStatus = "cached ($([int]$cacheAge)s ago)"
            return (Get-Content $script:CacheFile -Raw | ConvertFrom-Json)
        }
    }

    $token = Get-OAuthToken
    if (-not $token) {
        $script:FetchStatus = "no auth"
        return $null
    }

    try {
        $headers = @{
            "Accept"           = "application/json"
            "Content-Type"     = "application/json"
            "Authorization"    = "Bearer $token"
            "anthropic-beta"   = "oauth-2025-04-20"
        }
        $response = Invoke-WebRequest -Uri "https://api.anthropic.com/api/oauth/usage" `
            -Headers $headers -Method Get -TimeoutSec 10 -UseBasicParsing

        if ($response.StatusCode -eq 200) {
            $response.Content | Set-Content $script:CacheFile -Force
            $script:FetchStatus = "live"
            Write-Log "INFO" "API call success"
            return ($response.Content | ConvertFrom-Json)
        }
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }

        if ($statusCode -eq 429) {
            Write-Log "WARN" "Rate limited (429) - using stale cache"
            $script:FetchStatus = "rate limited - stale data"
        } else {
            Write-Log "ERROR" "API error (HTTP $statusCode): $_"
            $script:FetchStatus = "error (HTTP $statusCode) - stale data"
        }

        # Fall back to stale cache
        if (Test-Path $script:CacheFile) {
            return (Get-Content $script:CacheFile -Raw | ConvertFrom-Json)
        }
        return $null
    }
}

# ============================================================
# ICON RENDERING
# ============================================================
# We need to properly destroy old icons to avoid GDI handle leaks.
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class IconHelper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(IntPtr hIcon);
}
"@ -ErrorAction SilentlyContinue

$script:CurrentIconHandle = [IntPtr]::Zero

function Get-TierColor {
    param([string]$Tier)
    switch ($Tier) {
        "green"  { return [System.Drawing.Color]::FromArgb(46, 204, 113) }
        "orange" { return [System.Drawing.Color]::FromArgb(230, 126, 34) }
        "red"    { return [System.Drawing.Color]::FromArgb(231, 76, 60) }
        default  { return [System.Drawing.Color]::Gray }
    }
}

# Donut ring icon -- arc length reflects remaining % (for 5-hour session)
function New-DonutIcon {
    param([int]$Percent, [string]$ColorTier)

    $bmp = New-Object System.Drawing.Bitmap(16, 16)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $color = Get-TierColor $ColorTier

    # Background track (dim ring)
    $bgPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60, 60, 60), 2)
    $g.DrawEllipse($bgPen, 2, 2, 12, 12)
    $bgPen.Dispose()

    # Foreground arc -- starts at top (-90 deg), sweeps clockwise by percent
    if ($Percent -gt 0) {
        $sweepAngle = [int](360 * $Percent / 100)
        $pen = New-Object System.Drawing.Pen($color, 2)
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $g.DrawArc($pen, 2, 2, 12, 12, -90, $sweepAngle)
        $pen.Dispose()
    }

    $g.Dispose()
    return $bmp
}

# Horizontal bar icon -- filled bar for 7-day window
function New-BarIcon {
    param([int]$Percent, [string]$ColorTier)

    $bmp = New-Object System.Drawing.Bitmap(16, 16)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $color = Get-TierColor $ColorTier

    # Background track (dim bar)
    $bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(60, 60, 60))
    $g.FillRectangle($bgBrush, 1, 5, 14, 6)
    $bgBrush.Dispose()

    # Foreground fill -- left to right by percent
    if ($Percent -gt 0) {
        $fillWidth = [Math]::Max(1, [int](14 * $Percent / 100))
        $brush = New-Object System.Drawing.SolidBrush($color)
        $g.FillRectangle($brush, 1, 5, $fillWidth, 6)
        $brush.Dispose()
    }

    # Border
    $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(100, 100, 100), 1)
    $g.DrawRectangle($borderPen, 1, 5, 14, 6)
    $borderPen.Dispose()

    $g.Dispose()
    return $bmp
}

function Set-TrayIconFromBitmap {
    param([System.Drawing.Bitmap]$Bmp)

    # Destroy the previous icon handle to prevent GDI leak
    if ($script:CurrentIconHandle -ne [IntPtr]::Zero) {
        [IconHelper]::DestroyIcon($script:CurrentIconHandle) | Out-Null
        $script:CurrentIconHandle = [IntPtr]::Zero
    }

    $hIcon = $Bmp.GetHicon()
    $script:CurrentIconHandle = $hIcon
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)
    $script:NotifyIcon.Icon = $icon
    $Bmp.Dispose()
}

# ============================================================
# HELPERS
# ============================================================
function Get-ColorTier {
    param([double]$Remaining)
    if ($Remaining -le 20) { return "red" }
    elseif ($Remaining -le 50) { return "orange" }
    else { return "green" }
}

function ConvertTo-Emoji {
    param([int]$CodePoint)
    # Handle supplementary Unicode (above U+FFFF) via surrogate pairs
    if ($CodePoint -gt 0xFFFF) {
        $hi = [char](0xD800 + (($CodePoint - 0x10000) -shr 10))
        $lo = [char](0xDC00 + (($CodePoint - 0x10000) -band 0x3FF))
        return "$hi$lo"
    }
    return [string][char]$CodePoint
}

function Get-StatusEmoji {
    param([string]$Tier)
    switch ($Tier) {
        "green"  { return ConvertTo-Emoji 0x1F7E2 }
        "orange" { return ConvertTo-Emoji 0x1F7E1 }
        "red"    { return ConvertTo-Emoji 0x1F534 }
    }
}

function Format-Duration {
    param([int]$TotalSeconds)
    if ($TotalSeconds -le 0) { return "" }
    $days  = [Math]::Floor($TotalSeconds / 86400)
    $hours = [Math]::Floor(($TotalSeconds % 86400) / 3600)
    $mins  = [Math]::Floor(($TotalSeconds % 3600) / 60)
    if ($days -gt 0) { return "${days}d ${hours}h" }
    elseif ($hours -gt 0) { return "${hours}h ${mins}m" }
    else { return "${mins}m" }
}

function Format-ResetCountdown {
    param([string]$ResetTs)
    if ([string]::IsNullOrEmpty($ResetTs) -or $ResetTs -eq "null") { return "" }
    try {
        $resetTime = [DateTimeOffset]::Parse($ResetTs).UtcDateTime
        $diff = $resetTime - [DateTime]::UtcNow
        if ($diff.TotalSeconds -le 0) { return "" }
        return Format-Duration ([int]$diff.TotalSeconds)
    } catch { return "" }
}

function Format-LocalResetTime {
    param([string]$ResetTs)
    if ([string]::IsNullOrEmpty($ResetTs) -or $ResetTs -eq "null") { return "" }
    try {
        $resetTime = [DateTimeOffset]::Parse($ResetTs).LocalDateTime
        $diff = $resetTime - [DateTime]::Now
        if ($diff.TotalSeconds -le 0) { return "" }
        $today = [DateTime]::Today
        if ($resetTime.Date -eq $today) {
            return $resetTime.ToString("h:mm tt")
        } else {
            return $resetTime.ToString("MMM d h:mm tt")
        }
    } catch { return "" }
}

function Format-ProgressBar {
    param([int]$Percent)
    $width = 20
    $filled = [Math]::Floor($Percent * $width / 100)
    $empty = $width - $filled
    return ("$([char]0x25A0)" * $filled) + ("$([char]0x25A1)" * $empty)
}

# ============================================================
# PACE & BURNOUT
# ============================================================
function Get-Pace {
    param([double]$Utilization, [string]$ResetTs, [int]$WindowSeconds)
    if ($Utilization -le 0) { return $null }
    if ([string]::IsNullOrEmpty($ResetTs) -or $ResetTs -eq "null") { return $null }
    try {
        $resetTime = [DateTimeOffset]::Parse($ResetTs).UtcDateTime
        $secsUntilReset = ($resetTime - [DateTime]::UtcNow).TotalSeconds
        if ($secsUntilReset -le 0) { return $null }
        $elapsed = $WindowSeconds - $secsUntilReset
        if ($elapsed -le 0) { return $null }
        $pace = ($Utilization * $WindowSeconds) / (100 * $elapsed)
        return [Math]::Round($pace, 1)
    } catch { return $null }
}

function Get-PaceIcon {
    param([double]$Pace)
    if ($Pace -ge 2.0) { return ConvertTo-Emoji 0x1F525 }      # fire
    elseif ($Pace -ge 1.3) { return ConvertTo-Emoji 0x26A1 }   # lightning
    elseif ($Pace -ge 0.8) { return ConvertTo-Emoji 0x2705 }   # check
    else { return ConvertTo-Emoji 0x1F422 }                     # turtle
}

function Get-Burnout {
    param([double]$Utilization, [string]$ResetTs, [int]$WindowSeconds)
    if ($Utilization -le 0) { return "" }
    if ([string]::IsNullOrEmpty($ResetTs) -or $ResetTs -eq "null") { return "" }
    try {
        $resetTime = [DateTimeOffset]::Parse($ResetTs).UtcDateTime
        $secsUntilReset = ($resetTime - [DateTime]::UtcNow).TotalSeconds
        if ($secsUntilReset -le 0) { return "" }
        $elapsed = $WindowSeconds - $secsUntilReset
        if ($elapsed -le 0) { return "" }
        $remaining = 100 - $Utilization
        if ($remaining -le 0) { return "now" }
        $secsToBurnout = [int]($remaining * $elapsed / $Utilization)
        return Format-Duration $secsToBurnout
    } catch { return "" }
}

# ============================================================
# NOTIFICATIONS
# ============================================================
function Send-ThresholdNotification {
    param([string]$Label, [double]$Remaining, [string]$Key)
    $remainingInt = [int]$Remaining
    $stateFile = Join-Path $script:CacheDir "notify_state_$Key"

    $lastThreshold = 100
    if (Test-Path $stateFile) {
        $lastThreshold = [int](Get-Content $stateFile -Raw -ErrorAction SilentlyContinue)
        # Reset if usage has recovered (window reset)
        if ($remainingInt -gt $lastThreshold) {
            $lastThreshold = 100
            "100" | Set-Content $stateFile -Force
        }
    }

    foreach ($threshold in $script:NotifyThresholds) {
        if ($remainingInt -le $threshold -and $lastThreshold -gt $threshold) {
            $msg = $script:L.FmtNotify -f $Label, $remainingInt
            $script:NotifyIcon.BalloonTipTitle = $script:L.NotifyTitle
            $script:NotifyIcon.BalloonTipText = $msg
            $script:NotifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning
            $script:NotifyIcon.ShowBalloonTip(5000)
            "$threshold" | Set-Content $stateFile -Force
            Write-Log "INFO" "Notification sent: $Label at ${remainingInt}% (threshold: ${threshold}%)"
            return
        }
    }
}

# ============================================================
# DISPLAY UPDATE
# ============================================================
# Store parsed data for icon rotation
$script:DisplayData = $null
$script:ShowingDonut = $true  # Toggle between donut (5h) and bar (7d)

function Update-Display {
    try {
        $usage = Get-Usage
        if (-not $usage) {
            $script:NotifyIcon.Text = "Claude Code: $($script:L.NoData)"
            $script:DisplayData = $null
            $bmp = New-DonutIcon -Percent 0 -ColorTier "red"
            Set-TrayIconFromBitmap $bmp
            Update-ContextMenu $null
            return
        }

        # Parse usage data
        $fiveHrUsed   = [double]($usage.five_hour.utilization)
        $fiveHrReset  = $usage.five_hour.resets_at
        $sevenDayUsed = [double]($usage.seven_day.utilization)
        $sevenDayReset = $usage.seven_day.resets_at

        $fiveHrLeft   = [Math]::Round(100 - $fiveHrUsed, 1)
        $sevenDayLeft = [Math]::Round(100 - $sevenDayUsed, 1)

        $fiveColor = Get-ColorTier $fiveHrLeft
        $sevenColor = Get-ColorTier $sevenDayLeft

        # Pace & burnout
        $fivePace = Get-Pace $fiveHrUsed $fiveHrReset $script:Window5h
        $fiveBurnout = Get-Burnout $fiveHrUsed $fiveHrReset $script:Window5h
        $sevenPace = Get-Pace $sevenDayUsed $sevenDayReset $script:Window7d
        $sevenBurnout = Get-Burnout $sevenDayUsed $sevenDayReset $script:Window7d

        # Opus (optional)
        $opusLeft = $null
        $opusReset = $null
        $opusColor = $null
        $opusPace = $null
        $opusBurnout = ""
        if ($usage.seven_day_opus -and $usage.seven_day_opus.utilization) {
            $opusUsed = [double]($usage.seven_day_opus.utilization)
            $opusLeft = [Math]::Round(100 - $opusUsed, 1)
            $opusReset = $usage.seven_day_opus.resets_at
            $opusColor = Get-ColorTier $opusLeft
            $opusPace = Get-Pace $opusUsed $opusReset $script:Window7d
            $opusBurnout = Get-Burnout $opusUsed $opusReset $script:Window7d
        }

        # Store data for icon rotation
        $script:DisplayData = @{
            FiveHrLeft    = $fiveHrLeft
            FiveHrUsed    = $fiveHrUsed
            FiveColor     = $fiveColor
            FiveReset     = $fiveHrReset
            FivePace      = $fivePace
            FiveBurnout   = $fiveBurnout
            SevenDayLeft  = $sevenDayLeft
            SevenDayUsed  = $sevenDayUsed
            SevenColor    = $sevenColor
            SevenReset    = $sevenDayReset
            SevenPace     = $sevenPace
            SevenBurnout  = $sevenBurnout
            OpusLeft      = $opusLeft
            OpusUsed      = if ($opusLeft -ne $null) { $opusUsed } else { $null }
            OpusColor     = $opusColor
            OpusReset     = $opusReset
            OpusPace      = $opusPace
            OpusBurnout   = $opusBurnout
        }

        # Set initial icon
        Update-RotatingIcon

        # Tooltip (max 63 chars)
        $tooltip = "5h: $([int]$fiveHrLeft)% | 7d: $([int]$sevenDayLeft)%"
        if ($opusLeft -ne $null) { $tooltip += " | Opus: $([int]$opusLeft)%" }
        $script:NotifyIcon.Text = $tooltip

        Write-Log "INFO" "5h: ${fiveHrLeft}% | 7d: ${sevenDayLeft}% | src: $($script:FetchStatus)"

        # Update context menu
        Update-ContextMenu $script:DisplayData

        # Notifications
        Send-ThresholdNotification $script:L.Session5h $fiveHrLeft "5h"
        Send-ThresholdNotification $script:L.Window7d $sevenDayLeft "7d"
    } catch {
        Write-Log "ERROR" "Update-Display failed: $_"
    }
}

# Toggle between donut and bar icon every few seconds
function Update-RotatingIcon {
    if (-not $script:DisplayData) { return }

    if ($script:ShowingDonut) {
        # Donut for 5-hour session
        $bmp = New-DonutIcon -Percent ([int]$script:DisplayData.FiveHrLeft) -ColorTier $script:DisplayData.FiveColor
    } else {
        # Bar for 7-day window
        $bmp = New-BarIcon -Percent ([int]$script:DisplayData.SevenDayLeft) -ColorTier $script:DisplayData.SevenColor
    }

    Set-TrayIconFromBitmap $bmp

    # Update tooltip with current shape context
    $fullTip = "5h: $([int]$script:DisplayData.FiveHrLeft)% | 7d: $([int]$script:DisplayData.SevenDayLeft)%"
    if ($script:DisplayData.OpusLeft -ne $null) {
        $fullTip += " | Opus: $([int]$script:DisplayData.OpusLeft)%"
    }
    $script:NotifyIcon.Text = $fullTip

    $script:ShowingDonut = -not $script:ShowingDonut
}

# ============================================================
# CONTEXT MENU (right-click details)
# ============================================================
# Pre-create reusable fonts to avoid GDI leaks
$script:FontBold    = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$script:FontMono    = New-Object System.Drawing.Font("Consolas", 9)

function Add-SectionToMenu {
    param(
        $Menu, [string]$Label, [double]$Left, [string]$ColorTier,
        [string]$ResetTs, $Pace, [string]$Burnout, [int]$WindowSecs, [string]$ShapeTag
    )

    $emoji = Get-StatusEmoji $ColorTier
    $headerText = "$emoji  $Label"
    if ($ShapeTag) { $headerText += "  $ShapeTag" }
    $Menu.Items.Add($headerText).Enabled = $false

    $bar = Format-ProgressBar ([int]$Left)
    $barItem = $Menu.Items.Add("  $bar")
    $barItem.Enabled = $false
    $barItem.Font = $script:FontMono

    $remainText = $script:L.FmtRemaining -f [int]$Left
    $Menu.Items.Add("  $remainText").Enabled = $false

    # Refill countdown + local time
    $resetStr = Format-ResetCountdown $ResetTs
    $localTime = Format-LocalResetTime $ResetTs
    if ($resetStr) {
        $refillText = $script:L.FmtRefills -f $resetStr
        if ($localTime) { $refillText += " ($localTime)" }
        $Menu.Items.Add("  $refillText").Enabled = $false
    }

    # Pace
    if ($Pace -ne $null) {
        $paceIcon = Get-PaceIcon $Pace
        $paceText = $script:L.FmtPace -f $Pace
        $Menu.Items.Add("  $paceIcon $paceText").Enabled = $false
    }

    # Burnout
    if ($Burnout) {
        $burnText = $script:L.FmtBurns -f $Burnout
        $Menu.Items.Add("  $burnText").Enabled = $false
    }
}

function Update-ContextMenu {
    param($Data)

    # Dispose old menu before creating new one
    if ($script:NotifyIcon.ContextMenuStrip) {
        $script:NotifyIcon.ContextMenuStrip.Dispose()
    }

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.RenderMode = [System.Windows.Forms.ToolStripRenderMode]::System

    $subType = if ($script:SubscriptionType) { $script:SubscriptionType } else { "unknown" }
    $header = $menu.Items.Add("Claude Code ($subType)")
    $header.Enabled = $false
    $header.Font = $script:FontBold
    $menu.Items.Add("-") | Out-Null

    if ($Data) {
        # 5-Hour Session (donut shape)
        Add-SectionToMenu $menu $script:L.Session5h $Data.FiveHrLeft $Data.FiveColor `
            $Data.FiveReset $Data.FivePace $Data.FiveBurnout $script:Window5h "[donut]"

        $menu.Items.Add("-") | Out-Null

        # 7-Day Window (bar shape)
        Add-SectionToMenu $menu $script:L.Window7d $Data.SevenDayLeft $Data.SevenColor `
            $Data.SevenReset $Data.SevenPace $Data.SevenBurnout $script:Window7d "[bar]"

        # Opus (if available)
        if ($Data.OpusLeft -ne $null) {
            $menu.Items.Add("-") | Out-Null
            Add-SectionToMenu $menu $script:L.Window7dOpus $Data.OpusLeft $Data.OpusColor `
                $Data.OpusReset $Data.OpusPace $Data.OpusBurnout $script:Window7d ""
        }

        $menu.Items.Add("-") | Out-Null
        $srcItem = $menu.Items.Add("$($script:L.Source): $($script:FetchStatus)")
        $srcItem.Enabled = $false
    } else {
        $menu.Items.Add($script:L.NoData).Enabled = $false
    }

    $menu.Items.Add("-") | Out-Null

    # Refresh button
    $refreshItem = $menu.Items.Add($script:L.Refresh)
    $refreshItem.Add_Click({
        $script:CacheTTL = 0
        Update-Display
        $script:CacheTTL = 120
    })

    # Open log
    $logItem = $menu.Items.Add($script:L.OpenLog)
    $logItem.Add_Click({
        if (Test-Path $script:LogFile) {
            Start-Process notepad.exe $script:LogFile
        }
    })

    $menu.Items.Add("-") | Out-Null

    # Language submenu
    $globeEmoji = ConvertTo-Emoji 0x1F310
    $langMenu = New-Object System.Windows.Forms.ToolStripMenuItem("$globeEmoji $($script:L.Language)")
    $langs = @(
        @{ Code = "en"; Label = "English" },
        @{ Code = "zh"; Label = "$([char]0x4E2D)$([char]0x6587)" },
        @{ Code = "ja"; Label = "$([char]0x65E5)$([char]0x672C)$([char]0x8A9E)" },
        @{ Code = "ko"; Label = "$([char]0xD55C)$([char]0xAD6D)$([char]0xC5B4)" },
        @{ Code = "ta"; Label = "$([char]0x0BA4)$([char]0x0BAE)$([char]0x0BBF)$([char]0x0BB4)$([char]0x0BCD)" },
        @{ Code = "ms"; Label = "Bahasa Melayu" }
    )
    foreach ($langInfo in $langs) {
        $code = $langInfo.Code
        $label = $langInfo.Label
        $check = if ($script:CurrentLang -eq $code) { "$([char]0x2713) " } else { "" }
        $item = $langMenu.DropDownItems.Add("${check}${label}")
        # Capture $code in closure via Tag
        $item.Tag = $code
        $item.Add_Click({
            $clickedCode = $this.Tag
            Set-Language $clickedCode
            Update-Display
        })
    }
    $menu.Items.Add($langMenu) | Out-Null

    # Settings submenu (rotation speed, refresh interval)
    $settingsMenu = New-Object System.Windows.Forms.ToolStripMenuItem("$([char]0x2699) Settings")

    # Rotation speed options
    $rotLabel = $settingsMenu.DropDownItems.Add("Icon Rotation Speed")
    $rotLabel.Enabled = $false
    $speeds = @(
        @{ Label = "Fast (2s)"; Secs = 2 },
        @{ Label = "Normal (4s)"; Secs = 4 },
        @{ Label = "Slow (8s)"; Secs = 8 },
        @{ Label = "Very Slow (15s)"; Secs = 15 }
    )
    foreach ($spd in $speeds) {
        $secs = $spd.Secs
        $label = $spd.Label
        $check = if ($script:IconRotateInterval -eq $secs) { "$([char]0x2713) " } else { "" }
        $sItem = $settingsMenu.DropDownItems.Add("${check}${label}")
        $sItem.Tag = $secs
        $sItem.Add_Click({
            $newInterval = [int]$this.Tag
            $script:IconRotateInterval = $newInterval
            $script:IconTimer.Interval = $newInterval * 1000
            Write-Log "INFO" "Icon rotation speed changed to ${newInterval}s"
            Update-ContextMenu $script:DisplayData
        })
    }

    $settingsMenu.DropDownItems.Add("-") | Out-Null

    # Refresh interval options
    $refLabel = $settingsMenu.DropDownItems.Add("Data Refresh Interval")
    $refLabel.Enabled = $false
    $intervals = @(
        @{ Label = "30 seconds"; Secs = 30 },
        @{ Label = "1 minute"; Secs = 60 },
        @{ Label = "2 minutes"; Secs = 120 },
        @{ Label = "5 minutes"; Secs = 300 }
    )
    foreach ($intv in $intervals) {
        $secs = $intv.Secs
        $label = $intv.Label
        $check = if ($script:PollInterval -eq $secs) { "$([char]0x2713) " } else { "" }
        $iItem = $settingsMenu.DropDownItems.Add("${check}${label}")
        $iItem.Tag = $secs
        $iItem.Add_Click({
            $newInterval = [int]$this.Tag
            $script:PollInterval = $newInterval
            $script:DataTimer.Interval = $newInterval * 1000
            Write-Log "INFO" "Data refresh interval changed to ${newInterval}s"
            Update-ContextMenu $script:DisplayData
        })
    }

    $menu.Items.Add($settingsMenu) | Out-Null

    $menu.Items.Add("-") | Out-Null

    # Exit
    $exitItem = $menu.Items.Add($script:L.Exit)
    $exitItem.Add_Click({
        $script:DataTimer.Stop()
        $script:DataTimer.Dispose()
        $script:IconTimer.Stop()
        $script:IconTimer.Dispose()
        $script:NotifyIcon.Visible = $false
        $script:NotifyIcon.Dispose()
        $script:FontBold.Dispose()
        $script:FontMono.Dispose()
        if ($script:CurrentIconHandle -ne [IntPtr]::Zero) {
            [IconHelper]::DestroyIcon($script:CurrentIconHandle) | Out-Null
        }
        [System.Windows.Forms.Application]::Exit()
    })

    $script:NotifyIcon.ContextMenuStrip = $menu
}

# ============================================================
# MAIN - SYSTEM TRAY SETUP
# ============================================================

# Prevent multiple instances
$mutexName = "ClaudeCodeMonitor_SingleInstance"
$script:Mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $script:Mutex.WaitOne(0, $false)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Claude Code Monitor is already running.`nCheck your system tray.",
        "Claude Code Monitor",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    exit
}

# Create NotifyIcon
$script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:NotifyIcon.Text = "Claude Code Monitor - Loading..."
$bmp = New-DonutIcon -Percent 0 -ColorTier "green"
Set-TrayIconFromBitmap $bmp
$script:NotifyIcon.Visible = $true
$script:SubscriptionType = ""
$script:FetchStatus = ""

# Left-click also opens context menu (like Mac menu bar click)
$script:NotifyIcon.Add_Click({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        # Use reflection to invoke the private ShowContextMenu method
        $mi = [System.Windows.Forms.NotifyIcon].GetMethod("ShowContextMenu",
            [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic)
        if ($mi) { $mi.Invoke($script:NotifyIcon, $null) }
    }
})

# Initial fetch
Update-Display

# Timer for periodic data refresh (every 60s)
$script:DataTimer = New-Object System.Windows.Forms.Timer
$script:DataTimer.Interval = $script:PollInterval * 1000
$script:DataTimer.Add_Tick({ Update-Display })
$script:DataTimer.Start()

# Timer for icon rotation: donut (5h) <-> bar (7d) every 4s
$script:IconTimer = New-Object System.Windows.Forms.Timer
$script:IconTimer.Interval = $script:IconRotateInterval * 1000
$script:IconTimer.Add_Tick({ Update-RotatingIcon })
$script:IconTimer.Start()

# Run the message loop
[System.Windows.Forms.Application]::Run()

# Cleanup (runs after Application.Exit)
try {
    $script:Mutex.ReleaseMutex()
} catch {}
$script:Mutex.Dispose()
