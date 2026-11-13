import { MediaItem, QueryOptions, PagedItems, UserState } from '../common/Models';

/** A video file in a Quark source, linked to a scraped MediaItem. */
export class LocalFile {
  sourceId: string = '';
  fid: string = '';
  parentFid: string = '';
  path: string = '';          // display path relative to library root
  name: string = '';
  size: number = 0;
  updatedAt: number = 0;
  itemId: string = '';        // MediaItem.id (movie or episode) it was matched to, '' if unmatched
}

/**
 * OWNER: scraper agent. Local catalogue for Quark sources (relationalStore 'library.db').
 * MediaItem rows are stored with sourceId; ids are stable strings, e.g. 'tmdb-movie-603',
 * 'tmdb-tv-1399', 'tmdb-tv-1399-s1', 'tmdb-tv-1399-s1e2', or 'file-<fid>' for unmatched videos.
 */
export class LibraryDb {
  static async open(): Promise<void> {}
  static async upsertItem(item: MediaItem): Promise<void> {}
  static async getItem(sourceId: string, id: string): Promise<MediaItem | undefined> { return undefined; }
  static async query(sourceId: string, q: QueryOptions): Promise<PagedItems> { return new PagedItems(); }
  static async children(sourceId: string, parentId: string): Promise<MediaItem[]> { return []; }
  static async search(sourceId: string, term: string, limit: number): Promise<MediaItem[]> { return []; }
  static async genres(sourceId: string): Promise<string[]> { return []; }
  static async upsertFile(f: LocalFile): Promise<void> {}
  static async filesForItem(sourceId: string, itemId: string): Promise<LocalFile[]> { return []; }
  static async allFiles(sourceId: string): Promise<LocalFile[]> { return []; }
  static async removeFile(sourceId: string, fid: string): Promise<void> {}
  static async setState(sourceId: string, itemId: string, s: UserState): Promise<void> {}
  static async resume(sourceId: string, limit: number): Promise<MediaItem[]> { return []; }
  static async nextUp(sourceId: string, limit: number): Promise<MediaItem[]> { return []; }
  static async latest(sourceId: string, limit: number): Promise<MediaItem[]> { return []; }
  static async clearSource(sourceId: string): Promise<void> {}
}
