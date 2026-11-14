// Pure: decoder capability model + Emby/Jellyfin DeviceProfile builder. No @kit imports (the native probe is called
// from CodecCaps.ets); unit-tested in tools/tests/profile.test.mjs.
//
// Rules:
// - 'compat': H.264 + AAC/MP3 direct play only; everything else is transcoded to H.264/AAC in HLS-TS.
// - 'auto': every codec with a system decoder is allowed in every container family. Demuxer support is device
//   specific, so failures are handled at runtime (direct -> remux -> transcode).
// - Resolution: Width/Height <= range of the decoder AVPlayer would pick (hardware first). Above 1440p (4K) only when a
//   hardware decoder reports uhd30/uhd60 or a height range >= 2160, or a software decoder reports uhd30/uhd60.
// - Bit depth: AV1 10-bit; HEVC/VP9/VVC 10-bit when the decoder lists a 10-bit profile (or lists none and is hardware);
//   everything else 8-bit.
// - HDR (Jellyfin VideoRangeType, EqualsAny): with a 10-bit hardware decoder HEVC allows SDR, HDR10, HDR10+, HLG and
//   Dolby Vision that carries an HDR10/HLG/SDR base layer (profile 8.x). Pure Dolby Vision (profile 5, no fallback
//   layer), dual-layer DV (DOVIWithEL*) and DOVIInvalid are not allowed, so the server tone-maps them: AVPlayer has no
//   DV decoder and profile 5 would show green/purple colours. AV1/VP9 get SDR/HDR10/HDR10+/HLG. Without a 10-bit
//   hardware decoder: SDR only. The condition is not sent to Emby (its condition enum is not documented publicly;
//   an unknown value could make it reject the profile), so on Emby HDR is limited by bit depth only.
// - HLS (transcode/remux): Jellyfin uses fMP4 segments (Container 'mp4') listing h264,hevc,av1,vp9 so the server
//   stream-copies those; Emby uses TS segments with h264,hevc. The first codec (h264) is the encode target.
//   Audio copy list: aac,mp3,ac3,eac3 (+flac,opus in fMP4); anything else becomes AAC.
import {
  DeviceProfile, DirectPlayProfile, TranscodingProfile, SubtitleProfile, CodecProfile, ProfileCondition,
  DEFAULT_MAX_BITRATE, DIRECT_CONTAINERS
} from '../providers/DeviceProfile';

/** One decoder implementation reported by the system (see cpp/codec_probe.cpp). Re-exported by CodecCaps. */
export class DecoderInfo {
  name: string = '';
  hw: boolean = false;
  instances: number = 0;
  maxWidth: number = 0;     // video only
  maxHeight: number = 0;    // video only
  uhd60: boolean = false;
  uhd30: boolean = false;
  fhd60: boolean = false;
  maxChannels: number = 0;  // audio only
  profiles: number[] = [];
}

/** Probe result for one codec. codec uses Emby/ffmpeg names: h264 hevc vvc av1 vp9 vp8 mpeg2video mpeg4 h263 vc1 wmv3 rv40 mjpeg aac mp3 flac vorbis opus alac ape ac3 eac3 dts truehd wma pcm */
export class CodecEntry {
  codec: string = '';
  video: boolean = false;
  mime: string = '';
  decoders: DecoderInfo[] = [];
}

/** Video codecs in profile order (most common first). */
export const VIDEO_ORDER: string[] = ['h264', 'hevc', 'av1', 'vp9', 'vvc', 'vp8', 'mpeg2video', 'mpeg4', 'vc1', 'wmv3',
  'h263', 'rv40', 'mjpeg'];
export const AUDIO_ORDER: string[] = ['aac', 'mp3', 'ac3', 'eac3', 'flac', 'opus', 'vorbis', 'alac', 'dts', 'truehd',
  'ape', 'wma', 'pcm'];

/** Inputs besides the probed caps. kind: 'emby' | 'jellyfin' (HLS segment container and HDR conditions differ). */
export class ProfileOptions {
  maxBitrate: number = 0;       // bps, 0 = default 200 Mbps
  codecMode: string = 'auto';   // 'auto' | 'compat'
  preferRemux: boolean = true;  // false: HLS lists only h264, so other codecs are re-encoded instead of copied
  kind: string = 'emby';
}

