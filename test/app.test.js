const { test } = require('node:test');
const assert = require('node:assert');
const { createApp } = require('../app');

const config = {
  forwardTo: '+15557654321',
  ringTimeoutSeconds: 20,
  cooldownHours: 12,
  validateRequests: false,
  message: "I'm currently busy and I will get back to you as soon as I can.",
};

async function withServer(fn) {
  const sent = [];
  const app = createApp(config, async (to, body) => sent.push({ to, body }));
  const server = app.listen(0);
  const base = `http://127.0.0.1:${server.address().port}`;
  const post = (path, data) =>
    fetch(base + path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(data),
    }).then((r) => r.text());
  try {
    await fn(post, sent);
  } finally {
    server.close();
  }
}

test('incoming call is forwarded to your cell', () =>
  withServer(async (post) => {
    const xml = await post('/voice', { From: '+15550001111' });
    assert.match(xml, /<Dial[^>]*timeout="20"/);
    assert.match(xml, /<Number>\+15557654321<\/Number>/);
  }));

test('missed call sends the auto-reply text', () =>
  withServer(async (post, sent) => {
    await post('/after-dial', { From: '+15550001111', DialCallStatus: 'no-answer' });
    assert.deepStrictEqual(sent, [{ to: '+15550001111', body: config.message }]);
  }));

test('answered call sends nothing', () =>
  withServer(async (post, sent) => {
    await post('/after-dial', { From: '+15550001111', DialCallStatus: 'completed' });
    assert.strictEqual(sent.length, 0);
  }));

test('repeat calls within the cooldown get only one text', () =>
  withServer(async (post, sent) => {
    await post('/after-dial', { From: '+15550002222', DialCallStatus: 'busy' });
    await post('/after-dial', { From: '+15550002222', DialCallStatus: 'no-answer' });
    assert.strictEqual(sent.length, 1);
  }));

test('blocked caller ID is not texted', () =>
  withServer(async (post, sent) => {
    await post('/after-dial', { From: 'anonymous', DialCallStatus: 'no-answer' });
    assert.strictEqual(sent.length, 0);
  }));
