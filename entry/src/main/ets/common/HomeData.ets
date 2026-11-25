// Home screen aggregation across all enabled sources (or Settings.homeSourceId).
import { MediaItem, LibraryView, HomeRow, QueryOptions, PagedItems, MediaType } from './Models';
import { MediaProvider } from './MediaProvider';
import { ProviderRegistry } from '../providers/ProviderRegistry';
import { Settings } from './Settings';
import { SourceStore } from './SourceStore';
import { FlicxProvider } from '../flicx/FlicxProvider';
import { settleAll, Settled, dedupe, sortByLastPlayed, roundRobin, pickFeatured, shuffle } from '../components/MediaLogic';

export class SourceWarning {
  sourceId: string = '';
  sourceName: string = '';
  message: string = '';
}

export class HomeResult {
  featured: MediaItem[] = [];
  rows: HomeRow[] = [];
  views: LibraryView[] = [];
  warnings: SourceWarning[] = [];
  sourceCount: number = 0;
  loadedAt: number = 0;
}

class SourceHome {
  sourceId: string = '';
  resume: MediaItem[] = [];
  nextUp: MediaItem[] = [];
  views: LibraryView[] = [];
  latest: HomeRow[] = [];
  random: MediaItem[] = [];
  favorites: MediaItem[] = [];
  /** Rails a source supplies itself (Flicx home page). */
  rails: HomeRow[] = [];
  errors: string[] = [];
}

const ROW_LIMIT = 24;

export class HomeData {
  private static cache: HomeResult | undefined = undefined;
  private static inflight: Promise<HomeResult> | undefined = undefined;
  private static version: number = 0;
  /** Set by invalidate() so the next load also refetches remote rails (pull to refresh). */
  private static refetch: boolean = false;

  /** Last result in memory, if any. */
  static cached(): HomeResult | undefined {
    return HomeData.cache;
  }

  /** Drop the cache (e.g. after sources change). */
  static invalidate(): void {
    HomeData.cache = undefined;
    HomeData.version++;
    HomeData.refetch = true;
  }

  /** Providers shown on the home screen. */
  static providers(): MediaProvider[] {
    const all = ProviderRegistry.all();
    const hid = Settings.get().homeSourceId;
    if (hid.length > 0) {
      const one = all.filter((p: MediaProvider) => p.config.id === hid);
      if (one.length > 0) {
        return one;
      }
    }
    return all;
  }

  /** Load (deduplicates concurrent calls). force=false returns the cache when present. */
  static load(force: boolean): Promise<HomeResult> {
    if (!force && HomeData.cache !== undefined) {
      return Promise.resolve(HomeData.cache);
    }
    if (HomeData.inflight !== undefined) {
      return HomeData.inflight;
    }
    const v = HomeData.version;
    const refetch = HomeData.refetch;
    HomeData.refetch = false;
    const p = HomeData.doLoad(refetch).then((r: HomeResult) => {
      if (v === HomeData.version) {
        HomeData.cache = r;
      }
      HomeData.inflight = undefined;
      return r;
    }, (e: Object) => {
      HomeData.inflight = undefined;
      throw e as Error;
    });
    HomeData.inflight = p;
    return p;
  }

  private static async safe<T>(p: Promise<T>, fallback: T, errs: string[], what: string): Promise<T> {
    try {
      return await p;
    } catch (e) {
      const err = e as Error;
      errs.push(what + ': ' + (err?.message ?? String(e)));
      return fallback;
    }
  }

  private static async loadSource(p: MediaProvider, refetch: boolean): Promise<SourceHome> {
    const out = new SourceHome();
    out.sourceId = p.config.id;
    const errs = out.errors;
    if (p instanceof FlicxProvider) {
      // Site rails plus what this device saved for Flicx (continue watching, favourites).
      const fp = p as FlicxProvider;
      const fq = new QueryOptions();
      fq.favoritesOnly = true;
      fq.limit = ROW_LIMIT * 2;
      const railsP = HomeData.safe<HomeRow[]>(fp.home(refetch), [], errs, '首页');
      const resumeP = HomeData.safe<MediaItem[]>(fp.getResume(ROW_LIMIT), [], errs, '继续观看');
      const favP = HomeData.safe<PagedItems>(fp.getItems(fq), new PagedItems(), errs, '收藏');
      out.resume = await resumeP;
      out.favorites = (await favP).items;
      out.rails = await railsP;
      return out;
    }
    const empty: MediaItem[] = [];
    const resumeP = HomeData.safe<MediaItem[]>(p.getResume(ROW_LIMIT), empty, errs, '继续观看');
    const nextP = HomeData.safe<MediaItem[]>(p.getNextUp(ROW_LIMIT), empty, errs, '下一集');
    const viewsP = HomeData.safe<LibraryView[]>(p.getViews(), [], errs, '媒体库');
    const rq = new QueryOptions();
    rq.types = ['movie', 'series'] as MediaType[];
    rq.sortBy = 'Random';
    rq.limit = ROW_LIMIT;
    const emptyPage = new PagedItems();
    const randP = HomeData.safe<PagedItems>(p.getItems(rq), emptyPage, errs, '推荐');
    const fq = new QueryOptions();
    fq.types = ['movie', 'series', 'episode'] as MediaType[];
    fq.favoritesOnly = true;
    fq.sortBy = 'DateCreated';
    fq.sortDesc = true;
    fq.limit = ROW_LIMIT;
    const favP = HomeData.safe<PagedItems>(p.getItems(fq), emptyPage, errs, '收藏');

    out.views = await viewsP;
    const latestPs: Promise<MediaItem[]>[] = out.views.map((v: LibraryView) =>
      HomeData.safe<MediaItem[]>(p.getLatest(v.id, ROW_LIMIT), empty, errs, '最近添加'));
    out.resume = await resumeP;
    out.nextUp = await nextP;
    out.random = (await randP).items;
    out.favorites = (await favP).items;
    const latest = await Promise.all(latestPs);
    for (let i = 0; i < out.views.length; i++) {
      if (latest[i].length === 0) {
        continue;
      }
      const row = new HomeRow();
      row.key = 'latest:' + p.config.id + ':' + out.views[i].id;
      row.title = '最近添加 · ' + out.views[i].name;
      row.style = 'poster';
      row.items = latest[i];
      out.latest.push(row);
    }
    // a source that fails every call is reported once with the first error
    return out;
  }