/** Canonical Emby/ffmpeg codec name for aliases seen in server responses and probe output. */
export function normCodec(c: string): string {
  const s = c.trim().toLowerCase();
  switch (s) {
    case 'h265':
    case 'hvc1':
    case 'hev1':
      return 'hevc';
    case 'avc':
    case 'avc1':
      return 'h264';
    case 'h266':
      return 'vvc';
    case 'mpeg2':
      return 'mpeg2video';
    case 'dca':
      return 'dts';
    case 'wmav1':
    case 'wmav2':
    case 'wmapro':
      return 'wma';
    default:
      return s.startsWith('pcm_') ? 'pcm' : s;
  }
}

// ---------- probe JSON parsing ----------

interface RawDecoder {
  name?: string;
  hw?: boolean;
  instances?: number;
  maxWidth?: number;
  maxHeight?: number;
  uhd60?: boolean;
  uhd30?: boolean;
  fhd60?: boolean;
  maxChannels?: number;
  profiles?: number[];
}

interface RawEntry {
  codec?: string;
  video?: boolean;
  mime?: string;
  decoders?: RawDecoder[];
}

function num(v: number | undefined): number {
  return typeof v === 'number' && isFinite(v) && v > 0 ? Math.floor(v) : 0;
}

function bool(v: boolean | undefined): boolean {
  return v === true;
}

function str(v: string | undefined): string {
  return typeof v === 'string' ? v : '';
}

function parseDecoder(r: RawDecoder): DecoderInfo {
  const d = new DecoderInfo();
  d.name = str(r.name);
  d.hw = bool(r.hw);
  d.instances = num(r.instances);
  d.maxWidth = num(r.maxWidth);
  d.maxHeight = num(r.maxHeight);
  d.uhd60 = bool(r.uhd60);
  d.uhd30 = bool(r.uhd30);
  d.fhd60 = bool(r.fhd60);
  d.maxChannels = num(r.maxChannels);
  const ps = r.profiles;
  if (Array.isArray(ps)) {
    d.profiles = ps.filter((p: number) => typeof p === 'number' && isFinite(p));
  }
  return d;
}

/** Defensive parse of nativeProbeJson(); malformed input or entries are dropped, never thrown. */
export function parseProbeJson(json: string): CodecEntry[] {
  let parsed: RawEntry[] = [];
  try {
    parsed = JSON.parse(json) as RawEntry[];
  } catch (e) {
    return [];
  }
  if (!Array.isArray(parsed)) {
    return [];
  }
  const out: CodecEntry[] = [];
  parsed.forEach((r: RawEntry) => {
    if (r === null || typeof r !== 'object' || typeof r.codec !== 'string' || r.codec.length === 0) {
      return;
    }
    const e = new CodecEntry();
    e.codec = normCodec(r.codec);
    e.video = bool(r.video);
    e.mime = str(r.mime);
    const ds = r.decoders;
    if (Array.isArray(ds)) {
      ds.forEach((d: RawDecoder) => {
        if (d !== null && typeof d === 'object') {
          e.decoders.push(parseDecoder(d));
        }
      });
    }
    out.push(e);
  });
  return out;
}

// ---------- capability queries (pure; CodecCaps wraps these around the cached probe) ----------

export function findEntry(entries: CodecEntry[], codec: string): CodecEntry | undefined {
  const c = normCodec(codec);
  return entries.find((e: CodecEntry) => e.codec === c);
}

export function hasDecoder(entries: CodecEntry[], codec: string): boolean {
  const e = findEntry(entries, codec);
  return e !== undefined && e.decoders.length > 0;
}

export function hasHardware(entries: CodecEntry[], codec: string): boolean {
  const e = findEntry(entries, codec);
  return e !== undefined && e.decoders.some((d: DecoderInfo) => d.hw);
}

function area(d: DecoderInfo): number {
  return d.maxWidth * d.maxHeight;
}

