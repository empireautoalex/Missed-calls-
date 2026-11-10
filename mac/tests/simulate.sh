#!/bin/bash
# Runs after-hours-reply.sh against fake copies of the Mac's call history and
# Messages databases, with a fake clock and a fake Messages app. Sends nothing.
#   bash mac/tests/simulate.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
MAC="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export TZ=America/Los_Angeles
FAILS=0

pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

if [ "$(uname)" = Darwin ]; then
  epoch_of() { date -j -f '%Y-%m-%d %H:%M' "$1" +%s; }
  REAL_DATE=/bin/date
else
  epoch_of() { date -d "$1" +%s; }
  REAL_DATE="$(command -v date)"
fi
apple_s() { echo $(($1 - 978307200)); }
apple_ns() { echo "$(($1 - 978307200))000000000"; }

# --- a copy of the app with its own settings, state and logs -------------------
APP="$WORK/app"
mkdir -p "$APP" "$WORK/bin" "$WORK/home/Library/Messages" "$WORK/home/Library/Application Support/CallHistoryDB"
cp "$MAC/after-hours-reply.sh" "$MAC/send-message.applescript" "$MAC/settings.conf" "$APP/"
CALL_DB="$WORK/home/Library/Application Support/CallHistoryDB/CallHistory.storedata"
CHAT_DB="$WORK/home/Library/Messages/chat.db"
export HOME="$WORK/home"
sed -i.bak 's/^SEND_CHECK_SECONDS=.*/SEND_CHECK_SECONDS=2/' "$APP/settings.conf"

# --- fake clock: Tue Nov 10 2026, 8:00 PM Pacific ---------------------------------
FAKE_NOW="$(epoch_of '2026-11-10 20:00')"
export FAKE_NOW
cat > "$WORK/bin/date" <<EOF
#!/bin/bash
for a in "\$@"; do case "\$a" in -d|-r|-j) exec "$REAL_DATE" "\$@";; esac; done
if [ "$(uname)" = Darwin ]; then exec "$REAL_DATE" -r "\$FAKE_NOW" "\$@"; fi
exec "$REAL_DATE" -d "@\$FAKE_NOW" "\$@"
EOF

# --- fake Messages app: records each send and writes it into chat.db ---------------
cat > "$WORK/bin/osascript" <<'EOF'
#!/bin/bash
mode="$2"; target="$3"
echo "$mode|$target|$4" >> "$SENDS"
[ "$mode" = ping ] && { echo "Messages has 3 chats."; exit 0; }
num="${target##*;}"
err=0
case " ${FAIL_IMESSAGE:-} " in *" $num "*) [ "$mode" != sms ] && err=22 ;; esac
now_ns="$(( $(date +%s) - 978307200 ))000000000"
sqlite3 "$CHAT_DB" "
  INSERT OR IGNORE INTO handle (id, service) VALUES ('$num', 'iMessage');
  INSERT INTO message (guid, handle_id, date, is_from_me, error, is_delivered, is_sent, service)
  VALUES (lower(hex(randomblob(8))), (SELECT ROWID FROM handle WHERE id = '$num' LIMIT 1),
          $now_ns, 1, $err, $([ $err = 0 ] && echo 1 || echo 0), 1, '$mode');"
echo sent
EOF
chmod +x "$WORK/bin/"*
export PATH="$WORK/bin:$PATH" SENDS="$WORK/sends.txt" CHAT_DB
: > "$SENDS"

# --- fake databases with the same tables macOS uses ------------------------------
sqlite3 "$CALL_DB" "CREATE TABLE ZCALLRECORD (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER,
  ZANSWERED INTEGER, ZCALLTYPE INTEGER, ZORIGINATED INTEGER, ZDURATION FLOAT, ZDATE TIMESTAMP,
  ZADDRESS VARCHAR, ZSERVICE_PROVIDER VARCHAR);"
sqlite3 "$CHAT_DB" "
  CREATE TABLE handle (ROWID INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL, service TEXT);
  CREATE TABLE chat (ROWID INTEGER PRIMARY KEY AUTOINCREMENT, guid TEXT, style INTEGER,
    chat_identifier TEXT, service_name TEXT);
  CREATE TABLE message (ROWID INTEGER PRIMARY KEY AUTOINCREMENT, guid TEXT, text TEXT,
    handle_id INTEGER DEFAULT 0, service TEXT, date INTEGER, is_from_me INTEGER DEFAULT 0,
    cache_roomnames TEXT, associated_message_type INTEGER DEFAULT 0, item_type INTEGER DEFAULT 0,
    error INTEGER DEFAULT 0, is_delivered INTEGER DEFAULT 0, is_sent INTEGER DEFAULT 0);
  CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER);
  CREATE TABLE chat_handle_join (chat_id INTEGER, handle_id INTEGER);"

