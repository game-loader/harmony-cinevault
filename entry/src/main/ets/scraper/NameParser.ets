// Pure filename / path parser for scraping drive files. No @kit imports: unit-tested under node.

export class ParsedName {
  title: string = '';
  /** Alternative title (e.g. the English half of "流浪地球2 The Wandering Earth 2"), '' if none */
  altTitle: string = '';
  year: number = 0;
  season: number = -1;
  episode: number = -1;
  /** Last episode for multi-episode files (S01E01-E02), -1 otherwise */
  episodeEnd: number = -1;
  isTv: boolean = false;
  /** Quality / release noise that was removed, e.g. "1080p BluRay x264" */
  extra: string = '';
  /** Sample, trailer or other non-feature file that should not be scraped */
  excluded: boolean = false;
}

const VIDEO_EXT: string[] = ['mkv', 'mp4', 'avi', 'mov', 'wmv', 'flv', 'ts', 'm2ts', 'mts', 'rmvb', 'rm', 'webm',
  'mpg', 'mpeg', 'm4v', 'iso', 'vob', '3gp', 'f4v', 'tp', 'strm'];
const SUB_EXT: string[] = ['srt', 'ass', 'ssa', 'vtt', 'sub', 'sup', 'idx'];

const CN_DIGITS: Record<string, number> = {
  '零': 0, '〇': 0, '一': 1, '壹': 1, '二': 2, '贰': 2, '两': 2, '三': 3, '叁': 3, '四': 4, '肆': 4,
  '五': 5, '伍': 5, '六': 6, '陆': 6, '七': 7, '柒': 7, '八': 8, '捌': 8, '九': 9, '玖': 9
};
const CN_UNITS: Record<string, number> = { '十': 10, '拾': 10, '百': 100, '佰': 100, '千': 1000, '仟': 1000 };

/** Release-noise tokens (lowercase, compared against separator-split tokens). */
const NOISE: string[] = [
  '2160p', '1080p', '1080i', '720p', '576p', '480p', '360p', '4k', '8k', 'uhd', 'fhd', 'hd', 'sd', 'bluray', 'blu-ray',
  'bdrip', 'brrip', 'bdremux', 'bd', 'remux', 'web-dl', 'webdl', 'webrip', 'web', 'hdtv', 'hdrip', 'dvdrip', 'dvd',
  'dvdscr', 'hdcam', 'cam', 'ts', 'tc', 'x264', 'x265', 'h264', 'h265', 'h.264', 'h.265', 'hevc', 'avc', 'av1', 'vp9',
  'xvid', 'divx', 'aac', 'aac2.0', 'ac3', 'eac3', 'dts', 'dts-hd', 'dtshd', 'truehd', 'atmos', 'flac', 'mp3', 'ddp',
  'dd5.1', 'ddp5.1', 'dd+', '5.1', '7.1', '2.0', 'hdr', 'hdr10', 'hdr10+', 'dv', 'dovi', 'sdr', '10bit', '8bit',
  '12bit', 'hi10p', '60fps', '120fps', 'proper', 'repack', 'extended', 'unrated', 'remastered', 'uncut', 'imax',
  'internal', 'limited', 'complete', 'multi', 'dual', 'nf', 'amzn', 'dsnp', 'hmax', 'atvp', 'itunes', 'hulu',
  'chs', 'cht', 'chi', 'eng', 'gb', 'big5', 'subbed', 'dubbed', 'criterion', 'dc', 'directors', 'cut'
];
const NOISE_CN: string[] = ['中英字幕', '中英双字', '中英双语', '双语字幕', '国英双语', '国粤双语', '国语', '粤语', '中字',
  '双语', '简体', '繁体', '简繁', '简中', '繁中', '内封', '内嵌', '外挂', '高清', '超清', '蓝光', '原盘', '完整版', '未删减',
  '无删减', '导演剪辑版', '加长版', '特效字幕', '中文字幕', '字幕', '官方中字', '国配', '台配', '无水印', '收藏版'];

/** Folder names that never carry a title (library roots, quality folders...). */
const GENERIC_DIRS: string[] = ['movies', 'movie', 'films', 'film', 'tv', 'tv shows', 'tvshows', 'shows', 'series',
  'anime', 'video', 'videos', 'media', 'downloads', 'download', '电影', '电视剧', '剧集', '动漫', '动画', '纪录片', '综艺',
  '视频', '影视', '下载', '我的资源', '来自分享', '美剧', '日剧', '韩剧', '国产剧', '港剧', '台剧', '英剧', '番剧',
  '华语电影', '欧美电影', '日韩电影', '高清电影', '4k电影', '合集', 'extras', 'featurettes', 'subs', 'subtitles'];

