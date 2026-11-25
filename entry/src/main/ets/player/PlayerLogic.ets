// Pure player helpers (no @kit imports): sizing, language matching, resume/queue logic. Unit-tested.

export class VideoBox {
  width: number = 0;
  height: number = 0;
}

/** fit = letterbox, fill = stretch to area, crop = cover (container clips), 16:9 / 4:3 = forced ratio fitted in area */
export type AspectMode = 'fit' | 'fill' | 'crop' | '16:9' | '4:3';

export const ASPECT_MODES: string[] = ['fit', 'fill', 'crop', '16:9', '4:3'];

export function aspectLabel(mode: string): string {
  switch (mode) {
    case 'fill': return '拉伸铺满';
    case 'crop': return '裁剪填充';
    case '16:9': return '16:9';
    case '4:3': return '4:3';
    default: return '自适应';
  }
}

function fitRatio(areaW: number, areaH: number, ratio: number): VideoBox {
  const b = new VideoBox();
  if (areaW / areaH > ratio) {
    b.height = areaH;
    b.width = areaH * ratio;
  } else {
    b.width = areaW;
    b.height = areaW / ratio;
  }
  return b;
}

export function computeVideoBox(mode: string, areaW: number, areaH: number, videoW: number, videoH: number): VideoBox {
  const box = new VideoBox();
  if (areaW <= 0 || areaH <= 0) {
    return box;
  }
  if (mode === 'fill') {
    box.width = areaW;
    box.height = areaH;
    return box;
  }
  if (mode === '16:9') {
    return fitRatio(areaW, areaH, 16 / 9);
  }
  if (mode === '4:3') {
    return fitRatio(areaW, areaH, 4 / 3);
  }
  const ratio = videoW > 0 && videoH > 0 ? videoW / videoH : 16 / 9;
  if (mode === 'crop') {
    if (areaW / areaH > ratio) {
      box.width = areaW;
      box.height = areaW / ratio;
    } else {
      box.height = areaH;
      box.width = areaH * ratio;
    }
    return box;
  }
  return fitRatio(areaW, areaH, ratio);
}

export const SPEEDS: number[] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3];

export function speedLabel(s: number): string {
  return s === 1 ? '正常' : s + 'x';
}

export function nearestSpeed(s: number): number {
  let best = 1;
  let diff = 1000;
  for (let i = 0; i < SPEEDS.length; i++) {
    const d = Math.abs(SPEEDS[i] - s);
    if (d < diff) {
      diff = d;
      best = SPEEDS[i];
    }
  }
  return best;
}

const LANG_GROUPS: Record<string, string[]> = {
  'zh': ['chi', 'zho', 'zh', 'chs', 'cht', 'cn', 'zh-cn', 'zh-tw', 'zh-hk', 'zh-hans', 'zh-hant', 'chinese', 'mandarin',
    'cantonese', 'yue', 'cmn', '中文', '简体', '繁体', '繁體', '简中', '繁中', '国语', '國語', '粤语', '粵語', '普通话', '双语', '中英'],
  'en': ['eng', 'en', 'en-us', 'en-gb', 'english', '英语', '英文', '英語'],
  'ja': ['jpn', 'ja', 'jp', 'japanese', '日语', '日文', '日語'],
  'ko': ['kor', 'ko', 'kr', 'korean', '韩语', '韩文', '韓語'],
  'fr': ['fre', 'fra', 'fr', 'french', '法语'],
  'de': ['ger', 'deu', 'de', 'german', '德语'],
  'es': ['spa', 'es', 'spanish', '西班牙语'],
  'ru': ['rus', 'ru', 'russian', '俄语'],
  'th': ['tha', 'th', 'thai', '泰语']
};

/** Normalised language group key ('zh', 'en', ...) or the lowercased input when unknown. */
export function langKey(s: string): string {
  const v = s.trim().toLowerCase();
  if (v.length === 0) {
    return '';
  }
  const keys = Object.keys(LANG_GROUPS);
  for (let i = 0; i < keys.length; i++) {
    if (LANG_GROUPS[keys[i]].indexOf(v) >= 0) {
      return keys[i];
    }
  }
  return v;
}

