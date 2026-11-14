// Pure helpers for the 解码能力 page (no @kit imports, unit-tested in tools/tests/codecinfo.test.mjs).
// CodecCaps types are used as types only, so the transpiled JS never loads the native probe.
import { CodecEntry, DecoderInfo } from '../../media/CodecCaps';
import { LabeledString } from './SettingsLogic';

export class CodecName {
  codec: string = '';
  label: string = '';

  constructor(codec: string, label: string) {
    this.codec = codec;
    this.label = label;
  }
}

export const VIDEO_CODECS: CodecName[] = [
  new CodecName('h264', 'H.264/AVC'),
  new CodecName('hevc', 'H.265/HEVC'),
  new CodecName('vvc', 'H.266/VVC'),
  new CodecName('av1', 'AV1'),
  new CodecName('vp9', 'VP9'),
  new CodecName('vp8', 'VP8'),
  new CodecName('mpeg2video', 'MPEG-2'),
  new CodecName('mpeg4', 'MPEG-4'),
  new CodecName('h263', 'H.263'),
  new CodecName('vc1', 'VC-1'),
  new CodecName('wmv3', 'WMV3'),
  new CodecName('rv40', 'RealVideo'),
  new CodecName('mjpeg', 'MJPEG')
];

export const AUDIO_CODECS: CodecName[] = [
  new CodecName('aac', 'AAC'),
  new CodecName('mp3', 'MP3'),
  new CodecName('flac', 'FLAC'),
  new CodecName('vorbis', 'Vorbis'),
  new CodecName('opus', 'Opus'),
  new CodecName('alac', 'ALAC'),
  new CodecName('ape', 'APE'),
  new CodecName('ac3', 'AC-3 (杜比数字)'),
  new CodecName('eac3', 'E-AC-3 (杜比数字+)'),
  new CodecName('dts', 'DTS'),
  new CodecName('truehd', 'TrueHD'),
  new CodecName('wma', 'WMA'),
  new CodecName('pcm', 'PCM')
];

/** 'hw' = hardware decoder present, 'sw' = software only, 'none' = no decoder */
export const STATUS_HW: string = 'hw';
export const STATUS_SW: string = 'sw';
export const STATUS_NONE: string = 'none';

export class CodecRow {
  codec: string = '';
  label: string = '';
  video: boolean = false;
  status: string = STATUS_NONE;
  /** Name of the decoder AVPlayer would most likely use (hardware first) */
  decoderName: string = '';
  /** Detail fragments, joined with ' · ' by the page */
  details: string[] = [];
}

export class SummaryChip {
  text: string = '';
  /** STATUS_HW / STATUS_SW / STATUS_NONE, used for the chip color */
  status: string = STATUS_NONE;

  constructor(text: string, status: string) {
    this.text = text;
    this.status = status;
  }
}

export function statusText(status: string): string {
  if (status === STATUS_HW) {
    return '硬件解码';
  }
  if (status === STATUS_SW) {
    return '软件解码';
  }
  return '不支持';
}

export function statusColor(status: string): string {
  if (status === STATUS_HW) {
    return '#34C759';
  }
  if (status === STATUS_SW) {
    return '#F5A623';
  }
  return '#6B7280';
}

/** Translucent background for badges/chips (#AARRGGBB). */
export function statusBgColor(status: string): string {
  if (status === STATUS_HW) {
    return '#2634C759';
  }
  if (status === STATUS_SW) {
    return '#26F5A623';
  }
  return '#266B7280';
}

