# Missed Calls Auto-Reply

When you can't answer a call, the caller automatically gets this text:

> Hi, sorry I missed your call! I'm currently busy and I will get back to you as soon as I can.

## How it works

1. A customer calls your **Twilio number**.
2. The call rings **your cell phone** for 20 seconds (you can change this).
3. If you answer, nothing else happens.
4. If you don't answer, decline, or you're on another call, the caller hears a short
   message and **gets the text right away**.
5. A caller who tries several times only gets one text every 12 hours.

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
| `AUTO_REPLY_MESSAGE` | The text callers receive (already filled in) |
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
Call your Twilio number from another phone and let it ring. You should get the text
within a few seconds of the call ending.

Run the automated tests with `npm test`.
