import { QualityOption, SubtitleTrack } from '../common/Models';
import { FlicxId, FlicxKind, FlicxSearchResponse, FlicxSource, FlicxSourceResponse, FlicxSubtitleResponse,
  FlicxTitleItem } from './FlicxModels';

export const FLICX_ORIGIN: string = 'https://fli.cx';
export const FLICX_ID: string = 'flicx';

function clean(value: string | undefined): string {
  return typeof value === 'string' ? value.trim() : '';
}

function positive(value: number | undefined): number {
  return typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : 0;
}

const CHINESE_ORDER: string[] = ['zh-hans', 'zh-cn', 'zh', 'zh-hant', 'zh-tw', 'zh-hk'];
const LANG_NAMES: Record<string, string> = {
  'zh': '中文', 'zh-hans': '简体中文', 'zh-cn': '简体中文', 'zh-hant': '繁體中文', 'zh-tw': '繁體中文',
  'zh-hk': '繁體中文（香港）', 'en': '英语', 'ar': '阿拉伯语', 'ja': '日语', 'ko': '韩语',
  'es': '西班牙语', 'fr': '法语', 'de': '德语'
};

function subtitleOrder(track: SubtitleTrack): number {
  const i = CHINESE_ORDER.indexOf(track.language.toLowerCase());
  return i >= 0 ? i : CHINESE_ORDER.length;
}

export class FlicxMapper {
  static isCjkQuery(term: string): boolean {
    return /[\u3040-\u30ff\u3400-\u9fff\uf900-\ufaff]/.test(term);
  }

  static isImdbId(id: string): boolean {
    return /^tt[0-9]{7,12}$/.test(id);
  }

  static mediaId(kind: FlicxKind, imdbId: string): string {
    if (!FlicxMapper.isImdbId(imdbId)) {
      throw new Error('缺少有效的 IMDb 编号');
    }
    return 'flicx-' + kind + '-' + imdbId;
  }

  static parseMediaId(value: string): FlicxId | undefined {
    const m = /^flicx-(movie|tv)-(tt[0-9]{7,12})(?:-s(0|[1-9]\d{0,4})(?:e([1-9]\d{0,5}))?)?$/.exec(value);
    if (!m || (m[1] === 'movie' && m[3] !== undefined)) {
      return undefined;
    }
    const id = new FlicxId();
    id.kind = m[1] === 'movie' ? 'movie' : 'tv';
    id.imdbId = m[2];
    id.season = m[3] === undefined ? -1 : Number(m[3]);
    id.episode = m[4] === undefined ? -1 : Number(m[4]);
    return id;
  }

  /** Flicx web page for a film or a single episode; '' for series/season ids and foreign ids. */
  static watchPage(mediaId: string): string {
    const id = FlicxMapper.parseMediaId(mediaId);
    if (id === undefined) {
      return '';
    }
    if (id.kind === 'movie') {
      return FLICX_ORIGIN + '/watch/' + id.imdbId;
    }
    if (id.season < 0 || id.episode < 0) {
      return '';
    }
    return FLICX_ORIGIN + '/watch/' + id.imdbId + '/s' + id.season + 'e' + id.episode;
  }

  static absoluteUrl(path: string | undefined, baseUrl: string = FLICX_ORIGIN): string {
    const s = clean(path);
    if (!s || /[\s\\]/.test(s)) {
      return '';
    }
    if (/^https:\/\/[^/@?#]+(?:[/?#]|$)/i.test(s)) {
      return s;
    }
    return s.startsWith('/') && !s.startsWith('//') ? baseUrl.replace(/\/$/, '') + s : '';
  }

  static searchItems(response: FlicxSearchResponse, sourceId: string): FlicxTitleItem[] {
    const out: FlicxTitleItem[] = [];
    const seen = new Set<string>();
    if (!response || !Array.isArray(response.results)) {
      return out;
    }
    for (const row of response.results) {
      if (!row || !FlicxMapper.isImdbId(clean(row.id)) || !clean(row.title) ||
        (row.kind !== undefined && row.kind !== 'film' && row.kind !== 'show')) {
        continue;
      }
      const item = new FlicxTitleItem();
      item.imdbId = clean(row.id);
      item.slug = clean(row.slug);
      item.id = FlicxMapper.mediaId(row.kind === 'show' ? 'tv' : 'movie', item.imdbId);
      if (seen.has(item.id)) {
        continue;
      }
      seen.add(item.id);
      item.sourceId = sourceId;
      item.type = row.kind === 'show' ? 'series' : 'movie';
      item.title = clean(row.title);
      item.year = positive(row.year);
      item.rating = positive(row.rating);
      item.runtimeMs = positive(row.runtime) * 60000;
      item.genres = Array.isArray(row.genres) ? row.genres.filter((g: string) => typeof g === 'string') : [];
      item.images.poster = FlicxMapper.absoluteUrl(row.poster) || 'https://s.fli.cx/a/poster/medium/' + item.imdbId + '/img';
      item.images.backdrop = FlicxMapper.absoluteUrl(row.still);
      out.push(item);
    }
    return out;
  }

  static sources(response: FlicxSourceResponse, baseUrl: string = FLICX_ORIGIN): QualityOption[] {
    const out: QualityOption[] = [];
    if (!response || !Array.isArray(response.sources)) {
      return out;
    }
    const rows = response.sources.filter((s: FlicxSource) => !!s && s.kind === 'hls' && s.has === true);
    rows.sort((a: FlicxSource, b: FlicxSource) => Number(b.group === 'dedicated') - Number(a.group === 'dedicated'));
    const seen = new Set<string>();
    for (const s of rows) {
      const url = FlicxMapper.absoluteUrl(s.src, baseUrl);
      if (!url || seen.has(url)) {
        continue;
      }
      seen.add(url);
      const option = new QualityOption();
      option.url = url;
      option.label = clean(s.name) || '线路 ' + String(out.length + 1);
      if (clean(s.quality)) {
        option.label += ' · ' + clean(s.quality);
      }
      out.push(option);
    }
    return out;
  }

  static subtitles(response: FlicxSubtitleResponse, baseUrl: string = FLICX_ORIGIN): SubtitleTrack[] {
    const out: SubtitleTrack[] = [];
    if (!response || !Array.isArray(response.tracks)) {
      return out;
    }
    const seen = new Set<string>();
    for (let i = 0; i < response.tracks.length; i++) {
      const raw = response.tracks[i];
      if (!raw || clean(raw.format).toLowerCase() !== 'vtt') {
        continue;
      }
      const url = FlicxMapper.absoluteUrl(raw.src, baseUrl);
      const language = clean(raw.language);
      if (!url || !language || seen.has(url)) {
        continue;
      }
      seen.add(url);
      const t = new SubtitleTrack();
      t.index = i;
      t.isExternal = true;
      t.language = language;
      t.url = url;
      t.codec = 'vtt';
      t.title = LANG_NAMES[language.toLowerCase()] || language;
      if (raw.sdh === true) {
        t.title += '（听障）';
      }
      if (clean(raw.label)) {
        t.title += ' · ' + clean(raw.label);
      }
      out.push(t);
    }
    return out.sort((a: SubtitleTrack, b: SubtitleTrack) => subtitleOrder(a) - subtitleOrder(b) || a.index - b.index);
  }
}
