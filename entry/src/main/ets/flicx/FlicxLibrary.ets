// On-device favourites, watched marks and resume positions for the Flicx source (it has no account).
// Pure state lives in FlicxLibraryState so it can be unit-tested; FlicxLibrary persists it in preferences.
import { MediaItem } from '../common/Models';

export class SavedTitle {
  id: string = '';
  type: string = 'movie';
  title: string = '';
  year: number = 0;
  rating: number = 0;
  poster: string = '';
  backdrop: string = '';
  thumb: string = '';
  runtimeMs: number = 0;
  seriesId: string = '';
  seriesTitle: string = '';
  seasonId: string = '';
  seasonNumber: number = -1;
  episodeNumber: number = -1;
  imdbId: string = '';
  slug: string = '';
  favorite: boolean = false;
  favoriteAt: number = 0;
  played: boolean = false;
  positionMs: number = 0;
  lastPlayed: number = 0;
}

export class LibraryDump {
  version: number = 1;
  items: SavedTitle[] = [];
}

const MAX_ITEMS: number = 2000;
/** Positions this close to the start or the end are not worth resuming. */
const RESUME_MIN_MS: number = 30000;
const RESUME_END_MS: number = 120000;

function copyMeta(dst: SavedTitle, it: MediaItem, slug: string): void {
  dst.id = it.id;
  dst.type = it.type;
  dst.title = it.title || dst.title;
  dst.year = it.year || dst.year;
  dst.rating = it.rating || dst.rating;
  dst.poster = it.images.poster || dst.poster;
  dst.backdrop = it.images.backdrop || dst.backdrop;
  dst.thumb = it.images.thumb || dst.thumb;
  dst.runtimeMs = it.runtimeMs || dst.runtimeMs;
  dst.seriesId = it.seriesId || dst.seriesId;
  dst.seriesTitle = it.seriesTitle || dst.seriesTitle;
  dst.seasonId = it.seasonId || dst.seasonId;
  dst.seasonNumber = it.seasonNumber >= 0 ? it.seasonNumber : dst.seasonNumber;
  dst.episodeNumber = it.episodeNumber >= 0 ? it.episodeNumber : dst.episodeNumber;
  dst.imdbId = it.imdbId || dst.imdbId;
  dst.slug = slug || dst.slug;
}

export function toItem(s: SavedTitle, sourceId: string): MediaItem {
  const it = new MediaItem();
  it.sourceId = sourceId;
  it.id = s.id;
  it.type = s.type === 'series' ? 'series' : (s.type === 'episode' ? 'episode' : 'movie');
  it.title = s.title;
  it.year = s.year;
  it.rating = s.rating;
  it.images.poster = s.poster;
  it.images.backdrop = s.backdrop;
  it.images.thumb = s.thumb;
  it.runtimeMs = s.runtimeMs;
  it.seriesId = s.seriesId;
  it.seriesTitle = s.seriesTitle;
  it.seasonId = s.seasonId;
  it.seasonNumber = s.seasonNumber;
  it.episodeNumber = s.episodeNumber;
  it.imdbId = s.imdbId;
  it.state.favorite = s.favorite;
  it.state.played = s.played;
  it.state.positionMs = s.positionMs;
  it.state.lastPlayed = s.lastPlayed;
  return it;
}

function str(v: string | undefined, d: string): string {
  return typeof v === 'string' ? v : d;
}

function num(v: number | undefined, d: number): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : d;
}

function bool(v: boolean | undefined): boolean {
  return v === true;
}

/** Stored JSON back to a SavedTitle, ignoring wrongly typed fields. */
function sanitize(r: SavedTitle): SavedTitle {
  const s = new SavedTitle();
  s.id = r.id;
  s.type = str(r.type, s.type);
  s.title = str(r.title, '');
  s.year = num(r.year, 0);
  s.rating = num(r.rating, 0);
  s.poster = str(r.poster, '');
  s.backdrop = str(r.backdrop, '');
  s.thumb = str(r.thumb, '');
  s.runtimeMs = num(r.runtimeMs, 0);
  s.seriesId = str(r.seriesId, '');
  s.seriesTitle = str(r.seriesTitle, '');
  s.seasonId = str(r.seasonId, '');
  s.seasonNumber = num(r.seasonNumber, -1);
  s.episodeNumber = num(r.episodeNumber, -1);
  s.imdbId = str(r.imdbId, '');
  s.slug = str(r.slug, '');
  s.favorite = bool(r.favorite);
  s.favoriteAt = num(r.favoriteAt, 0);
  s.played = bool(r.played);
  s.positionMs = num(r.positionMs, 0);
  s.lastPlayed = num(r.lastPlayed, 0);
  return s;
}

export class FlicxLibraryState {
  private map: Map<string, SavedTitle> = new Map<string, SavedTitle>();

  load(dump: LibraryDump | undefined): void {
    this.map.clear();
    if (dump === undefined || dump === null || !Array.isArray(dump.items)) {
      return;
    }
    for (const raw of dump.items) {
      if (raw && typeof raw.id === 'string' && raw.id.startsWith('flicx-')) {
        const s = sanitize(raw);
        this.map.set(s.id, s);
      }
    }
  }

  dump(): LibraryDump {
    const d = new LibraryDump();
    this.map.forEach((v: SavedTitle) => { d.items.push(v); });
    return d;
  }

  get(id: string): SavedTitle | undefined {
    return this.map.get(id);
  }