  private static async doLoad(refetch: boolean): Promise<HomeResult> {
    await SourceStore.load();
    await Settings.load();
    const provs = HomeData.providers();
    const res = new HomeResult();
    res.sourceCount = provs.length;
    const settled: Settled<SourceHome>[] = await settleAll<SourceHome>(
      provs.map((p: MediaProvider) => HomeData.loadSource(p, refetch)));
    const homes: SourceHome[] = [];
    for (let i = 0; i < settled.length; i++) {
      const s = settled[i];
      const prov = provs[i];
      if (s.ok && s.value !== undefined) {
        homes.push(s.value);
        if (s.value.errors.length > 0) {
          const w = new SourceWarning();
          w.sourceId = prov.config.id;
          w.sourceName = prov.config.name;
          w.message = s.value.errors.length >= 5 ? '无法连接: ' + s.value.errors[0] : s.value.errors.join('；');
          res.warnings.push(w);
        }
      } else {
        const w = new SourceWarning();
        w.sourceId = prov.config.id;
        w.sourceName = prov.config.name;
        w.message = s.error;
        res.warnings.push(w);
      }
    }
    const resume = sortByLastPlayed(dedupe(HomeData.flat(homes.map((h: SourceHome) => h.resume))));
    const nextUp = dedupe(roundRobin<MediaItem>(homes.map((h: SourceHome) => h.nextUp), ROW_LIMIT * 2));
    // don't repeat in 下一集 what is already in 继续观看
    const resumeKeys = new Set<string>(resume.map((it: MediaItem) => it.sourceId + '|' + it.id));
    const nextFiltered = nextUp.filter((it: MediaItem) => !resumeKeys.has(it.sourceId + '|' + it.id));
    const random = dedupe(roundRobin<MediaItem>(homes.map((h: SourceHome) => h.random), ROW_LIMIT));
    const favs = dedupe(roundRobin<MediaItem>(homes.map((h: SourceHome) => h.favorites), ROW_LIMIT * 2));

    HomeData.addRow(res, 'resume', '继续观看', 'landscape', resume);
    HomeData.addRow(res, 'nextup', '下一集', 'landscape', nextFiltered);
    HomeData.addRow(res, 'favorites', '我的收藏', 'poster', favs);
    homes.forEach((h: SourceHome) => {
      h.latest.forEach((r: HomeRow) => { res.rows.push(r); });
      h.views.forEach((v: LibraryView) => { res.views.push(v); });
    });
    homes.forEach((h: SourceHome) => {
      h.rails.forEach((r: HomeRow) => { res.rows.push(r); });
    });
    HomeData.addRow(res, 'random', '推荐 · 随机', 'poster', random);

    const pool: MediaItem[] = [];
    random.forEach((it: MediaItem) => { pool.push(it); });
    homes.forEach((h: SourceHome) => {
      h.latest.forEach((r: HomeRow) => { r.items.forEach((it: MediaItem) => { pool.push(it); }); });
      // only the first rail (trending) so a personal library still dominates the banner
      if (h.rails.length > 0) {
        h.rails[0].items.forEach((it: MediaItem) => { pool.push(it); });
      }
    });
    res.featured = pickFeatured(pool, 8, Date.now());
    if (res.featured.length === 0) {
      // fall back to anything with a poster so the hero is never blank when there is content
      res.featured = shuffle(dedupe(pool).filter((it: MediaItem) =>
        it.images.poster.length > 0 && (it.type === 'movie' || it.type === 'series')), Date.now()).slice(0, 8);
    }
    res.loadedAt = Date.now();
    return res;
  }

  private static flat(lists: MediaItem[][]): MediaItem[] {
    const out: MediaItem[] = [];
    lists.forEach((l: MediaItem[]) => { l.forEach((it: MediaItem) => { out.push(it); }); });
    return out;
  }

  private static addRow(res: HomeResult, key: string, title: string, style: 'landscape' | 'poster',
    items: MediaItem[]): void {
    if (items.length === 0) {
      return;
    }
    const r = new HomeRow();
    r.key = key;
    r.title = title;
    r.style = style;
    r.items = items;
    res.rows.push(r);
  }
}
