// Pure cookie / string helpers for the Quark client. No @kit imports: unit-tested under node.

export class CookiePair {
  name: string = '';
  value: string = '';
}

export class CookieUtil {
  /** Parse "a=1; b=2" into ordered pairs. Empty / malformed segments are dropped. */
  static parse(cookie: string): CookiePair[] {
    const out: CookiePair[] = [];
    if (!cookie) {
      return out;
    }
    const segs = cookie.split(';');
    for (let i = 0; i < segs.length; i++) {
      const s = segs[i].trim();
      if (s.length === 0) {
        continue;
      }
      const eq = s.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const p = new CookiePair();
      p.name = s.substring(0, eq).trim();
      p.value = s.substring(eq + 1).trim();
      if (p.name.length === 0) {
        continue;
      }
      // later duplicates win
      const idx = CookieUtil.indexOf(out, p.name);
      if (idx >= 0) {
        out[idx] = p;
      } else {
        out.push(p);
      }
    }
    return out;
  }

  static stringify(pairs: CookiePair[]): string {
    return pairs.map((p: CookiePair) => p.name + '=' + p.value).join('; ');
  }

  static get(cookie: string, name: string): string {
    const pairs = CookieUtil.parse(cookie);
    const idx = CookieUtil.indexOf(pairs, name);
    return idx >= 0 ? pairs[idx].value : '';
  }

  /** Set or replace one cookie, keeping order of existing ones. */
  static set(cookie: string, name: string, value: string): string {
    const pairs = CookieUtil.parse(cookie);
    const idx = CookieUtil.indexOf(pairs, name);
    const p = new CookiePair();
    p.name = name;
    p.value = value;
    if (idx >= 0) {
      pairs[idx] = p;
    } else {
      pairs.push(p);
    }
    return CookieUtil.stringify(pairs);
  }

  /** Remove the named cookies. */
  static strip(cookie: string, names: string[]): string {
    const pairs = CookieUtil.parse(cookie).filter((p: CookiePair) => names.indexOf(p.name) < 0);
    return CookieUtil.stringify(pairs);
  }

  /** Merge b into a: values in b override, new names appended. */
  static merge(a: string, b: string): string {
    const pairs = CookieUtil.parse(a);
    const add = CookieUtil.parse(b);
    for (let i = 0; i < add.length; i++) {
      const idx = CookieUtil.indexOf(pairs, add[i].name);
      if (idx >= 0) {
        pairs[idx] = add[i];
      } else {
        pairs.push(add[i]);
      }
    }
    return CookieUtil.stringify(pairs);
  }

  /**
   * Parse Set-Cookie header lines ("__puus=xyz; Path=/; HttpOnly"). Only the leading name=value pair of each line
   * is used. Cookies with empty value, Max-Age<=0 or an Expires in the past are reported with value '' (= deletion).
   * A single string may hold several cookies separated by newlines.
   */
  static parseSetCookies(lines: string[], nowMs: number): CookiePair[] {
    const out: CookiePair[] = [];
    const all: string[] = [];
    lines.forEach((l: string) => {
      l.split(/\r?\n/).forEach((x: string) => {
        if (x.trim().length > 0) {
          all.push(x.trim());
        }
      });
    });
    for (let i = 0; i < all.length; i++) {
      const parts = all[i].split(';');
      const first = parts[0].trim();
      const eq = first.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const p = new CookiePair();
      p.name = first.substring(0, eq).trim();
      p.value = first.substring(eq + 1).trim();
      if (p.value.startsWith('"') && p.value.endsWith('"') && p.value.length >= 2) {
        p.value = p.value.substring(1, p.value.length - 1);
      }
      for (let j = 1; j < parts.length; j++) {
        const attr = parts[j].trim();
        const aeq = attr.indexOf('=');
        const an = (aeq >= 0 ? attr.substring(0, aeq) : attr).trim().toLowerCase();
        const av = aeq >= 0 ? attr.substring(aeq + 1).trim() : '';
        if (an === 'max-age') {
          const n = parseInt(av, 10);
          if (!isNaN(n) && n <= 0) {
            p.value = '';
          }
        } else if (an === 'expires') {
          const t = Date.parse(av);
          if (!isNaN(t) && t < nowMs) {
            p.value = '';
          }
        }
      }
      const idx = CookieUtil.indexOf(out, p.name);
      if (idx >= 0) {
        out[idx] = p;
      } else {
        out.push(p);
      }
    }
    return out;
  }

  /**
   * Apply Set-Cookie lines to a cookie string. When `only` is non-empty, only those names are applied.
   * Deletions (empty value) are ignored so a stray expiry can never wipe the session.
   * Returns the new cookie string (unchanged string if nothing applied).
   */
  static applySetCookies(cookie: string, lines: string[], only: string[], nowMs: number): string {
    let c = cookie;
    const pairs = CookieUtil.parseSetCookies(lines, nowMs);
    for (let i = 0; i < pairs.length; i++) {
      const p = pairs[i];
      if (only.length > 0 && only.indexOf(p.name) < 0) {
        continue;
      }
      if (p.value.length === 0) {
        continue;
      }
      if (CookieUtil.get(c, p.name) !== p.value) {
        c = CookieUtil.set(c, p.name, p.value);
      }
    }
    return c;
  }