export function fileExt(name: string): string {
  const i = name.lastIndexOf('.');
  return i > 0 && i >= name.length - 6 ? name.substring(i + 1).toLowerCase() : '';
}

export function stripExt(name: string): string {
  const e = fileExt(name);
  return e.length > 0 ? name.substring(0, name.length - e.length - 1) : name;
}

export function isVideoFile(name: string): boolean {
  return VIDEO_EXT.indexOf(fileExt(name)) >= 0;
}

export function isSubtitleFile(name: string): boolean {
  return SUB_EXT.indexOf(fileExt(name)) >= 0;
}

/** "十二" -> 12, "一百零五" -> 105, "两" -> 2, "12" -> 12, unknown -> -1 */
export function chineseToNumber(s: string): number {
  const t = s.trim();
  if (t.length === 0) {
    return -1;
  }
  if (/^\d+$/.test(t)) {
    return parseInt(t, 10);
  }
  let total = 0;
  let cur = 0;
  let any = false;
  for (let i = 0; i < t.length; i++) {
    const c = t.charAt(i);
    const d = CN_DIGITS[c];
    const u = CN_UNITS[c];
    if (d !== undefined) {
      cur = d;
      any = true;
    } else if (u !== undefined) {
      total += (cur === 0 ? 1 : cur) * u;
      cur = 0;
      any = true;
    } else {
      return -1;
    }
  }
  return any ? total + cur : -1;
}

const CN_NUM: string = '0-9零〇一二两三四五六七八九十百';
const RE_SXXEYY: RegExp = new RegExp('\\bS(\\d{1,2})\\s?E[Pp]?(\\d{1,4})(?:\\s?-\\s?E?[Pp]?(\\d{1,4})(?![\\dpPiI])|E(\\d{1,4}))?', 'i');
const RE_NXM: RegExp = new RegExp('\\b(\\d{1,2})x(\\d{2,3})\\b', 'i');
const RE_CN_SEASON: RegExp = new RegExp('第\\s*([' + CN_NUM + ']+)\\s*季');
const RE_EN_SEASON: RegExp = new RegExp('\\bSeason\\s*(\\d{1,2})\\b', 'i');
const RE_S_ONLY: RegExp = new RegExp('\\bS(\\d{1,2})\\b', 'i');
const RE_CN_EP: RegExp = new RegExp('第\\s*([' + CN_NUM + ']+)\\s*[集话話回期]');
const RE_CN_EP2: RegExp = new RegExp('(?:^|\\s)(\\d{1,4})\\s*[集话話]');
const RE_EP: RegExp = new RegExp('\\bE[Pp]?\\s?(\\d{1,4})(?:\\s?-\\s?E?[Pp]?(\\d{1,4})(?![\\dpPiI]))?\\b', 'i');
const RE_YEAR: RegExp = new RegExp('(?:^|[\\s(\\[（【])((?:19|20)\\d{2})(?=$|[\\s)\\]）】])', 'g');
const RE_EXCLUDE: RegExp = new RegExp('(?:^|[\\s._\\-\\[(])(sample|trailer|teaser|featurette|behind\\s?the\\s?scenes)(?:$|[\\s._\\-\\])])|预告|花絮|片花|样片|幕后', 'i');
const RE_DOTTED_NOISE: RegExp = new RegExp('(^|[\\s._\\-\\[(])(h\\.?26[45]|x\\.?26[45]|ddp?\\+?\\s?[257]\\.[01]|aac\\s?[257]\\.[01]|e?ac3\\s?[257]\\.[01]|dts-?hd(?:[\\s.]ma)?|truehd\\s?[57]\\.1|[57]\\.1|2\\.0|web-?dl|blu-?ray|hdr10\\+?|dts-?x)(?=$|[\\s._\\-\\])])', 'gi');
const RE_SITE: RegExp = new RegExp('(?:https?://)?(?:www\\.)?[a-z0-9\\-]+\\.(?:com|net|org|cc|cn|tv|me|xyz|top|vip|la|io)\\b', 'gi');
const RE_CN_JUNK: RegExp = new RegExp('(?:全|共)\\s*[' + CN_NUM + ']+\\s*[集话話季]|更新至\\s*[' + CN_NUM + ']*\\s*[集话話]?|已?完结|持续更新|连载中', 'g');
const RE_CJK: RegExp = new RegExp('[\\u3040-\\u30ff\\u3400-\\u9fff\\uf900-\\ufaff]');
const RE_LATIN: RegExp = new RegExp('[A-Za-z]{2,}');

