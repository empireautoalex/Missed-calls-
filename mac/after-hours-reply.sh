#!/bin/bash
# After-hours auto-reply for the calls and texts your iPhone shares with this Mac.
#
#   after-hours-reply.sh          Normal run. The LaunchAgent runs this every minute.
#   after-hours-reply.sh --test   Shows what it would have done over the last 24 hours.
#                                 Sends nothing and changes nothing.
#
# Written for the bash 3.2 that ships with macOS (no bash 4 features).

DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="$DIR/state"
LOG_DIR="$DIR/logs"
APPLE_EPOCH=978307200 # 2001-01-01, the start of Apple's clock
export PATH="$PATH:/usr/bin:/bin:/usr/sbin:/sbin"

MODE=run
[ "$1" = "--test" ] && MODE="test"

# ---------------------------------------------------------------- settings --
DRY_RUN=1
LOOKBACK_MINUTES=30
RECENT_TEXT_MINUTES=30
TEST_HOURS=24
DEFAULT_COUNTRY_CODE=1
SEND_CHECK_SECONDS=20
CALL_DB="$HOME/Library/Application Support/CallHistoryDB/CallHistory.storedata"
CHAT_DB="$HOME/Library/Messages/chat.db"
SETTINGS="${AHR_SETTINGS:-$DIR/settings.conf}"
if [ -f "$SETTINGS" ]; then
  # shellcheck source=settings.conf
  . "$SETTINGS"
else
  echo "Settings file not found: $SETTINGS" >&2
  exit 1
fi

mkdir -p "$STATE_DIR" "$LOG_DIR"

# ----------------------------------------------------------------- helpers --
log() { # activity log: everything the agent decides
  [ "$MODE" = test ] && return 0
  printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_DIR/activity.log"
}

reply_log() { # the log of every reply sent (or that would be sent in test mode)
  printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_DIR/replies.log"
}

# Log a warning at most once an hour so the log doesn't fill up.
warn_hourly() { # key, message
  local flag="$STATE_DIR/warned-$1"
  if [ -z "$(find "$flag" -mmin -60 2>/dev/null)" ]; then
    log "WARNING: $2"
    touch "$flag"
  fi
}

if [ "$(uname)" = Darwin ]; then
  fmt_epoch() { date -r "$1" "+$2"; }
else
  fmt_epoch() { date -d "@$1" "+$2"; } # GNU date, used only for testing off a Mac
fi

sql() { # database, query (always read-only)
  sqlite3 -readonly -batch -noheader -init /dev/null -cmd '.timeout 5000' -separator '|' "$1" "$2"
}

# SQL that strips a phone number column down to its digits.
sql_digits() {
  echo "replace(replace(replace(replace(replace(replace(IFNULL($1,''),'+',''),'-',''),' ',''),'(',''),')',''),'.','')"
}

# SQL that is true when column $1 is the same phone number as digits $2.
sql_same_number() {
  local d
  d="$(sql_digits "$1")"
  echo "($d = '$2' OR ('$DEFAULT_COUNTRY_CODE' || $d) = '$2')"
}

MSG_TIME="CAST((CASE WHEN m.date > 100000000000 THEN m.date / 1000000000 ELSE m.date END) + $APPLE_EPOCH AS INTEGER)"

# Sets NUM to a +E.164 number, or REASON to why it is skipped.
classify_number() {
  local raw="$1" digits
  NUM=""
  REASON=""
  case "$raw" in
    "") REASON="private number"; return 1 ;;
    *@*) REASON="email address"; return 1 ;;
    *[A-Za-z]*) REASON="private number"; return 1 ;; # "anonymous", "Unknown", ...
  esac
  digits="$(printf '%s' "$raw" | tr -cd '0-9')"
  case "$digits" in
    266696687 | 1266696687) REASON="private number"; return 1 ;; # spells ANONYMOUS
  esac
  if [ ${#digits} -lt 10 ]; then REASON="short code"; return 1; fi
  if [ ${#digits} -eq 10 ] && [ "${raw#+}" = "$raw" ]; then
    digits="$DEFAULT_COUNTRY_CODE$digits"
  fi
  if [ ${#digits} -gt 15 ]; then REASON="not a phone number"; return 1; fi
  NUM="+$digits"
}

hours_for_day() { # 1=Mon ... 7=Sun
  case "$1" in
    1) echo "$HOURS_MON" ;; 2) echo "$HOURS_TUE" ;; 3) echo "$HOURS_WED" ;;
    4) echo "$HOURS_THU" ;; 5) echo "$HOURS_FRI" ;; 6) echo "$HOURS_SAT" ;;
    7) echo "$HOURS_SUN" ;;
  esac
}