/** True if a track (language code and/or title) matches the preferred language. */
export function langMatches(pref: string, lang: string, title: string): boolean {
  const pk = langKey(pref);
  if (pk.length === 0) {
    return false;
  }
  if (langKey(lang) === pk) {
    return true;
  }
  const words = LANG_GROUPS[pk];
  if (words === undefined) {
    return false;
  }
  const t = title.toLowerCase();
  for (let i = 0; i < words.length; i++) {
    // only multi-char words and CJK words to avoid matching "en" inside random titles
    const w = words[i];
    if ((w.length >= 3 || w.charCodeAt(0) > 0x2e80) && t.indexOf(w) >= 0) {
      return true;
    }
  }
  return false;
}

/** Index (into the arrays) of the first track matching pref, else -1. */
export function pickByLanguage(langs: string[], titles: string[], pref: string): number {
  for (let i = 0; i < langs.length; i++) {
    if (langMatches(pref, langs[i], i < titles.length ? titles[i] : '')) {
      return i;
    }
  }
  return -1;
}

/** Resolve the start position. paramStart -1 = resume from saved (ignored near start/end). */
export function resolveStartMs(paramStart: number, savedMs: number, runtimeMs: number): number {
  if (paramStart >= 0) {
    return paramStart;
  }
  if (savedMs < 10000) {
    return 0;
  }
  if (runtimeMs > 0 && savedMs > runtimeMs - 15000) {
    return 0;
  }
  return savedMs;
}

/** Next id in queue after currentId, '' if none. */
export function nextInQueue(queue: string[], currentId: string): string {
  const i = queue.indexOf(currentId);
  if (i < 0 || i + 1 >= queue.length) {
    return '';
  }
  return queue[i + 1];
}

export function prevInQueue(queue: string[], currentId: string): string {
  const i = queue.indexOf(currentId);
  if (i <= 0) {
    return '';
  }
  return queue[i - 1];
}

export function clamp(v: number, lo: number, hi: number): number {
  return v < lo ? lo : (v > hi ? hi : v);
}

/** Milliseconds covered by a full-width horizontal swipe. */
export function swipeSeekRange(durationMs: number): number {
  if (durationMs <= 0) {
    return 120000;
  }
  return clamp(durationMs / 3, 60000, 300000);
}

export class BitrateOption {
  label: string = '';
  bitrate: number = 0;

  constructor(label: string, bitrate: number) {
    this.label = label;
    this.bitrate = bitrate;
  }
}

export function bitrateOptions(): BitrateOption[] {
  return [
    new BitrateOption('原画', 0),
    new BitrateOption('4K 40Mbps', 40000000),
    new BitrateOption('1080P 20Mbps', 20000000),
    new BitrateOption('1080P 10Mbps', 10000000),
    new BitrateOption('720P 4Mbps', 4000000),
    new BitrateOption('480P 2Mbps', 2000000),
    new BitrateOption('360P 1Mbps', 1000000)
  ];
}

/** Seconds left to show in the "即将播放下一集" countdown, -1 when not in the window. */
export function nextCountdown(positionMs: number, durationMs: number, windowMs: number): number {
  if (durationMs <= 0 || positionMs <= 0) {
    return -1;
  }
  const left = durationMs - positionMs;
  if (left > windowMs || left < 0) {
    return -1;
  }
  return Math.max(1, Math.ceil(left / 1000));
}

// ---------- automatic fallback chain ----------

/** Result of decideFallback. action: 'remux' | 'transcode' (re-request with forceMode) | 'quality' (switch to qualities[qualityIndex]) | 'none' */
export class FallbackStep {
  action: string = 'none';
  qualityIndex: number = -1;
  /** Attempt key to record in the tried list ('remux', 'transcode', 'q:<i>') */
  key: string = '';
  banner: string = '';
}

/** Maximum automatic switches per item; guards against loops even if keys repeat. */
export const MAX_AUTO_FALLBACKS: number = 3;

/**
 * Next step after a playback failure. Server sources (no qualities): direct -> remux -> transcode.
 * Quark-style sources (qualities non-empty, no server remux): original -> best untried transcoded quality.
 * tried holds keys of attempts already made for this item (including the failed current one).
 */
