import { MediaProvider } from '../common/MediaProvider';
import { HomeRow, LibraryView, MediaItem, PagedItems, Person, PlaybackInfo, PlaybackRequest, QualityOption, QueryOptions, SourceConfig,
  SubtitleTrack } from '../common/Models';
import { Settings } from '../common/Settings';
import { SourceStore } from '../common/SourceStore';
import { AppLog } from '../common/AppLog';
import { TmdbClient } from '../scraper/TmdbClient';
import { TmdbDetail, TmdbSeason, TmdbSeasonSummary } from '../scraper/TmdbTypes';
import { FlicxApi } from './FlicxApi';
import { FlicxMapper, FLICX_ID } from './FlicxMapper';
import { FlicxEpisode, FlicxId, FlicxSeasonRow, FlicxTitleItem } from './FlicxModels';
import { FlicxTitlePage } from './FlicxHome';
import { FlicxLibrary, toItem, SavedTitle } from './FlicxLibrary';
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

  private homeCache: HomeRow[] = [];
  private homeAt: number = 0;
  private homeLoad: Promise<HomeRow[]> | undefined = undefined;

  /** Flicx home page rails, cached for 10 minutes; force bypasses the cache (pull to refresh). */
  async home(force: boolean): Promise<HomeRow[]> {
    if (!force && this.homeCache.length > 0 && Date.now() - this.homeAt < 600000) {
      return this.homeCache;
    }
    if (this.homeLoad === undefined) {
      this.homeLoad = FlicxApi.home().then((rows: HomeRow[]) => {
        rows.forEach((r: HomeRow) => this.catalog.rememberSite(r.items));
        this.homeCache = rows;
        this.homeAt = Date.now();
        this.homeLoad = undefined;
        return rows;
      }, (e: Object) => {
        this.homeLoad = undefined;
        throw e as Error;
      });
    }
    return this.homeLoad;
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
      await this.enrich(site, id.kind);
      return new CatalogTitle(site, site.slug);
    }
    throw new Error('请重新搜索英文片名，或在设置中填写 TMDB API Key 以加载详情');
  }

  /** Without TMDB, the synopsis and credits come from the title's Flicx page (fetched once per title). */
  private async enrich(site: FlicxTitleItem, kind: 'movie' | 'tv'): Promise<void> {
    if (site.pageLoaded || !site.slug) {
      return;
    }
    const page: FlicxTitlePage | undefined = await FlicxApi.titlePage(kind, site.slug);
    if (page === undefined) {
      return;
    }
    site.pageLoaded = true;
    site.overview = site.overview || page.overview;
    site.premiereDate = site.premiereDate || page.premiereDate;
    site.runtimeMs = site.runtimeMs || page.runtimeMs;
    site.officialRating = site.officialRating || page.officialRating;
    if (page.genres.length > site.genres.length) {
      site.genres = page.genres;
    }
    if (site.studios.length === 0) {
      site.studios = page.studios;
    }
    if (site.people.length === 0 && page.people.length > 0) {
      site.people = page.people;
    }
    if (site.people.length === 0) {
      const people: Person[] = [];
      page.directors.forEach((n: string) => {
        const p = new Person();
        p.name = n;
        p.role = kind === 'movie' ? '导演' : '主创';
        people.push(p);
      });
      page.actors.forEach((n: string) => {
        const p = new Person();
        p.name = n;
        people.push(p);
      });
      site.people = people;
    }
    site.images.backdrop = site.images.backdrop || page.backdrop;
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

  /** Slug for a root id, so saved entries can reopen details without TMDB. */
  private slugFor(id: string): string {
    const ref = FlicxMapper.parseMediaId(id);
    if (ref === undefined) {
      return '';
    }
    return this.catalog.siteTitle(FlicxMapper.mediaId(ref.kind, ref.imdbId))?.slug ?? '';
  }

  /** Re-seed the site-title cache from saved entries (app restart, no TMDB key). */
  private restoreSite(rootId: string): void {
    if (this.catalog.siteTitle(rootId) !== undefined) {
      return;
    }
    const s = FlicxLibrary.state.get(rootId);
    if (s !== undefined && s.slug) {
      const it = new FlicxTitleItem();
      it.id = s.id;
      it.sourceId = FLICX_ID;
      it.type = s.type === 'series' ? 'series' : 'movie';
      it.title = s.title;
      it.year = s.year;
      it.rating = s.rating;
      it.imdbId = s.imdbId;
      it.slug = s.slug;
      it.images.poster = s.poster;
      it.images.backdrop = s.backdrop;
      it.runtimeMs = s.runtimeMs;
      this.catalog.rememberSite([it]);
    }
  }

  async getItem(value: string): Promise<MediaItem> {
    await FlicxLibrary.load();
    const id = parseId(value);
    this.restoreSite(FlicxMapper.mediaId(id.kind, id.imdbId));
    const title = await this.title(id);
    if (id.season < 0) {
      return FlicxLibrary.state.apply(title.item);
    }
    const items = id.episode < 0 ? await this.seasonItems(title) : await this.episodeItems(title, id.season);
    const match = items.find((item: MediaItem) => item.id === value);
    if (!match) {
      throw new Error('没有找到所选的季或集');
    }
    return FlicxLibrary.state.apply(match);
  }

  async getSeasons(seriesId: string): Promise<MediaItem[]> {
    await FlicxLibrary.load();
    const ref = parseId(seriesId);
    this.restoreSite(FlicxMapper.mediaId(ref.kind, ref.imdbId));
    return ref.kind === 'tv' ? this.seasonItems(await this.title(ref)) : [];
  }

  async getEpisodes(seriesId: string, seasonId: string): Promise<MediaItem[]> {
    await FlicxLibrary.load();
    const list = await this.loadEpisodes(seriesId, seasonId);
    return list.map((e: MediaItem) => FlicxLibrary.state.apply(e));
  }

  private async loadEpisodes(seriesId: string, seasonId: string): Promise<MediaItem[]> {
    const series = parseId(seriesId);
    this.restoreSite(FlicxMapper.mediaId(series.kind, series.imdbId));
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
    AppLog.info(`[Flicx] ${item.id}: ${info.qualities.length} lines: ` +
      info.qualities.map((q: QualityOption) => q.label).join(' | '));
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
  async getResume(limit: number): Promise<MediaItem[]> {
    await FlicxLibrary.load();
    return FlicxLibrary.state.resume().slice(0, limit).map((s: SavedTitle) => toItem(s, FLICX_ID));
  }
  async getNextUp(_limit: number): Promise<MediaItem[]> { return []; }
  async getLatest(_parentId: string, _limit: number): Promise<MediaItem[]> { return []; }
  /**
   * Movie/TV tabs list the titles from the home page rails while no personal server is added.
   * Once one is, those tabs show only the user's own library.
   */
  async getItems(q: QueryOptions): Promise<PagedItems> {
    const page = new PagedItems();
    if (q.favoritesOnly) {
      await FlicxLibrary.load();
      const favs = FlicxLibrary.state.favorites().map((s: SavedTitle) => toItem(s, FLICX_ID))
        .filter((it: MediaItem) => q.types.length === 0 || q.types.indexOf(it.type) >= 0);
      page.total = favs.length;
      page.items = favs.slice(q.startIndex, q.startIndex + q.limit);
      return page;
    }
    if (q.parentId || SourceStore.list().length > 0) {
      return page;
    }
    const seen = new Set<string>();
    const all: MediaItem[] = [];
    for (const row of await this.home(false)) {
      for (const item of row.items) {
        if (seen.has(item.id) || (q.types.length > 0 && q.types.indexOf(item.type) < 0) ||
          (q.genres.length > 0 && !item.genres.some((g: string) => q.genres.indexOf(g) >= 0)) ||
          (q.years.length > 0 && q.years.indexOf(item.year) < 0)) {
          continue;
        }
        seen.add(item.id);
        all.push(item);
      }
    }
    page.total = all.length;
    page.items = all.slice(q.startIndex, q.startIndex + q.limit);
    return page;
  }
  async getSimilar(_id: string, _limit: number): Promise<MediaItem[]> { return []; }
  async getGenres(_parentId: string): Promise<string[]> { return []; }
  // Flicx has no account: progress, watched marks and favourites are kept on this device.
  async reportStart(item: MediaItem, info: PlaybackInfo, positionMs: number): Promise<void> {
    await this.saveProgress(item, info, positionMs);
  }
  async reportProgress(item: MediaItem, info: PlaybackInfo, positionMs: number, _paused: boolean): Promise<void> {
    await this.saveProgress(item, info, positionMs);
  }
  async reportStopped(item: MediaItem, info: PlaybackInfo, positionMs: number): Promise<void> {
    await this.saveProgress(item, info, positionMs);
  }
  private async saveProgress(item: MediaItem, info: PlaybackInfo, positionMs: number): Promise<void> {
    await FlicxLibrary.load();
    FlicxLibrary.state.setProgress(item, this.slugFor(item.id), positionMs,
      info.durationMs > 0 ? info.durationMs : item.runtimeMs, Date.now());
    FlicxLibrary.changed();
  }
  async setPlayed(item: MediaItem, played: boolean): Promise<void> {
    await FlicxLibrary.load();
    FlicxLibrary.state.setPlayed(item, this.slugFor(item.id), played, Date.now());
    FlicxLibrary.changed();
  }
  async setFavorite(item: MediaItem, favorite: boolean): Promise<void> {
    await FlicxLibrary.load();
    FlicxLibrary.state.setFavorite(item, this.slugFor(item.id), favorite, Date.now());
    FlicxLibrary.changed();
  }
}
