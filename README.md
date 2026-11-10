# Missed Calls Auto-Reply

> **Free option, no Twilio:** if your iPhone's calls and texts show up on a Mac, use the
> **[Mac after-hours auto-reply](mac/README.md)** instead. It runs on the Mac and texts back
> through the Messages app.

Automatically texts callers back so you never lose a lead.

**Outside business hours** (Mon–Fri 10:30 AM–7:00 PM, Sat 10:30 AM–5:00 PM, closed Sunday),
your phone does not ring and the caller gets this text right away:

> Thanks for your message! I'm currently outside business hours and not available by call or text. My hours are Mon–Fri 10:30 AM–7:00 PM and Sat 10:30 AM–5:00 PM (closed Sunday). I'll get back to you during business hours.

**During business hours**, if you can't answer, the caller gets:

> Hi, sorry I missed your call! I'm currently busy and I will get back to you as soon as I can.

## How it works

1. A customer calls your **Twilio number**.
2. **After hours:** they hear "We're currently closed" and get the after-hours text. Your phone stays quiet.
3. **During hours:** the call rings **your cell phone** for 20 seconds (you can change this).
4. If you answer, nothing else happens.
5. If you don't answer, decline, or you're on another call, the caller hears a short
   message and **gets the text right away**.
6. A caller who tries several times only gets one text every 12 hours.

## Setup (about 15 minutes)

### 1. Get a Twilio number
- Sign up at <https://www.twilio.com> and buy a phone number with voice + SMS (about $1-2/month).
- In the US, register for **A2P 10DLC** texting in the Twilio console (required for business texting).
- Copy your **Account SID** and **Auth Token** from the console dashboard.

### 2. Configure
```bash
cp .env.example .env
```
Fill in `.env`:
| Setting | What to put |
|---|---|
| `TWILIO_ACCOUNT_SID` / `TWILIO_AUTH_TOKEN` | From the Twilio console |
| `TWILIO_PHONE_NUMBER` | The Twilio number you bought, e.g. `+15551234567` |
| `FORWARD_TO_NUMBER` | Your real cell phone |
| `BUSINESS_HOURS` | Your hours, 24-hour clock: `Mon-Fri 10:30-19:00; Sat 10:30-17:00` (days not listed are closed) |
| `TIMEZONE` | Your time zone: `America/New_York`, `America/Chicago`, `America/Denver` or `America/Los_Angeles` |
| `AFTER_HOURS_MESSAGE` | The text sent to after-hours callers (already filled in) |
| `AUTO_REPLY_MESSAGE` | The text sent when you miss a call during business hours (already filled in) |
| `RING_TIMEOUT_SECONDS` | How long to ring before it counts as missed (default 20) |
| `COOLDOWN_HOURS` | Minimum hours between texts to the same number (default 12) |

### 3. Run it
```bash
npm install
npm start
```
Host it anywhere that runs Node.js (Render, Railway, Fly.io, a VPS). Add the same
values from `.env` as environment variables on the host.

### 4. Connect Twilio to it
In the Twilio console, open **Phone Numbers → your number → Voice Configuration**:
- **A call comes in:** Webhook, `https://YOUR-APP-URL/voice`, HTTP POST

Save. Then give out the Twilio number as your business line, or forward your
existing number to it.

## Test it
- **During business hours:** call your Twilio number from another phone and let it ring.
  You should get the "busy" text within a few seconds of the call ending.
- **After hours:** call it. Your phone should not ring, and you should get the
  after-hours text right away.

Run the automated tests with `npm test`.