export function decideFallback(deliveryMode: string, qualityLabels: string[], currentQuality: number,
  tried: string[]): FallbackStep {
  const step = new FallbackStep();
  if (tried.length >= MAX_AUTO_FALLBACKS) {
    return step;
  }
  if (qualityLabels.length > 0) {
    const cur = currentQuality >= 0 && currentQuality < qualityLabels.length ? qualityLabels[currentQuality] : '';
    if (cur !== '原画') {
      // only the original link falls back; a failing transcode is not retried automatically
      return step;
    }
    for (let i = 0; i < qualityLabels.length; i++) {
      // qualities are ordered best first (QuarkProvider sorts by resolution rank)
      if (qualityLabels[i] !== '原画' && tried.indexOf('q:' + i) < 0) {
        step.action = 'quality';
        step.qualityIndex = i;
        step.key = 'q:' + i;
        step.banner = '原画播放失败，已切换为' + qualityLabels[i];
        return step;
      }
    }
    return step;
  }
  if (deliveryMode === 'direct' && tried.indexOf('remux') < 0) {
    step.action = 'remux';
    step.key = 'remux';
    step.banner = '直接播放失败，已切换为服务器转封装';
    return step;
  }
  if ((deliveryMode === 'direct' || deliveryMode === 'remux') && tried.indexOf('transcode') < 0) {
    step.action = 'transcode';
    step.key = 'transcode';
    step.banner = '已切换为服务器转码';
    return step;
  }
  return step;
}

/**
 * Next step for sources that offer several equivalent lines (Flicx): try the following untried line,
 * wrapping around, at most MAX_AUTO_FALLBACKS times per item. tried holds 'q:<i>' keys already attempted.
 */
export function decideLineFallback(lineLabels: string[], currentLine: number, tried: string[]): FallbackStep {
  const step = new FallbackStep();
  const n = lineLabels.length;
  if (n < 2 || tried.length >= MAX_AUTO_FALLBACKS + 1) {
    return step;
  }
  const from = currentLine >= 0 && currentLine < n ? currentLine : -1;
  for (let k = 1; k <= n; k++) {
    const i = (from + k + n) % n;
    if (i !== from && tried.indexOf('q:' + i) < 0) {
      step.action = 'quality';
      step.qualityIndex = i;
      step.key = 'q:' + i;
      step.banner = (from >= 0 ? lineLabels[from] + ' 无法播放，' : '') + '已切换到 ' + lineLabels[i];
      return step;
    }
  }
  return step;
}

// ---------- super resolution ----------

/** Super resolution only helps sources whose short side is below 1080 px. */
export function wantSuperResolution(videoW: number, videoH: number): boolean {
  if (videoW <= 0 || videoH <= 0) {
    return false;
  }
  return Math.min(videoW, videoH) < 1080;
}

/** setVideoWindowSize accepts 320..1920 x 320..1080 px: scale the on-screen size into that box keeping its ratio. */
export function srWindowSize(pxW: number, pxH: number): VideoBox {
  const b = new VideoBox();
  if (pxW <= 0 || pxH <= 0) {
    return b;
  }
  const s = Math.min(1, 1920 / pxW, 1080 / pxH);
  b.width = clamp(Math.round(pxW * s), 320, 1920);
  b.height = clamp(Math.round(pxH * s), 320, 1080);
  return b;
}

// ---------- codec names ----------

/** Normalise server / ffmpeg codec names to the keys CodecCaps uses. */
export function normCodec(name: string): string {
  const v = name.trim().toLowerCase();
  switch (v) {
    case 'avc': case 'h.264': case 'avc1': case 'x264': return 'h264';
    case 'h265': case 'h.265': case 'hev1': case 'hvc1': case 'x265': return 'hevc';
    case 'h266': case 'h.266': return 'vvc';
    case 'av01': return 'av1';
    case 'mpeg2': return 'mpeg2video';
    case 'dca': return 'dts';
    case 'mlp': return 'truehd';
    case 'wmav1': case 'wmav2': case 'wmapro': return 'wma';
    case 'wvc1': return 'vc1';
    case 'mp2': case 'mp3float': return 'mp3';
    default:
      return v.startsWith('pcm') ? 'pcm' : v;
  }
}

