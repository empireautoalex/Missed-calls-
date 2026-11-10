const { test } = require('node:test');
const assert = require('node:assert');
const { parseHours, isOpen } = require('../hours');
const { createApp } = require('../app');

const schedule = parseHours('Mon-Fri 10:30-19:00; Sat 10:30-17:00');
const tz = 'America/New_York';
const open = (iso) => isOpen(schedule, tz, new Date(iso));

// Nov 2026: New York is UTC-5. Nov 10 = Tuesday, Nov 14 = Saturday, Nov 15 = Sunday.
test('weekday hours 10:30 AM - 7:00 PM', () => {
  assert.strictEqual(open('2026-11-10T15:29:00Z'), false); // Tue 10:29 AM
  assert.strictEqual(open('2026-11-10T15:30:00Z'), true); //  Tue 10:30 AM
  assert.strictEqual(open('2026-11-10T23:59:00Z'), true); //  Tue 6:59 PM
  assert.strictEqual(open('2026-11-11T00:00:00Z'), false); // Tue 7:00 PM
});

test('Saturday hours 10:30 AM - 5:00 PM', () => {
  assert.strictEqual(open('2026-11-14T15:30:00Z'), true); //  Sat 10:30 AM
  assert.strictEqual(open('2026-11-14T21:59:00Z'), true); //  Sat 4:59 PM
  assert.strictEqual(open('2026-11-14T22:00:00Z'), false); // Sat 5:00 PM
});

test('closed all day Sunday', () => {
  assert.strictEqual(open('2026-11-15T17:00:00Z'), false); // Sun noon
});

test('daylight saving time is handled', () => {
  assert.strictEqual(open('2026-07-07T14:30:00Z'), true); // Tue 10:30 AM EDT (UTC-4)
  assert.strictEqual(open('2026-07-07T14:29:00Z'), false);
});

test('bad hours are rejected', () => {
  assert.throws(() => parseHours('Mon-Fri 10:30 to 7pm'));
});

async function callAt(iso) {
  const sent = [];
  const app = createApp(
    {
      forwardTo: '+15557654321',
      ringTimeoutSeconds: 20,
      cooldownHours: 12,
      validateRequests: false,
      message: 'busy message',
      afterHoursMessage: 'after hours message',
      businessHours: 'Mon-Fri 10:30-19:00; Sat 10:30-17:00',
      timeZone: tz,
      now: () => new Date(iso),
    },
    async (to, body) => sent.push({ to, body })
  );
  const server = app.listen(0);
  try {
    const xml = await fetch(`http://127.0.0.1:${server.address().port}/voice`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ From: '+15550003333' }),
    }).then((r) => r.text());
    return { xml, sent };
  } finally {
    server.close();
  }
}

test('call after hours: no ring, after-hours text sent', async () => {
  const { xml, sent } = await callAt('2026-11-11T01:00:00Z'); // Tue 8 PM
  assert.doesNotMatch(xml, /<Dial/);
  assert.deepStrictEqual(sent, [{ to: '+15550003333', body: 'after hours message' }]);
});

test('call during hours: rings your cell, no text yet', async () => {
  const { xml, sent } = await callAt('2026-11-10T17:00:00Z'); // Tue noon
  assert.match(xml, /<Dial/);
  assert.strictEqual(sent.length, 0);
});
