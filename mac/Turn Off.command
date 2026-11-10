#!/bin/bash
# Double-click to stop the after-hours auto-reply.
LABEL="com.afterhoursreply.agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DEST="$HOME/AfterHoursReply"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null
rm -f "$PLIST" "$DEST/state/call-mark" "$DEST/state/text-mark"
echo "The after-hours auto-reply is OFF. No more replies will be sent."
echo "Your settings and logs are still in $DEST."
echo "Double-click Install.command to turn it back on."
echo
read -n 1 -s -r -p "Press any key to close this window."
echo