function minPos(cur: number, p: number): number {
  if (p < 0) {
    return cur;
  }
  return cur < 0 || p < cur ? p : cur;
}

function isNoiseToken(tok: string): boolean {
  const t = tok.toLowerCase().replace(new RegExp('^[\\[(（【]+|[\\])）】,]+$', 'g'), '');
  if (t.length === 0) {
    return false;
  }
  if (NOISE.indexOf(t) >= 0 || NOISE_CN.indexOf(t) >= 0) {
    return true;
  }
  const dash = t.indexOf('-');
  if (dash > 0 && NOISE.indexOf(t.substring(0, dash)) >= 0) {
    return true;   // "x264-GROUP"
  }
  return new RegExp('^(?:\\d{3,4}[pi]|\\d{1,2}bit|\\d+fps|\\d+(?:\\.\\d+)?(?:gb|mb)|[257]\\.[01]|ddp?[257]\\.[01])$').test(t);
}

/** Replace brackets; numeric-only bracket content (not a year) becomes an episode hint. */
class BracketResult {
  text: string = '';
  episode: number = -1;
  removedFirst: string = '';
}

function handleBrackets(src: string): BracketResult {
  const res = new BracketResult();
  let s = src.trim();
  // leading release-group bracket: "[字幕组] Title" / "【xx发布】Title"
  const lead = new RegExp('^[\\[【]([^\\]】]*)[\\]】]\\s*').exec(s);
  if (lead !== null) {
    const rest = s.substring(lead[0].length).trim();
    if (rest.length > 0) {
      const inner = lead[1].trim();
      if (new RegExp('^(?:19|20)\\d{2}$').test(inner)) {
        s = rest + ' (' + inner + ')';
      } else {
        res.removedFirst = inner;
        s = rest;
      }
    }
  }
  // inner brackets: numeric -> episode, noise/sites -> drop, other -> keep as text
  s = s.replace(new RegExp('[\\[【]([^\\]】]*)[\\]】]', 'g'), (whole: string, inner: string): string => {
    const t = inner.trim();
    if (new RegExp('^\\d{1,4}(?:v\\d)?$', 'i').test(t) && !new RegExp('^(?:19|20)\\d{2}$').test(t)) {
      if (res.episode < 0) {
        res.episode = parseInt(t, 10);
      }
      return ' ';
    }
    if (new RegExp('^(?:19|20)\\d{2}$').test(t)) {
      return ' (' + t + ') ';
    }
    return ' ' + t + ' ';
  });
  res.text = s.replace(new RegExp('[《》「」『』]', 'g'), ' ');
  return res;
}

function cleanTitle(t: string): string {
  let s = t;
  NOISE_CN.forEach((w: string) => {
    s = s.split(w).join(' ');
  });
  s = s.replace(new RegExp('[()（）\\[\\]【】{}]', 'g'), ' ');
  s = s.replace(new RegExp('\\s+', 'g'), ' ').trim();
  s = s.replace(new RegExp('^[\\s\\-–—:：,，|·~]+|[\\s\\-–—:：,，|·~&+]+$', 'g'), '').trim();
  return s;
}

/** Split "流浪地球2 The Wandering Earth 2" into CJK title + latin alt title. */
function splitBilingual(t: string, out: ParsedName): void {
  if (!RE_CJK.test(t) || !RE_LATIN.test(t)) {
    out.title = t;
    return;
  }
  const words = t.split(' ');
  // find the contiguous CJK-containing run
  let first = -1;
  let last = -1;
  for (let i = 0; i < words.length; i++) {
    if (RE_CJK.test(words[i])) {
      if (first < 0) {
        first = i;
      }
      last = i;
    }
  }
  // attach pure-number words directly after the CJK run ("流浪地球 2")
  while (last + 1 < words.length && new RegExp('^\\d{1,2}$').test(words[last + 1]) && last + 2 < words.length) {
    last++;
  }
  const cjk = words.slice(first, last + 1).join(' ');
  const latin = words.slice(0, first).concat(words.slice(last + 1)).join(' ').trim();
  out.title = cleanTitle(cjk);
  out.altTitle = RE_LATIN.test(latin) ? cleanTitle(latin) : '';
  if (out.title.length === 0) {
    out.title = out.altTitle;
    out.altTitle = '';
  }
}

