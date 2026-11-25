import { MediaProvider } from '../common/MediaProvider';
import {
  SourceConfig, MediaItem, LibraryView, QueryOptions, PagedItems, PlaybackInfo, PlaybackRequest, UserState,
  SubtitleTrack, QualityOption, MediaType
} from '../common/Models';
import { SourceStore } from '../common/SourceStore';
import { LibraryDb, LocalFile } from '../library/LibraryDb';
import { FileLister, ScanProgress } from '../scraper/Scraper';
import { QuarkApi } from './QuarkApi';
import { QuarkTvApi } from './QuarkTvApi';
import { QuarkFile, QuarkQuality, QuarkLink, QuarkDrive } from './QuarkTypes';
import { isVideoName, isSubtitleName, isSkippedFolder, subtitleMatches, subtitleLang, fileExt, baseName } from './CookieUtil';
import { AppLog } from '../common/AppLog';

export const VIEW_MOVIES: string = 'quark-movies';
export const VIEW_TV: string = 'quark-tvshows';
export const VIEW_UNMATCHED: string = 'quark-unmatched';

class DirTask {
  fid: string = '';
  path: string = '';
  depth: number = 0;
}

/** Shared per-source client so cookie / token refresh state survives provider re-creation. */
class ApiHolder {
  drive: QuarkDrive;
  web: QuarkApi | undefined = undefined;
  tv: QuarkTvApi | undefined = undefined;
  persistTimer: number = -1;
  constructor(drive: QuarkDrive) {
    this.drive = drive;
  }
}

const TMDB_SIZES: number[] = [92, 154, 185, 342, 500, 780, 1280];

export class QuarkProvider implements MediaProvider, FileLister {
  readonly config: SourceConfig;
  private static holders: Map<string, ApiHolder> = new Map<string, ApiHolder>();
  /** Files seen in the browser that may not be in LibraryDb (for direct 'file-<fid>' playback). */
  private static fileCache: Map<string, QuarkFile> = new Map<string, QuarkFile>();
  private lastSaveMs: number = 0;

  constructor(cfg: SourceConfig) {
    this.config = cfg;
  }

  private isTv(): boolean {
    return this.config.quarkAuth === 'tv';
  }

  /** Drive backend for this source: TV client when quarkAuth is 'tv', else the web-cookie client. */
  get drive(): QuarkDrive {
    if (this.isTv()) {
      return this.tvApi();
    }
    return this.webApi();
  }

  /** TV client; reused while its device id matches and it has held the stored refresh token. */
  private tvApi(): QuarkTvApi {
    const h = QuarkProvider.holders.get(this.config.id);
    const cfg = this.config;
    if (h !== undefined && h.tv !== undefined && h.tv.deviceId === cfg.quarkDeviceId &&
      h.tv.knownTokens.indexOf(cfg.quarkRefreshToken) >= 0) {
      return h.tv;
    }
    const tv = new QuarkTvApi(cfg.quarkDeviceId, cfg.quarkRefreshToken);
    const holder = new ApiHolder(tv);
    holder.tv = tv;
    const sourceId = cfg.id;
    tv.onRefreshTokenChanged = (rt: string) => {
      QuarkProvider.persistRefreshToken(sourceId, rt);
    };
    QuarkProvider.holders.set(cfg.id, holder);
    return tv;
  }

  /** The web-cookie client (cookie kept in sync with SourceStore). */
  private webApi(): QuarkApi {
    let h = QuarkProvider.holders.get(this.config.id);
    if (h === undefined || h.web === undefined ||
      (h.web.cookie !== this.config.cookie && !QuarkProvider.isNewer(h.web.cookie, this.config.cookie))) {
      const api = new QuarkApi(this.config.cookie);
      h = new ApiHolder(api);
      h.web = api;
      const holder = h;
      const sourceId = this.config.id;
      api.onCookieChanged = (c: string) => {
        QuarkProvider.schedulePersist(sourceId, holder, c);
      };
      QuarkProvider.holders.set(this.config.id, h);
      return api;
    }
    return h.web;
  }

