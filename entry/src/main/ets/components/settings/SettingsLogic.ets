// Pure helpers for the settings pages (no @kit imports, unit-tested in tools/tests/settings.test.mjs).

export class LabeledNumber {
  label: string = '';
  value: number = 0;

  constructor(label: string, value: number) {
    this.label = label;
    this.value = value;
  }
}

export class LabeledString {
  label: string = '';
  value: string = '';

  constructor(label: string, value: string) {
    this.label = label;
    this.value = value;
  }
}

/** bits per second; 0 = original */
export const BITRATE_OPTIONS: LabeledNumber[] = [
  new LabeledNumber('原画', 0),
  new LabeledNumber('40 Mbps', 40000000),
  new LabeledNumber('20 Mbps', 20000000),
  new LabeledNumber('10 Mbps', 10000000),
  new LabeledNumber('8 Mbps', 8000000),
  new LabeledNumber('4 Mbps', 4000000),
  new LabeledNumber('2 Mbps', 2000000)
];

export const SPEED_OPTIONS: LabeledNumber[] = [
  new LabeledNumber('0.5x', 0.5),
  new LabeledNumber('0.75x', 0.75),
  new LabeledNumber('1.0x', 1),
  new LabeledNumber('1.25x', 1.25),
  new LabeledNumber('1.5x', 1.5),
  new LabeledNumber('2.0x', 2)
];

export const SUBTITLE_SCALE_OPTIONS: LabeledNumber[] = [
  new LabeledNumber('小', 0.8),
  new LabeledNumber('标准', 1),
  new LabeledNumber('大', 1.2),
  new LabeledNumber('特大', 1.5)
];

/** ISO 639-2 codes used by Emby/Jellyfin streams */
export const TRACK_LANG_OPTIONS: LabeledString[] = [
  new LabeledString('中文', 'chi'),
  new LabeledString('英语', 'eng'),
  new LabeledString('日语', 'jpn'),
  new LabeledString('韩语', 'kor'),
  new LabeledString('粤语', 'yue'),
  new LabeledString('自动（默认轨道）', '')
];

export const TMDB_LANG_OPTIONS: LabeledString[] = [
  new LabeledString('简体中文', 'zh-CN'),
  new LabeledString('繁體中文（台灣）', 'zh-TW'),
  new LabeledString('繁體中文（香港）', 'zh-HK'),
  new LabeledString('English', 'en-US'),
  new LabeledString('日本語', 'ja-JP'),
  new LabeledString('한국어', 'ko-KR')
];

export const TMDB_IMAGE_BASE_OPTIONS: LabeledString[] = [
  new LabeledString('官方 image.tmdb.org', 'https://image.tmdb.org/t/p/'),
  new LabeledString('镜像 image.tmdb.org (wsrv 代理)', 'https://wsrv.nl/?url=image.tmdb.org/t/p/')
];

export function indexOfNumber(opts: LabeledNumber[], v: number): number {
  for (let i = 0; i < opts.length; i++) {
    if (Math.abs(opts[i].value - v) < 1e-6) {
      return i;
    }
  }
  return -1;
}

export function indexOfString(opts: LabeledString[], v: string): number {
  for (let i = 0; i < opts.length; i++) {
    if (opts[i].value === v) {
      return i;
    }
  }
  return -1;
}

export function bitrateLabel(bps: number): string {
  const i = indexOfNumber(BITRATE_OPTIONS, bps);
  if (i >= 0) {
    return BITRATE_OPTIONS[i].label;
  }
  if (bps <= 0) {
    return '原画';
  }
  return `${Math.round(bps / 1000000)} Mbps`;
}

/**
 * Normalise a user-typed server URL: trims, adds http:// when no scheme, strips trailing slashes
 * and a trailing '/web' or '/web/index.html' (users often paste the web UI address).
 * Returns '' when the input is not a usable http(s) URL.
 */
export function normalizeServerUrl(input: string): string {
  let u = input.trim();
  if (!u) {
    return '';
  }
  if (!/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(u)) {
    u = 'http://' + u;
  }
  const m = /^(https?):\/\/([^\/?#\s]+)([^?#\s]*)/i.exec(u);
  if (m === null) {
    return '';
  }
  const scheme = m[1].toLowerCase();
  const host = m[2];
  let path = m[3];
  if (!/^[A-Za-z0-9.\-\[\]:_%]+$/.test(host) || host.startsWith(':') || host.startsWith('.')) {
    return '';
  }
  const hashIdx = path.indexOf('#');
  if (hashIdx >= 0) {
    path = path.substring(0, hashIdx);
  }
  path = path.replace(/\/web(\/index\.html)?\/?$/i, '');
  path = path.replace(/\/+$/, '');
  return `${scheme}://${host}${path}`;
}

/** Display text for a source's state in the settings list. */
export function sourceStatusText(kind: string, enabled: boolean, token: string, cookie: string,
  quarkAuth: string = 'cookie', quarkRefreshToken: string = ''): string {
  if (!enabled) {
    return '已停用';
  }
  if (kind === 'quark') {
    if (quarkAuth === 'tv') {
      return quarkRefreshToken ? '已登录 (TV)' : '未登录';
    }
    return cookie ? '已登录' : '未登录';
  }
  return token ? '已登录' : '未登录';
}

export function kindLabel(kind: string): string {
  if (kind === 'jellyfin') {
    return 'Jellyfin';
  }
  if (kind === 'quark') {
    return '夸克网盘';
  }
  return 'Emby';
}

/** v4 read tokens are JWTs starting with 'eyJ'; v3 keys are 32 hex chars. */
export function tmdbKeyLooksValid(key: string): boolean {
  const k = key.trim();
  if (k.startsWith('eyJ')) {
    return k.length > 40;
  }
  return /^[0-9a-fA-F]{32}$/.test(k);
}
