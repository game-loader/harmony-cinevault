import {
  SourceConfig, MediaItem, LibraryView, QueryOptions, PagedItems, PlaybackInfo, PlaybackRequest
} from './Models';

/**
 * One implementation per source kind:
 *  - providers/EmbyProvider.ets      (kind 'emby' and 'jellyfin', which share the API with small differences)
 *  - quark/QuarkProvider.ets         (Quark drive + local scraped library in library/LibraryDb.ets)
 * UI code only talks to this interface via providers/ProviderRegistry.ets.
 */
export interface MediaProvider {
  readonly config: SourceConfig;

  /** Validate credentials / refresh token. Throws Error with a user-readable message on failure. */
  connect(): Promise<void>;

  getViews(): Promise<LibraryView[]>;
  getResume(limit: number): Promise<MediaItem[]>;
  getNextUp(limit: number): Promise<MediaItem[]>;
  /** Latest additions; parentId '' = all libraries */
  getLatest(parentId: string, limit: number): Promise<MediaItem[]>;
  getItems(q: QueryOptions): Promise<PagedItems>;
  getItem(id: string): Promise<MediaItem>;
  getSeasons(seriesId: string): Promise<MediaItem[]>;
  getEpisodes(seriesId: string, seasonId: string): Promise<MediaItem[]>;
  getSimilar(id: string, limit: number): Promise<MediaItem[]>;
  search(term: string, limit: number): Promise<MediaItem[]>;
  getGenres(parentId: string): Promise<string[]>;

  getPlayback(item: MediaItem, req: PlaybackRequest): Promise<PlaybackInfo>;
  reportStart(item: MediaItem, info: PlaybackInfo, positionMs: number): Promise<void>;
  reportProgress(item: MediaItem, info: PlaybackInfo, positionMs: number, paused: boolean): Promise<void>;
  reportStopped(item: MediaItem, info: PlaybackInfo, positionMs: number): Promise<void>;

  setPlayed(item: MediaItem, played: boolean): Promise<void>;
  setFavorite(item: MediaItem, favorite: boolean): Promise<void>;

  /** Absolute image URL for the given item image kind, sized to maxWidth px. '' if none. */
  imageUrl(item: MediaItem, kind: 'poster' | 'backdrop' | 'logo' | 'thumb', maxWidth: number): string;
  /** Headers needed when loading images from this source (usually empty). */
  imageHeaders(): Record<string, string>;
}
