#!/bin/bash
# ArgusDesk daily auto-run for macOS.
# Runs /argusdesk on your tickers every weekday after the US close and saves the reports.
#
# Install:  curl -fsSL https://raw.githubusercontent.com/Bodila51/ArgusDesk/main/daily.sh | bash -s NVDA
# Options:  more tickers (NVDA TSLA), --time 23:30 (Mac time, default 23:30), --remove
set -euo pipefail

LABEL="com.argusdesk.daily"
RAW="https://raw.githubusercontent.com/Bodila51/ArgusDesk/main"
HOME_DIR="$HOME/.argusdesk"
REPORTS="$HOME/ArgusDesk-reports"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
TIME="23:30"
TICKERS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --remove)
      launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
      rm -f "$PLIST" "$HOME_DIR/daily-run.sh"
      echo "ArgusDesk daily run removed. Reports stay in $REPORTS"
      exit 0 ;;
    --time) TIME="$2"; shift ;;
    *) TICKERS+=("$(echo "$1" | tr '[:lower:]' '[:upper:]')") ;;
  esac
  shift
done
[ ${#TICKERS[@]} -eq 0 ] && TICKERS=(NVDA)
HOUR=$((10#${TIME%%:*})); MIN=$((10#${TIME##*:}))

[ "$(uname)" = "Darwin" ] || { echo "This script is for macOS."; exit 1; }

# 1. Latest skill
mkdir -p "$HOME/.claude/skills/argusdesk" "$HOME_DIR" "$REPORTS" "$HOME/Library/LaunchAgents"
curl -fsSL "$RAW/SKILL.md" -o "$HOME/.claude/skills/argusdesk/SKILL.md"
echo "Skill updated: ~/.claude/skills/argusdesk"

# 2. Claude Code CLI (the scheduler needs it; the Claude app alone has no command)
CLAUDE=""
for c in "$(command -v claude 2>/dev/null || true)" "$HOME/.local/bin/claude" "$HOME/.claude/local/claude" /opt/homebrew/bin/claude /usr/local/bin/claude; do
  [ -n "$c" ] && [ -x "$c" ] && { CLAUDE="$c"; break; }
done
if [ -z "$CLAUDE" ]; then
  echo "Installing the Claude Code CLI..."
  curl -fsSL https://claude.ai/install.sh | bash
  CLAUDE="$HOME/.local/bin/claude"
fi
[ -x "$CLAUDE" ] || { echo "Claude Code CLI not found. Install it from https://claude.ai/install.sh and run this again."; exit 1; }

OUT=$("$CLAUDE" -p "Reply with the single word OK" 2>&1 || true)
if [[ "$OUT" != *OK* ]]; then
  echo
  echo "One more step: log in to the CLI once."
  echo "  1. Run:  $CLAUDE"
  echo "  2. Log in with your Claude account, then type /exit"
  echo "  3. Run this install command again"
  exit 1
fi

# 3. The job itself
cat > "$HOME_DIR/daily-run.sh" <<EOF
#!/bin/bash
export PATH="$HOME/.local/bin:$PATH"
DAY=\$(date +%F)
for T in ${TICKERS[*]}; do
  DIR="$REPORTS/\$DAY/\$T"
  mkdir -p "\$DIR" && cd "\$DIR" || continue
  "$CLAUDE" -p "/argusdesk \$T auto-run" \\
    --allowedTools "Bash,Read,Write,Edit,Glob,Grep,Skill,WebFetch" > run.log 2>&1
  if [ -f argusdesk_report.md ]; then
    cp argusdesk_report.md "$REPORTS/latest-\$T.md"
    MSG="\$T: \$(head -1 argusdesk_report.md | cut -c1-120)"
  else
    MSG="\$T: no report, see \$DIR/run.log"
  fi
  osascript -e "display notification \"\$MSG\" with title \"ArgusDesk\"" || true
done
EOF
chmod +x "$HOME_DIR/daily-run.sh"

DAYS=""
for d in 1 2 3 4 5; do
  DAYS="$DAYS<dict><key>Weekday</key><integer>$d</integer><key>Hour</key><integer>$HOUR</integer><key>Minute</key><integer>$MIN</integer></dict>"
done
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$HOME_DIR/daily-run.sh</string></array>
  <key>StartCalendarInterval</key><array>$DAYS</array>
  <key>StandardOutPath</key><string>$HOME_DIR/daily.log</string>
  <key>StandardErrorPath</key><string>$HOME_DIR/daily.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo
echo "Done. ArgusDesk runs ${TICKERS[*]} Mon-Fri at $(printf '%02d:%02d' "$HOUR" "$MIN") (Mac time)."
echo "Reports: $REPORTS/latest-<TICKER>.md, plus a folder per day. You get a notification."
echo "If the Mac sleeps at that time, the run starts when it wakes. If it is off, that day is skipped."
echo "Run it right now:  launchctl kickstart gui/$(id -u)/$LABEL"
echo "Remove:  curl -fsSL $RAW/daily.sh | bash -s -- --remove"
