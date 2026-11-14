import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const P = require(path.join(process.env.CV_OUT, 'media/ProfileBuilder.js'));
const M = require(path.join(process.env.CV_OUT, 'providers/EmbyMapper.js'));

function dec(o) {
  return Object.assign({ name: 'x', hw: false, instances: 1, maxWidth: 0, maxHeight: 0, uhd60: false, uhd30: false,
    fhd60: false, maxChannels: 0, profiles: [] }, o);
}
const probe = JSON.stringify([
  { codec: 'h264', video: true, mime: 'video/avc', decoders: [
    dec({ name: 'sw.avc', maxWidth: 1920, maxHeight: 1088 }),
    dec({ name: 'hw.avc', hw: true, maxWidth: 4096, maxHeight: 2304, uhd60: true })] },
  { codec: 'hevc', video: true, mime: 'video/hevc', decoders: [
    dec({ name: 'hw.hevc', hw: true, maxWidth: 7680, maxHeight: 4320, uhd60: true, profiles: [0, 1, 3, 4] })] },
  { codec: 'av1', video: true, mime: 'video/av01', decoders: [dec({ name: 'sw.av1', maxWidth: 1920, maxHeight: 1080 })] },
  { codec: 'vp9', video: true, mime: 'video/x-vnd.on2.vp9', decoders: [] },
  { codec: 'aac', video: false, mime: 'audio/mp4a-latm', decoders: [dec({ maxChannels: 8 })] },
  { codec: 'eac3', video: false, mime: 'audio/eac3', decoders: [dec({ maxChannels: 6 })] },
  { codec: 'truehd', video: false, mime: 'audio/truehd', decoders: [dec({ maxChannels: 1 })] },
  { codec: 'dts', video: false, mime: '', decoders: [dec({})] },
  { bogus: 1 }, null, { codec: 'flac', decoders: 'nope' }
]);
const caps = P.parseProbeJson(probe);

function opts(o) {
  return Object.assign(new P.ProfileOptions(), o);
}
const condOf = (p, codec, prop) => {
  const cp = p.CodecProfiles.find((c) => c.Type === 'Video' && c.Codec.split(',').includes(codec));
  const c = cp && cp.Conditions.find((x) => x.Property === prop);
  return c ? c.Value : undefined;
};

test('probe parsing is defensive and decoderFor prefers hardware', () => {
  assert.deepEqual(P.parseProbeJson('not json'), []);
  assert.deepEqual(P.parseProbeJson('{"a":1}'), []);
  assert.equal(caps.length, 9);
  assert.equal(caps[8].codec, 'flac');
  assert.equal(caps[8].decoders.length, 0);
  assert.equal(P.pickDecoder(caps, 'h264').name, 'hw.avc');
  assert.equal(P.pickDecoder(caps, 'h265').name, 'hw.hevc');
  assert.equal(P.pickDecoder(caps, 'vp9'), undefined);
  assert.equal(P.hasDecoder(caps, 'vp9'), false);
  assert.equal(P.hasHardware(caps, 'av1'), false);
  assert.equal(P.maxHeightOf(caps, 'h264'), 2304);
  assert.match(P.formatReport(caps, ['dev']), /hevc:\n {4}硬解 · hw\.hevc · 7680x4320/);
});

test('compat profile: h264 + aac/mp3 only, TS HLS', () => {
  const p = P.buildProfile(caps, opts({ codecMode: 'compat', kind: 'jellyfin', maxBitrate: 8000000 }));
  assert.equal(p.MaxStreamingBitrate, 8000000);
  for (const d of p.DirectPlayProfiles.filter((x) => x.Type === 'Video')) {
    assert.equal(d.VideoCodec, 'h264');
    assert.equal(d.AudioCodec, 'aac,mp3');
  }
  const t = p.TranscodingProfiles[0];
  assert.deepEqual([t.Container, t.VideoCodec, t.AudioCodec, t.Protocol], ['ts', 'h264', 'aac', 'hls']);
  assert.ok(!JSON.stringify(p).includes('hevc'));
});

test('auto profile (jellyfin): probed codecs, decoder limits, HDR, fMP4 HLS copy list', () => {
  const p = P.buildProfile(caps, opts({ kind: 'jellyfin' }));
  assert.equal(p.MaxStreamingBitrate, 200000000);
  const mkv = p.DirectPlayProfiles.find((d) => d.Container === 'mkv,webm');
  assert.equal(mkv.VideoCodec, 'h264,hevc,h265,av1');
  assert.equal(mkv.AudioCodec, 'mp3,aac,eac3,dts,dca,truehd');
  for (const c of P.CONTAINER_FAMILIES) assert.ok(p.DirectPlayProfiles.some((d) => d.Container === c), c);
  assert.equal(condOf(p, 'hevc', 'Height'), '4320');
  assert.equal(condOf(p, 'hevc', 'VideoBitDepth'), '10');
  assert.match(condOf(p, 'hevc', 'VideoRangeType'), /HDR10\|HDR10Plus\|HLG\|DOVIWithHDR10/);
  assert.ok(!condOf(p, 'hevc', 'VideoRangeType').split('|').includes('DOVI'));
  assert.equal(condOf(p, 'h264', 'Height'), '2304');
  assert.equal(condOf(p, 'av1', 'Height'), '1080');
  assert.equal(condOf(p, 'av1', 'VideoRangeType'), 'SDR');  // software decoder: no HDR
  const ch = (c) => p.CodecProfiles.find((x) => x.Type === 'VideoAudio' && x.Codec.split(',').includes(c))
    .Conditions[0].Value;
  assert.equal(ch('eac3'), '6');
  assert.equal(ch('truehd'), '8');  // bogus range -> default
  const [fm, ts] = p.TranscodingProfiles;
  assert.deepEqual([fm.Container, fm.VideoCodec, fm.AudioCodec, fm.Protocol], ['mp4', 'h264,hevc,h265,av1', 'aac,eac3', 'hls']);
  assert.deepEqual([ts.Container, ts.VideoCodec], ['ts', 'h264']);
  assert.ok(p.TranscodingProfiles.some((t) => t.Type === 'Audio'));
  assert.ok(p.SubtitleProfiles.some((s) => s.Format === 'ass' && s.Method === 'External'));
  assert.ok(p.SubtitleProfiles.some((s) => s.Format === 'srt' && s.Method === 'Embed' && s.Container === 'mkv'));
  assert.ok(p.SubtitleProfiles.some((s) => s.Format === 'pgssub' && s.Method === 'Encode'));
});