  /** Store a rotated refresh token right away (losing it would force a new QR login). */
  private static persistRefreshToken(sourceId: string, rt: string): void {
    const cfg = SourceStore.get(sourceId);
    if (cfg === undefined || cfg.quarkRefreshToken === rt) {
      return;
    }
    cfg.quarkRefreshToken = rt;
    SourceStore.upsert(cfg).catch((e: Error) => {
      AppLog.warn('[quark] persist refresh token failed: ' + e.message);
    });
  }

  /** True when `live` only differs from the stored cookie by a rolled __puus (a pending persist). */
  private static isNewer(live: string, stored: string): boolean {
    const a = live.replace(/(^|;\s*)__puus=[^;]*/, '').replace(/(^|;\s*)__pus=[^;]*/, '');
    const b = stored.replace(/(^|;\s*)__puus=[^;]*/, '').replace(/(^|;\s*)__pus=[^;]*/, '');
    return a === b;
  }

  private static schedulePersist(sourceId: string, holder: ApiHolder, cookie: string): void {
    if (holder.persistTimer >= 0) {
      clearTimeout(holder.persistTimer);
    }
    holder.persistTimer = setTimeout(() => {
      holder.persistTimer = -1;
      const cfg = SourceStore.get(sourceId);
      if (cfg === undefined || cfg.cookie === cookie) {
        return;
      }
      cfg.cookie = cookie;
      SourceStore.upsert(cfg).catch((e: Error) => {
        AppLog.warn('[quark] persist cookie failed: ' + e.message);
      });
    }, 1500);
  }

  static rememberFile(sourceId: string, f: QuarkFile): void {
    QuarkProvider.fileCache.set(sourceId + '/' + f.fid, f);
  }

  static fileItemId(fid: string): string {
    return 'file-' + fid;
  }

  // ---------------- connection ----------------

  async connect(): Promise<void> {
    if (this.isTv()) {
      if (!this.config.quarkRefreshToken || !this.config.quarkDeviceId) {
        throw new Error('尚未登录夸克网盘');
      }
      await this.tvApi().accountName();
      await LibraryDb.open();
      return;
    }
    if (!this.config.cookie) {
      throw new Error('尚未登录夸克网盘');
    }
    const api = this.webApi();
    await api.accountInfo();
    await api.ensureFresh();
    await LibraryDb.open();
  }

  // ---------------- library (scraped catalogue) ----------------

  async getViews(): Promise<LibraryView[]> {
    await LibraryDb.open();
    const views: LibraryView[] = [];
    views.push(await this.makeView(VIEW_MOVIES, '电影', 'movies', ['movie'], true));
    views.push(await this.makeView(VIEW_TV, '剧集', 'tvshows', ['series'], true));
    const un = await this.makeView(VIEW_UNMATCHED, '未识别', 'mixed', ['video'], false);
    if (un.id.length > 0) {
      views.push(un);
    }
    return views;
  }

  private async makeView(id: string, name: string, ctype: string, types: MediaType[], always: boolean): Promise<LibraryView> {
    const v = new LibraryView();
    const q = new QueryOptions();
    q.types = types;
    q.limit = 1;
    q.sortBy = 'DateCreated';
    q.sortDesc = true;
    let total = 0;
    try {
      const r: PagedItems = await LibraryDb.query(this.config.id, q);
      total = r.total;
      if (r.items.length > 0) {
        const it = r.items[0];
        v.image = it.images.backdrop || it.images.poster || it.images.thumb;
      }
    } catch (e) {
      AppLog.warn('[quark] view query failed: ' + (e as Error).message);
    }
    if (!always && total === 0) {
      return v;
    }
    v.sourceId = this.config.id;
    v.id = id;
    v.name = name;
    v.collectionType = ctype;
    return v;
  }

  private static viewTypes(viewId: string): MediaType[] {
    if (viewId === VIEW_MOVIES) {
      return ['movie'];
    }
    if (viewId === VIEW_TV) {
      return ['series'];
    }
    if (viewId === VIEW_UNMATCHED) {
      return ['video'];
    }
    return [];
  }

