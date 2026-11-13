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
