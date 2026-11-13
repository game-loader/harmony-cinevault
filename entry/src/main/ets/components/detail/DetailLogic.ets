// Pure helpers for the detail page (no @kit imports, unit-tested in tools/tests/detail.test.mjs).
import { MediaItem } from '../../common/Models';

function pad2(n: number): string {
  return n < 10 ? '0' + n.toString() : n.toString();
}

/** 5025000 -> "1:23:45", 65000 -> "01:05" */
export function formatClock(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h > 0) {
    return h.toString() + ':' + pad2(m) + ':' + pad2(s);
  }
  return pad2(m) + ':' + pad2(s);
}

/** Runtime as "2小时3分钟" / "45分钟"; '' when unknown. */
export function formatRuntime(ms: number): string {
  if (ms <= 0) {
    return '';
  }
  const mins = Math.round(ms / 60000);
  if (mins < 1) {
    return '1分钟';
  }
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  if (h > 0) {
    return m > 0 ? h.toString() + '小时' + m.toString() + '分钟' : h.toString() + '小时';
  }
  return m.toString() + '分钟';
}

/** 1536 -> "1.5 KB", bytes to human readable. */
export function formatSize(bytes: number): string {
  if (bytes <= 0) {
    return '0 B';
  }
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
  let v = bytes;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v = v / 1024;
    i++;
  }
  const txt = i === 0 ? Math.round(v).toString() : (v >= 100 ? v.toFixed(0) : v.toFixed(1));
  return txt + ' ' + units[i];
}

/** Rating with one decimal, '' when 0. */
export function formatRating(r: number): string {
  if (!(r > 0)) {
    return '';
  }
  return (Math.round(r * 10) / 10).toFixed(1);
}

/** "S01E02" style label; '' when numbers are unknown. */
export function episodeCode(season: number, episode: number): string {
  if (episode < 0) {
    return season >= 0 ? '第' + season.toString() + '季' : '';
  }
  const s = season >= 0 ? 'S' + pad2(season) : '';
  return s + 'E' + pad2(episode);
}

export function seasonLabel(s: MediaItem): string {
  if (s.title.length > 0) {
    return s.title;
  }
  if (s.seasonNumber === 0) {
    return '特别篇';
  }
  if (s.seasonNumber > 0) {
    return '第 ' + s.seasonNumber.toString() + ' 季';
  }
  return '季';
}

/** Badges derived from width/height/container. */
export function mediaBadges(item: MediaItem): string[] {
  const out: string[] = [];
  const w = item.width;
  const h = item.height;
  if (w >= 3800 || h >= 2100) {
    out.push('4K');
  } else if (w >= 2500 || h >= 1400) {
    out.push('2K');
  } else if (w >= 1900 || h >= 1000) {
    out.push('1080P');
  } else if (w >= 1200 || h >= 700) {
    out.push('720P');
  } else if (w > 0 || h > 0) {
    out.push('SD');
  }
  const hay = (item.container + ' ' + item.tags.join(' ')).toLowerCase();
  if (hay.indexOf('dolby vision') >= 0 || hay.indexOf('dovi') >= 0 || /\bdv\b/.test(hay)) {
    out.push('杜比视界');
  } else if (hay.indexOf('hdr') >= 0) {
    out.push('HDR');
  }
  if (hay.indexOf('hevc') >= 0 || hay.indexOf('h265') >= 0 || hay.indexOf('x265') >= 0 || hay.indexOf('h.265') >= 0) {
    out.push('HEVC');
  } else if (hay.indexOf('h264') >= 0 || hay.indexOf('avc') >= 0 || hay.indexOf('x264') >= 0 || hay.indexOf('h.264') >= 0) {
    out.push('H.264');
  } else if (hay.indexOf('av1') >= 0) {
    out.push('AV1');
  }
  if (hay.indexOf('atmos') >= 0) {
    out.push('Atmos');
  }
  const c = item.container.toLowerCase().split(',')[0].trim();
  if (c.length > 0 && c.length <= 5 && /^[a-z0-9]+$/.test(c)) {
    out.push(c.toUpperCase());
  }
  return out;
}

/** "2023 · 2小时 · PG-13" meta line parts (rating shown separately with a star). */
export function metaParts(item: MediaItem): string[] {
  const out: string[] = [];
  if (item.year > 0) {
    out.push(item.year.toString());
  } else if (item.premiereDate.length >= 4) {
    out.push(item.premiereDate.substring(0, 4));
  }
  if (item.type === 'series' && item.childCount > 0) {
    out.push(item.childCount.toString() + ' 季');
  }
  const rt = formatRuntime(item.runtimeMs);
  if (rt.length > 0) {
    out.push(rt);
  }
  if (item.officialRating.length > 0) {
    out.push(item.officialRating);
  }
  return out;
}

