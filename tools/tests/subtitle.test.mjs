import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const S = require(path.join(process.env.CV_OUT, 'player/SubtitleParser.js'));

test('parseTimestamp variants', () => {
  assert.equal(S.parseTimestamp('00:01:02,345'), 62345);
  assert.equal(S.parseTimestamp('01:02.500'), 62500);
  assert.equal(S.parseTimestamp('1:00:00.50'), 3600500);
  assert.equal(S.parseTimestamp('0:00:01.5'), 1500);
  assert.equal(S.parseTimestamp('bad'), -1);
});

test('SRT with BOM, CRLF, tags, multi-line', () => {
  const srt = '﻿1\r\n00:00:01,000 --> 00:00:02,500\r\n<i>Hello</i>\r\n<font color="red">world</font>\r\n\r\n' +
    '2\r\n00:00:03,000 --> 00:00:04,000\r\nA &amp; B\r\n';
  const c = S.parseSrt(srt);
  assert.equal(c.length, 2);
  assert.equal(c[0].startMs, 1000);
  assert.equal(c[0].endMs, 2500);
  assert.equal(c[0].text, 'Hello\nworld');
  assert.equal(c[1].text, 'A & B');
});

test('WebVTT with header, NOTE, STYLE, cue ids and settings', () => {
  const vtt = 'WEBVTT - title\n\nSTYLE\n::cue { color: red }\n\nNOTE a comment\n\nintro\n00:01.000 --> 00:02.000 align:center line:90%\n' +
    '<v Bob>Hi <c.yellow>there</c></v>\n\n00:00:05.000 --> 00:00:06.000\nSecond';
  const c = S.parseVtt(vtt);
  assert.equal(c.length, 2);
  assert.equal(c[0].startMs, 1000);
  assert.equal(c[0].text, 'Hi there');
  assert.equal(c[1].startMs, 5000);
  assert.equal(S.detectFormat(vtt, ''), 'vtt');
});

test('ASS dialogue: override tags, \\N, commas in text, custom Format, drawings', () => {
  const ass = '[Script Info]\nTitle: x\n\n[V4+ Styles]\nFormat: Name, Fontname\nStyle: Default,Arial\n\n[Events]\n' +
    'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n' +
    'Dialogue: 0,0:00:02.00,0:00:04.50,Default,,0,0,0,,{\\an8\\fs20}你好，世界\\N{\\i1}second, line{\\i0}\n' +
    'Dialogue: 0,0:00:01.00,0:00:01.50,Default,,0,0,0,,{\\p1}m 0 0 l 100 0{\\p0}\n' +
    'Comment: 0,0:00:01.00,0:00:09.00,Default,,0,0,0,,ignored\n' +
    'Dialogue: 1,0:00:02.00,0:00:04.50,Default,,0,0,0,,English\\hline\n';
  const c = S.parseAss(ass);
  assert.equal(c.length, 1);
  assert.equal(c[0].startMs, 2000);
  assert.equal(c[0].endMs, 4500);
  assert.equal(c[0].text, '你好，世界\nsecond, line\nEnglish line');
  assert.equal(S.detectFormat(ass, ''), 'ass');
});

test('ASS with SSA v4 Format order', () => {
  const ssa = '[Events]\nFormat: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n' +
    'Dialogue: Marked=0,0:00:10.00,0:00:11.00,*Default,NTP,0000,0000,0000,!Effect,Old style\n';
  const c = S.parseAss(ssa);
  assert.equal(c.length, 1);
  assert.equal(c[0].startMs, 10000);
  assert.equal(c[0].text, 'Old style');
});

test('parseSubtitle hint and sniffing; cueTextAt', () => {
  const srt = '1\n00:00:01,000 --> 00:00:05,000\nlong\n\n2\n00:00:02,000 --> 00:00:03,000\nshort\n';
  const c = S.parseSubtitle(srt, 'https://x/sub.srt');
  assert.equal(c.length, 2);
  assert.equal(S.cueTextAt(c, 500), '');
  assert.equal(S.cueTextAt(c, 1500), 'long');
  assert.equal(S.cueTextAt(c, 2500), 'long\nshort');
  assert.equal(S.cueTextAt(c, 5000), '');
  assert.equal(S.cueTextAt([], 10), '');
  assert.equal(S.detectFormat('garbage', 'subrip'), 'srt');
});

test('formatDuration', () => {
  assert.equal(S.formatDuration(0), '00:00');
  assert.equal(S.formatDuration(65000), '01:05');
  assert.equal(S.formatDuration(3723000), '1:02:03');
});

const L = require(path.join(process.env.CV_OUT, 'player/PlayerLogic.js'));

test('computeVideoBox modes', () => {
  let b = L.computeVideoBox('fit', 1600, 900, 1920, 800);
  assert.equal(b.width, 1600); assert.ok(Math.abs(b.height - 666.67) < 0.1);
  b = L.computeVideoBox('fill', 1600, 900, 1920, 800);
  assert.equal(b.height, 900);
  b = L.computeVideoBox('crop', 1600, 900, 1920, 800);
  assert.equal(b.height, 900); assert.ok(b.width > 1600);
  b = L.computeVideoBox('4:3', 1600, 900, 1920, 800);
  assert.equal(b.height, 900); assert.equal(b.width, 1200);
  assert.equal(L.computeVideoBox('fit', 0, 0, 1, 1).width, 0);
});

test('language matching', () => {
  assert.equal(L.langKey('zho'), 'zh');
  assert.ok(L.langMatches('chi', 'zh-CN', ''));
  assert.ok(L.langMatches('chi', '', '简体中文'));
  assert.ok(!L.langMatches('chi', 'eng', 'English'));
  assert.equal(L.pickByLanguage(['eng', 'und'], ['English', '中文字幕'], 'chi'), 1);
  assert.equal(L.pickByLanguage(['eng'], ['English'], ''), -1);
});

test('resume / queue / countdown', () => {
  assert.equal(L.resolveStartMs(0, 50000, 0), 0);
  assert.equal(L.resolveStartMs(-1, 5000, 0), 0);
  assert.equal(L.resolveStartMs(-1, 50000, 3600000), 50000);
  assert.equal(L.resolveStartMs(-1, 3595000, 3600000), 0);
  assert.equal(L.nextInQueue(['a', 'b'], 'a'), 'b');
  assert.equal(L.nextInQueue(['a', 'b'], 'b'), '');
  assert.equal(L.prevInQueue(['a', 'b'], 'b'), 'a');
  assert.equal(L.nextCountdown(95500, 100000, 5000), 5);
  assert.equal(L.nextCountdown(50000, 100000, 5000), -1);
  assert.equal(L.nearestSpeed(1.4), 1.5);
});
