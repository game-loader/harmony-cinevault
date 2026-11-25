import { MediaItem, UserState } from '../common/Models';
import { Settings } from '../common/Settings';
import { LibraryDb, LocalFile } from '../library/LibraryDb';
import { ParsedName, parseName, isSubtitleFile, isVideoFile, stripExt, normKey, displayName, fileExt } from './NameParser';
import { TmdbClient, TmdbCandidate } from './TmdbClient';
import { TmdbDetail, TmdbSeason, TmdbEpisode, TmdbSeasonSummary } from './TmdbTypes';
import { AppLog } from '../common/AppLog';

export class ScanProgress {
  done: number = 0;
  total: number = 0;
  current: string = '';
  matched: number = 0;
  failed: number = 0;
}

/** Lists video files under a folder. Implemented by quark/QuarkProvider (so the scraper stays source-agnostic). */
export interface FileLister {
  /** Recursively list video files (and .srt/.ass/.vtt subtitle files) below rootFid. */
  listVideos(rootFid: string, onProgress: (p: ScanProgress) => void): Promise<LocalFile[]>;
}

const CONCURRENCY: number = 4;

/** One parsed video file waiting to be matched. */
class Job {
  file: LocalFile = new LocalFile();
  parsed: ParsedName = new ParsedName();
  /** item id before this scan ('' if new) */
  oldItemId: string = '';
}

/** All files of one show (same normalised title + year). */
class ShowGroup {
  key: string = '';
  parsed: ParsedName = new ParsedName();
  jobs: Job[] = [];
}

/** A fetched TMDB series with its seasons, cached for the duration of a scan / rematch. */
class SeriesCtx {
  series: MediaItem = new MediaItem();
  detail: TmdbDetail = {};
  seasons: Map<number, MediaItem> = new Map<number, MediaItem>();
  seasonData: Map<number, TmdbSeason | null> = new Map<number, TmdbSeason | null>();
}

function errText(e: Object): string {
  const er = e as Error;
  return er.message !== undefined ? er.message : String(e);
}

function isAuthError(msg: string): boolean {
  return msg.indexOf('API Key') >= 0;
}

async function runPool(tasks: Array<() => Promise<void>>, n: number): Promise<void> {
  let next = 0;
  const worker = async (): Promise<void> => {
    while (next < tasks.length) {
      const t = tasks[next];
      next++;
      await t();
    }
  };
  const ws: Promise<void>[] = [];
  for (let i = 0; i < Math.min(n, tasks.length); i++) {
    ws.push(worker());
  }
  await Promise.all(ws);
}

function cloneState(s: UserState): UserState {
  const c = new UserState();
  c.played = s.played;
  c.favorite = s.favorite;
  c.positionMs = s.positionMs;
  c.playCount = s.playCount;
  c.lastPlayed = s.lastPlayed;
  return c;
}

function hasState(s: UserState): boolean {
  return s.played || s.favorite || s.positionMs > 0 || s.playCount > 0;
}

/** OWNER: scraper agent. Filename parsing + TMDB match + LibraryDb write. */
export class Scraper {
  private static running: boolean = false;

  // ---------------- TMDB -> catalogue helpers ----------------

  private static async loadSeries(sourceId: string, tmdbId: string): Promise<SeriesCtx> {
    const d = await TmdbClient.tv(tmdbId);
    const ctx = new SeriesCtx();
    ctx.detail = d;
    ctx.series = TmdbClient.mapSeries(sourceId, d);
    await LibraryDb.upsertItem(ctx.series);
    return ctx;
  }

  private static async seasonData(ctx: SeriesCtx, n: number): Promise<TmdbSeason | undefined> {
    if (ctx.seasonData.has(n)) {
      const v = ctx.seasonData.get(n);
      return v === null || v === undefined ? undefined : v;
    }
    const known = ctx.detail.seasons === undefined ? true :
      ctx.detail.seasons.some((s: TmdbSeasonSummary) => s.season_number === n);
    let data: TmdbSeason | undefined = undefined;
    if (known) {
      try {
        data = await TmdbClient.season(ctx.series.tmdbId, n);
      } catch (e) {
        if (isAuthError(errText(e as Object))) {
          throw e as Error;
        }
        data = undefined;
      }
    }
    ctx.seasonData.set(n, data === undefined ? null : data);
    return data;
  }

