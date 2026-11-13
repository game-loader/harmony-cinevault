import { MediaItem, ImageSet, UserState } from '../common/Models';
import { ProviderRegistry } from '../providers/ProviderRegistry';
import { MediaProvider } from '../common/MediaProvider';

export type ImageKind = 'poster' | 'backdrop' | 'logo' | 'thumb';

function rawImage(set: ImageSet, kind: ImageKind): string {
  switch (kind) {
    case 'backdrop': return set.backdrop;
    case 'logo': return set.logo;
    case 'thumb': return set.thumb;
    default: return set.poster;
  }
}

/** Absolute image url via the item's provider, falling back to the raw url on the item. */
export function imageFor(item: MediaItem, kind: ImageKind, maxWidth: number): string {
  const p: MediaProvider | undefined = ProviderRegistry.get(item.sourceId);
  let url = '';
  if (p !== undefined) {
    try {
      url = p.imageUrl(item, kind, maxWidth);
    } catch (e) {
      url = '';
    }
  }
  if (url.length === 0) {
    url = rawImage(item.images, kind);
  }
  return url;
}

/** Landscape image for 16:9 cards: thumb, then backdrop, then poster. */
export function landscapeFor(item: MediaItem, maxWidth: number): string {
  const t = imageFor(item, 'thumb', maxWidth);
  if (t.length > 0) {
    return t;
  }
  const b = imageFor(item, 'backdrop', maxWidth);
  return b.length > 0 ? b : imageFor(item, 'poster', maxWidth);
}

/** Copy of an item with new user state (new object so @State/@Prop observers fire). */
export function cloneWithState(src: MediaItem, played: boolean, favorite: boolean): MediaItem {
  const it = new MediaItem();
  it.sourceId = src.sourceId;
  it.id = src.id;
  it.type = src.type;
  it.title = src.title;
  it.originalTitle = src.originalTitle;
  it.overview = src.overview;
  it.year = src.year;
  it.premiereDate = src.premiereDate;
  it.rating = src.rating;
  it.officialRating = src.officialRating;
  it.runtimeMs = src.runtimeMs;
  it.genres = src.genres;
  it.studios = src.studios;
  it.tags = src.tags;
  it.people = src.people;
  it.images = src.images;
  it.seriesId = src.seriesId;
  it.seriesTitle = src.seriesTitle;
  it.seasonId = src.seasonId;
  it.seasonNumber = src.seasonNumber;
  it.episodeNumber = src.episodeNumber;
  it.childCount = src.childCount;
  it.tmdbId = src.tmdbId;
  it.imdbId = src.imdbId;
  it.container = src.container;
  it.width = src.width;
  it.height = src.height;
  const st = new UserState();
  st.played = played;
  st.favorite = favorite;
  st.positionMs = played ? 0 : src.state.positionMs;
  st.playCount = src.state.playCount;
  st.lastPlayed = src.state.lastPlayed;
  it.state = st;
  return it;
}

export class MediaActions {
  /** Toggle played; resolves to the updated item. Throws Error with a readable message. */
  static async setPlayed(item: MediaItem, played: boolean): Promise<MediaItem> {
    const p = ProviderRegistry.get(item.sourceId);
    if (p === undefined) {
      throw new Error('媒体源不可用');
    }
    await p.setPlayed(item, played);
    return cloneWithState(item, played, item.state.favorite);
  }

  static async setFavorite(item: MediaItem, favorite: boolean): Promise<MediaItem> {
    const p = ProviderRegistry.get(item.sourceId);
    if (p === undefined) {
      throw new Error('媒体源不可用');
    }
    await p.setFavorite(item, favorite);
    return cloneWithState(item, item.state.played, favorite);
  }
}
