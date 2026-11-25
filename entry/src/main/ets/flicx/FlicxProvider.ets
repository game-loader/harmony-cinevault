import { MediaProvider } from '../common/MediaProvider';
import { LibraryView, MediaItem, PagedItems, PlaybackInfo, PlaybackRequest, QueryOptions, SourceConfig,
  SubtitleTrack } from '../common/Models';
import { Settings } from '../common/Settings';
import { TmdbClient } from '../scraper/TmdbClient';
import { TmdbDetail, TmdbSeason, TmdbSeasonSummary } from '../scraper/TmdbTypes';
import { FlicxApi } from './FlicxApi';
import { FlicxMapper, FLICX_ID } from './FlicxMapper';
import { FlicxEpisode, FlicxId, FlicxSeasonRow } from './FlicxModels';
import { FlicxSearch } from './FlicxSearch';

class CatalogTitle {
  item: MediaItem;
  detail?: TmdbDetail;
  slug: string;
  constructor(item: MediaItem, slug: string, detail?: TmdbDetail) {
    this.item = item;
    this.detail = detail;
    this.slug = slug;
  }
}

function parseId(value: string): FlicxId {
  const id = FlicxMapper.parseMediaId(value);
  if (!id) {
    throw new Error('无效的 Flicx 条目');
  }
  return id;
}

export class FlicxProvider implements MediaProvider {
  readonly config: SourceConfig = new SourceConfig();
  private catalog: FlicxSearch = new FlicxSearch();

  constructor() {
    this.config.kind = 'flicx';
    this.config.id = FLICX_ID;
    this.config.name = 'Flicx';
  }

  search(term: string, limit: number): Promise<MediaItem[]> {
    return this.catalog.search(term, limit);
  }

  private async title(id: FlicxId): Promise<CatalogTitle> {
    const root = FlicxMapper.mediaId(id.kind, id.imdbId);
    const site = this.catalog.siteTitle(root);
    if (Settings.get().tmdbApiKey.trim()) {
      try {
        const tid = await this.catalog.tmdbId(id);
        const detail = id.kind === 'tv' ? await TmdbClient.tv(tid) : await TmdbClient.movie(tid);
        const item = id.kind === 'tv' ? TmdbClient.mapSeries(FLICX_ID, detail) : TmdbClient.mapMovie(FLICX_ID, detail);
        if (item.imdbId && item.imdbId !== id.imdbId) {
          throw new Error('TMDB 详情与当前影片不符');
        }
        item.id = root;
        item.imdbId = id.imdbId;
        item.childCount = detail.number_of_seasons ?? 0;
        return new CatalogTitle(item, site?.slug ?? '', detail);
      } catch (e) {
        if (!site) {
          throw e as Error;
        }
      }
    }
    if (site) {
      return new CatalogTitle(site, site.slug);
    }
    throw new Error('请重新搜索英文片名，或在设置中填写 TMDB API Key 以加载详情');
  }

  private async seasonItems(title: CatalogTitle): Promise<MediaItem[]> {
    let seasons: TmdbSeasonSummary[] = title.detail?.seasons ?? [];
    if (seasons.length === 0 && title.slug) {
      const rows = await FlicxApi.seasons(title.slug);
      seasons = rows.map((s: FlicxSeasonRow): TmdbSeasonSummary => {
        return { season_number: s.n, episode_count: s.count };
      });
    }
    return seasons.filter((s: TmdbSeasonSummary) => Number.isSafeInteger(s.season_number) && (s.season_number ?? -1) >= 0)
      .map((s: TmdbSeasonSummary) => {
        const item = TmdbClient.mapSeason(title.item, s.season_number ?? 0, s, undefined);
        item.childCount = s.episode_count ?? 0;
        return item;
      });
  }

  private siteEpisode(season: MediaItem, series: MediaItem, e: FlicxEpisode): MediaItem {
    const item = TmdbClient.mapEpisode(season, series, e.n, undefined);
    item.imdbId = series.imdbId;
    item.title = e.title || item.title;
    item.overview = e.overview ?? '';
    item.premiereDate = e.aired ?? '';
    item.year = Number(item.premiereDate.slice(0, 4)) || 0;
    item.rating = e.rating ?? 0;
    if (typeof e.runtime === 'number' && e.runtime > 0) {
      item.runtimeMs = e.runtime * 60000;
    }
    item.images.thumb = FlicxMapper.absoluteUrl(e.still?.src) || item.images.backdrop;
    return item;
  }