  private static isView(id: string): boolean {
    return id === VIEW_MOVIES || id === VIEW_TV || id === VIEW_UNMATCHED;
  }

  async getResume(limit: number): Promise<MediaItem[]> {
    return LibraryDb.resume(this.config.id, limit);
  }

  async getNextUp(limit: number): Promise<MediaItem[]> {
    return LibraryDb.nextUp(this.config.id, limit);
  }

  async getLatest(parentId: string, limit: number): Promise<MediaItem[]> {
    if (parentId.length === 0 || !QuarkProvider.isView(parentId)) {
      return LibraryDb.latest(this.config.id, limit);
    }
    const q = new QueryOptions();
    q.types = QuarkProvider.viewTypes(parentId);
    q.sortBy = 'DateCreated';
    q.sortDesc = true;
    q.limit = limit;
    const r: PagedItems = await LibraryDb.query(this.config.id, q);
    return r.items;
  }

  async getItems(q: QueryOptions): Promise<PagedItems> {
    const qq = QuarkProvider.copyQuery(q);
    if (QuarkProvider.isView(qq.parentId)) {
      if (qq.types.length === 0) {
        qq.types = QuarkProvider.viewTypes(qq.parentId);
      }
      qq.parentId = '';
    } else if (qq.parentId.length === 0 && qq.types.length === 0) {
      qq.types = ['movie', 'series'];
    }
    return LibraryDb.query(this.config.id, qq);
  }

  private static copyQuery(q: QueryOptions): QueryOptions {
    const c = new QueryOptions();
    c.parentId = q.parentId;
    c.types = q.types.slice();
    c.recursive = q.recursive;
    c.sortBy = q.sortBy;
    c.sortDesc = q.sortDesc;
    c.startIndex = q.startIndex;
    c.limit = q.limit;
    c.searchTerm = q.searchTerm;
    c.genres = q.genres.slice();
    c.years = q.years.slice();
    c.favoritesOnly = q.favoritesOnly;
    c.unplayedOnly = q.unplayedOnly;
    return c;
  }

  async getItem(id: string): Promise<MediaItem> {
    const it: MediaItem | undefined = await LibraryDb.getItem(this.config.id, id);
    if (it !== undefined) {
      return it;
    }
    if (id.startsWith('file-')) {
      const fid = id.substring(5);
      const cached = QuarkProvider.fileCache.get(this.config.id + '/' + fid);
      const m = new MediaItem();
      m.sourceId = this.config.id;
      m.id = id;
      m.type = 'video';
      m.title = cached !== undefined ? baseName(cached.name) : '网盘视频';
      m.container = cached !== undefined ? fileExt(cached.name) : '';
      if (cached !== undefined) {
        m.images.thumb = cached.thumbnail;
        m.runtimeMs = cached.duration * 1000;
      }
      return m;
    }
    throw new Error('未找到该条目，可能需要重新刮削');
  }

  async getSeasons(seriesId: string): Promise<MediaItem[]> {
    const kids: MediaItem[] = await LibraryDb.children(this.config.id, seriesId);
    return kids.filter((m: MediaItem) => m.type === 'season')
      .sort((a: MediaItem, b: MediaItem) => QuarkProvider.seasonKey(a) - QuarkProvider.seasonKey(b));
  }

  private static seasonKey(m: MediaItem): number {
    // specials (season 0) go last
    return m.seasonNumber <= 0 ? 10000 : m.seasonNumber;
  }

  async getEpisodes(seriesId: string, seasonId: string): Promise<MediaItem[]> {
    let eps: MediaItem[] = [];
    if (seasonId.length > 0) {
      eps = await LibraryDb.children(this.config.id, seasonId);
    } else {
      const seasons = await this.getSeasons(seriesId);
      for (let i = 0; i < seasons.length; i++) {
        const k: MediaItem[] = await LibraryDb.children(this.config.id, seasons[i].id);
        k.forEach((m: MediaItem) => eps.push(m));
      }
      if (seasons.length === 0) {
        eps = await LibraryDb.children(this.config.id, seriesId);
      }
    }
    return eps.filter((m: MediaItem) => m.type === 'episode').sort((a: MediaItem, b: MediaItem) => {
      if (a.seasonNumber !== b.seasonNumber) {
        return QuarkProvider.seasonKey(a) - QuarkProvider.seasonKey(b);
      }
      return a.episodeNumber - b.episodeNumber;
    });
  }

