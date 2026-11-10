# After-Hours Auto-Reply for Mac

Your iPhone's calls and texts already show up on this Mac. This tool watches them, and when
someone calls or texts **outside your business hours**, it texts them back through the
Messages app. It's free: no Twilio and no paid app.

**Your business hours:** Mon–Fri 9 AM–6 PM, Sat 10 AM–4 PM, closed Sunday (change them in `settings.conf`)

**After a missed call:**
> Thanks for calling! I'm currently outside business hours. My hours are Mon–Fri 9 AM–6 PM, Sat 10 AM–4 PM (closed Sunday). I'll get back to you during business hours.

**After a text:**
> Thanks for your message! I'm currently outside business hours. My hours are Mon–Fri 9 AM–6 PM, Sat 10 AM–4 PM (closed Sunday). I'll get back to you during business hours.

## The rules it follows

- Checks every minute for incoming calls and new one-on-one texts from the last 30 minutes.
- Only replies to calls and texts that came in **outside** business hours.
- Doesn't reply to calls you answered.
- Each phone number gets **at most one auto-reply a day**.
- Doesn't reply if **you texted that person yourself** in the last 30 minutes.
- Skips private numbers, short codes (like 12345), email addresses and group chats.
- Sends through the existing chat first, then iMessage, then SMS. If iMessage fails to deliver, it tries SMS.
- When you turn it on, it **ignores everything that came in before**, so old messages never get a reply.
- It opens both databases **read-only**. It never changes your calls or messages.

## What's in the folder

| File | What it does |
|---|---|
| **Install.command** | Double-click to turn it on (or to update it). |
| **Test.command** | Double-click to see what it *would have done* over the last 24 hours. Sends nothing. |
| **Turn Off.command** | Double-click to stop it. |
| `settings.conf` | Your hours, messages, and the test/live switch (`DRY_RUN`). |
| `after-hours-reply.sh` | The script the Mac runs every minute. |
| `send-message.applescript` | Sends a text through Messages. |

After you install, everything lives in your home folder at **`~/AfterHoursReply`**, with logs in
`~/AfterHoursReply/logs`:
- `replies.log`: every reply it sent (or would have sent, in test mode)
- `activity.log`: every call and text it looked at, and why it replied or skipped
- `test-results.txt`: the last Test.command results

---

## Setup

### Step 0: Before you start
On the **iPhone**:
- **Settings → Phone → Calls on Other Devices**: turn it on and check this Mac.
- **Settings → Apps → Messages → Text Message Forwarding**: check this Mac. Without this, the Mac can only send iMessages, not SMS.

On the **Mac**:
- Messages is signed in with the same Apple ID as the iPhone.
- **FaceTime → Settings → Calls from iPhone** is on.
- **The Mac must stay on, logged in and awake.** It can't reply while it's asleep.
  - On a desktop Mac: **System Settings → Energy** (or **Displays → Advanced**), turn on **Prevent automatic sleeping when the display is off**.
  - On a MacBook: keep it plugged in with the lid open, and turn on the same setting under **Battery → Options**.

### Step 1: Give Terminal and /bin/bash Full Disk Access
Your call history and Messages are private, so macOS needs your OK before anything can read them.
- **Terminal** needs it for Install and Test, which run in Terminal.
- **/bin/bash** needs it for the background job that runs every minute.

1. Open **Apple menu  → System Settings → Privacy & Security**.
2. Scroll down and click **Full Disk Access**.
3. Click the **+** button under the list. Enter your Mac password or use Touch ID.
4. **Add Terminal:** go to **Applications → Utilities**, pick **Terminal**, and click **Open**.
5. Click **+** again. **Add bash:** press **Command (⌘) + Shift + G**, type `/bin/bash`, press **Return**, then click **Open**.
6. Make sure the switches next to **Terminal** and **bash** are both **on** (blue).
7. If macOS asks to quit and reopen Terminal, click **Quit & Reopen**.