/** Codec key + mime pair (from CodecCaps.entries()). */
export class CodecMime {
  codec: string = '';
  mime: string = '';

  constructor(codec: string, mime: string) {
    this.codec = codec;
    this.mime = mime;
  }
}

// mime strings confirmed in the SDK CodecMimeType enum
const SDK_MIMES: CodecMime[] = [
  new CodecMime('h264', 'video/avc'), new CodecMime('hevc', 'video/hevc'), new CodecMime('mpeg2video', 'video/mpeg2'),
  new CodecMime('mpeg4', 'video/mp4v-es'), new CodecMime('h263', 'video/h263'), new CodecMime('vp8', 'video/x-vnd.on2.vp8'),
  new CodecMime('aac', 'audio/mp4a-latm'), new CodecMime('mp3', 'audio/mpeg'), new CodecMime('flac', 'audio/flac'),
  new CodecMime('vorbis', 'audio/vorbis'), new CodecMime('pcm', 'audio/raw')
];

// substring fallbacks for mimes without an ArkTS constant (order matters: eac3 before ac3, vp9 before vp8)
const MIME_HINTS: string[][] = [
  ['av01', 'av1'], ['av1', 'av1'], ['vp9', 'vp9'], ['vp8', 'vp8'], ['vvc', 'vvc'], ['h266', 'vvc'], ['hevc', 'hevc'],
  ['h265', 'hevc'], ['avc', 'h264'], ['h264', 'h264'], ['wmv3', 'wmv3'], ['wvc1', 'vc1'], ['vc1', 'vc1'], ['rv40', 'rv40'],
  ['rv30', 'rv30'], ['mjpeg', 'mjpeg'], ['mpeg2', 'mpeg2video'], ['mp4v', 'mpeg4'], ['h263', 'h263'],
  ['eac3', 'eac3'], ['e-ac-3', 'eac3'], ['ac3', 'ac3'], ['ac-3', 'ac3'], ['truehd', 'truehd'], ['dts', 'dts'],
  ['opus', 'opus'], ['alac', 'alac'], ['ape', 'ape'], ['wma', 'wma'], ['flac', 'flac'], ['vorbis', 'vorbis'],
  ['mp4a', 'aac'], ['aac', 'aac'], ['mpeg', 'mp3'], ['raw', 'pcm'], ['pcm', 'pcm']
];

/** Map an AVPlayer track mime (MD_KEY_CODEC_MIME) to a CodecCaps key; probe table first, '' when unknown. */
export function mimeToCodec(mime: string, probe: CodecMime[]): string {
  const m = mime.trim().toLowerCase();
  if (m.length === 0) {
    return '';
  }
  for (let i = 0; i < probe.length; i++) {
    if (probe[i].mime.length > 0 && probe[i].mime.toLowerCase() === m) {
      return probe[i].codec;
    }
  }
  for (let i = 0; i < SDK_MIMES.length; i++) {
    if (SDK_MIMES[i].mime === m) {
      return SDK_MIMES[i].codec;
    }
  }
  const slash = m.indexOf('/');
  const tail = slash >= 0 ? m.substring(slash + 1) : m;
  for (let i = 0; i < MIME_HINTS.length; i++) {
    if (tail.indexOf(MIME_HINTS[i][0]) >= 0) {
      return MIME_HINTS[i][1];
    }
  }
  return '';
}

// ---------- "播放信息" panel ----------

export class InfoRow {
  label: string = '';
  value: string = '';

  constructor(label: string, value: string) {
    this.label = label;
    this.value = value;
  }
}

/** One track from getTrackDescription, already decoded to plain values. */
export class TrackStat {
  type: number = -1;        // 0 audio, 1 video, 2 subtitle
  mime: string = '';
  width: number = 0;
  height: number = 0;
  frameRate: number = 0;    // fps (already divided by 100)
  hdrType: string = '';     // raw MD_KEY_HDR_TYPE value
  bitrate: number = 0;
  channels: number = 0;
  sampleRate: number = 0;
  language: string = '';
}

