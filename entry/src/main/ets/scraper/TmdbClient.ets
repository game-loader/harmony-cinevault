import { request, buildQuery, HttpError } from '../common/Http';
import { Settings, AppSettings } from '../common/Settings';
import { MediaItem, Person } from '../common/Models';
import { ParsedName, titleSimilarity, normKey } from './NameParser';
import {
  TmdbSearchResponse, TmdbSearchResult, TmdbDetail, TmdbSeason, TmdbEpisode, TmdbImage, TmdbCast, TmdbCrew,
  TmdbErrorBody, TmdbReleaseCountry, TmdbReleaseDate, TmdbGenre, TmdbCompany, TmdbContentRating, TmdbSeasonSummary
} from './TmdbTypes';

export type TmdbKind = 'movie' | 'tv';

export class TmdbCandidate {
  kind: TmdbKind = 'movie';
  result: TmdbSearchResult = {};
  score: number = 0;
}

const CACHE_MAX: number = 400;
const MAX_CAST: number = 20;

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(() => resolve(), ms);
  });
}

function yearOf(date: string | null | undefined): number {
  if (date === undefined || date === null || date.length < 4) {
    return 0;
  }
  const y = parseInt(date.substring(0, 4), 10);
  return isNaN(y) ? 0 : y;
}

function str(s: string | null | undefined): string {
  return s === undefined || s === null ? '' : s;
}

function num(n: number | null | undefined): number {
  return n === undefined || n === null || isNaN(n) ? 0 : n;
}

const RE_CJK: RegExp = new RegExp('[\\u3040-\\u30ff\\u3400-\\u9fff\\uf900-\\ufaff]');

/** TMDB v3 client with an in-memory response cache and 429 back-off. */
export class TmdbClient {
  private static cache: Map<string, Promise<string>> = new Map<string, Promise<string>>();

  static clearCache(): void {
    TmdbClient.cache.clear();
  }

  private static settings(): AppSettings {
    const s = Settings.get();
    if (s.tmdbApiKey.trim().length === 0) {
      throw new Error('请先在设置中填写 TMDB API Key');
    }
    return s;
  }

  static imageUrl(path: string | null | undefined, size: string): string {
    const p = str(path);
    if (p.length === 0) {
      return '';
    }
    let base = Settings.get().tmdbImageBase;
    if (base.length === 0) {
      base = 'https://image.tmdb.org/t/p/';
    }
    if (!base.endsWith('/')) {
      base = base + '/';
    }
    return base + size + (p.startsWith('/') ? p : '/' + p);
  }

  private static langPrefix(): string {
    const l = Settings.get().tmdbLanguage;
    const i = l.indexOf('-');
    return (i > 0 ? l.substring(0, i) : l).toLowerCase();
  }

  /** GET <apiBase>/<path>?params, JSON body string (cached). */
  private static async get(path: string, params: Record<string, string>): Promise<string> {
    const s = TmdbClient.settings();
    const key = s.tmdbApiKey.trim();
    const p: Record<string, string> = {};
    Object.keys(params).forEach((k: string) => {
      p[k] = params[k];
    });
    if (p['language'] === undefined) {
      p['language'] = s.tmdbLanguage.length > 0 ? s.tmdbLanguage : 'zh-CN';
    }
    const headers: Record<string, string> = { 'Accept': 'application/json' };
    if (key.startsWith('eyJ')) {
      headers['Authorization'] = 'Bearer ' + key;
    } else {
      p['api_key'] = key;
    }
    let base = s.tmdbApiBase.length > 0 ? s.tmdbApiBase : 'https://api.themoviedb.org/3';
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    const url = base + path + '?' + buildQuery(p);
    const hit = TmdbClient.cache.get(url);
    if (hit !== undefined) {
      return hit;
    }
    if (TmdbClient.cache.size >= CACHE_MAX) {
      TmdbClient.cache.clear();
    }
    const pr = TmdbClient.fetchWithRetry(url, headers);
    TmdbClient.cache.set(url, pr);
    pr.catch(() => {
      TmdbClient.cache.delete(url);
    });
    return pr;
  }