  async getSimilar(id: string, limit: number): Promise<MediaItem[]> {
    const it: MediaItem | undefined = await LibraryDb.getItem(this.config.id, id);
    if (it === undefined || it.genres.length === 0) {
      return [];
    }
    const q = new QueryOptions();
    q.types = [it.type === 'episode' || it.type === 'season' ? 'series' : it.type];
    q.genres = it.genres.slice(0, 2);
    q.sortBy = 'CommunityRating';
    q.sortDesc = true;
    q.limit = limit + 1;
    const r: PagedItems = await LibraryDb.query(this.config.id, q);
    const self = it.seriesId.length > 0 ? it.seriesId : it.id;
    return r.items.filter((m: MediaItem) => m.id !== self).slice(0, limit);
  }

  async search(term: string, limit: number): Promise<MediaItem[]> {
    if (term.trim().length === 0) {
      return [];
    }
    return LibraryDb.search(this.config.id, term.trim(), limit);
  }

  async getGenres(parentId: string): Promise<string[]> {
    return LibraryDb.genres(this.config.id);
  }

  // ---------------- playback ----------------

  /** Resolve the drive file backing an item (first matching LocalFile, or the fid of a 'file-<fid>' id). */
  private async resolveFile(item: MediaItem): Promise<LocalFile> {
    let files: LocalFile[] = [];
    try {
      files = await LibraryDb.filesForItem(this.config.id, item.id);
    } catch (e) {
      AppLog.warn('[quark] filesForItem failed: ' + (e as Error).message);
    }
    const vids = files.filter((f: LocalFile) => isVideoName(f.name) || !isSubtitleName(f.name));
    if (vids.length > 0) {
      // largest file wins when several versions exist
      vids.sort((a: LocalFile, b: LocalFile) => b.size - a.size);
      return vids[0];
    }
    if (item.id.startsWith('file-')) {
      const fid = item.id.substring(5);
      const lf = new LocalFile();
      lf.sourceId = this.config.id;
      lf.fid = fid;
      const cached = QuarkProvider.fileCache.get(this.config.id + '/' + fid);
      if (cached !== undefined) {
        lf.name = cached.name;
        lf.parentFid = cached.parentFid;
        lf.size = cached.size;
      }
      return lf;
    }
    if (item.type === 'series' || item.type === 'season') {
      throw new Error('请选择具体的剧集播放');
    }
    throw new Error('找不到对应的网盘文件，请重新刮削媒体库');
  }