  private static async ensureSeason(ctx: SeriesCtx, n: number): Promise<MediaItem> {
    const have = ctx.seasons.get(n);
    if (have !== undefined) {
      return have;
    }
    const data = await Scraper.seasonData(ctx, n);
    let summary: TmdbSeasonSummary | undefined = undefined;
    if (ctx.detail.seasons !== undefined) {
      summary = ctx.detail.seasons.find((s: TmdbSeasonSummary) => s.season_number === n);
    }
    const m = TmdbClient.mapSeason(ctx.series, n, summary, data);
    ctx.seasons.set(n, m);
    await LibraryDb.upsertItem(m);
    return m;
  }

  /**
   * Resolve season/episode numbers against TMDB. Files without a season folder often use absolute
   * numbering ("第28集" of a show TMDB splits into seasons), so map those onto the right season.
   */
  private static async locateEpisode(ctx: SeriesCtx, season: number, ep: number): Promise<number[]> {
    const data = await Scraper.seasonData(ctx, season);
    if (data !== undefined && data.episodes !== undefined &&
      data.episodes.some((e: TmdbEpisode) => e.episode_number === ep)) {
      return [season, ep];
    }
    if (season === 1 && ctx.detail.seasons !== undefined) {
      let rest = ep;
      const regular = ctx.detail.seasons.filter((s: TmdbSeasonSummary) => (s.season_number ?? 0) > 0)
        .sort((a: TmdbSeasonSummary, b: TmdbSeasonSummary) => (a.season_number ?? 0) - (b.season_number ?? 0));
      for (let i = 0; i < regular.length; i++) {
        const cnt = regular[i].episode_count ?? 0;
        if (cnt <= 0) {
          break;
        }
        if (rest <= cnt) {
          return [regular[i].season_number ?? 1, rest];
        }
        rest -= cnt;
      }
    }
    return [season, ep];
  }

  private static async episodeItem(ctx: SeriesCtx, season: number, ep: number): Promise<MediaItem> {
    const loc = await Scraper.locateEpisode(ctx, season, ep);
    const sItem = await Scraper.ensureSeason(ctx, loc[0]);
    const data = await Scraper.seasonData(ctx, loc[0]);
    let e: TmdbEpisode | undefined = undefined;
    if (data !== undefined && data.episodes !== undefined) {
      e = data.episodes.find((x: TmdbEpisode) => x.episode_number === loc[1]);
    }
    const m = TmdbClient.mapEpisode(sItem, ctx.series, loc[1], e);
    await LibraryDb.upsertItem(m);
    return m;
  }

  private static async movieItem(sourceId: string, tmdbId: string): Promise<MediaItem> {
    const d = await TmdbClient.movie(tmdbId);
    const m = TmdbClient.mapMovie(sourceId, d);
    await LibraryDb.upsertItem(m);
    return m;
  }

  private static async unmatchedItem(f: LocalFile, p: ParsedName): Promise<MediaItem> {
    const m = new MediaItem();
    m.sourceId = f.sourceId;
    m.id = 'file-' + f.fid;
    m.type = 'video';
    m.title = displayName(p);
    if (m.title.length === 0) {
      m.title = stripExt(f.name);
    }
    m.originalTitle = f.name;
    m.year = p.year;
    m.container = fileExt(f.name);
    m.overview = f.path;
    await LibraryDb.upsertItem(m);
    return m;
  }

  private static async link(f: LocalFile, itemId: string): Promise<void> {
    f.itemId = itemId;
    await LibraryDb.upsertFile(f);
  }

  /** Carry user state from an item that is going away to its replacement. */
  private static async moveState(sourceId: string, fromId: string, toId: string): Promise<void> {
    if (fromId.length === 0 || fromId === toId) {
      return;
    }
    const old = await LibraryDb.getItem(sourceId, fromId);
    if (old === undefined || !hasState(old.state)) {
      return;
    }
    const target = await LibraryDb.getItem(sourceId, toId);
    if (target !== undefined && hasState(target.state)) {
      return;
    }
    await LibraryDb.setState(sourceId, toId, cloneState(old.state));
  }

  // ---------------- matching ----------------

  private static async matchMovieGroup(g: ShowGroup): Promise<boolean> {
    let cand: TmdbCandidate | undefined = undefined;
    try {
      cand = await TmdbClient.findBest(g.parsed, 'movie');
    } catch (e) {
      const msg = errText(e as Object);
      if (isAuthError(msg)) {
        throw e as Error;
      }
      AppLog.warn('[scraper] movie search failed: ' + g.parsed.title + ': ' + msg);
      await Scraper.keepOrUnmatch(g.jobs);
      return false;
    }
    if (cand === undefined) {
      await Scraper.markUnmatched(g.jobs);
      return false;
    }
    const m = await Scraper.movieItem(g.jobs[0].file.sourceId, String(cand.result.id ?? 0));
    for (let i = 0; i < g.jobs.length; i++) {
      const j = g.jobs[i];
      await Scraper.link(j.file, m.id);
      await Scraper.moveState(j.file.sourceId, j.oldItemId, m.id);
    }
    return true;
  }