const SENTINEL: string = '§';
const WEAK_NOISE: string[] = ['hd', 'sd', 'ts', 'tc', 'dc', 'cut', 'dual', 'multi', 'complete', 'web', 'cam', 'dv', 'gb',
  'chi', 'eng', 'directors', 'criterion', 'extended', 'limited', 'internal', 'unrated', 'imax', 'uncut', 'remastered',
  'proper', 'repack', 'dubbed', 'subbed', 'mp3', 'flac', 'dts', 'atmos'];
const RE_DASH_EP: RegExp = new RegExp('\\s-\\s(\\d{1,4})(?:v\\d)?(?=\\s|$)');
const RE_EPISODE_WORD: RegExp = new RegExp('\\bEpisode\\s?(\\d{1,4})\\b', 'i');

function isStrongNoise(tok: string): boolean {
  if (tok === SENTINEL) {
    return true;
  }
  const t = tok.toLowerCase().replace(new RegExp('^[\\[(（【]+|[\\])）】,]+$', 'g'), '');
  return isNoiseToken(t) && WEAK_NOISE.indexOf(t) < 0;
}

class Tok {
  text: string = '';
  pos: number = 0;
}

function tokens(s: string): Tok[] {
  const out: Tok[] = [];
  const re = new RegExp('\\S+', 'g');
  let m = re.exec(s);
  while (m !== null) {
    const t = new Tok();
    t.text = m[0];
    t.pos = m.index;
    out.push(t);
    m = re.exec(s);
  }
  return out;
}

function trimNoiseWords(t: string): string {
  const words = t.split(' ').filter((w: string): boolean => w.length > 0);
  while (words.length > 0 && (isNoiseToken(words[0]) || words[0] === SENTINEL)) {
    words.shift();
  }
  while (words.length > 0 && (isNoiseToken(words[words.length - 1]) || words[words.length - 1] === SENTINEL)) {
    words.pop();
  }
  return words.filter((w: string): boolean => w !== SENTINEL).join(' ');
}

function toInt(s: string | undefined): number {
  if (s === undefined || s === null || s.length === 0) {
    return -1;
  }
  return parseInt(s, 10);
}