  async getPlayback(item: MediaItem, req: PlaybackRequest): Promise<PlaybackInfo> {
    const api = this.drive;
    await api.ensureFresh();
    const file = await this.resolveFile(item);
    const info = new PlaybackInfo();
    info.mediaSourceId = file.fid;
    info.playSessionId = 'q' + Date.now().toString(36);
    info.container = fileExt(file.name);
    info.durationMs = item.runtimeMs;

    let original: QuarkLink | undefined = undefined;
    let originalErr = '';
    let transcodes: QuarkQuality[] = [];
    const tasks: Promise<void>[] = [];
    tasks.push(api.downloadLink(file.fid).then((l: QuarkLink) => {
      original = l;
    }).catch((e: Error) => {
      originalErr = e.message;
    }));
    tasks.push(api.playQualities(file.fid).then((q: QuarkQuality[]) => {
      transcodes = q;
    }).catch((e: Error) => {
      AppLog.info('[quark] no transcodes: ' + e.message);
    }));
    await Promise.all(tasks);

    const playHdr = api.streamHeaders();
    const origLink = original as QuarkLink | undefined;
    if (origLink !== undefined) {
      const o = new QualityOption();
      o.label = '原画';
      o.url = origLink.url;
      o.headers = origLink.headers;
      info.qualities.push(o);
    }
    transcodes.forEach((t: QuarkQuality) => {
      const o = new QualityOption();
      o.label = t.label;
      o.url = t.url;
      o.headers = playHdr;
      info.qualities.push(o);
      if (info.durationMs <= 0 && t.durationSec > 0) {
        info.durationMs = t.durationSec * 1000;
      }
    });
    if (info.qualities.length === 0) {
      throw new Error(originalErr.length > 0 ? originalErr : '无法获取播放地址');
    }

    // Choose the primary stream: original unless a bitrate cap asks for a transcode
    let chosen = info.qualities[0];
    if (req.maxBitrate > 0 && transcodes.length > 0) {
      const t = QuarkProvider.pickByBitrate(transcodes, req.maxBitrate);
      for (let i = 0; i < info.qualities.length; i++) {
        if (info.qualities[i].url === t.url) {
          chosen = info.qualities[i];
        }
      }
    }
    info.url = chosen.url;
    info.headers = chosen.headers;
    info.isTranscode = chosen.label !== '原画';
    info.deliveryMode = info.isTranscode ? 'transcode' : 'direct';
    if (info.isTranscode) {
      info.container = chosen.url.indexOf('.m3u8') >= 0 ? 'm3u8' : 'mp4';
    }

    if (file.parentFid.length > 0 && file.name.length > 0) {
      try {
        info.subtitles = await this.findSubtitles(file);
      } catch (e) {
        AppLog.warn('[quark] subtitle lookup failed: ' + (e as Error).message);
      }
    }
    return info;
  }

  /** Map a bitrate cap (bps) to a resolution tier. */
  private static pickByBitrate(list: QuarkQuality[], maxBitrate: number): QuarkQuality {
    let wanted = 'low';
    if (maxBitrate >= 40000000) {
      wanted = '4k';
    } else if (maxBitrate >= 15000000) {
      wanted = '2k';
    } else if (maxBitrate >= 6000000) {
      wanted = 'super';
    } else if (maxBitrate >= 3000000) {
      wanted = 'high';
    } else if (maxBitrate >= 1500000) {
      wanted = 'normal';
    }
    const order: string[] = ['4k', '2k', 'super', 'high', 'normal', 'low'];
    const start = order.indexOf(wanted);
    for (let i = start; i < order.length; i++) {
      for (let j = 0; j < list.length; j++) {
        if (list[j].resolution === order[i]) {
          return list[j];
        }
      }
    }
    return list[list.length - 1];
  }

  private async findSubtitles(file: LocalFile): Promise<SubtitleTrack[]> {
    const api = this.drive;
    const siblings = await api.listAll(file.parentFid);
    const subs = siblings.filter((f: QuarkFile) => !f.isDir && isSubtitleName(f.name) && subtitleMatches(file.name, f.name));
    // a lone subtitle in a folder with a single video also belongs to it
    if (subs.length === 0) {
      const vids = siblings.filter((f: QuarkFile) => !f.isDir && isVideoName(f.name));
      const allSubs = siblings.filter((f: QuarkFile) => !f.isDir && isSubtitleName(f.name));
      if (vids.length === 1 && allSubs.length > 0 && allSubs.length <= 3) {
        allSubs.forEach((f: QuarkFile) => subs.push(f));
      }
    }
    const limited = subs.slice(0, 8);
    const tracks: SubtitleTrack[] = [];
    const vb = baseName(file.name);
    const links = await Promise.all(limited.map((f: QuarkFile) => api.downloadLink(f.fid)
      .then((l: QuarkLink): string => l.url).catch((): string => '')));
    for (let i = 0; i < limited.length; i++) {
      if (links[i].length === 0) {
        continue;
      }
      const lang = subtitleLang(vb, limited[i].name);
      const t = new SubtitleTrack();
      t.index = 1000 + i;
      t.language = lang[0];
      t.title = lang[1] + ' (' + fileExt(limited[i].name).toUpperCase() + ')';
      t.url = links[i];
      t.isExternal = true;
      t.codec = fileExt(limited[i].name);
      tracks.push(t);
    }
    // prefer Simplified Chinese as default
    let def = -1;
    for (let i = 0; i < tracks.length && def < 0; i++) {
      if (tracks[i].language === 'zh-Hans' || tracks[i].language === 'zh') {
        def = i;
      }
    }
    if (def >= 0) {
      tracks[def].isDefault = true;
    }
    return tracks;
  }