  private static async matchTvGroup(g: ShowGroup, onFile: (j: Job, ok: boolean) => void): Promise<void> {
    let ctx: SeriesCtx | undefined = undefined;
    try {
      const cand = await TmdbClient.findBest(g.parsed, 'tv');
      if (cand !== undefined) {
        ctx = await Scraper.loadSeries(g.jobs[0].file.sourceId, String(cand.result.id ?? 0));
      }
    } catch (e) {
      const msg = errText(e as Object);
      if (isAuthError(msg)) {
        throw e as Error;
      }
      AppLog.warn('[scraper] tv search failed: ' + g.parsed.title + ': ' + msg);
      await Scraper.keepOrUnmatch(g.jobs);
      g.jobs.forEach((j: Job) => onFile(j, j.file.itemId.length > 0 && !j.file.itemId.startsWith('file-')));
      return;
    }
    if (ctx === undefined) {
      await Scraper.markUnmatched(g.jobs);
      g.jobs.forEach((j: Job) => onFile(j, false));
      return;
    }
    const c = ctx as SeriesCtx;
    // files without an episode number get sequential numbers in path order
    let seq = 0;
    for (let i = 0; i < g.jobs.length; i++) {
      const j = g.jobs[i];
      let ok = false;
      try {
        const season = j.parsed.season >= 0 ? j.parsed.season : 1;
        let ep = j.parsed.episode;
        if (ep < 0) {
          seq++;
          ep = seq;
        }
        const m = await Scraper.episodeItem(c, season, ep);
        await Scraper.link(j.file, m.id);
        await Scraper.moveState(j.file.sourceId, j.oldItemId, m.id);
        ok = true;
      } catch (e) {
        const msg = errText(e as Object);
        if (isAuthError(msg)) {
          throw e as Error;
        }
        AppLog.warn('[scraper] episode failed: ' + j.file.path + ': ' + msg);
        await Scraper.keepOrUnmatch([j]);
      }
      onFile(j, ok);
    }
  }

  private static async markUnmatched(jobs: Job[]): Promise<void> {
    for (let i = 0; i < jobs.length; i++) {
      const j = jobs[i];
      const m = await Scraper.unmatchedItem(j.file, j.parsed);
      await Scraper.link(j.file, m.id);
      await Scraper.moveState(j.file.sourceId, j.oldItemId, m.id);
    }
  }

  /** On transient errors keep an existing match; brand-new files become unmatched videos so they stay playable. */
  private static async keepOrUnmatch(jobs: Job[]): Promise<void> {
    const fresh: Job[] = [];
    for (let i = 0; i < jobs.length; i++) {
      const j = jobs[i];
      if (j.oldItemId.length > 0 && !j.oldItemId.startsWith('file-')) {
        await Scraper.link(j.file, j.oldItemId);
      } else {
        fresh.push(j);
      }
    }
    await Scraper.markUnmatched(fresh);
  }

  /** Attach subtitle files to the item of the video with the same stem (or the only video) in their folder. */
  private static async linkSubtitles(subs: LocalFile[], videos: LocalFile[]): Promise<void> {
    for (let i = 0; i < subs.length; i++) {
      const s = subs[i];
      const stem = normKey(stripExt(stripExt(s.name)));
      const peers = videos.filter((v: LocalFile) => v.parentFid === s.parentFid && v.itemId.length > 0);
      let target = peers.find((v: LocalFile) => {
        const vs = normKey(stripExt(v.name));
        return vs.length > 0 && (stem.startsWith(vs) || vs.startsWith(stem));
      });
      if (target === undefined && peers.length === 1) {
        target = peers[0];
      }
      s.itemId = target !== undefined ? target.itemId : '';
      await LibraryDb.upsertFile(s);
    }
  }

  private static groupKey(p: ParsedName, tv: boolean): string {
    const k = normKey(p.title);
    return (tv ? 'tv:' : 'mv:') + (k.length > 0 ? k : normKey(p.altTitle)) + (tv ? '' : ':' + p.year);
  }