/** 0..1 watched fraction for progress bars. */
export function progressFraction(item: MediaItem): number {
  if (item.runtimeMs <= 0 || item.state.positionMs <= 0) {
    return 0;
  }
  return Math.min(1, item.state.positionMs / item.runtimeMs);
}

export function hasResume(item: MediaItem): boolean {
  return item.state.positionMs > 0 && !item.state.played;
}

/**
 * Pick the episode the main play button should start:
 * the first in-progress episode, else the first unplayed after the last played one, else the first.
 * Returns -1 for an empty list.
 */
export function pickNextEpisode(eps: MediaItem[]): number {
  if (eps.length === 0) {
    return -1;
  }
  for (let i = 0; i < eps.length; i++) {
    if (hasResume(eps[i])) {
      return i;
    }
  }
  let lastPlayed = -1;
  for (let i = 0; i < eps.length; i++) {
    if (eps[i].state.played) {
      lastPlayed = i;
    }
  }
  for (let i = lastPlayed + 1; i < eps.length; i++) {
    if (!eps[i].state.played) {
      return i;
    }
  }
  for (let i = 0; i < eps.length; i++) {
    if (!eps[i].state.played) {
      return i;
    }
  }
  return 0;
}

/** Ids after index (play queue for auto-next). */
export function queueAfter(eps: MediaItem[], index: number): string[] {
  const out: string[] = [];
  for (let i = index + 1; i < eps.length; i++) {
    out.push(eps[i].id);
  }
  return out;
}

/** Index of the season to show first: matching seasonId/seasonNumber, else first regular season (skip specials). */
export function pickSeasonIndex(seasons: MediaItem[], seasonId: string, seasonNumber: number): number {
  if (seasons.length === 0) {
    return -1;
  }
  for (let i = 0; i < seasons.length; i++) {
    if (seasonId.length > 0 && seasons[i].id === seasonId) {
      return i;
    }
  }
  if (seasonNumber >= 0) {
    for (let i = 0; i < seasons.length; i++) {
      if (seasons[i].seasonNumber === seasonNumber) {
        return i;
      }
    }
  }
  for (let i = 0; i < seasons.length; i++) {
    if (seasons[i].seasonNumber !== 0) {
      return i;
    }
  }
  return 0;
}

/** TMDB search type for an item. */
export function tmdbTypeFor(item: MediaItem): 'movie' | 'tv' {
  return (item.type === 'series' || item.type === 'season' || item.type === 'episode') ? 'tv' : 'movie';
}

/** Best guess search term for re-match: title, else filename stripped of extension and tags. */
export function guessQuery(item: MediaItem): string {
  const base = item.type === 'episode' && item.seriesTitle.length > 0 ? item.seriesTitle : item.title;
  let s = base.replace(/\.[a-zA-Z0-9]{2,4}$/, '');
  s = s.replace(/[._]/g, ' ');
  s = s.replace(/\b(19|20)\d{2}\b.*$/, '');
  s = s.replace(/\b(2160p|1080p|720p|4k|bluray|web-?dl|hdr|x26[45]|h\.?26[45]).*$/i, '');
  s = s.replace(/[\[【(（].*?[\]】)）]/g, ' ');
  s = s.replace(/\s+/g, ' ').trim();
  return s.length > 0 ? s : base;
}

/** Shallow copy with a new UserState so @State arrays re-render after an optimistic change. */
export function withPlayed(src: MediaItem, played: boolean): MediaItem {
  const n = new MediaItem();
  n.sourceId = src.sourceId; n.id = src.id; n.type = src.type; n.title = src.title;
  n.originalTitle = src.originalTitle; n.overview = src.overview; n.year = src.year;
  n.premiereDate = src.premiereDate; n.rating = src.rating; n.officialRating = src.officialRating;
  n.runtimeMs = src.runtimeMs; n.genres = src.genres; n.studios = src.studios; n.tags = src.tags;
  n.people = src.people; n.images = src.images; n.seriesId = src.seriesId; n.seriesTitle = src.seriesTitle;
  n.seasonId = src.seasonId; n.seasonNumber = src.seasonNumber; n.episodeNumber = src.episodeNumber;
  n.childCount = src.childCount; n.tmdbId = src.tmdbId; n.imdbId = src.imdbId; n.container = src.container;
  n.width = src.width; n.height = src.height;
  n.state.played = played;
  n.state.favorite = src.state.favorite;
  n.state.positionMs = played ? 0 : src.state.positionMs;
  n.state.playCount = src.state.playCount;
  n.state.lastPlayed = src.state.lastPlayed;
  return n;
}