  // ---------------- user state ----------------

  private async currentState(item: MediaItem): Promise<UserState> {
    const s = new UserState();
    let src = item.state;
    try {
      const stored: MediaItem | undefined = await LibraryDb.getItem(this.config.id, item.id);
      if (stored !== undefined) {
        src = stored.state;
      }
    } catch (e) {
      // fall back to the in-memory state
    }
    if (src) {
      s.played = src.played;
      s.favorite = src.favorite;
      s.positionMs = src.positionMs;
      s.playCount = src.playCount;
      s.lastPlayed = src.lastPlayed;
    }
    return s;
  }

  private async savePosition(item: MediaItem, info: PlaybackInfo, positionMs: number, finished: boolean): Promise<void> {
    const s = await this.currentState(item);
    const dur = info.durationMs > 0 ? info.durationMs : item.runtimeMs;
    s.lastPlayed = Date.now();
    if (finished || (dur > 0 && positionMs >= dur * 0.92)) {
      if (!s.played) {
        s.playCount = s.playCount + 1;
      }
      s.played = true;
      s.positionMs = 0;
    } else if (positionMs > 30000) {
      s.positionMs = Math.floor(positionMs);
    }
    item.state = s;
    await LibraryDb.setState(this.config.id, item.id, s);
  }

  async reportStart(item: MediaItem, info: PlaybackInfo, positionMs: number): Promise<void> {
    const s = await this.currentState(item);
    s.lastPlayed = Date.now();
    item.state = s;
    await LibraryDb.setState(this.config.id, item.id, s);
  }

  async reportProgress(item: MediaItem, info: PlaybackInfo, positionMs: number, paused: boolean): Promise<void> {
    // throttle db writes to one every 10 s
    const now = Date.now();
    if (!paused && now - this.lastSaveMs < 10000) {
      return;
    }
    this.lastSaveMs = now;
    await this.savePosition(item, info, positionMs, false);
  }

  async reportStopped(item: MediaItem, info: PlaybackInfo, positionMs: number): Promise<void> {
    this.lastSaveMs = 0;
    await this.savePosition(item, info, positionMs, false);
  }

  async setPlayed(item: MediaItem, played: boolean): Promise<void> {
    const s = await this.currentState(item);
    s.played = played;
    s.positionMs = 0;
    if (played) {
      s.playCount = s.playCount + 1;
      s.lastPlayed = Date.now();
    }
    item.state = s;
    await LibraryDb.setState(this.config.id, item.id, s);
    // marking a series / season applies to its episodes
    if (item.type === 'series' || item.type === 'season') {
      const eps: MediaItem[] = item.type === 'series' ? await this.getEpisodes(item.id, '')
        : await LibraryDb.children(this.config.id, item.id);
      for (let i = 0; i < eps.length; i++) {
        const es = await this.currentState(eps[i]);
        es.played = played;
        es.positionMs = 0;
        await LibraryDb.setState(this.config.id, eps[i].id, es);
      }
    }
  }

  async setFavorite(item: MediaItem, favorite: boolean): Promise<void> {
    const s = await this.currentState(item);
    s.favorite = favorite;
    item.state = s;
    await LibraryDb.setState(this.config.id, item.id, s);
  }

  // ---------------- images ----------------

  imageUrl(item: MediaItem, kind: 'poster' | 'backdrop' | 'logo' | 'thumb', maxWidth: number): string {
    let u = '';
    if (kind === 'poster') {
      u = item.images.poster;
    } else if (kind === 'backdrop') {
      u = item.images.backdrop;
    } else if (kind === 'logo') {
      u = item.images.logo;
    } else {
      u = item.images.thumb || item.images.backdrop;
    }
    if (!u) {
      return '';
    }
    return QuarkProvider.sizeTmdb(u, maxWidth);
  }

