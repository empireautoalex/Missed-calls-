require('dotenv').config();
const twilio = require('twilio');
const { createApp } = require('./app');

function required(name) {
  const value = process.env[name];
  if (!value) {
    console.error(`Missing ${name}. Copy .env.example to .env and fill it in.`);
    process.exit(1);
  }
  return value;
}

const config = {
  accountSid: required('TWILIO_ACCOUNT_SID'),
  authToken: required('TWILIO_AUTH_TOKEN'),
  fromNumber: required('TWILIO_PHONE_NUMBER'),
  forwardTo: required('FORWARD_TO_NUMBER'),
  ringTimeoutSeconds: Number(process.env.RING_TIMEOUT_SECONDS || 20),
  cooldownHours: Number(process.env.COOLDOWN_HOURS || 12),
  validateRequests: process.env.VALIDATE_TWILIO_REQUESTS !== 'false',
  businessHours: process.env.BUSINESS_HOURS || 'Mon-Fri 10:30-19:00; Sat 10:30-17:00',
  timeZone: process.env.TIMEZONE || 'America/New_York',
  afterHoursMessage:
    process.env.AFTER_HOURS_MESSAGE ||
    "Thanks for your message! I'm currently outside business hours and not available by call or text. My hours are Mon–Fri 10:30 AM–7:00 PM and Sat 10:30 AM–5:00 PM (closed Sunday). I'll get back to you during business hours.",
  message:
    process.env.AUTO_REPLY_MESSAGE ||
    "Hi, sorry I missed your call! I'm currently busy and I will get back to you as soon as I can.",
};

const client = twilio(config.accountSid, config.authToken);
const sendSms = (to, body) =>
  client.messages.create({ to, from: config.fromNumber, body });

const port = Number(process.env.PORT || 3000);
createApp(config, sendSms).listen(port, () => {
  console.log(`Missed-call auto-reply listening on port ${port}`);
});