  private static async fetchWithRetry(url: string, headers: Record<string, string>): Promise<string> {
    let attempt = 0;
    while (true) {
      try {
        const r = await request('GET', url, headers, undefined, 15000);
        return r.body;
      } catch (e) {
        const he = e as HttpError;
        const status = he.status !== undefined ? he.status : 0;
        if ((status === 429 || status === 0 || status >= 500) && attempt < 4) {
          attempt++;
          await sleep(status === 429 ? 1000 * attempt * attempt : 800 * attempt);
          continue;
        }
        throw TmdbClient.friendlyError(he, status);
      }
    }
  }

  private static friendlyError(e: HttpError, status: number): Error {
    let msg = '';
    try {
      if (e.body !== undefined && e.body.length > 0) {
        const b = JSON.parse(e.body) as TmdbErrorBody;
        msg = str(b.status_message);
      }
    } catch (pe) {
      msg = '';
    }
    if (status === 401) {
      return new Error('TMDB API Key 无效或已过期' + (msg.length > 0 ? '：' + msg : ''));
    }
    if (status === 404) {
      return new Error('TMDB 未找到该条目');
    }
    if (status === 429) {
      return new Error('TMDB 请求过于频繁，请稍后重试');
    }
    if (status === 0) {
      return new Error('无法连接 TMDB，请检查网络或 API 地址（' + (e.message ?? '') + '）');
    }
    return new Error('TMDB 请求失败 (' + status + ')' + (msg.length > 0 ? '：' + msg : ''));
  }

  // ---------------- raw API ----------------

  static async searchMovie(query: string, year: number): Promise<TmdbSearchResult[]> {
    const p: Record<string, string> = { 'query': query, 'include_adult': 'false' };
    if (year > 0) {
      p['year'] = String(year);
    }
    const body = await TmdbClient.get('/search/movie', p);
    const r = JSON.parse(body) as TmdbSearchResponse;
    return r.results !== undefined ? r.results : [];
  }

  static async searchTv(query: string, year: number): Promise<TmdbSearchResult[]> {
    const p: Record<string, string> = { 'query': query, 'include_adult': 'false' };
    if (year > 0) {
      p['first_air_date_year'] = String(year);
    }
    const body = await TmdbClient.get('/search/tv', p);
    const r = JSON.parse(body) as TmdbSearchResponse;
    return r.results !== undefined ? r.results : [];
  }

  static async movie(id: string): Promise<TmdbDetail> {
    const body = await TmdbClient.get('/movie/' + encodeURIComponent(id), {
      'append_to_response': 'credits,images,release_dates,external_ids',
      'include_image_language': TmdbClient.langPrefix() + ',en,null'
    });
    return JSON.parse(body) as TmdbDetail;
  }

  static async tv(id: string): Promise<TmdbDetail> {
    const body = await TmdbClient.get('/tv/' + encodeURIComponent(id), {
      'append_to_response': 'credits,images,external_ids,content_ratings',
      'include_image_language': TmdbClient.langPrefix() + ',en,null'
    });
    return JSON.parse(body) as TmdbDetail;
  }

  static async season(tvId: string, n: number): Promise<TmdbSeason> {
    const body = await TmdbClient.get('/tv/' + encodeURIComponent(tvId) + '/season/' + n, {});
    return JSON.parse(body) as TmdbSeason;
  }

  // ---------------- matching ----------------

  static resultTitle(r: TmdbSearchResult): string {
    return str(r.title !== undefined ? r.title : r.name);
  }

  static resultOriginal(r: TmdbSearchResult): string {
    return str(r.original_title !== undefined ? r.original_title : r.original_name);
  }

  static resultYear(r: TmdbSearchResult): number {
    return yearOf(r.release_date !== undefined ? r.release_date : r.first_air_date);
  }

