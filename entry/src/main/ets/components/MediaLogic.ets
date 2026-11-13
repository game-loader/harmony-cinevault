// Pure, UI-free helpers shared by the home screen, library grid and search.
// Only type imports from Models (elided at runtime) so this module is unit-testable under node.
import { MediaItem, MediaType } from '../common/Models';

export class Settled<T> {
  ok: boolean = false;
  value?: T;
  error: string = '';
}

export function errMessage(e: Object | undefined | null): string {
  if (e === undefined || e === null) {
    return '未知错误';
  }
  if (e instanceof Error) {
    return e.message && e.message.length > 0 ? e.message : '未知错误';
  }
  return String(e);
}

/** Like Promise.allSettled: never rejects, keeps input order. */
export function settleAll<T>(ps: Promise<T>[]): Promise<Settled<T>[]> {
  return new Promise<Settled<T>[]>((resolve: (v: Settled<T>[]) => void) => {
    const out: Settled<T>[] = [];
    for (let i = 0; i < ps.length; i++) {
      out.push(new Settled<T>());
    }
    let left = ps.length;
    if (left === 0) {
      resolve(out);
      return;
    }
    const done = () => {
      left--;
      if (left === 0) {
        resolve(out);
      }
    };
    for (let i = 0; i < ps.length; i++) {
      const slot = out[i];
      ps[i].then((v: T) => {
        slot.ok = true;
        slot.value = v;
        done();
      }, (e: Object) => {
        slot.ok = false;
        slot.error = errMessage(e);
        done();
      });
    }
  });
}

export function itemKey(it: MediaItem): string {
  return it.sourceId + '|' + it.id;
}

export function dedupe(items: MediaItem[]): MediaItem[] {
  const seen = new Set<string>();
  const out: MediaItem[] = [];
  for (const it of items) {
    const k = itemKey(it);
    if (!seen.has(k)) {
      seen.add(k);
      out.push(it);
    }
  }
  return out;
}

/** Most recently played first (stable). */
export function sortByLastPlayed(items: MediaItem[]): MediaItem[] {
  const idx = new Map<MediaItem, number>();
  items.forEach((it: MediaItem, i: number) => { idx.set(it, i); });
  return items.slice().sort((a: MediaItem, b: MediaItem) => {
    const d = (b.state.lastPlayed ?? 0) - (a.state.lastPlayed ?? 0);
    return d !== 0 ? d : (idx.get(a) ?? 0) - (idx.get(b) ?? 0);
  });
}

/** Interleave several lists: a0, b0, c0, a1, b1, ... up to max items. */
export function roundRobin<T>(lists: T[][], max: number): T[] {
  const out: T[] = [];
  let i = 0;
  let any = true;
  while (any && out.length < max) {
    any = false;
    for (const l of lists) {
      if (i < l.length) {
        any = true;
        out.push(l[i]);
        if (out.length >= max) {
          break;
        }
      }
    }
    i++;
  }
  return out;
}