/** Decoder AVPlayer would use: hardware first (largest supported size among them), else the best software one. */
export function pickDecoder(entries: CodecEntry[], codec: string): DecoderInfo | undefined {
  const e = findEntry(entries, codec);
  if (e === undefined || e.decoders.length === 0) {
    return undefined;
  }
  const hw = e.decoders.filter((d: DecoderInfo) => d.hw);
  const pool = hw.length > 0 ? hw : e.decoders;
  let best = pool[0];
  pool.forEach((d: DecoderInfo) => {
    if (area(d) > area(best)) {
      best = d;
    }
  });
  return best;
}

export function maxHeightOf(entries: CodecEntry[], codec: string): number {
  const e = findEntry(entries, codec);
  if (e === undefined) {
    return 0;
  }
  let h = 0;
  e.decoders.forEach((d: DecoderInfo) => {
    h = Math.max(h, d.maxHeight);
  });
  return h;
}

/** Height cap for the profile: decoder range; 1080 when the range is unknown unless uhd flags say 4K works. */
export function heightCap(d: DecoderInfo): number {
  if (d.maxHeight > 0) {
    return d.maxHeight;
  }
  return d.uhd30 || d.uhd60 ? 2160 : 1080;
}

export function widthCap(d: DecoderInfo): number {
  if (d.maxWidth > 0) {
    return d.maxWidth;
  }
  return d.uhd30 || d.uhd60 ? 4096 : 1920;
}

// OH_HEVCProfile: MAIN_10 = 1, MAIN_10_HDR10 = 3, MAIN_10_HDR10_PLUS = 4. OH_VP9Profile: 2/3 = 10/12-bit.
const HEVC_10BIT_PROFILES: number[] = [1, 3, 4];
const VP9_10BIT_PROFILES: number[] = [2, 3];

/** Highest bit depth the chosen decoder handles (8 or 10). */
export function bitDepthOf(codec: string, d: DecoderInfo): number {
  const c = normCodec(codec);
  if (c === 'av1' || c === 'vvc') {
    return 10;
  }
  if (c === 'hevc') {
    if (d.profiles.length === 0) {
      return d.hw ? 10 : 8;
    }
    return d.profiles.some((p: number) => HEVC_10BIT_PROFILES.indexOf(p) >= 0) ? 10 : 8;
  }
  if (c === 'vp9') {
    return d.profiles.some((p: number) => VP9_10BIT_PROFILES.indexOf(p) >= 0) ? 10 : 8;
  }
  return 8;
}

/** Jellyfin VideoRangeType values allowed for a codec (see header comment for the rule). */
export function rangeTypesFor(codec: string, d: DecoderInfo): string {
  const c = normCodec(codec);
  const hdr = d.hw && bitDepthOf(c, d) >= 10;
  if (c === 'hevc' && hdr) {
    return 'SDR|HDR10|HDR10Plus|HLG|DOVIWithHDR10|DOVIWithHLG|DOVIWithSDR|DOVIWithHDR10Plus';
  }
  if ((c === 'av1' || c === 'vp9') && hdr) {
    return 'SDR|HDR10|HDR10Plus|HLG';
  }
  return 'SDR';
}

// ---------- DeviceProfile ----------

/** Names servers use for a probed codec (Emby/Jellyfin report ffmpeg codec names). */
export function serverNames(codec: string): string[] {
  switch (codec) {
    case 'hevc': return ['hevc', 'h265'];
    case 'dts': return ['dts', 'dca'];
    case 'pcm': return ['pcm_s16le', 'pcm_s24le', 'pcm_s16be', 'pcm_s24be'];
    case 'wma': return ['wmapro'];
    default: return [codec];
  }
}

function joinNames(codecs: string[]): string {
  const out: string[] = [];
  codecs.forEach((c: string) => {
    serverNames(c).forEach((n: string) => {
      if (out.indexOf(n) < 0) {
        out.push(n);
      }
    });
  });
  return out.join(',');
}

export const CONTAINER_FAMILIES: string[] = ['mp4,m4v,mov', 'mkv,webm', 'ts,m2ts,mpegts', 'flv', 'avi', 'wmv,asf',
  'rmvb,rm'];

const COMPAT_VIDEO: string[] = ['h264'];
const COMPAT_AUDIO: string[] = ['aac', 'mp3'];