  private async episodeItems(title: CatalogTitle, n: number): Promise<MediaItem[]> {
    const series = title.item;
    const summary = title.detail?.seasons?.find((s: TmdbSeasonSummary) => s.season_number === n);
    let data: TmdbSeason | undefined = undefined;
    if (series.tmdbId) {
      try {
        data = await TmdbClient.season(series.tmdbId, n);
      } catch (e) {
        data = undefined; // fall back to the Flicx episode list below
      }
    }
    const season = TmdbClient.mapSeason(series, n, summary, data);
    // Flicx accepts either its slug or the IMDb id here; it lists which episodes actually play.
    const show = title.slug || series.imdbId;
    if (data && Array.isArray(data.episodes) && data.episodes.length > 0) {
      let playable: Set<number> | undefined = undefined;
      try {
        playable = new Set<number>((await FlicxApi.episodes(show, n)).map((e: FlicxEpisode) => e.n));
      } catch (e) {
        playable = undefined; // keep the TMDB list; playback reports a missing episode itself
      }
      const items: MediaItem[] = [];
      for (const e of data.episodes) {
        const number = e.episode_number ?? 0;
        if (Number.isSafeInteger(number) && number > 0 && (playable === undefined || playable.has(number))) {
          const item = TmdbClient.mapEpisode(season, series, number, e);
          item.imdbId = series.imdbId;
          items.push(item);
        }
      }
      return items;
    }
    const eps = await FlicxApi.episodes(show, n);
    return eps.map((e: FlicxEpisode) => this.siteEpisode(season, series, e));
  }

  async getItem(value: string): Promise<MediaItem> {
    const id = parseId(value);
    const title = await this.title(id);
    if (id.season < 0) {
      return title.item;
    }
    const items = id.episode < 0 ? await this.seasonItems(title) : await this.episodeItems(title, id.season);
    const match = items.find((item: MediaItem) => item.id === value);
    if (!match) {
      throw new Error('没有找到所选的季或集');
    }
    return match;
  }

  async getSeasons(seriesId: string): Promise<MediaItem[]> {
    const ref = parseId(seriesId);
    return ref.kind === 'tv' ? this.seasonItems(await this.title(ref)) : [];
  }

  async getEpisodes(seriesId: string, seasonId: string): Promise<MediaItem[]> {
    const series = parseId(seriesId);
    if (series.kind !== 'tv') {
      return [];
    }
    const title = await this.title(series);
    if (seasonId) {
      const season = parseId(seasonId);
      if (season.imdbId !== series.imdbId || season.season < 0 || season.episode >= 0) {
        throw new Error('所选的季不属于当前剧集');
      }
      return this.episodeItems(title, season.season);
    }
    const seasons = await this.seasonItems(title);
    const first = seasons.find((s: MediaItem) => s.seasonNumber > 0) ?? seasons[0];
    return first ? this.episodeItems(title, first.seasonNumber) : [];
  }

  async getPlayback(item: MediaItem, _req: PlaybackRequest): Promise<PlaybackInfo> {
    const ref = parseId(item.id);
    if (ref.kind === 'tv' && ref.episode < 1) {
      throw new Error('请先选择要播放的集数');
    }
    const options = FlicxApi.sources(ref.imdbId, ref.season, ref.episode);
    const tracks = FlicxApi.subtitles(ref.imdbId, ref.season, ref.episode).catch((): SubtitleTrack[] => []);
    const info = new PlaybackInfo();
    info.qualities = await options;
    if (!info.qualities.length) {
      throw new Error('Flicx 暂无这部影片或这一集的可用线路');
    }
    info.url = info.qualities[0].url;
    info.container = 'm3u8';
    info.durationMs = item.runtimeMs;
    info.mediaSourceId = item.id;
    info.subtitles = await tracks;
    return info;
  }

  imageUrl(item: MediaItem, kind: 'poster' | 'backdrop' | 'logo' | 'thumb', _maxWidth: number): string {
    switch (kind) {
      case 'backdrop': return item.images.backdrop;
      case 'logo': return item.images.logo;
      case 'thumb': return item.images.thumb;
      default: return item.images.poster;
    }
  }
  imageHeaders(): Record<string, string> { return {}; }

  // Public search source. There is no personal Flicx account or library to sync.
  async connect(): Promise<void> {}
  async getViews(): Promise<LibraryView[]> { return []; }
  async getResume(_limit: number): Promise<MediaItem[]> { return []; }
  async getNextUp(_limit: number): Promise<MediaItem[]> { return []; }
  async getLatest(_parentId: string, _limit: number): Promise<MediaItem[]> { return []; }
  async getItems(_q: QueryOptions): Promise<PagedItems> { return new PagedItems(); }
  async getSimilar(_id: string, _limit: number): Promise<MediaItem[]> { return []; }
  async getGenres(_parentId: string): Promise<string[]> { return []; }
  async reportStart(_item: MediaItem, _info: PlaybackInfo, _positionMs: number): Promise<void> {}
  async reportProgress(_item: MediaItem, _info: PlaybackInfo, _positionMs: number, _paused: boolean): Promise<void> {}
  async reportStopped(_item: MediaItem, _info: PlaybackInfo, _positionMs: number): Promise<void> {}
  async setPlayed(_item: MediaItem, _played: boolean): Promise<void> { throw new Error('Flicx 搜索源暂不保存已看标记'); }
  async setFavorite(_item: MediaItem, _favorite: boolean): Promise<void> { throw new Error('Flicx 搜索源暂不保存收藏'); }
}