/** Display name for a codec id; unknown ids are upper-cased. */
export function codecLabel(codec: string): string {
  const all = VIDEO_CODECS.concat(AUDIO_CODECS);
  for (let i = 0; i < all.length; i++) {
    if (all[i].codec === codec) {
      return all[i].label;
    }
  }
  return codec.toUpperCase();
}
/** "8K" / "4K" / "2K" / "1080p" / "720p" / "480p"; '' when unknown. Uses the shorter side so 4096x2304 reads as 4K. */
export function resolutionLabel(w: number, h: number): string {
  let s = 0;
  if (w > 0 && h > 0) {
    s = Math.min(w, h);
  } else {
    s = Math.max(w, h);
  }
  if (s <= 0) {
    return '';
  }
  if (s >= 4320) {
    return '8K';
  }
  if (s >= 2160) {
    return '4K';
  }
  if (s >= 1440) {
    return '2K';
  }
  if (s >= 1080) {
    return '1080p';
  }
  if (s >= 720) {
    return '720p';
  }
  return `${s}p`;
}

export function findEntry(entries: CodecEntry[], codec: string): CodecEntry | undefined {
  for (let i = 0; i < entries.length; i++) {
    if (entries[i].codec === codec) {
      return entries[i];
    }
  }
  return undefined;
}

function decArea(d: DecoderInfo): number {
  return (d.maxWidth > 0 ? d.maxWidth : 0) * (d.maxHeight > 0 ? d.maxHeight : 0);
}

/** Hardware decoders first, then the one with the largest max resolution / channel count. */
export function bestDecoder(e: CodecEntry | undefined): DecoderInfo | undefined {
  if (e === undefined || !e.decoders || e.decoders.length === 0) {
    return undefined;
  }
  let best: DecoderInfo = e.decoders[0];
  for (let i = 1; i < e.decoders.length; i++) {
    const d = e.decoders[i];
    if (d.hw !== best.hw) {
      if (d.hw) {
        best = d;
      }
      continue;
    }
    if (decArea(d) > decArea(best) || (decArea(d) === decArea(best) && d.maxChannels > best.maxChannels)) {
      best = d;
    }
  }
  return best;
}

export function statusOf(e: CodecEntry | undefined): string {
  const d = bestDecoder(e);
  if (d === undefined) {
    return STATUS_NONE;
  }
  return d.hw ? STATUS_HW : STATUS_SW;
}

function videoDetails(d: DecoderInfo): string[] {
  const out: string[] = [];
  if (d.maxWidth > 0 && d.maxHeight > 0) {
    const r = resolutionLabel(d.maxWidth, d.maxHeight);
    out.push(`最高 ${d.maxWidth}×${d.maxHeight}${r ? '（' + r + '）' : ''}`);
  }
  if (d.uhd60) {
    out.push('4K60 ✓');
  } else if (d.uhd30) {
    out.push('4K30 ✓ · 4K60 ✗');
  } else if (d.maxHeight > 0 && Math.min(d.maxWidth, d.maxHeight) >= 2160) {
    out.push('4K 帧率未知');
  } else if (d.fhd60) {
    out.push('1080p60 ✓');
  }
  return out;
}

function audioDetails(d: DecoderInfo): string[] {
  const out: string[] = [];
  if (d.maxChannels > 0) {
    out.push(`最多 ${d.maxChannels} 声道`);
  }
  return out;
}

export function buildRow(entries: CodecEntry[], n: CodecName, video: boolean): CodecRow {
  const r = new CodecRow();
  r.codec = n.codec;
  r.label = n.label;
  r.video = video;
  const e = findEntry(entries, n.codec);
  const d = bestDecoder(e);
  if (e === undefined || d === undefined) {
    return r;
  }
  r.status = d.hw ? STATUS_HW : STATUS_SW;
  r.decoderName = d.name;
  r.details = video ? videoDetails(d) : audioDetails(d);
  if (d.instances > 0) {
    r.details.push(`可同时 ${d.instances} 路`);
  }
  const others = e.decoders.length - 1;
  if (others > 0) {
    let hasSw = false;
    for (let i = 0; i < e.decoders.length; i++) {
      if (!e.decoders[i].hw) {
        hasSw = true;
      }
    }
    r.details.push(d.hw && hasSw ? `另有 ${others} 个备用解码器（含软件解码）` : `另有 ${others} 个备用解码器`);
  }
  return r;
}