/** Decoder chosen for a codec (from CodecCaps.decoderFor), known = a decoder was found. */
export class DecoderStat {
  codec: string = '';
  known: boolean = false;
  hw: boolean = false;
  name: string = '';
}

export class StatsInput {
  deliveryMode: string = 'direct';
  transcodeReasons: string[] = [];
  /** extra note after the mode, e.g. '夸克云端' */
  modeNote: string = '';
  container: string = '';
  videoCodec: string = '';
  audioCodec: string = '';
  videoWidth: number = 0;
  videoHeight: number = 0;
  videoRange: string = '';
  bitrate: number = 0;
  videoDecoder: DecoderStat = new DecoderStat();
  audioDecoder: DecoderStat = new DecoderStat();
  tracks: TrackStat[] = [];
  /** 'off' | 'on' | 'idle' (enabled, source is >= 1080p) | 'unavailable' */
  superRes: string = 'off';
  renderW: number = 0;
  renderH: number = 0;
  /** network: -1 = unknown */
  downloadRate: number = -1;
  avgDownloadRate: number = -1;
  bufferSec: number = -1;
  downloading: number = -1;
  serverIp: string = '';
}

export function deliveryLabel(mode: string): string {
  switch (mode) {
    case 'remux': return '转封装';
    case 'transcode': return '转码';
    default: return '直接播放';
  }
}

export function formatRate(bps: number): string {
  if (bps < 0) {
    return '—';
  }
  if (bps >= 1000000) {
    return (bps / 1000000).toFixed(1) + ' Mbps';
  }
  return Math.round(bps / 1000) + ' Kbps';
}

/** MD_KEY_HDR_TYPE (media.HdrType: 0 none, 1 HDR Vivid); other non-empty values are shown raw. */
export function hdrTypeLabel(raw: string): string {
  const v = raw.trim();
  if (v.length === 0 || v === '0' || v === '-1') {
    return '';
  }
  if (v === '1') {
    return 'HDR Vivid';
  }
  return v;
}

function decoderText(d: DecoderStat): string {
  if (d.codec.length === 0) {
    return '未知';
  }
  if (!d.known) {
    return '未探测到解码器';
  }
  return d.hw ? `硬件解码 (${d.name})` : `软件解码${d.name.length > 0 ? ' (' + d.name + ')' : ''}`;
}

function superResText(s: string): string {
  switch (s) {
    case 'on': return '已开启';
    case 'idle': return '已启用（片源 ≥1080P，未生效）';
    case 'unavailable': return '超分不可用';
    default: return '关闭';
  }
}

function resText(w: number, h: number): string {
  return w > 0 && h > 0 ? `${w}×${h}` : '';
}

function joinNonEmpty(parts: string[], sep: string): string {
  return parts.filter((s: string) => s.length > 0).join(sep);
}

export function buildInfoRows(s: StatsInput): InfoRow[] {
  const rows: InfoRow[] = [];
  let mode = deliveryLabel(s.deliveryMode);
  if (s.modeNote.length > 0) {
    mode += '（' + s.modeNote + '）';
  }
  rows.push(new InfoRow('播放方式', mode));
  if (s.deliveryMode !== 'direct' && s.transcodeReasons.length > 0) {
    rows.push(new InfoRow('转码原因', s.transcodeReasons.join(', ')));
  }
  const src = joinNonEmpty([s.container.toUpperCase(), s.videoCodec.toUpperCase(), s.audioCodec.toUpperCase()], ' / ');
  if (src.length > 0) {
    rows.push(new InfoRow('片源编码', src));
  }
  const srcVideo = joinNonEmpty([resText(s.videoWidth, s.videoHeight), s.videoRange,
    s.bitrate > 0 ? formatRate(s.bitrate) : ''], ' · ');
  if (srcVideo.length > 0) {
    rows.push(new InfoRow('片源画面', srcVideo));
  }
  rows.push(new InfoRow('视频解码', decoderText(s.videoDecoder)));
  rows.push(new InfoRow('音频解码', decoderText(s.audioDecoder)));
  for (let i = 0; i < s.tracks.length; i++) {
    const t = s.tracks[i];
    if (t.type === 1) {
      rows.push(new InfoRow('视频轨', joinNonEmpty([t.mime, resText(t.width, t.height),
        t.frameRate > 0 ? (Math.round(t.frameRate * 100) / 100) + ' fps' : '', hdrTypeLabel(t.hdrType),
        t.bitrate > 0 ? formatRate(t.bitrate) : ''], ' · ')));
    } else if (t.type === 0) {
      rows.push(new InfoRow('音频轨', joinNonEmpty([t.mime, t.language, t.channels > 0 ? t.channels + ' 声道' : '',
        t.sampleRate > 0 ? t.sampleRate + ' Hz' : ''], ' · ')));
    }
  }
  if (s.renderW > 0 && s.renderH > 0) {
    rows.push(new InfoRow('输出画面', resText(s.renderW, s.renderH)));
  }
  rows.push(new InfoRow('超分辨率', superResText(s.superRes)));
  rows.push(new InfoRow('下载速度', formatRate(s.downloadRate) +
    (s.avgDownloadRate >= 0 ? '（平均 ' + formatRate(s.avgDownloadRate) + '）' : '')));
  rows.push(new InfoRow('缓冲时长', s.bufferSec >= 0 ? s.bufferSec.toFixed(1) + ' 秒' +
    (s.downloading === 0 ? '（已下载完成）' : '') : '—'));
  if (s.serverIp.length > 0) {
    rows.push(new InfoRow('服务器', s.serverIp));
  }
  return rows;
}