test('auto profile (emby): TS HLS, no VideoRangeType; preferRemux=false lists only h264', () => {
  const p = P.buildProfile(caps, opts({ kind: 'emby' }));
  const t = p.TranscodingProfiles[0];
  assert.deepEqual([t.Container, t.VideoCodec, t.AudioCodec], ['ts', 'h264,hevc,h265', 'aac,eac3']);
  assert.equal(condOf(p, 'hevc', 'VideoRangeType'), undefined);
  const q = P.buildProfile(caps, opts({ kind: 'emby', preferRemux: false }));
  assert.equal(q.TranscodingProfiles[0].VideoCodec, 'h264');
  const empty = P.buildProfile([], opts({ kind: 'emby' }));
  assert.equal(empty.DirectPlayProfiles[0].VideoCodec, 'h264');
  assert.equal(empty.DirectPlayProfiles[0].AudioCodec, 'aac,mp3');
});

test('delivery mode detection', () => {
  const jf = '/videos/m1/master.m3u8?MediaSourceId=a&VideoCodec=h264,hevc&AudioCodec=aac&SegmentContainer=mp4' +
    '&TranscodeReasons=ContainerNotSupported,AudioCodecNotSupported';
  const rs = P.transcodeReasons(jf, ['ContainerNotSupported']);
  assert.deepEqual(rs, ['ContainerNotSupported', 'AudioCodecNotSupported']);
  assert.equal(P.detectDelivery(jf, true, 'hevc', rs), 'remux');
  assert.equal(P.detectDelivery(jf, true, 'av1', rs), 'transcode');
  assert.equal(P.detectDelivery(jf, false, 'hevc', []), 'direct');
  assert.equal(P.detectDelivery(jf + '&SubtitleMethod=Encode', true, 'hevc', rs), 'transcode');
  const vr = P.transcodeReasons(jf.replace('AudioCodecNotSupported', 'VideoRangeTypeNotSupported'), []);
  assert.equal(P.detectDelivery(jf, true, 'hevc', vr), 'transcode');
  assert.equal(P.detectDelivery('/x/master.m3u8?VideoCodec=copy', true, '', []), 'remux');
  assert.equal(P.detectDelivery('/x/stream.mkv?Static=true', true, 'hevc', []), 'direct');
  assert.equal(P.detectDelivery('/x/master.m3u8?VideoCodec=h264', true, 'h264', []), 'remux');
  assert.equal(P.urlBitrate('/a?VideoBitrate=7808000&AudioBitrate=192000'), 8000000);
  assert.equal(P.rangeLabel('DOVIWithHDR10', 'HDR', '', ''), 'DOVI');
  assert.equal(P.rangeLabel('', 'HDR', 'arib-std-b67', ''), 'HLG');
  assert.equal(P.rangeLabel('', 'HDR', '', 'Hdr10Plus'), 'HDR10');
  assert.equal(P.rangeLabel('', 'SDR', 'bt709', ''), 'SDR');
});

test('mapPlayback fills stream info', () => {
  const ctx = M.makeContext('s', 'http://nas:8096', 'TOK', 'u1', 'dev1');
  const streams = [
    { Index: 0, Type: 'Video', Codec: 'hevc', Width: 3840, Height: 2160, VideoRangeType: 'HDR10' },
    { Index: 1, Type: 'Audio', Codec: 'truehd', IsDefault: true },
    { Index: 2, Type: 'Audio', Codec: 'ac3' }];
  const res = { PlaySessionId: 'p', MediaSources: [{ Id: 'ms', Bitrate: 60000000, SupportsDirectPlay: false,
    SupportsDirectStream: false, MediaStreams: streams, TranscodingSubProtocol: 'hls',
    TranscodingUrl: '/videos/m1/master.m3u8?VideoCodec=h264,hevc&AudioCodec=aac&VideoBitrate=1000&AudioBitrate=10' +
      '&TranscodeReasons=ContainerNotSupported,AudioCodecNotSupported' }] };
  const info = M.mapPlayback(ctx, 'm1', res, '', 0);
  assert.equal(info.deliveryMode, 'remux');
  assert.deepEqual([info.videoCodec, info.audioCodec, info.videoWidth, info.videoHeight, info.videoRange],
    ['hevc', 'truehd', 3840, 2160, 'HDR10']);
  assert.equal(info.bitrate, 60000000);
  assert.deepEqual(info.transcodeReasons, ['ContainerNotSupported', 'AudioCodecNotSupported']);
  M.applyStreamInfo(info, res.MediaSources[0], 2);
  assert.equal(info.audioCodec, 'ac3');
  const d = M.mapPlayback(ctx, 'm1', { MediaSources: [{ Id: 'ms', SupportsDirectPlay: true, MediaStreams: streams,
    Bitrate: 5 }] }, '', 0);
  assert.equal(d.deliveryMode, 'direct');
  assert.deepEqual(d.transcodeReasons, []);
  assert.equal(d.bitrate, 5);
});