  /** Score 0..~1.3: title similarity dominates, year proximity and popularity break ties. */
  static score(r: TmdbSearchResult, titles: string[], year: number): number {
    let sim = 0;
    const t1 = TmdbClient.resultTitle(r);
    const t2 = TmdbClient.resultOriginal(r);
    titles.forEach((t: string) => {
      sim = Math.max(sim, titleSimilarity(t, t1), titleSimilarity(t, t2));
    });
    let s = sim;
    const ry = TmdbClient.resultYear(r);
    if (year > 0 && ry > 0) {
      const d = Math.abs(ry - year);
      s += d === 0 ? 0.2 : (d === 1 ? 0.1 : (d <= 3 ? -0.05 : -0.25));
    }
    const pop = num(r.popularity);
    s += Math.min(0.1, Math.log10(1 + pop) * 0.04);
    s += Math.min(0.05, Math.log10(1 + num(r.vote_count)) * 0.015);
    return s;
  }

  /** Build the list of query strings to try for a parsed name. */
  static queries(p: ParsedName): string[] {
    const out: string[] = [];
    const add = (q: string) => {
      const t = q.trim();
      if (t.length > 0 && out.indexOf(t) < 0) {
        out.push(t);
      }
    };
    add(p.title);
    add(p.altTitle);
    // strip the Chinese or English half when the title is mixed
    if (RE_CJK.test(p.title)) {
      const latin = p.title.replace(new RegExp('[\\u3000-\\u303f\\u3040-\\u30ff\\u3400-\\u9fff\\uf900-\\ufaff\\uff00-\\uffef]+', 'g'), ' ')
        .replace(new RegExp('\\s+', 'g'), ' ').trim();
      if (new RegExp('[A-Za-z]{3,}').test(latin)) {
        add(latin);
      }
      const cjk = p.title.replace(new RegExp('[A-Za-z][A-Za-z\\s\\u0027\\-:]*', 'g'), ' ').replace(new RegExp('\\s+', 'g'), ' ').trim();
      add(cjk);
      // "流浪地球2" -> "流浪地球" is NOT added (sequels must stay distinct); but "庆余年 第二部" style suffix is
      const noPart = p.title.replace(new RegExp('\\s*(?:第[0-9一二三四五六七八九十]+[部季]|[上下]部|前传|续集)$'), '').trim();
      add(noPart);
    } else {
      // drop trailing country / part markers: "The Office US" -> "The Office"
      add(p.title.replace(new RegExp('\\s+(?:US|UK|AU|CA|NZ|JP|KR)$', 'i'), ''));
      add(p.title.replace(new RegExp('\\s+(?:Part|Pt|Vol|Chapter)\\s*\\d+$', 'i'), ''));
    }
    return out;
  }