  // ---------------- public API ----------------

  /** Full or incremental scan of a source; already-matched unchanged files are skipped unless force. */
  static async scan(sourceId: string, rootFid: string, lister: FileLister, force: boolean,
    onProgress: (p: ScanProgress) => void): Promise<ScanProgress> {
    if (Scraper.running) {
      throw new Error('已有刮削任务正在进行，请稍候');
    }
    Scraper.running = true;
    const prog = new ScanProgress();
    try {
      const st = await Settings.load();
      if (st.tmdbApiKey.trim().length === 0) {
        throw new Error('请先在设置中填写 TMDB API Key');
      }
      if (force) {
        TmdbClient.clearCache();
      }
      await LibraryDb.open();
      prog.current = '正在读取网盘文件列表…';
      onProgress(prog);
      const listed = await lister.listVideos(rootFid, (p: ScanProgress) => {
        prog.current = p.current.length > 0 ? '读取目录：' + p.current : '正在读取网盘文件列表…';
        onProgress(prog);
      });
      const existing = new Map<string, LocalFile>();
      (await LibraryDb.allFiles(sourceId)).forEach((f: LocalFile) => existing.set(f.fid, f));
      const seen = new Set<string>();
      const videos: LocalFile[] = [];
      const subs: LocalFile[] = [];
      const jobs: Job[] = [];
      let skipped = 0;
      listed.forEach((f: LocalFile) => {
        f.sourceId = sourceId;
        if (seen.has(f.fid)) {
          return;
        }
        seen.add(f.fid);
        if (isSubtitleFile(f.name)) {
          subs.push(f);
          return;
        }
        const p = parseName(f.path.length > 0 ? f.path : f.name);
        if (p.excluded) {
          seen.delete(f.fid);   // sample / trailer: drop from the library
          return;
        }
        videos.push(f);
        const old = existing.get(f.fid);
        const oldId = old !== undefined ? old.itemId : '';
        if (!force && old !== undefined && oldId.length > 0 && !oldId.startsWith('file-') &&
          old.size === f.size && old.updatedAt === f.updatedAt && old.path === f.path) {
          f.itemId = oldId;
          skipped++;
          return;
        }
        if (!isVideoFile(f.name) && p.title.length === 0) {
          p.title = stripExt(f.name);
        }
        const j = new Job();
        j.file = f;
        j.parsed = p;
        j.oldItemId = oldId;
        jobs.push(j);
      });
      // deleted (or now excluded) files
      const gone: string[] = [];
      existing.forEach((f: LocalFile, fid: string) => {
        if (!seen.has(fid)) {
          gone.push(fid);
        }
      });
      for (let i = 0; i < gone.length; i++) {
        await LibraryDb.removeFile(sourceId, gone[i]);
      }
      // keep skipped files' metadata (name/path) fresh
      for (let i = 0; i < videos.length; i++) {
        const v = videos[i];
        if (v.itemId.length > 0) {
          await LibraryDb.upsertFile(v);
        }
      }

      prog.total = jobs.length + skipped;
      prog.done = skipped;
      prog.matched = skipped;
      prog.current = jobs.length > 0 ? '正在匹配 TMDB…' : '没有新增或变更的文件';
      onProgress(prog);

      // group: every show once, identical movies once
      const groups = new Map<string, ShowGroup>();
      const order: string[] = [];
      jobs.forEach((j: Job) => {
        const key = Scraper.groupKey(j.parsed, j.parsed.isTv);
        let g = groups.get(key);
        if (g === undefined) {
          g = new ShowGroup();
          g.key = key;
          g.parsed = j.parsed;
          groups.set(key, g);
          order.push(key);
        } else if (g.parsed.year === 0 && j.parsed.year > 0) {
          g.parsed = j.parsed;
        }
        g.jobs.push(j);
      });
      const tasks: Array<() => Promise<void>> = [];
      let fatal: Error | undefined = undefined;
      order.forEach((key: string) => {
        const g = groups.get(key) as ShowGroup;
        g.jobs.sort((a: Job, b: Job) => a.file.path.localeCompare(b.file.path));
        tasks.push(async (): Promise<void> => {
          if (fatal !== undefined) {
            return;
          }
          prog.current = g.parsed.title.length > 0 ? g.parsed.title : g.jobs[0].file.name;
          onProgress(prog);
          try {
            if (key.startsWith('tv:')) {
              await Scraper.matchTvGroup(g, (j: Job, ok: boolean) => {
                prog.done++;
                if (ok) {
                  prog.matched++;
                } else {
                  prog.failed++;
                }
                onProgress(prog);
              });
            } else {
              const ok = await Scraper.matchMovieGroup(g);
              prog.done += g.jobs.length;
              if (ok) {
                prog.matched += g.jobs.length;
              } else {
                prog.failed += g.jobs.length;
              }
              onProgress(prog);
            }
          } catch (e) {
            fatal = e as Error;
          }
        });
      });
      await runPool(tasks, CONCURRENCY);
      if (fatal !== undefined) {
        throw fatal as Error;
      }
      await Scraper.linkSubtitles(subs, videos);
      await LibraryDb.pruneOrphans(sourceId);
      prog.current = '完成';
      prog.done = prog.total;
      onProgress(prog);
      return prog;
    } finally {
      Scraper.running = false;
    }
  }

