import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const L = require(path.join(process.env.CV_OUT, 'components/settings/CodecInfoLogic.js'));

function dec(o) {
  return Object.assign({ name: 'x', hw: false, instances: 0, maxWidth: 0, maxHeight: 0, uhd60: false, uhd30: false,
    fhd60: false, maxChannels: 0, profiles: [] }, o);
}
function entry(codec, video, decoders) {
  return { codec, video, mime: '', decoders };
}

const entries = [
  entry('hevc', true, [dec({ name: 'OMX.sw.hevc', maxWidth: 1920, maxHeight: 1080 }),
    dec({ name: 'OMX.hisi.hevc', hw: true, maxWidth: 4096, maxHeight: 2304, uhd60: true, uhd30: true, instances: 8 })]),
  entry('h264', true, [dec({ name: 'avc.hw', hw: true, maxWidth: 3840, maxHeight: 2160, uhd30: true })]),
  entry('av1', true, [dec({ name: 'av1.sw', maxWidth: 1920, maxHeight: 1080, fhd60: true })]),
  entry('ac3', false, [dec({ name: 'ac3.sw', maxChannels: 6 })]),
  entry('eac3', false, [dec({ name: 'eac3.sw', maxChannels: 8 })]),
  entry('aac', false, [])
];

test('bestDecoder prefers hardware', () => {
  assert.equal(L.bestDecoder(L.findEntry(entries, 'hevc')).name, 'OMX.hisi.hevc');
  assert.equal(L.bestDecoder(L.findEntry(entries, 'aac')), undefined);
  assert.equal(L.bestDecoder(undefined), undefined);
  assert.equal(L.statusOf(L.findEntry(entries, 'av1')), L.STATUS_SW);
  assert.equal(L.statusOf(L.findEntry(entries, 'vvc')), L.STATUS_NONE);
});

test('resolutionLabel', () => {
  assert.equal(L.resolutionLabel(4096, 2304), '4K');
  assert.equal(L.resolutionLabel(1920, 1080), '1080p');
  assert.equal(L.resolutionLabel(7680, 4320), '8K');
  assert.equal(L.resolutionLabel(0, 0), '');
  assert.equal(L.resolutionLabel(720, 480), '480p');
});

test('rows', () => {
  const v = L.buildRows(entries, true);
  assert.equal(v.length, L.VIDEO_CODECS.length);
  const hevc = v.find((r) => r.codec === 'hevc');
  assert.equal(hevc.label, 'H.265/HEVC');
  assert.equal(hevc.status, 'hw');
  assert.equal(hevc.decoderName, 'OMX.hisi.hevc');
  assert.ok(hevc.details.includes('4K60 ✓'));
  assert.ok(hevc.details.includes('可同时 8 路'));
  assert.ok(hevc.details.some((d) => d.includes('备用')));
  const h264 = v.find((r) => r.codec === 'h264');
  assert.ok(h264.details.includes('4K30 ✓ · 4K60 ✗'));
  assert.equal(v.find((r) => r.codec === 'vc1').status, 'none');
  const a = L.buildRows(entries, false);
  assert.equal(a.find((r) => r.codec === 'aac').status, 'none');
  assert.deepEqual(a.find((r) => r.codec === 'eac3').details, ['最多 8 声道']);
  assert.equal(L.groupCount(v), '支持 3/13 · 硬解 2');
});

test('summary chips', () => {
  const c = L.summaryChips(entries);
  assert.equal(c[0].text, '硬解 H.265 · 4K60');
  assert.equal(c[1].text, '硬解 H.264 · 4K30');
  assert.equal(c[2].text, '软解 AV1 · 1080p');
  assert.ok(!c.some((x) => x.text.includes('H.266')));
  assert.equal(c.find((x) => x.text.includes('VP9')).text, 'VP9 不支持');
  assert.equal(c[c.length - 1].text, '杜比/DTS 音频：AC-3/E-AC-3');
  assert.equal(L.summaryChips([]).length, 1);
});

test('codec mode', () => {
  assert.equal(L.CODEC_MODE_OPTIONS[L.codecModeIndex('compat')].value, 'compat');
  assert.equal(L.codecModeIndex('auto'), 0);
  assert.equal(L.codecModeIndex('bogus'), 0);
  assert.equal(L.statusText('sw'), '软件解码');
  assert.equal(L.codecLabel('eac3'), 'E-AC-3 (杜比数字+)');
});
