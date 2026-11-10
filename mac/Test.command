#!/bin/bash
# Double-click to see what the auto-reply would have done over the last 24 hours.
# Sends nothing and changes nothing.
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/after-hours-reply.sh"
[ -f "$HOME/AfterHoursReply/after-hours-reply.sh" ] && SCRIPT="$HOME/AfterHoursReply/after-hours-reply.sh"
RESULTS="$(dirname "$SCRIPT")/logs/test-results.txt"
mkdir -p "$(dirname "$RESULTS")"

/bin/bash "$SCRIPT" --test 2>&1 | tee "$RESULTS"
echo
echo "Saved to $RESULTS"
echo
read -n 1 -s -r -p "Press any key to close this window."
echo