/** Parse a single name (file base name without extension, or a folder name). */
export function parseSegment(raw: string): ParsedName {
  const out = new ParsedName();
  const extras: string[] = [];
  let s = raw.replace(RE_SITE, ' ');
  const br = handleBrackets(s);
  s = br.text;
  s = s.replace(RE_DOTTED_NOISE, (whole: string, pre: string, tok: string): string => {
    extras.push(tok);
    return pre + ' ' + SENTINEL + ' ';
  });
  s = s.replace(RE_CN_JUNK, ' ' + SENTINEL + ' ');
  s = s.replace(new RegExp('[._]+', 'g'), ' ').replace(new RegExp('\\s+', 'g'), ' ').trim();

  let cut = -1;
  const se = RE_SXXEYY.exec(s);
  if (se !== null) {
    out.season = toInt(se[1]);
    out.episode = toInt(se[2]);
    const end = toInt(se[3] !== undefined ? se[3] : se[4]);
    if (end > out.episode) {
      out.episodeEnd = end;
    }
    cut = minPos(cut, se.index);
  } else {
    const nx = RE_NXM.exec(s);
    if (nx !== null) {
      out.season = toInt(nx[1]);
      out.episode = toInt(nx[2]);
      cut = minPos(cut, nx.index);
    }
  }
  if (out.season < 0) {
    const cs = RE_CN_SEASON.exec(s);
    const es = RE_EN_SEASON.exec(s);
    const so = RE_S_ONLY.exec(s);
    if (cs !== null) {
      out.season = chineseToNumber(cs[1]);
      cut = minPos(cut, cs.index);
    } else if (es !== null) {
      out.season = toInt(es[1]);
      cut = minPos(cut, es.index);
    } else if (so !== null) {
      out.season = toInt(so[1]);
      cut = minPos(cut, so.index);
    }
  }
  if (out.episode < 0) {
    const ce = RE_CN_EP.exec(s);
    const ew = RE_EPISODE_WORD.exec(s);
    const ep = RE_EP.exec(s);
    const de = RE_DASH_EP.exec(s);
    const c2 = RE_CN_EP2.exec(s);
    if (ce !== null) {
      out.episode = chineseToNumber(ce[1]);
      cut = minPos(cut, ce.index);
    } else if (ew !== null) {
      out.episode = toInt(ew[1]);
      cut = minPos(cut, ew.index);
    } else if (ep !== null) {
      out.episode = toInt(ep[1]);
      const end = toInt(ep[2]);
      if (end > out.episode) {
        out.episodeEnd = end;
      }
      cut = minPos(cut, ep.index);
    } else if (de !== null) {
      out.episode = toInt(de[1]);
      cut = minPos(cut, de.index);
    } else if (c2 !== null) {
      out.episode = toInt(c2[1]);
      cut = minPos(cut, c2.index);
    } else if (new RegExp('^\\d{1,3}$').test(s)) {
      out.episode = toInt(s);
      cut = 0;
    } else if (br.episode >= 0) {
      out.episode = br.episode;
    }
  }
  // year: the last plausible year that is not the very first word
  const yre = new RegExp(RE_YEAR.source, 'g');
  let ym = yre.exec(s);
  let yPos = -1;
  let yVal = 0;
  while (ym !== null) {
    const p = ym.index + ym[0].length - 4;
    if (p > 0) {
      yPos = p;
      yVal = toInt(ym[1]);
    }
    yre.lastIndex = ym.index + 1;
    ym = yre.exec(s);
  }
  if (yPos > 0 && yVal >= 1900 && yVal <= 2099) {
    out.year = yVal;
    cut = minPos(cut, yPos);
  }
  // release noise
  tokens(s).forEach((t: Tok) => {
    if (t.text !== SENTINEL && isNoiseToken(t.text)) {
      extras.push(t.text);
    }
    if (t.pos > 0 && isStrongNoise(t.text)) {
      cut = minPos(cut, t.pos);
    }
  });
  NOISE_CN.forEach((w: string) => {
    const p = s.indexOf(w);
    if (p > 0) {
      cut = minPos(cut, p);
    }
  });
  let title = cut >= 0 ? s.substring(0, cut) : s;
  title = cleanTitle(trimNoiseWords(cleanTitle(title)));
  if (title.length === 0 && br.removedFirst.length > 0 && cut !== 0) {
    title = cleanTitle(br.removedFirst);
  }
  splitBilingual(title, out);
  out.isTv = out.season >= 0 || out.episode >= 0;
  out.extra = extras.join(' ');
  out.excluded = RE_EXCLUDE.test(raw);
  return out;
}

function isGenericDir(name: string): boolean {
  const n = name.trim().toLowerCase();
  if (n.length === 0 || GENERIC_DIRS.indexOf(n) >= 0) {
    return true;
  }
  return new RegExp('^(?:\\d{3,4}p|4k|uhd|hdr|bluray|web-?dl|remux)$', 'i').test(n);
}

/** A folder that is only a season marker: "Season 2", "S02", "第二季", "Specials". */
function seasonOnlyDir(name: string): number {
  const n = name.trim();
  if (new RegExp('^(?:specials?|特别篇|sp)$', 'i').test(n)) {
    return 0;
  }
  const m = new RegExp('^(?:season\\s*(\\d{1,2})|s(\\d{1,2})|第\\s*([' + CN_NUM + ']+)\\s*季)$', 'i').exec(n);
  if (m === null) {
    return -1;
  }
  if (m[1] !== undefined) {
    return parseInt(m[1], 10);
  }
  if (m[2] !== undefined) {
    return parseInt(m[2], 10);
  }
  return chineseToNumber(m[3]);
}

/** True if the file-level title is useless (empty, only digits, only generic words). */
function weakTitle(t: string): boolean {
  const n = t.trim();
  return n.length === 0 || new RegExp('^\\d{1,3}$').test(n) || new RegExp('^[\\s\\-]+$').test(n) || isGenericDir(n) ||
    new RegExp('^(?:episode|ep|e|part|cd|disc|vol)\\s*\\d*$', 'i').test(n);
}

/**
 * Parse a path like "Breaking Bad/Season 2/E03.mkv" or a bare filename. Parent folders fill in
 * the show title, season and year when the file name lacks them.
 */
