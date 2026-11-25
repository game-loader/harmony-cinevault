import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { AppLog, redact } = require(path.join(process.env.CV_OUT, 'common/AppLog.js'));

test('copied logs hide signed URL queries and long tokens but keep hosts and error text', () => {
  const signed = 'https://s.fli.cx/s/ENPm0UODfb8OafM0VA8H4NiiDFE03dJpflViwqive.m3u8';
  assert.equal(redact('open ' + signed), 'open https://s.fli.cx/s/ENPm0U….m3u8');
  assert.equal(redact('GET https://emby.local/Videos/1/stream?api_key=secret&x=1 ok'),
    'GET https://emby.local/Videos/1/stream?… ok');
  assert.equal(redact('[Player] AVPlayer error 5400102 Operate Not Permit'), '[Player] AVPlayer error 5400102 Operate Not Permit');
});

test('log keeps order and levels, notifies listeners, caps its size, and clears', () => {
  const quiet = { info: console.info, warn: console.warn, error: console.error };
  console.info = console.warn = console.error = () => {};
  try {
    AppLog.clear();
    let calls = 0;
    const off = AppLog.onChange(() => { calls++; });
    AppLog.info('a');
    AppLog.warn('b');
    AppLog.error('c');
    assert.deepEqual(AppLog.all().map(l => l.level + l.text), ['Ia', 'Wb', 'Ec']);
    assert.equal(calls, 3);
    off();
    AppLog.info('d');
    assert.equal(calls, 3);
    assert.match(AppLog.dump(['header']), /^header\n\d\d-\d\d \d\d:\d\d:\d\d\.\d{3} I a\n/);
    for (let i = 0; i < 2000; i++) AppLog.info('x' + i);
    assert.equal(AppLog.all().length, 1500);
    assert.equal(AppLog.all().at(-1).text, 'x1999');
    AppLog.clear();
    assert.equal(AppLog.all().length, 0);
  } finally {
    Object.assign(console, quiet);
  }
});
