import { HttpError, request } from '../common/Http';
import { QualityOption, SubtitleTrack } from '../common/Models';
import { FlicxSearchResponse, FlicxSourceResponse, FlicxSubtitleResponse, FlicxTitleItem,
  FlicxLibraryResponse, FlicxSeasonRow, FlicxEpisodesResponse, FlicxEpisode } from './FlicxModels';
import { FlicxMapper, FLICX_ID, FLICX_ORIGIN } from './FlicxMapper';
import { HomeRow } from '../common/Models';
import { AppLog } from '../common/AppLog';
import { FlicxHome, FlicxTitlePage, parseTitlePage } from './FlicxHome';

export class FlicxApi {
  private static async read<T>(path: string): Promise<T | undefined> {
    let body: string;
    try {
      const r = await request('GET', FLICX_ORIGIN + path, { 'Accept': 'application/json' }, undefined, 8000);
      body = r.body;
    } catch (e) {
      const err = e as HttpError;
      if (err.status === 404) {
        return undefined;
      }
      AppLog.warn(`[Flicx] GET ${path} failed: HTTP ${err.status} ${err.message ?? ''}`);
      throw new Error(err.status > 0 ? 'Flicx 请求失败 (HTTP ' + err.status + ')' : '无法连接 Flicx，请检查网络后重试');
    }
    try {
      return JSON.parse(body) as T;
    } catch (e) {
      throw new Error('Flicx 返回的内容不是有效的 JSON');
    }
  }

  private static path(imdbId: string, season: number, episode: number, subs: boolean): string {
    if (!FlicxMapper.isImdbId(imdbId)) {
      throw new Error('无效的 Flicx 影片编号');
    }
    const base = (subs ? '/api/subtitles/' : '/api/sources/') + imdbId;
    if (season === -1 && episode === -1) {
      return base;
    }
    if (!Number.isSafeInteger(season) || !Number.isSafeInteger(episode) || season < 0 || episode < 1) {
      throw new Error('缺少有效的季号或集号');
    }
    return subs ? base + '/' + season + '/' + episode : base + '?s=' + season + '&e=' + episode;
  }

  /** Rails from the server-rendered home page (no JSON endpoint exists for it). */
  static async home(): Promise<HomeRow[]> {
    let body: string;
    try {
      body = (await request('GET', FLICX_ORIGIN + '/', { 'Accept': 'text/html' }, undefined, 10000)).body;
    } catch (e) {
      const err = e as HttpError;
      throw new Error(err.status > 0 ? 'Flicx 首页加载失败 (HTTP ' + err.status + ')' : '无法连接 Flicx，请检查网络后重试');
    }
    const rows = FlicxHome.parse(body);
    if (rows.length === 0) {
      throw new Error('无法识别 Flicx 首页内容，可直接使用搜索');
    }
    return rows;
  }

  /** Synopsis/credits from the title's web page; undefined when the page has no recognisable metadata. */
  static async titlePage(kind: 'movie' | 'tv', slug: string): Promise<FlicxTitlePage | undefined> {
    if (!/^[a-z0-9][a-z0-9-]{0,200}$/.test(slug)) {
      return undefined;
    }
    try {
      const r = await request('GET', FLICX_ORIGIN + '/' + kind + '/' + slug, { 'Accept': 'text/html' }, undefined, 8000);
      return parseTitlePage(r.body);
    } catch (e) {
      return undefined;
    }
  }

  static async search(term: string): Promise<FlicxTitleItem[]> {
    const data = await FlicxApi.read<FlicxSearchResponse>('/api/search?q=' + encodeURIComponent(term));
    if (data === undefined) {
      return [];
    }
    if (!data || !Array.isArray(data.results)) {
      throw new Error('无法识别 Flicx 搜索结果');
    }
    return FlicxMapper.searchItems(data, FLICX_ID);
  }

  static async seasons(slug: string): Promise<FlicxSeasonRow[]> {
    const data = await FlicxApi.read<FlicxLibraryResponse>('/api/library?shows=' + encodeURIComponent(slug));
    const rows = data?.shows?.[slug]?.seasons;
    if (!Array.isArray(rows)) {
      throw new Error('Flicx 没有返回这部剧的季列表');
    }
    return rows.filter((s: FlicxSeasonRow) => !!s && Number.isSafeInteger(s.n) && s.n >= 0);
  }

  static async episodes(slug: string, season: number): Promise<FlicxEpisode[]> {
    const path = '/api/tv/season?show=' + encodeURIComponent(slug) + '&n=' + season;
    const data = await FlicxApi.read<FlicxEpisodesResponse>(path);
    if (!data || !Array.isArray(data.episodes)) {
      throw new Error('Flicx 没有返回这一季的集数');
    }
    return data.episodes.filter((e: FlicxEpisode) => !!e && Number.isSafeInteger(e.n) && e.n > 0 && e.plays !== false);
  }

  static async sources(imdbId: string, season: number, episode: number): Promise<QualityOption[]> {
    const data = await FlicxApi.read<FlicxSourceResponse>(FlicxApi.path(imdbId, season, episode, false));
    if (data === undefined) {
      return [];
    }
    if (!data || !Array.isArray(data.sources) || (data.imdb !== undefined && data.imdb !== imdbId) ||
      (data.season != null && data.season !== season) || (data.episode != null && data.episode !== episode)) {
      throw new Error('Flicx 返回的播放线路与当前影片或集号不符');
    }
    return FlicxMapper.sources(data);
  }

  static async hasPlayableSource(imdbId: string, season: number, episode: number): Promise<boolean> {
    return (await FlicxApi.sources(imdbId, season, episode)).length > 0;
  }

  static async subtitles(imdbId: string, season: number, episode: number): Promise<SubtitleTrack[]> {
    const data = await FlicxApi.read<FlicxSubtitleResponse>(FlicxApi.path(imdbId, season, episode, true));
    return data === undefined ? [] : FlicxMapper.subtitles(data);
  }
}