is_business_hours() { # epoch
  local spec open close now
  spec="$(hours_for_day "$(fmt_epoch "$1" %u)")"
  [ -z "$spec" ] && return 1 # closed all day
  open="${spec%-*}"; close="${spec#*-}"
  open="${open/:/}"; close="${close/:/}"
  now="$(fmt_epoch "$1" %H%M)"
  [ $((10#$now)) -ge $((10#$open)) ] && [ $((10#$now)) -lt $((10#$close)) ]
}

already_replied() { # day, number, file
  [ -f "$3" ] && grep -qxF "$1 $2" "$3"
}

texted_them_recently() { # number, from_epoch, to_epoch
  local t count
  t="${1#+}"
  count="$(sql "$CHAT_DB" "
    SELECT COUNT(*) FROM message m
    LEFT JOIN handle h ON h.ROWID = m.handle_id
    LEFT JOIN chat_message_join j ON j.message_id = m.ROWID
    LEFT JOIN chat c ON c.ROWID = j.chat_id
    WHERE m.is_from_me = 1 AND $MSG_TIME BETWEEN $2 AND $3
      AND ($(sql_same_number h.id "$t") OR (c.style = 45 AND $(sql_same_number c.chat_identifier "$t")));")"
  [ "${count:-0}" -gt 0 ]
}

# Calls and texts newer than the bookmarks, as "epoch|kind|answered|raw number".
list_events() { # since_epoch, call_after, call_upto, msg_after, msg_upto
  if [ "$CALLS_OK" = 1 ]; then
    sql "$CALL_DB" "
      SELECT CAST(ZDATE + $APPLE_EPOCH AS INTEGER), 'call', IFNULL(ZANSWERED, 0),
             IFNULL(CAST(ZADDRESS AS TEXT), '')
      FROM ZCALLRECORD
      WHERE IFNULL(ZORIGINATED, 0) = 0
        AND Z_PK > $2 AND Z_PK <= $3
        AND ZDATE + $APPLE_EPOCH >= $1;"
  fi
  if [ "$TEXTS_OK" = 1 ]; then
    sql "$CHAT_DB" "
      SELECT $MSG_TIME, 'text', 0, IFNULL(h.id, '')
      FROM message m
      JOIN chat_message_join j ON j.message_id = m.ROWID
      JOIN chat c ON c.ROWID = j.chat_id
      LEFT JOIN handle h ON h.ROWID = m.handle_id
      WHERE m.is_from_me = 0
        AND c.style = 45                             -- one-on-one chats only
        AND m.cache_roomnames IS NULL
        AND IFNULL(m.associated_message_type, 0) = 0 -- skip reactions (tapbacks)
        AND IFNULL(m.item_type, 0) = 0               -- skip renames, joins, etc.
        AND m.ROWID > $4 AND m.ROWID <= $5
        AND $MSG_TIME >= $1;"
  fi
}

# Decides what to do with one event. Sets ACTION (reply/skip), REASON, NUM, MESSAGE.
decide() { # epoch, kind, answered, raw, reference "now" epoch, dedupe file
  ACTION=skip
  MESSAGE=""
  if ! classify_number "$4"; then return; fi
  if [ "$2" = call ] && [ "$3" = 1 ]; then REASON="you answered"; return; fi
  if is_business_hours "$1"; then REASON="during business hours"; return; fi
  if already_replied "$(fmt_epoch "$1" %Y-%m-%d)" "$NUM" "$6"; then
    REASON="already auto-replied to this number today"; return
  fi
  if [ "$TEXTS_OK" = 1 ] && texted_them_recently "$NUM" $(($5 - RECENT_TEXT_MINUTES * 60)) "$5"; then
    REASON="you texted them in the last $RECENT_TEXT_MINUTES minutes"; return
  fi
  ACTION=reply
  REASON=""
  if [ "$2" = call ]; then MESSAGE="$CALL_MESSAGE"; else MESSAGE="$TEXT_MESSAGE"; fi
}

# ----------------------------------------------------------------- sending --
existing_chat_id() { # number
  sql "$CHAT_DB" "
    SELECT c.guid FROM chat c
    WHERE c.style = 45 AND $(sql_same_number c.chat_identifier "${1#+}")
    ORDER BY (SELECT MAX(m.date) FROM chat_message_join j JOIN message m ON m.ROWID = j.message_id
              WHERE j.chat_id = c.ROWID) DESC
    LIMIT 1;"
}

# Watches chat.db for the message we just sent. 0 = sent, 1 = failed, 2 = can't tell.
check_sent() { # number, start_epoch, method
  local t waited=0 row err delivered sent
  t="${1#+}"
  while :; do
    row="$(sql "$CHAT_DB" "
      SELECT IFNULL(m.error, 0), IFNULL(m.is_delivered, 0), IFNULL(m.is_sent, 0)
      FROM message m
      LEFT JOIN handle h ON h.ROWID = m.handle_id
      LEFT JOIN chat_message_join j ON j.message_id = m.ROWID
      LEFT JOIN chat c ON c.ROWID = j.chat_id
      WHERE m.is_from_me = 1 AND $MSG_TIME >= $2
        AND ($(sql_same_number h.id "$t") OR $(sql_same_number c.chat_identifier "$t"))
      ORDER BY m.ROWID DESC LIMIT 1;")"
    if [ -n "$row" ]; then
      IFS='|' read -r err delivered sent <<EOF
$row
EOF
      [ "$err" != 0 ] && return 1
      [ "$delivered" = 1 ] && return 0
      [ "$3" != imessage ] && [ "$sent" = 1 ] && return 0
    fi
    [ "$waited" -ge "$SEND_CHECK_SECONDS" ] && break
    sleep 2
    waited=$((waited + 2))
  done
  [ -n "$row" ] && return 0 # no error so far: still on its way
  return 2
}

# Tries the existing chat, then iMessage, then SMS. Sets SENT_VIA.
send_reply() { # number, message
  local chat_id start method target out status
  SENT_VIA=""
  chat_id="$(existing_chat_id "$1")"
  for method in chat imessage sms; do
    target="$1"
    if [ "$method" = chat ]; then
      [ -z "$chat_id" ] && continue
      target="$chat_id"
    fi
    start=$(($(date +%s) - 5))
    if ! out="$(osascript "$DIR/send-message.applescript" "$method" "$target" "$2" 2>&1 </dev/null)"; then
      log "  $method send to $1 didn't work: $out"
      continue
    fi
    check_sent "$1" "$start" "$method"
    status=$?
    if [ "$status" = 1 ]; then
      log "  $method message to $1 failed to deliver, trying the next way"
      continue
    fi
    SENT_VIA="$method"
    [ "$status" = 2 ] && SENT_VIA="$method (sent, not yet confirmed)"
    return 0
  done
  return 1
}

# ------------------------------------------------------------- test mode --
check_databases() {
  CALLS_OK=0
  TEXTS_OK=0
  CALL_MAX="$(sql "$CALL_DB" "SELECT IFNULL(MAX(Z_PK), 0) FROM ZCALLRECORD;" 2>/dev/null)" && CALLS_OK=1
  MSG_MAX="$(sql "$CHAT_DB" "SELECT IFNULL(MAX(ROWID), 0) FROM message;" 2>/dev/null)" && TEXTS_OK=1
}

run_test() {
  local now since tmp dedupe would=0 skipped=0 epoch kind answered raw label
  check_databases
  echo "After-hours auto-reply: TEST of the last $TEST_HOURS hours. Nothing is sent."
  echo
  [ "$CALLS_OK" = 1 ] || echo "!! Can't read call history: $CALL_DB"
  [ "$TEXTS_OK" = 1 ] || echo "!! Can't read Messages: $CHAT_DB"
  if [ "$CALLS_OK" = 0 ] || [ "$TEXTS_OK" = 0 ]; then
    echo "   Give Terminal Full Disk Access (see the README), then run the test again."
    echo
    [ "$CALLS_OK" = 0 ] && [ "$TEXTS_OK" = 0 ] && return 1
  fi
  now=$(date +%s)
  since=$((now - TEST_HOURS * 3600))
  tmp="$(mktemp)"
  dedupe="$(mktemp)"
  list_events "$since" 0 "${CALL_MAX:-0}" 0 "${MSG_MAX:-0}" | sort -t'|' -k1,1n > "$tmp"

  printf '%-20s %-5s %-16s %s\n' "WHEN" "TYPE" "FROM" "WHAT IT WOULD DO"
  while IFS='|' read -r epoch kind answered raw <&3; do
    # Pretend the check runs one minute after the call or text.
    decide "$epoch" "$kind" "$answered" "$raw" $((epoch + 60)) "$dedupe"
    if [ "$ACTION" = reply ]; then
      echo "$(fmt_epoch "$epoch" %Y-%m-%d) $NUM" >> "$dedupe"
      label="WOULD REPLY (\"${MESSAGE%%!*}!...\")"
      would=$((would + 1))
    else
      label="skip: $REASON"
      skipped=$((skipped + 1))
    fi
    printf '%-20s %-5s %-16s %s\n' "$(fmt_epoch "$epoch" '%a %b %e %l:%M %p')" "$kind" "${NUM:-${raw:-(none)}}" "$label"
  done 3< "$tmp"
  rm -f "$tmp" "$dedupe"
  [ $((would + skipped)) = 0 ] && echo "(no incoming calls or one-on-one texts in the last $TEST_HOURS hours)"
  echo
  echo "Summary: $would would get an auto-reply, $skipped skipped."
  echo
  echo "After a call:  $CALL_MESSAGE"
  echo "After a text:  $TEXT_MESSAGE"
  echo
  if [ "$DRY_RUN" = 1 ]; then
    echo "Status: TEST MODE (DRY_RUN=1). To go live, set DRY_RUN=0 in settings.conf."
  else
    echo "Status: LIVE (DRY_RUN=0). Replies are being sent."
  fi
}

# --------------------------------------------------------------- run mode --
run_once() {
  local now since call_mark msg_mark tmp dedupe epoch kind answered raw when
  check_databases
  if [ "$CALLS_OK" = 0 ] && [ "$TEXTS_OK" = 0 ]; then
    warn_hourly fda "Can't read call history or Messages. Give /bin/bash Full Disk Access (see the README)."
    return 1
  fi
  [ "$CALLS_OK" = 1 ] || warn_hourly calls "Can't read call history ($CALL_DB). Calls are being ignored."
  [ "$TEXTS_OK" = 1 ] || warn_hourly texts "Can't read Messages ($CHAT_DB). Texts are being ignored."

  # Ask for permission to control Messages right away (macOS shows a popup once),
  # so it's sorted out while you're at the Mac, not at the first after-hours call.
  if [ ! -f "$STATE_DIR/messages-allowed" ]; then
    local out
    if out="$(osascript "$DIR/send-message.applescript" ping 2>&1 </dev/null)"; then
      touch "$STATE_DIR/messages-allowed"
      log "Allowed to control Messages."
    else
      warn_hourly automation "Not allowed to control Messages yet ($out). See the README, Step 3."
    fi
  fi

  # Bookmarks: the newest call and text already looked at.
  call_mark="$(cat "$STATE_DIR/call-mark" 2>/dev/null)"
  msg_mark="$(cat "$STATE_DIR/text-mark" 2>/dev/null)"
  if [ -z "$call_mark" ] && [ -z "$msg_mark" ]; then
    echo "${CALL_MAX:-0}" > "$STATE_DIR/call-mark"
    echo "${MSG_MAX:-0}" > "$STATE_DIR/text-mark"
    log "Turned on. Ignoring everything before now; only new calls and texts get replies."
    return 0
  fi
  # A source that couldn't be read before starts from "now" too.
  [ -z "$call_mark" ] && call_mark="${CALL_MAX:-0}"
  [ -z "$msg_mark" ] && msg_mark="${MSG_MAX:-0}"
  # If a database was rebuilt and is now smaller, start from its newest item.
  [ "$CALLS_OK" = 1 ] && [ "$CALL_MAX" -lt "$call_mark" ] && call_mark="$CALL_MAX"
  [ "$TEXTS_OK" = 1 ] && [ "$MSG_MAX" -lt "$msg_mark" ] && msg_mark="$MSG_MAX"

  now=$(date +%s)
  since=$((now - LOOKBACK_MINUTES * 60))
  if [ "$DRY_RUN" = 1 ]; then dedupe="$STATE_DIR/replied-test-mode.txt"; else dedupe="$STATE_DIR/replied.txt"; fi
  tmp="$(mktemp)"
  list_events "$since" "$call_mark" "${CALL_MAX:-$call_mark}" "$msg_mark" "${MSG_MAX:-$msg_mark}" |
    sort -t'|' -k1,1n > "$tmp"

  while IFS='|' read -r epoch kind answered raw <&3; do
    when="$(fmt_epoch "$epoch" '%a %l:%M %p' | tr -s ' ')"
    decide "$epoch" "$kind" "$answered" "$raw" "$(date +%s)" "$dedupe"
    if [ "$ACTION" != reply ]; then
      log "$kind from ${NUM:-${raw:-unknown}} at $when: skipped ($REASON)"
      continue
    fi
    if [ "$DRY_RUN" = 1 ]; then
      echo "$(fmt_epoch "$epoch" %Y-%m-%d) $NUM" >> "$dedupe"
      log "$kind from $NUM at $when: would reply (test mode)"
      reply_log "TEST MODE, NOT SENT  to $NUM after $kind at $when: $MESSAGE"
    elif send_reply "$NUM" "$MESSAGE"; then
      echo "$(fmt_epoch "$epoch" %Y-%m-%d) $NUM" >> "$dedupe"
      log "$kind from $NUM at $when: replied via $SENT_VIA"
      reply_log "SENT via $SENT_VIA  to $NUM after $kind at $when: $MESSAGE"
    else
      log "$kind from $NUM at $when: COULD NOT SEND (see lines above)"
      reply_log "FAILED  to $NUM after $kind at $when"
    fi
  done 3< "$tmp"
  rm -f "$tmp"

  [ "$CALLS_OK" = 1 ] && echo "$CALL_MAX" > "$STATE_DIR/call-mark"
  [ "$TEXTS_OK" = 1 ] && echo "$MSG_MAX" > "$STATE_DIR/text-mark"

  # Forget daily reply records older than two days, and keep the activity log small.
  if [ -f "$dedupe" ]; then
    grep -E "^($(date +%Y-%m-%d)|$(fmt_epoch $((now - 86400)) %Y-%m-%d)) " "$dedupe" > "$dedupe.new"
    mv "$dedupe.new" "$dedupe"
  fi
  if [ -f "$LOG_DIR/activity.log" ] && [ "$(wc -c < "$LOG_DIR/activity.log")" -gt 2000000 ]; then
    tail -n 5000 "$LOG_DIR/activity.log" > "$LOG_DIR/activity.log.new"
    mv "$LOG_DIR/activity.log.new" "$LOG_DIR/activity.log"
  fi
}

# -------------------------------------------------------------------- main --
if [ "$MODE" = test ]; then
  run_test
  exit $?
fi

LOCK="$STATE_DIR/lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  # Another run is still going. Clear the lock only if it is stale.
  [ -z "$(find "$LOCK" -maxdepth 0 -mmin +10 2>/dev/null)" ] && exit 0
  rmdir "$LOCK" 2>/dev/null
  mkdir "$LOCK" 2>/dev/null || exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
run_once