  /** Rewrite .../t/p/<size>/x.jpg to the smallest TMDB size >= maxWidth (original stays for > 1280). */
  private static sizeTmdb(u: string, maxWidth: number): string {
    const m = u.match(/\/t\/p\/(w\d+|original|h\d+)\//);
    if (m === null || maxWidth <= 0) {
      return u;
    }
    let size = 'original';
    for (let i = 0; i < TMDB_SIZES.length; i++) {
      if (TMDB_SIZES[i] >= maxWidth) {
        size = 'w' + TMDB_SIZES[i];
        break;
      }
    }
    return u.replace(m[0], '/t/p/' + size + '/');
  }

  imageHeaders(): Record<string, string> {
    const h: Record<string, string> = {};
    return h;
  }

  // ---------------- FileLister ----------------

  async listVideos(rootFid: string, onProgress: (p: ScanProgress) => void): Promise<LocalFile[]> {
    const api = this.drive;
    await api.ensureFresh();
    const out: LocalFile[] = [];
    const queue: DirTask[] = [];
    const root = new DirTask();
    root.fid = rootFid.length > 0 ? rootFid : '0';
    queue.push(root);
    const progress = new ScanProgress();
    let folders = 0;
    let firstError: Error | undefined = undefined;
    const CONCURRENCY = 3;

    const worker = async (): Promise<void> => {
      while (true) {
        const t = queue.shift();
        if (t === undefined) {
          // another worker may still enqueue; wait briefly while any are busy
          if (busy === 0) {
            return;
          }
          await QuarkApi.sleep(80);
          continue;
        }
        busy++;
        try {
          progress.current = t.path.length > 0 ? t.path : '/';
          onProgress(progress);
          const entries = await api.listAll(t.fid);
          folders++;
          for (let i = 0; i < entries.length; i++) {
            const f = entries[i];
            const p = t.path.length > 0 ? t.path + '/' + f.name : f.name;
            if (f.isDir) {
              if (!isSkippedFolder(f.name) && t.depth < 12) {
                const d = new DirTask();
                d.fid = f.fid;
                d.path = p;
                d.depth = t.depth + 1;
                queue.push(d);
              }
              continue;
            }
            const ext = fileExt(f.name);
            if (ext === 'iso') {
              continue;
            }
            const video = isVideoName(f.name) || (f.category === 1 && ext !== 'iso');
            if (!video && !isSubtitleName(f.name)) {
              continue;
            }
            if (video && f.size > 0 && f.size < 2 * 1024 * 1024 && /sample|trailer|预告/i.test(f.name)) {
              continue;
            }
            const lf = new LocalFile();
            lf.sourceId = this.config.id;
            lf.fid = f.fid;
            lf.parentFid = t.fid;
            lf.path = p;
            lf.name = f.name;
            lf.size = f.size;
            lf.updatedAt = f.updatedAt;
            out.push(lf);
            QuarkProvider.rememberFile(this.config.id, f);
          }
          progress.total = out.length;
          progress.current = t.path.length > 0 ? t.path : '/';
          onProgress(progress);
          // be gentle with the API
          await QuarkApi.sleep(150);
        } catch (e) {
          const err = e as Error;
          AppLog.warn('[quark] list ' + t.path + ' failed: ' + err.message);
          if (firstError === undefined) {
            firstError = err;
          }
          if (t.depth === 0 || err.message.indexOf('登录') >= 0) {
            queue.length = 0;
          }
        } finally {
          busy--;
        }
      }
    };
    let busy = 0;
    const workers: Promise<void>[] = [];
    for (let i = 0; i < CONCURRENCY; i++) {
      workers.push(worker());
    }
    await Promise.all(workers);
    const fe = firstError as Error | undefined;
    if (fe !== undefined && (folders === 0 || fe.message.indexOf('登录') >= 0)) {
      throw fe;
    }
    return out;
  }
}
