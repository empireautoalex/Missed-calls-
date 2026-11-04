const express = require('express');
const twilio = require('twilio');

const { VoiceResponse } = twilio.twiml;

// Dial outcomes that mean you didn't pick up.
const MISSED_STATUSES = new Set(['no-answer', 'busy', 'failed', 'canceled']);

function createApp(config, smsSender) {
  const app = express();
  app.set('trust proxy', true); // so Twilio signature checks work behind hosting proxies
  app.use(express.urlencoded({ extended: false }));

  // Last time we texted each number, so a caller who tries 3 times
  // in a row only gets one text.
  const lastTexted = new Map();
  const cooldownMs = config.cooldownHours * 60 * 60 * 1000;

  function shouldText(number, now = Date.now()) {
    // Skip blocked caller ID. Twilio reports it as "anonymous" or +266696687
    // (which spells "ANONYMOUS" on a keypad).
    if (!number || number === 'anonymous' || number.startsWith('+266696687')) {
      return false;
    }
    const last = lastTexted.get(number);
    return last === undefined || now - last >= cooldownMs;
  }

  // Optionally verify requests really come from Twilio.
  const verify = config.validateRequests
    ? twilio.webhook(config.authToken)
    : (req, res, next) => next();

  app.get('/', (req, res) => res.send('Missed-call auto-reply is running.'));

  // 1) Someone calls your Twilio number: ring your cell.
  app.post('/voice', verify, (req, res) => {
    const twiml = new VoiceResponse();
    const dial = twiml.dial({
      timeout: config.ringTimeoutSeconds,
      action: '/after-dial',
      method: 'POST',
      callerId: req.body.From, // show the real caller on your phone
    });
    dial.number(config.forwardTo);
    res.type('text/xml').send(twiml.toString());
  });

  // 2) The ringing stopped. If you didn't answer, text them back.
  app.post('/after-dial', verify, async (req, res) => {
    const status = req.body.DialCallStatus;
    const caller = req.body.From;
    const twiml = new VoiceResponse();

    if (MISSED_STATUSES.has(status)) {
      if (shouldText(caller)) {
        lastTexted.set(caller, Date.now());
        try {
          await smsSender(caller, config.message);
          console.log(`Missed call from ${caller} (${status}) - auto-reply sent.`);
        } catch (err) {
          lastTexted.delete(caller);
          console.error(`Failed to text ${caller}:`, err.message);
        }
      } else {
        console.log(`Missed call from ${caller} - skipped (cooldown or no caller ID).`);
      }
      twiml.say("Sorry, I can't take your call right now. I'll text you shortly.");
    }
    twiml.hangup();
    res.type('text/xml').send(twiml.toString());
  });

  return app;
}

module.exports = { createApp, MISSED_STATUSES };