export function buildRows(entries: CodecEntry[], video: boolean): CodecRow[] {
  const names = video ? VIDEO_CODECS : AUDIO_CODECS;
  return names.map((n: CodecName) => buildRow(entries, n, video));
}

/** Chip for one video codec, e.g. "硬解 H.265 · 4K60", "软解 AV1", "H.266 不支持". */
export function videoChip(entries: CodecEntry[], codec: string, shortName: string): SummaryChip {
  const d = bestDecoder(findEntry(entries, codec));
  if (d === undefined) {
    return new SummaryChip(`${shortName} 不支持`, STATUS_NONE);
  }
  let res = '';
  if (d.uhd60) {
    res = '4K60';
  } else if (d.uhd30) {
    res = '4K30';
  } else {
    res = resolutionLabel(d.maxWidth, d.maxHeight);
  }
  const head = `${d.hw ? '硬解' : '软解'} ${shortName}`;
  return new SummaryChip(res ? `${head} · ${res}` : head, d.hw ? STATUS_HW : STATUS_SW);
}

const SURROUND: CodecName[] = [
  new CodecName('ac3', 'AC-3'),
  new CodecName('eac3', 'E-AC-3'),
  new CodecName('truehd', 'TrueHD'),
  new CodecName('dts', 'DTS')
];

/** Dolby/DTS chip: green when all four decode, amber when some do, grey when none. */
export function surroundChip(entries: CodecEntry[]): SummaryChip {
  const ok: string[] = [];
  for (let i = 0; i < SURROUND.length; i++) {
    if (bestDecoder(findEntry(entries, SURROUND[i].codec)) !== undefined) {
      ok.push(SURROUND[i].label);
    }
  }
  if (ok.length === SURROUND.length) {
    return new SummaryChip('杜比/DTS 音频 全支持', STATUS_HW);
  }
  if (ok.length === 0) {
    return new SummaryChip('杜比/DTS 音频 不支持', STATUS_NONE);
  }
  return new SummaryChip(`杜比/DTS 音频：${ok.join('/')}`, STATUS_SW);
}

export function summaryChips(entries: CodecEntry[]): SummaryChip[] {
  if (entries.length === 0) {
    return [new SummaryChip('未检测到解码器（探测失败）', STATUS_NONE)];
  }
  const out: SummaryChip[] = [];
  out.push(videoChip(entries, 'hevc', 'H.265'));
  out.push(videoChip(entries, 'h264', 'H.264'));
  out.push(videoChip(entries, 'av1', 'AV1'));
  const vvc = videoChip(entries, 'vvc', 'H.266');
  if (vvc.status !== STATUS_NONE) {
    out.push(vvc);
  }
  out.push(videoChip(entries, 'vp9', 'VP9'));
  out.push(surroundChip(entries));
  return out;
}

/** "视频 9/13 · 硬解 4" style count line for a group header. */
export function groupCount(rows: CodecRow[]): string {
  let ok = 0;
  let hw = 0;
  for (let i = 0; i < rows.length; i++) {
    if (rows[i].status !== STATUS_NONE) {
      ok++;
    }
    if (rows[i].status === STATUS_HW) {
      hw++;
    }
  }
  return `支持 ${ok}/${rows.length}${hw > 0 ? ' · 硬解 ' + hw : ''}`;
}

/** Settings: 编码兼容模式 options (value = AppSettings.codecMode). */
export const CODEC_MODE_OPTIONS: LabeledString[] = [
  new LabeledString('自动（按本机解码能力）', 'auto'),
  new LabeledString('兼容（仅 H.264+AAC，其余转码）', 'compat')
];

export function codecModeIndex(v: string): number {
  for (let i = 0; i < CODEC_MODE_OPTIONS.length; i++) {
    if (CODEC_MODE_OPTIONS[i].value === v) {
      return i;
    }
  }
  return 0;
}
