import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const Q = require(path.join(process.env.CV_OUT, 'quark/CookieUtil.js'));
const C = Q.CookieUtil;

test('parse / get / stringify', () => {
  const s = ' a=1; b = 2 ;; bad; =x; c=x=y; a=3';
  assert.equal(C.stringify(C.parse(s)), 'a=3; b=2; c=x=y');
  assert.equal(C.get(s, 'c'), 'x=y');
  assert.equal(C.get(s, 'zz'), '');
  assert.deepEqual(C.parse(''), []);
});

test('set / strip / merge', () => {
  assert.equal(C.set('a=1; b=2', 'a', '9'), 'a=9; b=2');
  assert.equal(C.set('a=1', '__puus', 'p'), 'a=1; __puus=p');
  assert.equal(C.strip('a=1; __puus=p; b=2', ['__puus']), 'a=1; b=2');
  assert.equal(C.merge('a=1; b=2', 'b=3; c=4'), 'a=1; b=3; c=4');
  assert.equal(C.merge('', 'x=1'), 'x=1');
});

test('parseSetCookies handles attributes, quotes and expiry', () => {
  const now = Date.parse('2026-01-01T00:00:00Z');
  const r = C.parseSetCookies([
    '__puus=abc; Path=/; Domain=.quark.cn; HttpOnly; Secure',
    'q="quoted"; Max-Age=60\r\nold=v; Expires=Wed, 21 Oct 2015 07:28:00 GMT',
    'gone=1; Max-Age=0',
  ], now);
  const m = Object.fromEntries(r.map((p) => [p.name, p.value]));
  assert.deepEqual(m, { __puus: 'abc', q: 'quoted', old: '', gone: '' });
});

test('applySetCookies only merges whitelisted, ignores deletions', () => {
  const now = Date.now();
  const base = '__pus=P; __puus=old; x=1';
  const out = C.applySetCookies(base, ['__puus=new; Path=/', 'x=2', '__pus=; Max-Age=0'], ['__puus', '__pus'], now);
  assert.equal(out, '__pus=P; __puus=new; x=1');
  assert.equal(C.applySetCookies(base, [], [], now), base);
  assert.equal(C.applySetCookies('a=1', ['b=2'], [], now), 'a=1; b=2');
});

test('normalize pasted cookie', () => {
  assert.equal(C.normalize('Cookie: a=1;\n b=2 \r\n'), 'a=1; b=2');
});

test('htmlUnescape', () => {
  assert.equal(Q.htmlUnescape('Tom &amp; Jerry &#39;s &#x4E2D;&lt;b&gt; &quot;x&quot; &unknown;'),
    'Tom & Jerry \'s 中<b> "x" &unknown;');
  assert.equal(Q.htmlUnescape('plain'), 'plain');
  assert.equal(Q.htmlUnescape('&#128512;'), '😀');
});

test('file helpers', () => {
  assert.equal(Q.fileExt('A.Movie.2020.MKV'), 'mkv');
  assert.equal(Q.fileExt('.hidden'), '');
  assert.equal(Q.fileExt('noext'), '');
  assert.equal(Q.baseName('a.b.mp4'), 'a.b');
  assert.ok(Q.isVideoName('x.rmvb'));
  assert.ok(!Q.isVideoName('x.iso'));
  assert.ok(Q.isSubtitleName('x.ASS'));
  assert.ok(Q.isSkippedFolder('@eaDir'));
  assert.ok(Q.isSkippedFolder('.sync'));
  assert.ok(Q.isSkippedFolder('#recycle'));
  assert.ok(!Q.isSkippedFolder('电影'));
  assert.equal(Q.formatSize(0), '0 B');
  assert.equal(Q.formatSize(1536), '1.50 KB');
  assert.equal(Q.formatSize(5 * 1024 ** 3), '5.00 GB');
  assert.equal(Q.formatSize(150 * 1024 ** 2), '150 MB');
});

test('subtitle matching and language', () => {
  assert.ok(Q.subtitleMatches('Movie.2020.mkv', 'Movie.2020.srt'));
  assert.ok(Q.subtitleMatches('Movie.2020.mkv', 'movie.2020.chs.ass'));
  assert.ok(!Q.subtitleMatches('S01E01.mkv', 'S01E010.srt'));
  assert.deepEqual(Q.subtitleLang('Movie', 'Movie.chs.srt'), ['zh-Hans', '简体中文']);
  assert.deepEqual(Q.subtitleLang('Movie', 'Movie.cht.srt'), ['zh-Hant', '繁体中文']);
  assert.deepEqual(Q.subtitleLang('Movie', 'Movie.chs&eng.ass'), ['zh-Hans', '简体中文']);
  assert.deepEqual(Q.subtitleLang('Movie', 'Movie.eng.srt'), ['en', 'English']);
  assert.deepEqual(Q.subtitleLang('Movie', 'Movie.srt'), ['', '外挂字幕']);
  assert.deepEqual(Q.subtitleLang('Movie', 'Movie.简繁.ass'), ['zh', '简繁']);
});