// ---------- HLS variants (fixed resolution) ----------

export class HlsVariant {
  bandwidth: number = 0;
  width: number = 0;
  height: number = 0;
}

/** #EXT-X-STREAM-INF entries of a master playlist, highest bandwidth first, duplicates (same bandwidth) dropped. */
export function parseHlsVariants(text: string): HlsVariant[] {
  const out: HlsVariant[] = [];
  if (typeof text !== 'string' || text.indexOf('#EXT-X-STREAM-INF') < 0) {
    return out;
  }
  const seen = new Set<number>();
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line.startsWith('#EXT-X-STREAM-INF:')) {
      continue;
    }
    const bw = /(?:^|[:,])BANDWIDTH=(\d+)/.exec(line);
    if (bw === null) {
      continue;
    }
    const v = new HlsVariant();
    v.bandwidth = Number(bw[1]);
    const res = /(?:^|[:,])RESOLUTION=(\d+)x(\d+)/.exec(line);
    if (res !== null) {
      v.width = Number(res[1]);
      v.height = Number(res[2]);
    }
    if (v.bandwidth > 0 && !seen.has(v.bandwidth)) {
      seen.add(v.bandwidth);
      out.push(v);
    }
  }
  return out.sort((a: HlsVariant, b: HlsVariant) => b.bandwidth - a.bandwidth);
}

/** "4K", "1080p", ... from the short side; falls back to the bitrate. */
export function variantLabel(v: HlsVariant): string {
  const short = v.width > 0 && v.height > 0 ? Math.min(v.width, v.height) : 0;
  if (short >= 2000) {
    return '4K';
  }
  if (short >= 1400) {
    return '1440p';
  }
  if (short > 0) {
    const steps = [1080, 720, 540, 480, 360, 240];
    for (const s of steps) {
      if (short >= s * 0.9) {
        return s + 'p';
      }
    }
    return short + 'p';
  }
  return (v.bandwidth / 1e6).toFixed(1) + ' Mbps';
}

/** Variant to lock for a wanted height: the tallest one not above it, else the shortest. undefined for an empty list. */
export function pickVariant(list: HlsVariant[], wantHeight: number): HlsVariant | undefined {
  if (list.length === 0) {
    return undefined;
  }
  const h = (v: HlsVariant): number => v.width > 0 && v.height > 0 ? Math.min(v.width, v.height) : 0;
  let best: HlsVariant | undefined = undefined;
  for (const v of list) {
    if (h(v) <= wantHeight * 1.05 && (best === undefined || h(v) > h(best) ||
      (h(v) === h(best) && v.bandwidth > best.bandwidth))) {
      best = v;
    }
  }
  if (best !== undefined) {
    return best;
  }
  return list.reduce((a: HlsVariant, b: HlsVariant) => (h(b) < h(a) ? b : a));
}
