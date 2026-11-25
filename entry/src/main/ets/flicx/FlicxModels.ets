import { MediaItem } from '../common/Models';

// Only fields used from the Flicx JSON responses.
export interface FlicxTitle {
  id?: string;
  slug?: string;
  kind?: string;
  title?: string;
  year?: number;
  runtime?: number;
  rating?: number;
  genres?: string[];
  still?: string;
  poster?: string;
}

export interface FlicxSearchResponse {
  results?: FlicxTitle[];
}

export interface FlicxSource {
  kind?: string;
  name?: string;
  src?: string;
  group?: string;
  quality?: string;
  has?: boolean;
}

export interface FlicxSourceResponse {
  imdb?: string;
  season?: number | null;
  episode?: number | null;
  sources?: FlicxSource[];
}

export interface FlicxTrack {
  src?: string;
  language?: string;
  format?: string;
  label?: string;
  sdh?: boolean;
}

export interface FlicxSubtitleResponse {
  tracks?: FlicxTrack[];
}

export type FlicxKind = 'movie' | 'tv';

export class FlicxTitleItem extends MediaItem {
  slug: string = '';
}

export interface FlicxSeasonRow {
  n: number;
  count?: number;
  last?: number;
}

export interface FlicxLibraryShow {
  seasons?: FlicxSeasonRow[];
}

export interface FlicxLibraryResponse {
  shows?: Record<string, FlicxLibraryShow>;
}

export interface FlicxStill {
  src?: string;
}

export interface FlicxEpisode {
  n: number;
  title?: string;
  overview?: string;
  still?: FlicxStill;
  runtime?: number;
  aired?: string;
  rating?: number;
  plays?: boolean;
}

export interface FlicxEpisodesResponse {
  episodes?: FlicxEpisode[];
}

export class FlicxId {
  kind: FlicxKind = 'movie';
  imdbId: string = '';
  season: number = -1;
  episode: number = -1;
}