/** Probed video codecs in profile order; h264 is assumed when the probe returned nothing (stub / failed native lib). */
export function videoCodecs(entries: CodecEntry[]): string[] {
  const out = VIDEO_ORDER.filter((c: string) => hasDecoder(entries, c));
  if (out.indexOf('h264') < 0) {
    out.unshift('h264');
  }
  return out;
}

/** Probed audio codecs in profile order; aac/mp3 are assumed. */
export function audioCodecs(entries: CodecEntry[]): string[] {
  const out = AUDIO_ORDER.filter((c: string) => hasDecoder(entries, c));
  ['mp3', 'aac'].forEach((c: string) => {
    if (out.indexOf(c) < 0) {
      out.unshift(c);
    }
  });
  return out;
}

function directVideo(container: string, video: string, audio: string): DirectPlayProfile {
  const p = new DirectPlayProfile();
  p.Container = container;
  p.Type = 'Video';
  p.VideoCodec = video;
  p.AudioCodec = audio;
  return p;
}

function sub(format: string, method: string, container: string): SubtitleProfile {
  const s = new SubtitleProfile();
  s.Format = format;
  s.Method = method;
  if (container.length > 0) {
    s.Container = container;
  }
  return s;
}

function cond(condition: string, property: string, value: string): ProfileCondition {
  const c = new ProfileCondition();
  c.Condition = condition;
  c.Property = property;
  c.Value = value;
  c.IsRequired = false;
  return c;
}

function hls(container: string, video: string[], audio: string[], channels: string): TranscodingProfile {
  const t = new TranscodingProfile();
  t.Container = container;
  t.Type = 'Video';
  t.VideoCodec = joinNames(video);
  t.AudioCodec = joinNames(audio);
  t.Protocol = 'hls';
  t.Context = 'Streaming';
  t.MaxAudioChannels = channels;
  t.MinSegments = 1;
  t.BreakOnNonKeyFrames = true;
  return t;
}

function audioTranscode(): TranscodingProfile {
  const t = new TranscodingProfile();
  t.Type = 'Audio';
  t.Container = 'aac';
  t.VideoCodec = '';
  t.AudioCodec = 'aac';
  t.Protocol = 'http';
  t.MaxAudioChannels = '2';
  return t;
}

function h264Profile(entries: CodecEntry[], withSize: boolean): CodecProfile {
  const p = new CodecProfile();
  p.Codec = 'h264';
  p.Conditions.push(cond('NotEquals', 'IsAnamorphic', 'true'));
  p.Conditions.push(cond('LessThanEqual', 'VideoBitDepth', '8'));
  p.Conditions.push(cond('LessThanEqual', 'VideoLevel', '52'));
  const d = pickDecoder(entries, 'h264');
  if (withSize && d !== undefined) {
    p.Conditions.push(cond('LessThanEqual', 'Width', String(widthCap(d))));
    p.Conditions.push(cond('LessThanEqual', 'Height', String(heightCap(d))));
  }
  return p;
}

function videoCodecProfile(entries: CodecEntry[], codec: string, jellyfin: boolean): CodecProfile | undefined {
  const d = pickDecoder(entries, codec);
  if (d === undefined) {
    return undefined;
  }
  const p = new CodecProfile();
  p.Codec = joinNames([codec]);
  p.Conditions.push(cond('LessThanEqual', 'Width', String(widthCap(d))));
  p.Conditions.push(cond('LessThanEqual', 'Height', String(heightCap(d))));
  p.Conditions.push(cond('LessThanEqual', 'VideoBitDepth', String(bitDepthOf(codec, d))));
  if (jellyfin) {
    p.Conditions.push(cond('EqualsAny', 'VideoRangeType', rangeTypesFor(codec, d)));
  }
  return p;
}

/** Channel limit for one audio codec: decoder range when reported (>= 2), else 8. */
export function channelsFor(entries: CodecEntry[], codec: string): number {
  const d = pickDecoder(entries, codec);
  if (d === undefined || d.maxChannels < 2) {
    return 8;
  }
  return Math.min(d.maxChannels, 8);
}