  /**
   * Find the best TMDB match for a parsed name. Returns undefined when nothing scores high enough.
   * kind: 'movie' / 'tv' forces a type; undefined uses p.isTv and falls back to the other type.
   */
  static async findBest(p: ParsedName, kind?: TmdbKind): Promise<TmdbCandidate | undefined> {
    const primary: TmdbKind = kind !== undefined ? kind : (p.isTv ? 'tv' : 'movie');
    const kinds: TmdbKind[] = [primary];
    if (kind === undefined) {
      kinds.push(primary === 'tv' ? 'movie' : 'tv');
    }
    const titles = [p.title, p.altTitle].filter((t: string) => t.length > 0);
    const qs = TmdbClient.queries(p);
    let best: TmdbCandidate | undefined = undefined;
    for (let k = 0; k < kinds.length; k++) {
      const kd = kinds[k];
      for (let i = 0; i < qs.length; i++) {
        const years: number[] = p.year > 0 ? [p.year, 0] : [0];
        for (let y = 0; y < years.length; y++) {
          const res = kd === 'tv' ? await TmdbClient.searchTv(qs[i], years[y]) : await TmdbClient.searchMovie(qs[i], years[y]);
          res.slice(0, 10).forEach((r: TmdbSearchResult) => {
            let sc = TmdbClient.score(r, titles.concat([qs[i]]), p.year);
            if (kd !== primary) {
              sc -= 0.15;     // prefer the type the filename suggests
            }
            if (best === undefined || sc > best.score) {
              const c = new TmdbCandidate();
              c.kind = kd;
              c.result = r;
              c.score = sc;
              best = c;
            }
          });
          const b = best as TmdbCandidate | undefined;
          if (b !== undefined && b.score >= 1.0) {
            return b;
          }
          if (res.length > 0 && years[y] > 0) {
            break;  // got results with the year filter; no need to retry without
          }
        }
        const b2 = best as TmdbCandidate | undefined;
        if (b2 !== undefined && b2.score >= 0.85) {
          return b2;
        }
      }
      const b3 = best as TmdbCandidate | undefined;
      if (b3 !== undefined && b3.score >= 0.6 && b3.kind === primary) {
        return b3;
      }
    }
    const fin = best as TmdbCandidate | undefined;
    return fin !== undefined && fin.score >= 0.55 ? fin : undefined;
  }

  // ---------------- mapping ----------------

  private static pickLogo(logos: TmdbImage[] | undefined): string {
    if (logos === undefined || logos.length === 0) {
      return '';
    }
    const lang = TmdbClient.langPrefix();
    const order: string[] = [lang, 'en', ''];
    for (let i = 0; i < order.length; i++) {
      const want = order[i];
      const c = logos.filter((l: TmdbImage) => str(l.iso_639_1) === want && str(l.file_path).length > 0)
        .sort((a: TmdbImage, b: TmdbImage) => num(b.vote_average) - num(a.vote_average));
      if (c.length > 0) {
        return TmdbClient.imageUrl(c[0].file_path, 'w500');
      }
    }
    return TmdbClient.imageUrl(logos[0].file_path, 'w500');
  }

  private static people(cast: TmdbCast[] | undefined, crew: TmdbCrew[] | undefined): Person[] {
    const out: Person[] = [];
    if (crew !== undefined) {
      crew.filter((c: TmdbCrew) => c.job === 'Director' || c.job === 'Creator').slice(0, 3).forEach((c: TmdbCrew) => {
        const p = new Person();
        p.name = str(c.name);
        p.role = '导演';
        p.image = TmdbClient.imageUrl(c.profile_path, 'w185');
        out.push(p);
      });
    }
    if (cast !== undefined) {
      cast.slice(0, MAX_CAST).forEach((c: TmdbCast) => {
        const p = new Person();
        p.name = str(c.name);
        p.role = str(c.character);
        p.image = TmdbClient.imageUrl(c.profile_path, 'w185');
        out.push(p);
      });
    }
    return out;
  }

  private static certification(d: TmdbDetail): string {
    const prefer: string[] = ['CN', 'HK', 'TW', 'US'];
    if (d.release_dates !== undefined && d.release_dates.results !== undefined) {
      const res = d.release_dates.results;
      for (let i = 0; i < prefer.length; i++) {
        const c = res.find((r: TmdbReleaseCountry) => r.iso_3166_1 === prefer[i]);
        if (c !== undefined && c.release_dates !== undefined) {
          const rd = c.release_dates.find((x: TmdbReleaseDate) => str(x.certification).length > 0);
          if (rd !== undefined) {
            return str(rd.certification);
          }
        }
      }
    }
    if (d.content_ratings !== undefined && d.content_ratings.results !== undefined) {
      const res = d.content_ratings.results;
      for (let i = 0; i < prefer.length; i++) {
        const c = res.find((r: TmdbContentRating) => r.iso_3166_1 === prefer[i] && str(r.rating).length > 0);
        if (c !== undefined) {
          return str(c.rating);
        }
      }
    }
    return '';
  }