> **Good to know:** turning this on for /bin/bash lets *any* bash script on this Mac read
> protected files. That's fine on a Mac only you use. If you stop using this tool, switch bash
> off again on the same screen.

### Step 2: Install
1. Double-click **Install.command**.
   - If macOS says it "can't be opened because it's from an unidentified developer", **right-click** (or Control-click) the file, choose **Open**, then click **Open** again.
2. A Terminal window opens and sets everything up. It checks each permission and tells you what's **[OK]** or **[NEEDED]**.

### Step 3: Allow it to control Messages
During the install, macOS shows popups like these. Click **OK** (or **Allow**) on each:
- **"Terminal" wants access to control "Messages"**: from the installer.
- **"bash" wants access to control "Messages"** (it may say "osascript" instead): from the background job, within a minute of installing.

If you clicked **Don't Allow** by mistake:
1. Go to **System Settings → Privacy & Security → Automation**.
2. Under **Terminal**, and under **bash** (or **osascript**), turn **Messages** on.
3. If nothing is listed there, open Terminal and run `tccutil reset AppleEvents`, then double-click Install.command again. The popups will come back.

### Step 4: Check the test results (nothing is sent yet)
It starts in **test mode** (`DRY_RUN=1`): it watches and logs, but never sends anything.

1. Double-click **Test.command**. It goes over the last 24 hours and shows what it would have done:

```
After-hours auto-reply: TEST of the last 24 hours. Nothing is sent.

WHEN                 TYPE  FROM             WHAT IT WOULD DO
Mon Nov  9  9:00 PM  call  +15550000001     WOULD REPLY ("Thanks for calling!...")
Tue Nov 10 10:00 AM  call  +15550000002     skip: during business hours
Tue Nov 10  7:10 PM  call  +15550000005     skip: already auto-replied to this number today
Tue Nov 10  7:22 PM  call  +15550000007     skip: you answered
Tue Nov 10  7:30 PM  text  +15550000008     WOULD REPLY ("Thanks for your message!...")
Tue Nov 10  7:40 PM  text  +15550000010     skip: you texted them in the last 30 minutes

Summary: 2 would get an auto-reply, 4 skipped.
```

2. Check that the times are right and that each reply/skip makes sense.
3. You can also leave it in test mode for a day, then look at `~/AfterHoursReply/logs/replies.log`.
   Every line there starts with `TEST MODE, NOT SENT` and shows exactly what it would have sent.

### Step 5: Go live
1. Open `~/AfterHoursReply/settings.conf` in TextEdit.
2. Change `DRY_RUN=1` to `DRY_RUN=0` and save.
3. That's it. The next after-hours call or text gets a real reply. Every reply sent is logged in `logs/replies.log`.

To go back to test mode, change it back to `DRY_RUN=1`.

## Changing your hours or message
Edit `~/AfterHoursReply/settings.conf`. Hours use a 24-hour clock (`18:00` = 6 PM), and `""`
means closed all day. If you change the hours, also update `HOURS_TEXT`, which is how the hours
read in the text. Changes apply within a minute; no need to reinstall.

## Turning it off
Double-click **Turn Off.command**. To turn it back on, double-click **Install.command**. It
will ignore anything that came in while it was off.

## Troubleshooting
- **No replies:** open `~/AfterHoursReply/logs/activity.log`. It says what happened to every call and text, or which permission is missing.
- **"You don't have permission" when double-clicking:** open Terminal and run `chmod +x ` followed by a space, drag the file onto the Terminal window, and press Return.
- **Calls don't show up:** check Step 0. Calls must appear in the Mac's FaceTime app under Recents.
- **Texts go out as iMessage but some people don't get them:** that's what the SMS fallback is for, and it needs Text Message Forwarding (Step 0).

## For developers
`bash mac/tests/simulate.sh` runs the script against fake copies of the call history and
Messages databases, with a fake clock and a fake Messages app. It works on macOS or Linux and
needs `sqlite3`.