/** Codecs AVPlayer is expected to take inside HLS segments, which lets the server stream-copy them. */
export function hlsVideoCodecs(entries: CodecEntry[], fmp4: boolean, preferRemux: boolean): string[] {
  const out: string[] = ['h264'];
  if (!preferRemux) {
    return out;
  }
  const extra = fmp4 ? ['hevc', 'av1', 'vp9'] : ['hevc'];
  extra.forEach((c: string) => {
    if (hasDecoder(entries, c)) {
      out.push(c);
    }
  });
  return out;
}

export function hlsAudioCodecs(entries: CodecEntry[], fmp4: boolean): string[] {
  const out: string[] = ['aac'];
  const extra = fmp4 ? ['mp3', 'ac3', 'eac3', 'flac', 'opus'] : ['mp3', 'ac3', 'eac3'];
  extra.forEach((c: string) => {
    if (hasDecoder(entries, c)) {
      out.push(c);
    }
  });
  return out;
}

function addCommon(p: DeviceProfile): void {
  const audioOnly = new DirectPlayProfile();
  audioOnly.Container = 'mp3,aac,m4a,flac,ogg';
  audioOnly.Type = 'Audio';
  p.DirectPlayProfiles.push(audioOnly);
  // Text subtitles are fetched as files by the player; mkv may keep them embedded on direct play.
  // Image subtitles (PGS/DVD) can't be rendered by AVPlayer, so they are burned in (forces a video transcode).
  ['srt', 'subrip', 'vtt', 'webvtt', 'ass', 'ssa'].forEach((f: string) => {
    p.SubtitleProfiles.push(sub(f, 'External', ''));
  });
  ['srt', 'subrip', 'ass', 'ssa'].forEach((f: string) => {
    p.SubtitleProfiles.push(sub(f, 'Embed', 'mkv'));
  });
  ['pgssub', 'pgs', 'dvdsub', 'dvbsub', 'vobsub'].forEach((f: string) => {
    p.SubtitleProfiles.push(sub(f, 'Encode', ''));
  });
}

/** Emby/Jellyfin DeviceProfile from probed decoder caps; see the header comment for the rules. */
export function buildProfile(entries: CodecEntry[], opts: ProfileOptions): DeviceProfile {
  const bitrate = opts.maxBitrate > 0 ? Math.floor(opts.maxBitrate) : DEFAULT_MAX_BITRATE;
  const jellyfin = opts.kind === 'jellyfin';
  const p = new DeviceProfile();
  p.MaxStreamingBitrate = bitrate;
  p.MaxStaticBitrate = bitrate;

  if (opts.codecMode === 'compat') {
    const v = joinNames(COMPAT_VIDEO);
    const a = joinNames(COMPAT_AUDIO);
    DIRECT_CONTAINERS.forEach((c: string) => {
      p.DirectPlayProfiles.push(directVideo(c, v, a));
    });
    p.TranscodingProfiles.push(hls('ts', COMPAT_VIDEO, ['aac'], '6'));
    p.TranscodingProfiles.push(audioTranscode());
    p.CodecProfiles.push(h264Profile(entries, false));
    const audio = new CodecProfile();
    audio.Type = 'VideoAudio';
    audio.Codec = a;
    audio.Conditions.push(cond('LessThanEqual', 'AudioChannels', '8'));
    p.CodecProfiles.push(audio);
    addCommon(p);
    return p;
  }

  const vids = videoCodecs(entries);
  const auds = audioCodecs(entries);
  const v = joinNames(vids);
  const a = joinNames(auds);
  CONTAINER_FAMILIES.forEach((c: string) => {
    p.DirectPlayProfiles.push(directVideo(c, v, a));
  });

  // HLS: Jellyfin -> fMP4 segments (copies hevc/av1/vp9) with a TS/h264 fallback; Emby -> TS segments.
  if (jellyfin) {
    const fv = hlsVideoCodecs(entries, true, opts.preferRemux);
    const fa = hlsAudioCodecs(entries, true);
    p.DirectPlayProfiles.push(directVideo('hls', joinNames(fv), joinNames(fa)));
    p.TranscodingProfiles.push(hls('mp4', fv, fa, '8'));
    p.TranscodingProfiles.push(hls('ts', ['h264'], hlsAudioCodecs(entries, false), '8'));
  } else {
    const tv = hlsVideoCodecs(entries, false, opts.preferRemux);
    const ta = hlsAudioCodecs(entries, false);
    p.DirectPlayProfiles.push(directVideo('hls', joinNames(tv), joinNames(ta)));
    p.TranscodingProfiles.push(hls('ts', tv, ta, '8'));
  }
  p.TranscodingProfiles.push(audioTranscode());

  vids.forEach((c: string) => {
    if (c === 'h264') {
      const hp = h264Profile(entries, true);
      if (jellyfin) {
        hp.Conditions.push(cond('EqualsAny', 'VideoRangeType', 'SDR'));
      }
      p.CodecProfiles.push(hp);
      return;
    }
    const cp = videoCodecProfile(entries, c, jellyfin);
    if (cp !== undefined) {
      p.CodecProfiles.push(cp);
    }
  });
  auds.forEach((c: string) => {
    const ap = new CodecProfile();
    ap.Type = 'VideoAudio';
    ap.Codec = joinNames([c]);
    ap.Conditions.push(cond('LessThanEqual', 'AudioChannels', String(channelsFor(entries, c))));
    p.CodecProfiles.push(ap);
  });
  addCommon(p);
  return p;
}