  private static fillCommon(m: MediaItem, d: TmdbDetail): void {
    m.overview = str(d.overview);
    m.rating = Math.round(num(d.vote_average) * 10) / 10;
    m.genres = d.genres !== undefined ? d.genres.map((g: TmdbGenre) => str(g.name)).filter((x: string) => x.length > 0) : [];
    const comp: TmdbCompany[] = [];
    if (d.networks !== undefined) {
      d.networks.forEach((c: TmdbCompany) => comp.push(c));
    }
    if (d.production_companies !== undefined) {
      d.production_companies.forEach((c: TmdbCompany) => comp.push(c));
    }
    m.studios = comp.map((c: TmdbCompany) => str(c.name)).filter((x: string, i: number, a: string[]) => x.length > 0 && a.indexOf(x) === i)
      .slice(0, 5);
    m.tags = str(d.tagline).length > 0 ? [str(d.tagline)] : [];
    m.people = TmdbClient.people(d.credits !== undefined ? d.credits.cast : undefined,
      d.credits !== undefined ? d.credits.crew : undefined);
    m.images.poster = TmdbClient.imageUrl(d.poster_path, 'w500');
    m.images.backdrop = TmdbClient.imageUrl(d.backdrop_path, 'w1280');
    if (m.images.backdrop.length === 0 && d.images !== undefined && d.images.backdrops !== undefined && d.images.backdrops.length > 0) {
      m.images.backdrop = TmdbClient.imageUrl(d.images.backdrops[0].file_path, 'w1280');
    }
    m.images.logo = TmdbClient.pickLogo(d.images !== undefined ? d.images.logos : undefined);
    m.officialRating = TmdbClient.certification(d);
    const imdb = d.external_ids !== undefined ? str(d.external_ids.imdb_id) : str(d.imdb_id);
    m.imdbId = imdb;
  }

  static mapMovie(sourceId: string, d: TmdbDetail): MediaItem {
    const m = new MediaItem();
    m.sourceId = sourceId;
    m.id = 'tmdb-movie-' + num(d.id);
    m.type = 'movie';
    m.tmdbId = String(num(d.id));
    m.title = str(d.title).length > 0 ? str(d.title) : str(d.original_title);
    m.originalTitle = str(d.original_title);
    m.premiereDate = str(d.release_date);
    m.year = yearOf(d.release_date);
    m.runtimeMs = num(d.runtime) * 60000;
    TmdbClient.fillCommon(m, d);
    return m;
  }

  static mapSeries(sourceId: string, d: TmdbDetail): MediaItem {
    const m = new MediaItem();
    m.sourceId = sourceId;
    m.id = 'tmdb-tv-' + num(d.id);
    m.type = 'series';
    m.tmdbId = String(num(d.id));
    m.title = str(d.name).length > 0 ? str(d.name) : str(d.original_name);
    m.originalTitle = str(d.original_name);
    m.premiereDate = str(d.first_air_date);
    m.year = yearOf(d.first_air_date);
    if (d.episode_run_time !== undefined && d.episode_run_time.length > 0) {
      m.runtimeMs = d.episode_run_time[0] * 60000;
    }
    TmdbClient.fillCommon(m, d);
    return m;
  }

