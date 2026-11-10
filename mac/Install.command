#!/bin/bash
# Double-click to turn on the after-hours auto-reply (or to update it).
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/AfterHoursReply"
LABEL="com.afterhoursreply.agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
CHAT_DB="$HOME/Library/Messages/chat.db"

pause() { echo; read -n 1 -s -r -p "Press any key to close this window."; echo; }

echo "== After-hours auto-reply: install =="
echo
mkdir -p "$DEST/logs" "$DEST/state" "$HOME/Library/LaunchAgents"
if [ "$SRC" != "$DEST" ]; then
  for f in after-hours-reply.sh send-message.applescript Install.command Test.command "Turn Off.command" README.md; do
    cp "$SRC/$f" "$DEST/" || { echo "Couldn't copy $f"; pause; exit 1; }
  done
  if [ -f "$DEST/settings.conf" ]; then
    echo "Keeping your existing settings: $DEST/settings.conf"
  else
    cp "$SRC/settings.conf" "$DEST/"
  fi
fi
chmod +x "$DEST"/*.command "$DEST/after-hours-reply.sh"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null

# Forget the old bookmarks, so turning on never replies to old calls or texts.
rm -f "$DEST/state/call-mark" "$DEST/state/text-mark"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$DEST/after-hours-reply.sh</string>
  </array>
  <key>StartInterval</key><integer>60</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$DEST/logs/launchd.log</string>
  <key>StandardErrorPath</key><string>$DEST/logs/launchd.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
if ! launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null; then
  launchctl load -w "$PLIST" || { echo "Couldn't start the background job."; pause; exit 1; }
fi
echo "Background job installed: it runs every minute."
echo

# Permission 1: Full Disk Access for Terminal (needed by Test.command).
if sqlite3 -readonly "$CHAT_DB" "SELECT 1;" >/dev/null 2>&1; then
  echo "[OK] Terminal can read Messages and call history."
else
  echo "[NEEDED] Full Disk Access for Terminal and for /bin/bash."
  echo "   Opening System Settings > Privacy & Security > Full Disk Access."
  echo "   Follow the steps in the README, then run Install again."
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
fi

# Permission 2: let Terminal control Messages. macOS asks once; click OK.
echo
echo "Checking permission to control Messages (click OK if macOS asks)..."
if out="$(osascript "$DEST/send-message.applescript" ping 2>&1)"; then
  echo "[OK] $out"
else
  echo "[NEEDED] Terminal isn't allowed to control Messages: $out"
  echo "   Turn it on in System Settings > Privacy & Security > Automation > Terminal > Messages."
fi

# Did the background job manage to read the databases?
sleep 5
echo
if grep -q "Turned on" "$DEST/logs/activity.log" 2>/dev/null &&
   [ -f "$DEST/state/text-mark" ]; then
  echo "[OK] The background job is running and can read your calls and texts."
else
  echo "[NEEDED] The background job can't read your calls and texts yet."
  echo "   Give /bin/bash Full Disk Access (see the README). It starts working within a minute after that."
fi

echo
if grep -q '^DRY_RUN=0' "$DEST/settings.conf"; then
  echo "Mode: LIVE. Auto-replies are being sent."
else
  echo "Mode: TEST (nothing is sent). Double-click Test.command to see what it would do."
  echo "To go live, open $DEST/settings.conf and change DRY_RUN=1 to DRY_RUN=0."
fi
open "$DEST"
pause