// ---------- server delivery mode ----------

/** TranscodeReasons that don't require re-encoding the video stream (container repackaging / audio only). */
export const REMUX_REASONS: string[] = ['ContainerNotSupported', 'AudioCodecNotSupported', 'AudioChannelsNotSupported',
  'AudioProfileNotSupported', 'AudioSampleRateNotSupported', 'AudioBitDepthNotSupported', 'AudioBitrateNotSupported',
  'SecondaryAudioNotSupported', 'UnknownAudioStreamInfo', 'AudioIsExternal', 'DirectPlayError'];

/** Query parameters of a URL with lower-cased keys (decoded values). */
export function queryParams(url: string): Map<string, string> {
  const out = new Map<string, string>();
  const qi = url.indexOf('?');
  if (qi < 0) {
    return out;
  }
  let q = url.substring(qi + 1);
  const hi = q.indexOf('#');
  if (hi >= 0) {
    q = q.substring(0, hi);
  }
  q.split('&').forEach((kv: string) => {
    if (kv.length === 0) {
      return;
    }
    const eq = kv.indexOf('=');
    const k = (eq >= 0 ? kv.substring(0, eq) : kv).toLowerCase();
    const raw = eq >= 0 ? kv.substring(eq + 1) : '';
    let v = raw;
    try {
      v = decodeURIComponent(raw.replace(/\+/g, ' '));
    } catch (e) {
      v = raw;
    }
    out.set(k, v);
  });
  return out;
}

function splitList(s: string): string[] {
  return s.split(',').map((x: string) => x.trim()).filter((x: string) => x.length > 0);
}

/** TranscodeReasons from the transcoding URL merged with the media source's own list (deduplicated). */
export function transcodeReasons(url: string, sourceReasons: string[]): string[] {
  const out: string[] = [];
  const q = queryParams(url).get('transcodereasons') ?? '';
  splitList(q).concat(sourceReasons).forEach((r: string) => {
    const t = r.trim();
    if (t.length > 0 && out.indexOf(t) < 0) {
      out.push(t);
    }
  });
  return out;
}

/**
 * 'direct' | 'remux' | 'transcode' for a playback URL.
 * remux = the server serves HLS but copies the video stream: VideoCodec=copy, or the source codec is in the URL's
 * VideoCodec list and every TranscodeReason is container/audio related (audio may still be re-encoded to AAC).
 * Burned-in subtitles (SubtitleMethod=Encode), AllowVideoStreamCopy=false or any video reason => transcode.
 */