  /** Copy saved state onto an item fetched from the network. */
  apply(it: MediaItem): MediaItem {
    const s = this.map.get(it.id);
    if (s !== undefined) {
      it.state.favorite = s.favorite;
      it.state.played = s.played;
      it.state.positionMs = s.positionMs;
      it.state.lastPlayed = s.lastPlayed;
    }
    return it;
  }

  private entry(it: MediaItem, slug: string): SavedTitle {
    let s = this.map.get(it.id);
    if (s === undefined) {
      s = new SavedTitle();
      this.map.set(it.id, s);
    }
    copyMeta(s, it, slug);
    return s;
  }

  setFavorite(it: MediaItem, slug: string, v: boolean, now: number): void {
    const s = this.entry(it, slug);
    s.favorite = v;
    s.favoriteAt = v ? now : 0;
    this.prune();
  }

  /** Marking a series watched also marks its saved episodes. */
  setPlayed(it: MediaItem, slug: string, v: boolean, now: number): void {
    const s = this.entry(it, slug);
    s.played = v;
    s.positionMs = 0;
    if (v) {
      s.lastPlayed = now;
    }
    if (it.type === 'series') {
      this.map.forEach((e: SavedTitle) => {
        if (e.seriesId === it.id) {
          e.played = v;
          e.positionMs = 0;
        }
      });
    }
    this.prune();
  }

  /** Player progress; near the end counts as watched. */
  setProgress(it: MediaItem, slug: string, positionMs: number, durationMs: number, now: number): void {
    const s = this.entry(it, slug);
    const dur = durationMs > 0 ? durationMs : s.runtimeMs;
    if (dur > 0 && positionMs >= dur - RESUME_END_MS && positionMs >= dur * 0.9) {
      s.played = true;
      s.positionMs = 0;
    } else {
      s.positionMs = positionMs >= RESUME_MIN_MS ? positionMs : 0;
      if (s.positionMs > 0) {
        s.played = false;
      }
    }
    if (dur > 0) {
      s.runtimeMs = dur;
    }
    s.lastPlayed = now;
    this.prune();
  }

  favorites(): SavedTitle[] {
    const out: SavedTitle[] = [];
    this.map.forEach((v: SavedTitle) => {
      if (v.favorite) {
        out.push(v);
      }
    });
    return out.sort((a: SavedTitle, b: SavedTitle) => b.favoriteAt - a.favoriteAt);
  }

  /** In-progress titles/episodes, latest first; one entry per series (its most recent episode). */
  resume(): SavedTitle[] {
    const all: SavedTitle[] = [];
    this.map.forEach((v: SavedTitle) => {
      if (v.positionMs > 0 && !v.played && v.type !== 'series') {
        all.push(v);
      }
    });
    all.sort((a: SavedTitle, b: SavedTitle) => b.lastPlayed - a.lastPlayed);
    const seen = new Set<string>();
    return all.filter((v: SavedTitle) => {
      const k = v.seriesId || v.id;
      if (seen.has(k)) {
        return false;
      }
      seen.add(k);
      return true;
    });
  }

  /** Keep the store bounded: drop the oldest entries that are neither favourite nor in progress. */
  private prune(): void {
    if (this.map.size <= MAX_ITEMS) {
      return;
    }
    const idle: SavedTitle[] = [];
    this.map.forEach((v: SavedTitle) => {
      if (!v.favorite && v.positionMs <= 0) {
        idle.push(v);
      }
    });
    idle.sort((a: SavedTitle, b: SavedTitle) => a.lastPlayed - b.lastPlayed);
    for (let i = 0; i < idle.length && this.map.size > MAX_ITEMS; i++) {
      this.map.delete(idle[i].id);
    }
  }
}

/** Persisted singleton (preferences file 'flicx_library'). Writes are debounced. */
export class FlicxLibrary {
  static readonly state: FlicxLibraryState = new FlicxLibraryState();
  private static loaded: boolean = false;
  private static loading: Promise<void> | undefined = undefined;
  private static saveTimer: number = -1;
  private static listeners: Array<() => void> = [];
  /** Set by the platform layer: load/save the JSON text. Kept injectable so unit tests run without ArkData. */
  static readText: () => Promise<string> = async (): Promise<string> => '';
  static writeText: (text: string) => Promise<void> = async (t: string): Promise<void> => {};

  static async load(): Promise<void> {
    if (FlicxLibrary.loaded) {
      return;
    }
    if (FlicxLibrary.loading === undefined) {
      FlicxLibrary.loading = (async (): Promise<void> => {
        try {
          const text = await FlicxLibrary.readText();
          FlicxLibrary.state.load(text ? JSON.parse(text) as LibraryDump : undefined);
        } catch (e) {
          FlicxLibrary.state.load(undefined);
        }
        FlicxLibrary.loaded = true;
      })();
    }
    return FlicxLibrary.loading;
  }

  static onChange(cb: () => void): () => void {
    FlicxLibrary.listeners.push(cb);
    return () => {
      FlicxLibrary.listeners = FlicxLibrary.listeners.filter((x: () => void) => x !== cb);
    };
  }

  /** Call after every state change. */
  static changed(): void {
    clearTimeout(FlicxLibrary.saveTimer);
    FlicxLibrary.saveTimer = setTimeout(() => {
      FlicxLibrary.writeText(JSON.stringify(FlicxLibrary.state.dump())).catch(() => {});
    }, 400);
    FlicxLibrary.listeners.forEach((cb: () => void) => {
      try {
        cb();
      } catch (e) {
        // listener errors must not block saving
      }
    });
  }
}