/** Deterministic shuffle (mulberry32) so tests are stable; pass Date.now() in the app. */
export function shuffle<T>(arr: T[], seed: number): T[] {
  const a = arr.slice();
  let s = seed >>> 0;
  const rnd = (): number => {
    s = (s + 0x6D2B79F5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    const tmp = a[i];
    a[i] = a[j];
    a[j] = tmp;
  }
  return a;
}
/** 0..1 watched fraction from resume position, 0 when unknown. */
export function progressOf(it: MediaItem): number {
  if (it.runtimeMs <= 0 || it.state.positionMs <= 0) {
    return 0;
  }
  const f = it.state.positionMs / it.runtimeMs;
  return f < 0 ? 0 : (f > 1 ? 1 : f);
}

export function ratingText(r: number): string {
  if (!(r > 0)) {
    return '';
  }
  return (Math.round(r * 10) / 10).toFixed(1);
}

export function epCode(season: number, episode: number): string {
  if (season < 0 && episode < 0) {
    return '';
  }
  const s = season >= 0 ? 'S' + (season < 10 ? '0' : '') + season.toString() : '';
  const e = episode >= 0 ? 'E' + (episode < 10 ? '0' : '') + episode.toString() : '';
  return s + e;
}

/** Main line under a card. Episodes show the series name. */
export function cardTitle(it: MediaItem): string {
  if (it.type === 'episode' && it.seriesTitle.length > 0) {
    return it.seriesTitle;
  }
  return it.title;
}

/** Secondary line under a card: year for movies/series, SxxEyy · title for episodes. */
export function cardSubtitle(it: MediaItem): string {
  if (it.type === 'episode') {
    const code = epCode(it.seasonNumber, it.episodeNumber);
    if (it.seriesTitle.length > 0) {
      return code.length > 0 ? code + ' · ' + it.title : it.title;
    }
    return code;
  }
  if (it.type === 'series' && it.childCount > 0 && it.year > 0) {
    return it.year.toString() + ' · ' + it.childCount.toString() + ' 季';
  }
  return it.year > 0 ? it.year.toString() : '';
}

export function remainingText(it: MediaItem): string {
  if (it.runtimeMs <= 0) {
    return '';
  }
  const left = Math.max(0, it.runtimeMs - it.state.positionMs);
  const min = Math.round(left / 60000);
  if (min <= 0) {
    return '即将看完';
  }
  if (min >= 60) {
    const h = Math.floor(min / 60);
    const m = min % 60;
    return '剩余 ' + h.toString() + ' 小时' + (m > 0 ? ' ' + m.toString() + ' 分钟' : '');
  }
  return '剩余 ' + min.toString() + ' 分钟';
}

export function typeLabel(t: MediaType): string {
  switch (t) {
    case 'movie': return '电影';
    case 'series': return '剧集';
    case 'season': return '季';
    case 'episode': return '单集';
    case 'folder': return '文件夹';
    case 'collection': return '合集';
    default: return '视频';
  }
}

/** Hero candidates: prefer items with a backdrop, then by rating, unique, up to max. */
export function pickFeatured(pool: MediaItem[], max: number, seed: number): MediaItem[] {
  const usable = dedupe(pool).filter((it: MediaItem) =>
    (it.type === 'movie' || it.type === 'series') && it.images.backdrop.length > 0);
  const top = usable.slice().sort((a: MediaItem, b: MediaItem) => b.rating - a.rating)
    .slice(0, Math.max(max * 2, max));
  return shuffle(top, seed).slice(0, max);
}

/** Search results grouped for display. */
export class SearchGroup {
  key: string = '';
  title: string = '';
  items: MediaItem[] = [];
}

export function groupSearch(items: MediaItem[]): SearchGroup[] {
  const movies = new SearchGroup();
  movies.key = 'movie';
  movies.title = '电影';
  const series = new SearchGroup();
  series.key = 'series';
  series.title = '剧集';
  const eps = new SearchGroup();
  eps.key = 'episode';
  eps.title = '剧集单集';
  const other = new SearchGroup();
  other.key = 'other';
  other.title = '其他';
  for (const it of dedupe(items)) {
    if (it.type === 'movie') {
      movies.items.push(it);
    } else if (it.type === 'series') {
      series.items.push(it);
    } else if (it.type === 'episode') {
      eps.items.push(it);
    } else if (it.type !== 'season') {
      other.items.push(it);
    }
  }
  return [movies, series, eps, other].filter((g: SearchGroup) => g.items.length > 0);
}

/** Move term to the front of the recent list, case-insensitive dedupe, capped. */
export function pushRecent(list: string[], term: string, cap: number): string[] {
  const t = term.trim();
  if (t.length === 0) {
    return list.slice(0, cap);
  }
  const lower = t.toLowerCase();
  const out: string[] = [t];
  for (const s of list) {
    if (s.toLowerCase() !== lower && out.length < cap) {
      out.push(s);
    }
  }
  return out;
}

export function parseRecent(json: string): string[] {
  if (json.length === 0) {
    return [];
  }
  try {
    const v = JSON.parse(json) as Object;
    if (Array.isArray(v)) {
      const arr = v as Object[];
      return arr.filter((x: Object) => typeof x === 'string').map((x: Object) => x as string);
    }
  } catch (e) {
    return [];
  }
  return [];
}

/** Adaptive poster grid columns for a container width in vp. */
export function gridColumns(widthVp: number, minCardVp: number, gapVp: number): number {
  if (widthVp <= 0) {
    return 3;
  }
  const n = Math.floor((widthVp + gapVp) / (minCardVp + gapVp));
  return Math.max(2, Math.min(n, 12));
}

/** Year filter options: decades for older, single years for recent. Newest first. */
export function yearOptions(nowYear: number, back: number): number[] {
  const out: number[] = [];
  for (let y = nowYear; y > nowYear - back; y--) {
    out.push(y);
  }
  return out;
}

export class SortOption {
  key: string = '';
  label: string = '';
  constructor(key: string, label: string) {
    this.key = key;
    this.label = label;
  }
}

export const SORT_OPTIONS: SortOption[] = [
  new SortOption('SortName', '名称'),
  new SortOption('DateCreated', '添加时间'),
  new SortOption('PremiereDate', '上映日期'),
  new SortOption('CommunityRating', '评分'),
  new SortOption('Random', '随机')
];

export function sortLabel(key: string): string {
  for (const o of SORT_OPTIONS) {
    if (o.key === key) {
      return o.label;
    }
  }
  return '名称';
}

/** Default direction when the user picks a sort key: names ascending, everything else descending. */
export function defaultSortDesc(key: string): boolean {
  return key !== 'SortName';
}

/** Local filter/sort over a merged multi-source list (used for aggregated libraries). */
export function compareItems(a: MediaItem, b: MediaItem, sortBy: string): number {
  switch (sortBy) {
    case 'DateCreated':
    case 'PremiereDate': {
      const da = a.premiereDate.length > 0 ? a.premiereDate : a.year.toString();
      const db = b.premiereDate.length > 0 ? b.premiereDate : b.year.toString();
      return da < db ? -1 : (da > db ? 1 : 0);
    }
    case 'CommunityRating':
      return a.rating - b.rating;
    default:
      return a.title.localeCompare(b.title);
  }
}

/** Merge pages from several sources into one sorted list. Random keeps round-robin order. */
export function mergeSorted(lists: MediaItem[][], sortBy: string, desc: boolean): MediaItem[] {
  if (sortBy === 'Random') {
    return dedupe(roundRobin(lists, 1 << 30));
  }
  const all: MediaItem[] = [];
  lists.forEach((l: MediaItem[]) => { l.forEach((it: MediaItem) => { all.push(it); }); });
  const sorted = dedupe(all).sort((a: MediaItem, b: MediaItem) => compareItems(a, b, sortBy));
  return desc ? sorted.reverse() : sorted;
}
