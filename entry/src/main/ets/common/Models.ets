// Shared data model. Every source (Emby, Jellyfin, Quark+scraper) maps into these types.
// ArkTS rules: classes with explicit field types, no `any`, no untyped object literals.

export type SourceKind = 'emby' | 'jellyfin' | 'quark';

export type MediaType = 'movie' | 'series' | 'season' | 'episode' | 'folder' | 'collection' | 'video';

/** A configured source the user added (one per server / one per Quark account). */
export class SourceConfig {
  id: string = '';            // stable local id (uuid-ish)
  kind: SourceKind = 'emby';
  name: string = '';          // display name
  baseUrl: string = '';       // Emby/Jellyfin server URL, '' for quark
  username: string = '';
  userId: string = '';        // server user id after login
  token: string = '';         // Emby/Jellyfin access token
  deviceId: string = '';
  cookie: string = '';        // Quark cookie
  rootFid: string = '0';      // Quark: folder that holds the media library
  enabled: boolean = true;
  /** Quark auth mode: 'tv' = TV-client QR login with refresh token (default for new logins), 'cookie' = web cookie */
  quarkAuth: string = 'cookie';
  quarkRefreshToken: string = '';
  quarkDeviceId: string = '';   // TV API device_id (md5 hex), generated once per source
}

export class ImageSet {
  poster: string = '';    // portrait 2:3
  backdrop: string = '';  // landscape 16:9 fanart
  logo: string = '';      // transparent title logo
  thumb: string = '';     // episode still / landscape thumb
}

export class Person {
  name: string = '';
  role: string = '';      // character or job
  image: string = '';
}

export class UserState {
  played: boolean = false;
  favorite: boolean = false;
  positionMs: number = 0;      // resume position
  playCount: number = 0;
  lastPlayed: number = 0;      // epoch ms
}

export class MediaItem {
  sourceId: string = '';
  id: string = '';              // id inside the source (Emby item id / Quark fid / local scraped id)
  type: MediaType = 'movie';
  title: string = '';
  originalTitle: string = '';
  overview: string = '';
  year: number = 0;
  premiereDate: string = '';
  rating: number = 0;           // 0..10
  officialRating: string = '';
  runtimeMs: number = 0;
  genres: string[] = [];
  studios: string[] = [];
  tags: string[] = [];
  people: Person[] = [];
  images: ImageSet = new ImageSet();
  seriesId: string = '';
  seriesTitle: string = '';
  seasonId: string = '';
  seasonNumber: number = -1;
  episodeNumber: number = -1;
  childCount: number = 0;
  tmdbId: string = '';
  imdbId: string = '';
  container: string = '';
  width: number = 0;
  height: number = 0;
  state: UserState = new UserState();
}

/** A top-level library / view on a source (Emby view, or a Quark-backed scraped library). */
export class LibraryView {
  sourceId: string = '';
  id: string = '';
  name: string = '';
  collectionType: string = '';   // 'movies' | 'tvshows' | 'mixed' | ...
  image: string = '';
}

export class QueryOptions {
  parentId: string = '';
  types: MediaType[] = [];
  recursive: boolean = true;
  sortBy: string = 'SortName';    // SortName | DateCreated | PremiereDate | CommunityRating | DatePlayed | Random
  sortDesc: boolean = false;
  startIndex: number = 0;
  limit: number = 60;
  searchTerm: string = '';
  genres: string[] = [];
  years: number[] = [];
  favoritesOnly: boolean = false;
  unplayedOnly: boolean = false;
}

export class PagedItems {
  items: MediaItem[] = [];
  total: number = 0;
}

export class SubtitleTrack {
  index: number = 0;
  language: string = '';
  title: string = '';
  url: string = '';         // external subtitle url, '' when embedded
  isExternal: boolean = false;
  isDefault: boolean = false;
  codec: string = '';
}

export class AudioTrack {
  index: number = 0;
  language: string = '';
  title: string = '';
  codec: string = '';
  channels: number = 0;
  isDefault: boolean = false;
}

export class PlaybackInfo {
  url: string = '';
  headers: Record<string, string> = {};
  isTranscode: boolean = false;
  container: string = '';
  mediaSourceId: string = '';
  playSessionId: string = '';
  durationMs: number = 0;
  audioTracks: AudioTrack[] = [];
  subtitles: SubtitleTrack[] = [];
  /** Alternative qualities (e.g. Quark transcodes); label -> url */
  qualities: QualityOption[] = [];
  /** How the server delivers it: 'direct' (original file), 'remux' (container changed, streams copied), 'transcode' */
  deliveryMode: string = 'direct';
  /** Source stream codecs as reported by the server ('' if unknown), e.g. 'hevc', 'eac3' */
  videoCodec: string = '';
  audioCodec: string = '';
  videoWidth: number = 0;
  videoHeight: number = 0;
  videoRange: string = '';       // 'SDR' | 'HDR10' | 'HLG' | 'DOVI' | 'HDR Vivid' | ''
  bitrate: number = 0;           // bps, 0 unknown
  /** Why the server transcoded (Emby TranscodeReasons), empty when direct */
  transcodeReasons: string[] = [];
}

export class QualityOption {
  label: string = '';
  url: string = '';
  headers: Record<string, string> = {};
}

export class PlaybackRequest {
  maxBitrate: number = 0;          // 0 = original / direct play
  audioIndex: number = -1;
  subtitleIndex: number = -1;
  startMs: number = 0;
}

/** Row on the home screen */
export class HomeRow {
  key: string = '';
  title: string = '';
  style: 'landscape' | 'poster' = 'poster';
  items: MediaItem[] = [];
}