add_call() { # 'YYYY-MM-DD HH:MM', number, answered, originated
  sqlite3 "$CALL_DB" "INSERT INTO ZCALLRECORD (ZANSWERED, ZCALLTYPE, ZORIGINATED, ZDATE, ZADDRESS)
    VALUES ($3, 1, ${4:-0}, $(apple_s "$(epoch_of "$1")"), '$2');"
}
add_text() { # 'YYYY-MM-DD HH:MM', number, from_me, style (45 one-on-one / 43 group), tapback
  local style="${4:-45}" rooms=NULL
  [ "$style" = 43 ] && rooms="'chat123'"
  sqlite3 "$CHAT_DB" "
    INSERT INTO handle (id, service) SELECT '$2', 'iMessage' WHERE NOT EXISTS (SELECT 1 FROM handle WHERE id = '$2');
    INSERT INTO chat (guid, style, chat_identifier, service_name)
      SELECT CASE $style WHEN 45 THEN 'iMessage;-;$2' ELSE 'iMessage;+;chat123' END, $style,
             CASE $style WHEN 45 THEN '$2' ELSE 'chat123' END, 'iMessage'
      WHERE NOT EXISTS (SELECT 1 FROM chat WHERE chat_identifier = CASE $style WHEN 45 THEN '$2' ELSE 'chat123' END);
    INSERT INTO message (guid, text, handle_id, service, date, is_from_me, cache_roomnames, associated_message_type)
      VALUES (lower(hex(randomblob(8))), 'hi', (SELECT ROWID FROM handle WHERE id = '$2'), 'iMessage',
              $(apple_ns "$(epoch_of "$1")"), ${3:-0}, $rooms, ${5:-0});
    INSERT INTO chat_message_join VALUES
      ((SELECT ROWID FROM chat WHERE chat_identifier = CASE $style WHEN 45 THEN '$2' ELSE 'chat123' END),
       last_insert_rowid());"
}
run() { /bin/bash "$APP/after-hours-reply.sh" "$@"; }
set_setting() { sed -i.bak "s/^$1=.*/$1=$2/" "$APP/settings.conf"; }

# --- the last day of calls and texts (now = Tue 8:00 PM) --------------------------
add_call '2026-11-09 10:00' '+15550000099' 0     # Mon 10 AM: more than 24 hours ago
add_call '2026-11-09 21:00' '+15550000001' 0     # Mon 9 PM: after hours
add_call '2026-11-10 10:00' '(555) 000-0002' 0   # Tue 10 AM: business hours
add_call '2026-11-10 08:59' '5550000003' 0       # Tue 8:59 AM: before opening
add_call '2026-11-10 18:00' '5550000004' 0       # Tue 6:00 PM: just closed
add_call '2026-11-10 19:00' '5550000005' 0       # Tue 7 PM: after hours
add_call '2026-11-10 19:10' '+15550000005' 0     # same caller again
add_call '2026-11-10 19:20' '' 0                 # no caller ID
add_call '2026-11-10 19:21' '+266696687' 0       # "ANONYMOUS"
add_call '2026-11-10 19:22' '+15550000007' 1     # you answered
add_call '2026-11-10 19:23' '+15550000070' 0 1   # a call you made
add_text '2026-11-10 19:30' '+15550000008'       # after-hours text
add_text '2026-11-10 19:31' '+15550000009' 0 43  # group chat
add_text '2026-11-10 19:32' '12345'              # short code
add_text '2026-11-10 19:33' 'friend@icloud.com'  # email
add_text '2026-11-10 19:35' '+15550000010' 1     # you texted them...
add_text '2026-11-10 19:40' '+15550000010'       # ...then they texted back
add_text '2026-11-10 19:41' '+15550000011' 0 45 2000 # a reaction (tapback)
add_text '2026-11-10 12:00' '+15550000012'       # Tue noon: business hours

echo "== Test command (last 24 hours) =="
OUT="$(run --test)"
echo "$OUT" | sed 's/^/    /'
echo
line() { echo "$OUT" | grep -F -- "$1"; }
check "Mon 9 PM call gets a reply"                  'line "+15550000001" | grep -q "WOULD REPLY"'
check "call over 24 hours ago is not listed"        '! line "+15550000099" >/dev/null'
check "business-hours call skipped"                 'line "+15550000002" | grep -q "during business hours"'
check "8:59 AM call gets a reply (before opening)"  'line "+15550000003" | grep -q "WOULD REPLY"'
check "6:00 PM call gets a reply (just closed)"     'line "+15550000004" | grep -q "WOULD REPLY"'
check "10-digit number gets +1, replied once"       '[ "$(line "+15550000005" | grep -c "WOULD REPLY")" = 1 ]'
check "second call same day skipped"                'line "+15550000005" | grep -q "already auto-replied"'
check "no caller ID skipped"                        '[ "$(echo "$OUT" | grep -c "private number")" = 2 ]'
check "answered call skipped"                       'line "+15550000007" | grep -q "you answered"'
check "outgoing call not listed"                    '! line "+15550000070" >/dev/null'
check "after-hours text gets the text message"      'line "+15550000008" | grep -q "Thanks for your message"'
check "call reply uses the call message"            'line "+15550000001" | grep -q "Thanks for calling"'
check "group chat not listed"                       '! line "+15550000009" >/dev/null'
check "short code skipped"                          'line "12345" | grep -q "short code"'
check "email skipped"                               'line "friend@icloud.com" | grep -q "email address"'
check "skipped when you texted them first"          'line "+15550000010" | grep -q "you texted them"'
check "reaction not listed"                         '! line "+15550000011" >/dev/null'
check "business-hours text skipped"                 'line "+15550000012" | grep -q "during business hours"'
check "test command sent nothing"                   '[ ! -s "$SENDS" ]'
check "test command saved no state"                 '[ -z "$(ls "$APP/state")" ]'

