import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const L = require(path.join(process.env.CV_OUT, 'player/PlayerLogic.js'));

test('server fallback: direct -> remux -> transcode -> none', () => {
  let s = L.decideFallback('direct', [], -1, ['direct']);
  assert.equal(s.action, 'remux');
  assert.equal(s.banner, '直接播放失败，已切换为服务器转封装');
  s = L.decideFallback('remux', [], -1, ['direct', 'remux']);
  assert.equal(s.action, 'transcode');
  assert.equal(s.banner, '已切换为服务器转码');
  assert.equal(L.decideFallback('transcode', [], -1, ['direct', 'remux', 'transcode']).action, 'none');
  // already remux at start: straight to transcode
  assert.equal(L.decideFallback('remux', [], -1, ['remux']).action, 'transcode');
  // server ignored forceMode and returned direct again: remux already tried -> transcode, never loops
  assert.equal(L.decideFallback('direct', [], -1, ['direct', 'remux']).action, 'transcode');
  assert.equal(L.decideFallback('direct', [], -1, ['direct', 'remux', 'transcode']).action, 'none');
  assert.equal(L.decideFallback('transcode', [], -1, ['transcode']).action, 'none');
});

test('quark fallback: original -> best untried transcode only', () => {
  const labels = ['原画', '4K', '超清 1080P', '高清 720P'];
  let s = L.decideFallback('direct', labels, 0, ['q:0']);
  assert.equal(s.action, 'quality');
  assert.equal(s.qualityIndex, 1);
  assert.equal(s.key, 'q:1');
  assert.ok(s.banner.indexOf('4K') >= 0);
  s = L.decideFallback('direct', labels, 0, ['q:0', 'q:1']);
  assert.equal(s.qualityIndex, 2);
  // a failing transcode is not chained further
  assert.equal(L.decideFallback('direct', labels, 1, ['q:0', 'q:1']).action, 'none');
  // only the original available
  assert.equal(L.decideFallback('direct', ['原画'], 0, ['q:0']).action, 'none');
  // attempt cap
  assert.equal(L.decideFallback('direct', labels, 0, ['a', 'b', 'c']).action, 'none');
});

test('super resolution helpers', () => {
  assert.ok(L.wantSuperResolution(1280, 720));
  assert.ok(!L.wantSuperResolution(1920, 1080));
  assert.ok(!L.wantSuperResolution(3840, 2160));
  assert.ok(L.wantSuperResolution(720, 1280));
  assert.ok(!L.wantSuperResolution(0, 0));
  let b = L.srWindowSize(2400, 1080);
  assert.ok(b.width <= 1920 && b.height <= 1080);
  assert.ok(Math.abs(b.width / b.height - 2400 / 1080) < 0.01);
  b = L.srWindowSize(200, 100);
  assert.equal(b.width, 320); assert.equal(b.height, 320);
  assert.equal(L.srWindowSize(0, 500).width, 0);
});

test('codec name / mime mapping', () => {
  assert.equal(L.normCodec('H265'), 'hevc');
  assert.equal(L.normCodec('avc'), 'h264');
  assert.equal(L.normCodec('dca'), 'dts');
  assert.equal(L.normCodec('pcm_s24le'), 'pcm');
  assert.equal(L.normCodec('eac3'), 'eac3');
  const probe = [new L.CodecMime('av1', 'video/av1-custom')];
  assert.equal(L.mimeToCodec('video/av1-custom', probe), 'av1');
  assert.equal(L.mimeToCodec('video/avc', []), 'h264');
  assert.equal(L.mimeToCodec('video/hevc', []), 'hevc');
  assert.equal(L.mimeToCodec('video/mp4v-es', []), 'mpeg4');
  assert.equal(L.mimeToCodec('video/av01', []), 'av1');
  assert.equal(L.mimeToCodec('video/x-vnd.on2.vp9', []), 'vp9');
  assert.equal(L.mimeToCodec('video/x-vnd.on2.vp8', []), 'vp8');
  assert.equal(L.mimeToCodec('audio/eac3', []), 'eac3');
  assert.equal(L.mimeToCodec('audio/ac3', []), 'ac3');
  assert.equal(L.mimeToCodec('audio/mp4a-latm', []), 'aac');
  assert.equal(L.mimeToCodec('audio/mpeg', []), 'mp3');
  assert.equal(L.mimeToCodec('audio/vnd.dts', []), 'dts');
  assert.equal(L.mimeToCodec('', []), '');
  assert.equal(L.mimeToCodec('application/x-foo', []), '');
});

test('info rows', () => {
  const s = new L.StatsInput();
  s.deliveryMode = 'transcode';
  s.transcodeReasons = ['VideoCodecNotSupported'];
  s.videoCodec = 'hevc';
  s.videoWidth = 3840; s.videoHeight = 2160; s.videoRange = 'HDR10';
  s.videoDecoder.codec = 'h264'; s.videoDecoder.known = true; s.videoDecoder.hw = true; s.videoDecoder.name = 'OMX.hisi.avc';
  s.audioDecoder.codec = 'aac'; s.audioDecoder.known = true; s.audioDecoder.name = 'OH.Media.Codec.Decoder.Audio.AAC';
  const t = new L.TrackStat(); t.type = 1; t.mime = 'video/avc'; t.width = 1920; t.height = 1080; t.frameRate = 23.976; t.hdrType = '1';
  s.tracks = [t];
  s.superRes = 'unavailable';
  s.downloadRate = 12500000; s.bufferSec = 8.25;
  const rows = L.buildInfoRows(s);
  const get = (k) => (rows.find((r) => r.label === k) ?? { value: undefined }).value;
  assert.equal(get('播放方式'), '转码');
  assert.equal(get('转码原因'), 'VideoCodecNotSupported');
  assert.equal(get('视频解码'), '硬件解码 (OMX.hisi.avc)');
  assert.equal(get('音频解码'), '软件解码 (OH.Media.Codec.Decoder.Audio.AAC)');
  assert.ok(get('视频轨').indexOf('23.98 fps') >= 0 && get('视频轨').indexOf('HDR Vivid') >= 0);
  assert.equal(get('超分辨率'), '超分不可用');
  assert.equal(get('下载速度'), '12.5 Mbps');
  assert.equal(get('缓冲时长'), '8.3 秒');
  assert.ok(get('片源画面').indexOf('3840×2160') >= 0);
  assert.equal(L.deliveryLabel('remux'), '转封装');
  assert.equal(L.hdrTypeLabel('0'), '');
  assert.equal(L.formatRate(-1), '—');
});