  /** Manual re-match: user picks a TMDB result for a file / item. */
  static async rematch(sourceId: string, itemId: string, tmdbType: 'movie' | 'tv', tmdbId: string): Promise<MediaItem | undefined> {
    await Settings.load();
    await LibraryDb.open();
    const item = await LibraryDb.getItem(sourceId, itemId);
    let files: LocalFile[] = [];
    if (item !== undefined && (item.type === 'series' || item.type === 'season')) {
      files = await LibraryDb.filesUnder(sourceId, itemId);
    } else {
      files = await LibraryDb.filesForItem(sourceId, itemId);
    }
    if (files.length === 0 && itemId.startsWith('file-')) {
      const f = await LibraryDb.getFile(sourceId, itemId.substring(5));
      if (f !== undefined) {
        files = [f];
      }
    }
    const vids = files.filter((f: LocalFile) => !isSubtitleFile(f.name));
    const subs = files.filter((f: LocalFile) => isSubtitleFile(f.name));
    if (vids.length === 0) {
      throw new Error('找不到该条目对应的网盘文件，请先重新刮削');
    }
    let result: MediaItem | undefined = undefined;
    if (tmdbType === 'movie') {
      const m = await Scraper.movieItem(sourceId, tmdbId);
      for (let i = 0; i < files.length; i++) {
        const old = files[i].itemId;
        await Scraper.link(files[i], m.id);
        await Scraper.moveState(sourceId, old, m.id);
      }
      result = m;
    } else {
      const ctx = await Scraper.loadSeries(sourceId, tmdbId);
      vids.sort((a: LocalFile, b: LocalFile) => a.path.localeCompare(b.path));
      let seq = 0;
      for (let i = 0; i < vids.length; i++) {
        const f = vids[i];
        const p = parseName(f.path.length > 0 ? f.path : f.name);
        let season = p.season;
        let ep = p.episode;
        if (ep < 0 && item !== undefined && item.type === 'episode' && vids.length === 1) {
          season = item.seasonNumber;
          ep = item.episodeNumber;
        }
        if (ep < 0) {
          seq++;
          ep = seq;
        }
        const m = await Scraper.episodeItem(ctx, season >= 0 ? season : 1, ep);
        const old = f.itemId;
        await Scraper.link(f, m.id);
        await Scraper.moveState(sourceId, old, m.id);
      }
      await Scraper.linkSubtitles(subs, vids);
      result = await LibraryDb.getItem(sourceId, ctx.series.id);
    }
    await LibraryDb.pruneOrphans(sourceId);
    return result;
  }

  /** TMDB search for the manual match UI. Items carry id = tmdbId = TMDB numeric id. */
  static async searchTmdb(query: string, year: number, type: 'movie' | 'tv'): Promise<MediaItem[]> {
    await Settings.load();
    const q = query.trim();
    if (q.length === 0) {
      return [];
    }
    let res = type === 'tv' ? await TmdbClient.searchTv(q, year) : await TmdbClient.searchMovie(q, year);
    if (res.length === 0 && year > 0) {
      res = type === 'tv' ? await TmdbClient.searchTv(q, 0) : await TmdbClient.searchMovie(q, 0);
    }
    if (res.length === 0) {
      // try the cleaned title when the user pasted a raw file name
      const p = parseName(q);
      if (p.title.length > 0 && p.title !== q) {
        const y = year > 0 ? year : p.year;
        res = type === 'tv' ? await TmdbClient.searchTv(p.title, y) : await TmdbClient.searchMovie(p.title, y);
      }
    }
    return res.slice(0, 20).map((r) => TmdbClient.mapSearchResult(r, type));
  }
}