export function detectDelivery(url: string, isTranscode: boolean, sourceVideoCodec: string,
  reasons: string[]): string {
  if (!isTranscode) {
    return 'direct';
  }
  const q = queryParams(url);
  if ((q.get('static') ?? '').toLowerCase() === 'true') {
    return 'direct';
  }
  if ((q.get('subtitlemethod') ?? '').toLowerCase() === 'encode') {
    return 'transcode';
  }
  if ((q.get('allowvideostreamcopy') ?? '').toLowerCase() === 'false') {
    return 'transcode';
  }
  if (reasons.some((r: string) => REMUX_REASONS.indexOf(r) < 0)) {
    return 'transcode';
  }
  const vc = splitList(q.get('videocodec') ?? '').map((c: string) => normCodec(c));
  if (vc.indexOf('copy') >= 0) {
    return 'remux';
  }
  const src = normCodec(sourceVideoCodec);
  if (src.length > 0) {
    return vc.indexOf(src) >= 0 ? 'remux' : 'transcode';
  }
  // Unknown source codec: only container/audio reasons were given, so the server has no reason to re-encode video.
  return reasons.length > 0 ? 'remux' : 'transcode';
}

/** Output bitrate of a transcode URL (VideoBitrate + AudioBitrate), 0 if absent. */
export function urlBitrate(url: string): number {
  const q = queryParams(url);
  const v = parseInt(q.get('videobitrate') ?? '', 10);
  const a = parseInt(q.get('audiobitrate') ?? '', 10);
  return (isNaN(v) ? 0 : v) + (isNaN(a) ? 0 : a);
}

/** Normalised range label from server stream fields ('SDR' | 'HDR10' | 'HLG' | 'DOVI' | 'HDR Vivid' | ''). */
export function rangeLabel(rangeType: string, range: string, transfer: string, extType: string): string {
  const t = rangeType.toLowerCase();
  const x = extType.toLowerCase();
  if (t.startsWith('dovi') || x.indexOf('dolbyvision') >= 0) {
    return 'DOVI';
  }
  if (t === 'hlg' || x.indexOf('hyperloggamma') >= 0 || x === 'hlg' || transfer === 'arib-std-b67') {
    return 'HLG';
  }
  if (t.startsWith('hdr10') || x.startsWith('hdr10') || transfer === 'smpte2084') {
    return 'HDR10';
  }
  if (x.indexOf('vivid') >= 0) {
    return 'HDR Vivid';
  }
  if (t === 'sdr' || range.toLowerCase() === 'sdr') {
    return 'SDR';
  }
  if (range.toLowerCase() === 'hdr') {
    return 'HDR10';
  }
  return '';
}

// ---------- plain-text report ----------

function decoderLine(d: DecoderInfo, video: boolean): string {
  const parts: string[] = [d.hw ? '硬解' : '软解', d.name.length > 0 ? d.name : '(未命名)'];
  if (video) {
    if (d.maxWidth > 0 && d.maxHeight > 0) {
      parts.push(d.maxWidth + 'x' + d.maxHeight);
    }
    const flags: string[] = [];
    if (d.uhd60) {
      flags.push('4K60');
    } else if (d.uhd30) {
      flags.push('4K30');
    }
    if (d.fhd60) {
      flags.push('1080p60');
    }
    if (flags.length > 0) {
      parts.push(flags.join('/'));
    }
  } else if (d.maxChannels > 0) {
    parts.push('最多 ' + d.maxChannels + ' 声道');
  }
  if (d.instances > 0) {
    parts.push('实例 ' + d.instances);
  }
  if (d.profiles.length > 0) {
    parts.push('profiles [' + d.profiles.join(',') + ']');
  }
  return '    ' + parts.join(' · ');
}

/** Text for the "复制报告" button. header lines (device model, OS) are prepended as given. */
export function formatReport(entries: CodecEntry[], header: string[]): string {
  const lines: string[] = header.slice();
  if (entries.length === 0) {
    lines.push('未获取到解码器信息');
    return lines.join('\n');
  }
  const section = (title: string, video: boolean): void => {
    lines.push('');
    lines.push('[' + title + ']');
    entries.filter((e: CodecEntry) => e.video === video).forEach((e: CodecEntry) => {
      if (e.decoders.length === 0) {
        lines.push(e.codec + ': 不支持');
        return;
      }
      lines.push(e.codec + ':');
      e.decoders.forEach((d: DecoderInfo) => {
        lines.push(decoderLine(d, video));
      });
    });
  };
  section('视频', true);
  section('音频', false);
  return lines.join('\n');
}