echo
echo "== Turning it on =="
run
check "first run asks to control Messages"          'grep -q "^ping" "$SENDS" && [ -f "$APP/state/messages-allowed" ]'
: > "$SENDS"
run
check "asks only once"                              '[ ! -s "$SENDS" ]'
check "first run sends nothing"                     '! grep -qv "^ping" "$SENDS"'
check "first run bookmarks the newest items"        '[ -s "$APP/state/call-mark" ] && [ -s "$APP/state/text-mark" ]'
check "old calls and texts were never replied to"   '[ ! -s "$APP/logs/replies.log" ]'

echo
echo "== Test mode (DRY_RUN=1) =="
FAKE_NOW=$((FAKE_NOW + 120)); export FAKE_NOW   # 8:02 PM
add_call '2026-11-10 20:01' '+15550000020' 0
run
check "dry run sends nothing"                       '[ ! -s "$SENDS" ]'
check "dry run logs what it would send"             'grep -q "TEST MODE, NOT SENT  to +15550000020 after call" "$APP/logs/replies.log"'

echo
echo "== Live (DRY_RUN=0) =="
set_setting DRY_RUN 0
FAKE_NOW=$((FAKE_NOW + 60)); export FAKE_NOW    # 8:03 PM
add_call '2026-11-10 20:02' '+15550000021' 0     # no chat yet -> iMessage
add_text '2026-11-10 20:02' '+15550000008'       # existing chat -> that chat
FAIL_IMESSAGE='+15550000022' add_call '2026-11-10 20:02' '+15550000022' 0
add_call '2026-11-10 19:20' '+15550000023' 0     # shows up late, 43 minutes old
FAIL_IMESSAGE='+15550000022' run
echo "    sends: $(tr '\n' ' ' < "$SENDS")"
check "new caller texted by iMessage"               'grep -q "^imessage|+15550000021|Thanks for calling" "$SENDS"'
check "texter replied in their existing chat"       'grep -q "^chat|iMessage;-;+15550000008|Thanks for your message" "$SENDS"'
check "iMessage failure falls back to SMS"          'grep -q "^imessage|+15550000022" "$SENDS" && grep -q "^sms|+15550000022" "$SENDS"'
check "item older than 30 minutes skipped"          '! grep -q "+15550000023" "$SENDS"'
check "every send is in the reply log"              '[ "$(grep -c "^.*SENT via" "$APP/logs/replies.log")" = 3 ]'
check "reply log shows the method used"             'grep -q "SENT via sms  to +15550000022" "$APP/logs/replies.log"'

: > "$SENDS"
FAKE_NOW=$((FAKE_NOW + 60)); export FAKE_NOW
add_call '2026-11-10 20:03' '+15550000021' 0     # calls again
run
check "same number not texted twice in a day"       '[ ! -s "$SENDS" ]'
run
check "nothing new, nothing sent"                   '[ ! -s "$SENDS" ]'

echo
echo "== Weekend hours =="
FAKE_NOW="$(epoch_of '2026-11-14 16:10')"; export FAKE_NOW   # Sat 4:10 PM
add_call '2026-11-14 15:59' '+15550000030' 0     # Sat 3:59 PM: open
add_call '2026-11-14 16:00' '+15550000031' 0     # Sat 4:00 PM: closed
run
check "Saturday 3:59 PM is business hours"          '! grep -q "+15550000030" "$SENDS" && grep -q "+15550000030.*during business hours" "$APP/logs/activity.log"'
check "Saturday 4:00 PM gets a reply"               'grep -q "+15550000031" "$SENDS"'
FAKE_NOW="$(epoch_of '2026-11-15 12:01')"; export FAKE_NOW   # Sun noon
add_call '2026-11-15 12:00' '+15550000032' 0
run
check "Sunday noon gets a reply (closed)"           'grep -q "+15550000032" "$SENDS"'

echo
echo "== Turn off and on again =="
: > "$SENDS"
rm -f "$APP/state/call-mark" "$APP/state/text-mark"   # what Turn Off does
FAKE_NOW=$((FAKE_NOW + 60)); export FAKE_NOW
add_call '2026-11-15 12:01' '+15550000033' 0     # arrived while it was off
run
check "calls from while it was off are ignored"     '[ ! -s "$SENDS" ]'

echo
echo "== Activity log =="
sed 's/^/    /' "$APP/logs/activity.log"
echo
if [ "$FAILS" = 0 ]; then echo "ALL CHECKS PASSED"; else echo "$FAILS CHECK(S) FAILED"; exit 1; fi