  /** Season item; `summary` from tv detail, `season` from the season API (either may be missing). */
  static mapSeason(series: MediaItem, n: number, summary: TmdbSeasonSummary | undefined, season: TmdbSeason | undefined): MediaItem {
    const m = new MediaItem();
    m.sourceId = series.sourceId;
    m.id = series.id + '-s' + n;
    m.type = 'season';
    m.tmdbId = series.tmdbId;
    m.seriesId = series.id;
    m.seriesTitle = series.title;
    m.seasonNumber = n;
    const name = season !== undefined ? str(season.name) : (summary !== undefined ? str(summary.name) : '');
    m.title = name.length > 0 ? name : (n === 0 ? '特别篇' : '第 ' + n + ' 季');
    m.overview = season !== undefined && str(season.overview).length > 0 ? str(season.overview)
      : (summary !== undefined ? str(summary.overview) : '');
    if (m.overview.length === 0) {
      m.overview = series.overview;
    }
    const air = season !== undefined ? str(season.air_date) : (summary !== undefined ? str(summary.air_date) : '');
    m.premiereDate = air;
    m.year = yearOf(air);
    const poster = season !== undefined ? season.poster_path : (summary !== undefined ? summary.poster_path : undefined);
    m.images.poster = TmdbClient.imageUrl(poster, 'w500');
    if (m.images.poster.length === 0) {
      m.images.poster = series.images.poster;
    }
    m.images.backdrop = series.images.backdrop;
    m.images.logo = series.images.logo;
    m.genres = series.genres.slice();
    m.rating = series.rating;
    m.officialRating = series.officialRating;
    m.imdbId = series.imdbId;
    m.originalTitle = series.originalTitle;
    return m;
  }

  static mapEpisode(season: MediaItem, series: MediaItem, ep: number, e: TmdbEpisode | undefined): MediaItem {
    const m = new MediaItem();
    m.sourceId = season.sourceId;
    m.id = series.id + '-s' + season.seasonNumber + 'e' + ep;
    m.type = 'episode';
    m.tmdbId = series.tmdbId;
    m.seriesId = series.id;
    m.seriesTitle = series.title;
    m.seasonId = season.id;
    m.seasonNumber = season.seasonNumber;
    m.episodeNumber = ep;
    m.genres = series.genres.slice();
    m.officialRating = series.officialRating;
    m.images.poster = season.images.poster;
    m.images.backdrop = series.images.backdrop;
    m.images.logo = series.images.logo;
    m.runtimeMs = series.runtimeMs;
    if (e !== undefined) {
      m.title = str(e.name);
      m.overview = str(e.overview);
      m.premiereDate = str(e.air_date);
      m.year = yearOf(e.air_date);
      m.rating = Math.round(num(e.vote_average) * 10) / 10;
      m.images.thumb = TmdbClient.imageUrl(e.still_path, 'w300');
      if (e.runtime !== undefined && e.runtime !== null && e.runtime > 0) {
        m.runtimeMs = e.runtime * 60000;
      }
      const ppl = TmdbClient.people(e.guest_stars, e.crew);
      m.people = ppl.length > 0 ? ppl.slice(0, 12) : series.people.slice(0, 12);
    } else {
      m.people = series.people.slice(0, 12);
    }
    if (m.title.length === 0 || new RegExp('^(?:第\\s*\\d+\\s*集|Episode\\s*\\d+)$', 'i').test(m.title.trim())) {
      m.title = '第 ' + ep + ' 集';
    }
    if (m.images.thumb.length === 0) {
      m.images.thumb = series.images.backdrop;
    }
    return m;
  }

  /** Light MediaItem for search results shown in the manual-match UI (id = tmdb id, tmdbId set). */
  static mapSearchResult(r: TmdbSearchResult, kind: TmdbKind): MediaItem {
    const m = new MediaItem();
    m.id = String(num(r.id));
    m.tmdbId = String(num(r.id));
    m.type = kind === 'tv' ? 'series' : 'movie';
    m.title = TmdbClient.resultTitle(r);
    m.originalTitle = TmdbClient.resultOriginal(r);
    m.year = TmdbClient.resultYear(r);
    m.premiereDate = str(r.release_date !== undefined ? r.release_date : r.first_air_date);
    m.overview = str(r.overview);
    m.rating = Math.round(num(r.vote_average) * 10) / 10;
    m.images.poster = TmdbClient.imageUrl(r.poster_path, 'w500');
    m.images.backdrop = TmdbClient.imageUrl(r.backdrop_path, 'w1280');
    return m;
  }

  static sameTitle(a: string, b: string): boolean {
    return normKey(a) === normKey(b);
  }
}
