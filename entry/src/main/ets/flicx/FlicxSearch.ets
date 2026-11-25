import { MediaItem } from '../common/Models';
import { Settings } from '../common/Settings';
import { TmdbClient } from '../scraper/TmdbClient';
import { TmdbSearchResult, TmdbSeasonSummary } from '../scraper/TmdbTypes';
import { FlicxApi } from './FlicxApi';
import { FlicxMapper, FLICX_ID } from './FlicxMapper';
import { FlicxId, FlicxSeasonRow, FlicxTitleItem } from './FlicxModels';

const CANDIDATE_LIMIT: number = 12;
const CONCURRENCY: number = 3;
const CACHE_LIMIT: number = 512;

function remember<T>(map: Map<string, T>, key: string, value: T): void {
  if (map.size >= CACHE_LIMIT && !map.has(key)) {
    const first = map.keys().next();
    if (!first.done) {
      map.delete(first.value);
    }
  }
  map.set(key, value);
}

class Availability {
  expires: number = Date.now() + 180000;
  result: Promise<boolean>;
  constructor(result: Promise<boolean>) {
    this.result = result;
  }
}

/** Search keeps only title metadata and short-lived availability flags. Play always resolves fresh URLs. */
export class FlicxSearch {
  private siteTitles: Map<string, FlicxTitleItem> = new Map<string, FlicxTitleItem>();
  private tmdbIds: Map<string, string> = new Map<string, string>();
  private availability: Map<string, Availability> = new Map<string, Availability>();
  private revision: number = 0;

  /** Titles shown outside search (home rails) so details work without a TMDB key. */
  rememberSite(items: MediaItem[]): void {
    for (const item of items) {
      if (item instanceof FlicxTitleItem) {
        remember(this.siteTitles, item.id, item);
      }
    }
  }

  siteTitle(rootId: string): FlicxTitleItem | undefined {
    return this.siteTitles.get(rootId);
  }

  async tmdbId(ref: FlicxId): Promise<string> {
    const key = FlicxMapper.mediaId(ref.kind, ref.imdbId);
    const cached = this.tmdbIds.get(key);
    if (cached) {
      return cached;
    }
    const row = await TmdbClient.findByImdbId(ref.imdbId, ref.kind);
    if (!row || !row.id) {
      throw new Error('TMDB 未收录这部影片');
    }
    const value = String(row.id);
    remember(this.tmdbIds, key, value);
    return value;
  }

  private async available(imdbId: string, season: number, episode: number): Promise<boolean> {
    const key = imdbId + '/' + season + '/' + episode;
    const old = this.availability.get(key);
    if (old && old.expires > Date.now()) {
      return old.result;
    }
    const entry = new Availability(FlicxApi.hasPlayableSource(imdbId, season, episode));
    remember(this.availability, key, entry);
    try {
      return await entry.result;
    } catch (e) {
      if (this.availability.get(key) === entry) {
        this.availability.delete(key);
      }
      throw e as Error;
    }
  }

  private async candidates(term: string): Promise<MediaItem[]> {
    if (!FlicxMapper.isCjkQuery(term)) {
      return FlicxApi.search(term);
    }
    if (!Settings.get().tmdbApiKey.trim()) {
      throw new Error('中文片名搜索需要 TMDB API Key，请在设置中填写，或输入英文片名');
    }
    const lists = await Promise.all([TmdbClient.searchMovie(term, 0), TmdbClient.searchTv(term, 0)]);
    const out: MediaItem[] = [];
    // Leave room for TV even when common film titles fill the whole first page.
    for (let i = 0; i < Math.max(lists[0].length, lists[1].length) && out.length < CANDIDATE_LIMIT; i++) {
      for (let k = 0; k < lists.length; k++) {
        const row: TmdbSearchResult = lists[k][i];
        if (row && row.id && row.id > 0) {
          out.push(TmdbClient.mapSearchResult(row, k === 0 ? 'movie' : 'tv'));
        }
      }
    }
    return out;
  }

  private async hasSeries(item: MediaItem, rev: number): Promise<boolean> {
    if (await this.available(item.imdbId, 1, 1)) {
      return true;
    }
    if (rev !== this.revision) {
      return false;
    }
    // A series can have only specials, or only later episodes. Probe at most two other actual episodes.
    let seasons: TmdbSeasonSummary[] = [];
    if (item instanceof FlicxTitleItem && item.slug) {
      const list = await FlicxApi.seasons(item.slug);
      seasons = list.map((s: FlicxSeasonRow): TmdbSeasonSummary => {
        return { season_number: s.n, episode_count: s.last ?? s.count };
      });
    } else if (item.tmdbId) {
      seasons = (await TmdbClient.tv(item.tmdbId)).seasons ?? [];
    }
    let attempts = 0;
    for (let i = seasons.length - 1; i >= 0 && attempts < 2 && rev === this.revision; i--) {
      const s = seasons[i];
      const season = s.season_number ?? -1;
      if (season < 0 || (s.episode_count ?? 0) < 1) {
        continue;
      }
      // S1E1 was already checked above.
      const ep = season === 1 ? s.episode_count ?? 1 : 1;
      if (season === 1 && ep === 1) {
        continue;
      }
      attempts++;
      if (await this.available(item.imdbId, season, ep)) {
        return true;
      }
    }
    return false;
  }

  private async resolve(item: MediaItem, rev: number): Promise<MediaItem | undefined> {
    const kind = item.type === 'series' ? 'tv' : 'movie';
    if (!item.imdbId) {
      item.imdbId = await TmdbClient.imdbIdFor(kind, item.tmdbId);
    }
    if (rev !== this.revision || !FlicxMapper.isImdbId(item.imdbId)) {
      return undefined;
    }
    const playable = kind === 'tv' ? await this.hasSeries(item, rev) : await this.available(item.imdbId, -1, -1);
    if (!playable || rev !== this.revision) {
      return undefined;
    }
    item.id = FlicxMapper.mediaId(kind, item.imdbId);
    item.sourceId = FLICX_ID;
    if (item.tmdbId) {
      remember(this.tmdbIds, item.id, item.tmdbId);
    }
    if (item instanceof FlicxTitleItem) {
      remember(this.siteTitles, item.id, item);
    }
    return item;
  }

  async search(query: string, limit: number): Promise<MediaItem[]> {
    const rev = ++this.revision;
    const term = query.trim();
    if (!term || limit <= 0) {
      return [];
    }
    const list = (await this.candidates(term)).slice(0, CANDIDATE_LIMIT);
    const hits: Array<MediaItem | undefined> = [];
    let next = 0;
    let error: Error | undefined = undefined;
    const worker = async (): Promise<void> => {
      while (rev === this.revision && next < list.length) {
        const i = next++;
        try {
          hits[i] = await this.resolve(list[i], rev);
        } catch (e) {
          error = e as Error;
        }
      }
    };
    const workers: Promise<void>[] = [];
    for (let i = 0; i < Math.min(list.length, CONCURRENCY); i++) {
      workers.push(worker());
    }
    await Promise.all(workers);
    const out: MediaItem[] = [];
    const seen = new Set<string>();
    for (const hit of hits) {
      if (hit && !seen.has(hit.id) && out.length < limit) {
        seen.add(hit.id);
        out.push(hit);
      }
    }
    if (rev !== this.revision) {
      return [];
    }
    if (out.length === 0 && error !== undefined) {
      throw error as Error;
    }
    return out;
  }
}