  /** Normalise user-pasted cookie text: drop a leading "Cookie:" and newlines. */
  static normalize(raw: string): string {
    let s = raw.trim();
    if (s.toLowerCase().startsWith('cookie:')) {
      s = s.substring(7);
    }
    s = s.replace(/[\r\n]+/g, ' ');
    return CookieUtil.stringify(CookieUtil.parse(s));
  }

  private static indexOf(pairs: CookiePair[], name: string): number {
    for (let i = 0; i < pairs.length; i++) {
      if (pairs[i].name === name) {
        return i;
      }
    }
    return -1;
  }
}

const NAMED_ENTITIES: Record<string, string> = {
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': '\'', 'nbsp': ' ',
  'ldquo': '“', 'rdquo': '”', 'lsquo': '‘', 'rsquo': '’',
  'hellip': '…', 'mdash': '—', 'ndash': '–', 'middot': '·', 'times': '×'
};

/** Decode HTML entities (&amp; &#39; &#x27; and common named ones). Unknown entities are left untouched. */
export function htmlUnescape(s: string): string {
  if (!s || s.indexOf('&') < 0) {
    return s;
  }
  return s.replace(/&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/g, (m: string, body: string): string => {
    if (body.charAt(0) === '#') {
      const hex = body.charAt(1) === 'x' || body.charAt(1) === 'X';
      const code = hex ? parseInt(body.substring(2), 16) : parseInt(body.substring(1), 10);
      if (isNaN(code) || code < 0 || code > 0x10FFFF) {
        return m;
      }
      return String.fromCodePoint(code);
    }
    const v = NAMED_ENTITIES[body.toLowerCase()];
    return v !== undefined ? v : m;
  });
}

/** Human readable size, e.g. 1.5 GB */
export function formatSize(bytes: number): string {
  if (!(bytes > 0)) {
    return '0 B';
  }
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
  let v = bytes;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return (i === 0 ? v.toFixed(0) : v.toFixed(v >= 100 ? 0 : (v >= 10 ? 1 : 2))) + ' ' + units[i];
}

/** Lower-case extension without dot ('' if none). */
export function fileExt(name: string): string {
  const i = name.lastIndexOf('.');
  if (i <= 0 || i === name.length - 1) {
    return '';
  }
  return name.substring(i + 1).toLowerCase();
}

/** Name without the final extension. */
export function baseName(name: string): string {
  const i = name.lastIndexOf('.');
  return i > 0 ? name.substring(0, i) : name;
}

export const VIDEO_EXTS: string[] = ['mp4', 'mkv', 'avi', 'mov', 'm4v', 'ts', 'm2ts', 'mts', 'wmv', 'flv', 'webm',
  'rmvb', 'rm', 'mpg', 'mpeg', 'vob', '3gp', 'f4v'];
export const SUB_EXTS: string[] = ['srt', 'ass', 'ssa', 'vtt'];

export function isVideoName(name: string): boolean {
  return VIDEO_EXTS.indexOf(fileExt(name)) >= 0;
}

export function isSubtitleName(name: string): boolean {
  return SUB_EXTS.indexOf(fileExt(name)) >= 0;
}

/** Folders skipped during recursive scans (Synology / hidden / recycle / sample). */
export function isSkippedFolder(name: string): boolean {
  if (name.length === 0 || name.startsWith('.') || name.startsWith('@')) {
    return true;
  }
  const n = name.toLowerCase();
  return n === '#recycle' || n === '$recycle.bin' || n === 'lost+found' || n === 'sample' || n === 'samples';
}

/**
 * Subtitle language guess from the part between the video basename and the extension,
 * e.g. "Movie.chs.srt" -> zh-Hans. Returns [languageCode, title].
 */
export function subtitleLang(videoBase: string, subName: string): string[] {
  let mid = baseName(subName);
  if (mid.startsWith(videoBase)) {
    mid = mid.substring(videoBase.length);
  }
  const t = mid.replace(/^[.\-_ ]+/, '').toLowerCase();
  if (t.length === 0) {
    return ['', '外挂字幕'];
  }
  if (/(chs|sc|zh-?hans|gb|简)/.test(t) && /(cht|tc|zh-?hant|big5|繁)/.test(t)) {
    return ['zh', '简繁'];
  }
  if (/(chs|^sc$|zh-?cn|zh-?hans|gb|简)/.test(t)) {
    return ['zh-Hans', '简体中文'];
  }
  if (/(cht|^tc$|zh-?tw|zh-?hk|zh-?hant|big5|繁)/.test(t)) {
    return ['zh-Hant', '繁体中文'];
  }
  if (/(^zh|chi|chn|中)/.test(t)) {
    return ['zh', '中文'];
  }
  if (/(^en|eng|英)/.test(t)) {
    return ['en', 'English'];
  }
  if (/(^ja|jpn|jap|日)/.test(t)) {
    return ['ja', '日本語'];
  }
  if (/(^ko|kor|韩)/.test(t)) {
    return ['ko', '한국어'];
  }
  return ['', mid.replace(/^[.\-_ ]+/, '')];
}

/** Subtitle belongs to the video if names match after stripping extensions (and an optional language suffix). */
export function subtitleMatches(videoName: string, subName: string): boolean {
  const vb = baseName(videoName).toLowerCase();
  const sb = baseName(subName).toLowerCase();
  if (sb === vb) {
    return true;
  }
  if (!sb.startsWith(vb)) {
    return false;
  }
  const c = sb.charAt(vb.length);
  return c === '.' || c === '_' || c === '-' || c === ' ';
}