export function parseName(path: string): ParsedName {
  const parts = path.split(new RegExp('[/\\\\]+')).filter((x: string): boolean => x.trim().length > 0);
  if (parts.length === 0) {
    return new ParsedName();
  }
  const file = parts[parts.length - 1];
  const base = isVideoFile(file) || isSubtitleFile(file) ? stripExt(file) : file;
  const out = parseSegment(base);
  // exclusion also if a parent folder is "Samples"/"Trailers"/"花絮"
  for (let i = 0; i < parts.length - 1; i++) {
    if (new RegExp('^(?:samples?|trailers?|extras|featurettes|花絮|预告片?|幕后)$', 'i').test(parts[i].trim())) {
      out.excluded = true;
    }
  }
  const needTitle = weakTitle(out.title);
  for (let i = parts.length - 2; i >= 0; i--) {
    const dir = parts[i];
    const so = seasonOnlyDir(dir);
    if (so >= 0) {
      if (out.season < 0) {
        out.season = so;
      }
      continue;
    }
    if (isGenericDir(dir)) {
      continue;
    }
    const pd = parseSegment(dir);
    if (out.season < 0 && pd.season >= 0 && (out.episode >= 0 || needTitle)) {
      out.season = pd.season;
    }
    if (needTitle && !weakTitle(pd.title)) {
      out.title = pd.title;
      out.altTitle = pd.altTitle;
      if (out.year === 0) {
        out.year = pd.year;
      }
      break;
    }
    if (!needTitle) {
      if (out.year === 0 && pd.year > 0 && normKey(pd.title) === normKey(out.title)) {
        out.year = pd.year;
      }
      break;
    }
  }
  if (weakTitle(out.title)) {
    out.title = cleanTitle(base.replace(new RegExp('[._]+', 'g'), ' '));
  }
  out.isTv = out.season >= 0 || out.episode >= 0;
  if (out.isTv && out.season < 0 && out.episode >= 0) {
    out.season = 1;
  }
  return out;
}

/** Normalised comparison key: lowercase, no punctuation/spaces, full-width -> half-width digits. */
export function normKey(s: string): string {
  let t = s.toLowerCase();
  t = t.replace(new RegExp('[０-９]', 'g'), (c: string): string => String.fromCharCode(c.charCodeAt(0) - 0xFEE0));
  t = t.replace(new RegExp('&', 'g'), 'and');
  t = t.replace(new RegExp('^(?:the|a|an)\\s+'), '');
  return t.replace(new RegExp('[\\s\\-–—_.,，。:：;；!！?？\'"’‘“”·・()（）\\[\\]【】《》<>~/\\\\]', 'g'), '');
}

/** Similarity 0..1 between two titles (exact key = 1, containment, then bigram Dice). */
export function titleSimilarity(a: string, b: string): number {
  const x = normKey(a);
  const y = normKey(b);
  if (x.length === 0 || y.length === 0) {
    return 0;
  }
  if (x === y) {
    return 1;
  }
  if (x.indexOf(y) >= 0 || y.indexOf(x) >= 0) {
    const r = Math.min(x.length, y.length) / Math.max(x.length, y.length);
    return 0.6 + 0.3 * r;
  }
  const bx = bigrams(x);
  const by = bigrams(y);
  if (bx.length === 0 || by.length === 0) {
    return 0;
  }
  let hit = 0;
  const used: boolean[] = by.map((): boolean => false);
  bx.forEach((g: string) => {
    for (let i = 0; i < by.length; i++) {
      if (!used[i] && by[i] === g) {
        used[i] = true;
        hit++;
        break;
      }
    }
  });
  return (2 * hit) / (bx.length + by.length) * 0.9;
}

function bigrams(s: string): string[] {
  const out: string[] = [];
  if (s.length === 1) {
    out.push(s);
  }
  for (let i = 0; i + 1 < s.length; i++) {
    out.push(s.substring(i, i + 2));
  }
  return out;
}

/** Display name for an unmatched file: cleaned title, plus SxxEyy when present. */
export function displayName(p: ParsedName): string {
  let t = p.title;
  if (p.isTv && p.episode >= 0) {
    const s = p.season >= 0 ? p.season : 1;
    t = t + ' S' + (s < 10 ? '0' : '') + s + 'E' + (p.episode < 10 ? '0' : '') + p.episode;
  } else if (p.year > 0) {
    t = t + ' (' + p.year + ')';
  }
  return t.trim();
}
