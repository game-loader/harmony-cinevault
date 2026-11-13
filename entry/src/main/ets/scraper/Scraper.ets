import { MediaItem } from '../common/Models';
import { LocalFile } from '../library/LibraryDb';

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

/** OWNER: scraper agent. Filename parsing + TMDB match + LibraryDb write. */
export class Scraper {
  /** Full or incremental scan of a source; already-matched unchanged files are skipped unless force. */
  static async scan(sourceId: string, rootFid: string, lister: FileLister, force: boolean,
    onProgress: (p: ScanProgress) => void): Promise<ScanProgress> { return new ScanProgress(); }
  /** Manual re-match: user picks a TMDB result for a file / item. */
  static async rematch(sourceId: string, itemId: string, tmdbType: 'movie' | 'tv', tmdbId: string): Promise<MediaItem | undefined> { return undefined; }
  static async searchTmdb(query: string, year: number, type: 'movie' | 'tv'): Promise<MediaItem[]> { return []; }
}
