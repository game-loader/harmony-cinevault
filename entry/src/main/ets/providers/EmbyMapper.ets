// Pure Emby/Jellyfin JSON -> CineVault model mapping. No @kit imports: unit-tested under node (tools/tests/emby.test.mjs).
import {
  MediaItem, MediaType, LibraryView, Person, UserState, QueryOptions, PlaybackInfo, PlaybackRequest,
  AudioTrack, SubtitleTrack, SourceKind
} from '../common/Models';
import {
  EmbyItem, EmbyUserData, EmbyMediaSource, EmbyMediaStream, EmbyPlaybackInfoResult, EmbyPublicInfo
} from './EmbyTypes';
import { detectDelivery, transcodeReasons, urlBitrate, rangeLabel, normCodec } from '../media/ProfileBuilder';

export const TICKS_PER_MS: number = 10000;

export const LIST_FIELDS: string = 'PrimaryImageAspectRatio,Overview,Genres,ProductionYear,PremiereDate,' +
  'CommunityRating,OfficialRating,ProviderIds,ChildCount,RecursiveItemCount,BasicSyncInfo,OriginalTitle,' +
  'SeriesPrimaryImage,Width,Height,MediaSourceCount';
export const DETAIL_FIELDS: string = LIST_FIELDS + ',People,Studios,Tags,MediaSources,MediaStreams,Taglines,SortName,Path';
export const IMAGE_TYPES: string = 'Primary,Backdrop,Thumb,Logo';

export const POSTER_WIDTH: number = 400;
export const BACKDROP_WIDTH: number = 1280;
export const LOGO_WIDTH: number = 500;
export const THUMB_WIDTH: number = 640;

/** What the mapper needs to know about the server to build absolute URLs. */
export class EmbyContext {
  sourceId: string = '';
  baseUrl: string = '';
  token: string = '';
  userId: string = '';
  deviceId: string = '';
}

export function makeContext(sourceId: string, baseUrl: string, token: string, userId: string,
  deviceId: string): EmbyContext {
  const c = new EmbyContext();
  c.sourceId = sourceId;
  c.baseUrl = baseUrl;
  c.token = token;
  c.userId = userId;
  c.deviceId = deviceId;
  return c;
}

export function ticksToMs(ticks: number | undefined): number {
  if (ticks === undefined || ticks === null || ticks <= 0) {
    return 0;
  }
  return Math.floor(ticks / TICKS_PER_MS);
}

export function msToTicks(ms: number): number {
  return ms > 0 ? Math.floor(ms) * TICKS_PER_MS : 0;
}

function enc(s: string): string {
  return encodeURIComponent(s);
}

/** Add http:// if no scheme, drop trailing slashes and web-client paths ("/web/index.html#!/home"). */
export function normaliseUrl(input: string): string {
  let u = input.trim();
  if (u.length === 0) {
    return '';
  }
  if (!/^https?:\/\//i.test(u)) {
    u = 'http://' + u;
  }
  const hash = u.indexOf('#');
  if (hash >= 0) {
    u = u.substring(0, hash);
  }
  const q = u.indexOf('?');
  if (q >= 0) {
    u = u.substring(0, q);
  }
  u = u.replace(/\/web(\/.*)?$/i, '');
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  return u;
}

/** Base URLs to try in order: as typed, then with/without the Emby "/emby" prefix. */
export function candidateBaseUrls(input: string): string[] {
  const u = normaliseUrl(input);
  if (u.length === 0) {
    return [];
  }
  if (/\/emby$/i.test(u)) {
    return [u, u.substring(0, u.length - 5)];
  }
  return [u, u + '/emby'];
}

export function detectKind(info: EmbyPublicInfo): SourceKind {
  const product = (info.ProductName ?? '').toLowerCase();
  return product.indexOf('jellyfin') >= 0 ? 'jellyfin' : 'emby';
}

function quoteVal(s: string): string {
  return s.replace(/"/g, '');
}

/** MediaBrowser authorization value shared by Emby (X-Emby-Authorization) and Jellyfin (Authorization). */
export function authValue(deviceId: string, token: string): string {
  let v = 'MediaBrowser Client="CineVault", Device="HarmonyOS", DeviceId="' + quoteVal(deviceId) +
    '", Version="1.0.0"';
  if (token.length > 0) {
    v += ', Token="' + quoteVal(token) + '"';
  }
  return v;
}

export function authHeaders(deviceId: string, token: string): Record<string, string> {
  const h: Record<string, string> = {};
  const v = authValue(deviceId, token);
  h['X-Emby-Authorization'] = v;
  h['Authorization'] = v;
  h['Accept'] = 'application/json';
  if (token.length > 0) {
    h['X-Emby-Token'] = token;
  }
  return h;
}

export function mapType(raw: EmbyItem): MediaType {
  switch (raw.Type ?? '') {
    case 'Movie': return 'movie';
    case 'Series': return 'series';
    case 'Season': return 'season';
    case 'Episode': return 'episode';
    case 'BoxSet': return 'collection';
    case 'Folder':
    case 'CollectionFolder':
    case 'UserView':
    case 'PlaylistsFolder':
    case 'Playlist':
      return 'folder';
    case 'Video':
    case 'MusicVideo':
    case 'Trailer':
      return 'video';
    default:
      return raw.IsFolder === true ? 'folder' : 'video';
  }
}

export function embyTypeName(t: MediaType): string {
  switch (t) {
    case 'movie': return 'Movie';
    case 'series': return 'Series';
    case 'season': return 'Season';
    case 'episode': return 'Episode';
    case 'collection': return 'BoxSet';
    case 'folder': return 'Folder';
    default: return 'Video';
  }
}
/** /Items/{id}/Images/{type}[/{index}]?maxWidth=&quality=90&tag= ; '' when no tag. */
export function imageUrlFor(ctx: EmbyContext, itemId: string, imageType: string, index: number, tag: string,
  maxWidth: number): string {
  if (itemId.length === 0 || tag.length === 0) {
    return '';
  }
  let path = ctx.baseUrl + '/Items/' + enc(itemId) + '/Images/' + imageType;
  if (index >= 0) {
    path += '/' + index;
  }
  return path + '?maxWidth=' + Math.max(1, Math.floor(maxWidth)) + '&quality=90&tag=' + enc(tag);
}

/** Rewrite the maxWidth of an image URL built by imageUrlFor. */
export function resizeImageUrl(url: string, maxWidth: number): string {
  if (url.length === 0 || maxWidth <= 0) {
    return url;
  }
  return url.replace(/maxWidth=\d+/, 'maxWidth=' + Math.floor(maxWidth));
}

function tagOf(tags: Record<string, string> | undefined, key: string): string {
  if (tags === undefined || tags === null) {
    return '';
  }
  const v = tags[key];
  return v === undefined || v === null ? '' : v;
}

function firstOf(arr: string[] | undefined): string {
  return arr !== undefined && arr !== null && arr.length > 0 ? arr[0] : '';
}

export function mapUserState(u: EmbyUserData | undefined): UserState {
  const s = new UserState();
  if (u === undefined || u === null) {
    return s;
  }
  s.played = u.Played === true;
  s.favorite = u.IsFavorite === true;
  s.positionMs = ticksToMs(u.PlaybackPositionTicks);
  s.playCount = u.PlayCount ?? 0;
  if (u.LastPlayedDate !== undefined && u.LastPlayedDate.length > 0) {
    const t = Date.parse(u.LastPlayedDate);
    s.lastPlayed = isNaN(t) ? 0 : t;
  }
  return s;
}

function providerId(ids: Record<string, string> | undefined, key: string): string {
  if (ids === undefined || ids === null) {
    return '';
  }
  // Emby uses "Tmdb"/"Imdb", some versions lower-case keys.
  const want = key.toLowerCase();
  let out = '';
  Object.keys(ids).forEach((k: string) => {
    if (out.length === 0 && k.toLowerCase() === want) {
      out = String(ids[k]);
    }
  });
  return out;
}

export function mapImages(ctx: EmbyContext, raw: EmbyItem, item: MediaItem): void {
  const id = raw.Id ?? '';
  const primary = tagOf(raw.ImageTags, 'Primary');
  const ownBackdrop = firstOf(raw.BackdropImageTags);
  let backdrop = ownBackdrop.length > 0 ? imageUrlFor(ctx, id, 'Backdrop', 0, ownBackdrop, BACKDROP_WIDTH) : '';
  if (backdrop.length === 0) {
    backdrop = imageUrlFor(ctx, raw.ParentBackdropItemId ?? '', 'Backdrop', 0, firstOf(raw.ParentBackdropImageTags),
      BACKDROP_WIDTH);
  }
  let logo = imageUrlFor(ctx, id, 'Logo', -1, tagOf(raw.ImageTags, 'Logo'), LOGO_WIDTH);
  if (logo.length === 0) {
    logo = imageUrlFor(ctx, raw.ParentLogoItemId ?? '', 'Logo', -1, raw.ParentLogoImageTag ?? '', LOGO_WIDTH);
  }
  let thumb = imageUrlFor(ctx, id, 'Thumb', -1, tagOf(raw.ImageTags, 'Thumb'), THUMB_WIDTH);
  let poster = '';
  if (item.type === 'episode') {
    // Episode Primary is a 16:9 still: use it as thumb, and the series (or season) poster as poster.
    const still = imageUrlFor(ctx, id, 'Primary', -1, primary, THUMB_WIDTH);
    if (still.length > 0) {
      thumb = still;
    }
    poster = imageUrlFor(ctx, raw.SeriesId ?? '', 'Primary', -1, raw.SeriesPrimaryImageTag ?? '', POSTER_WIDTH);
    if (poster.length === 0) {
      poster = imageUrlFor(ctx, raw.ParentPrimaryImageItemId ?? '', 'Primary', -1, raw.ParentPrimaryImageTag ?? '',
        POSTER_WIDTH);
    }
    if (poster.length === 0) {
      poster = imageUrlFor(ctx, id, 'Primary', -1, primary, POSTER_WIDTH);
    }
  } else {
    poster = imageUrlFor(ctx, id, 'Primary', -1, primary, POSTER_WIDTH);
    if (poster.length === 0 && item.type === 'season') {
      poster = imageUrlFor(ctx, raw.SeriesId ?? '', 'Primary', -1, raw.SeriesPrimaryImageTag ?? '', POSTER_WIDTH);
    }
  }
  if (thumb.length === 0) {
    thumb = imageUrlFor(ctx, raw.ParentThumbItemId ?? '', 'Thumb', -1, raw.ParentThumbImageTag ?? '', THUMB_WIDTH);
  }
  if (thumb.length === 0 && backdrop.length > 0) {
    thumb = resizeImageUrl(backdrop, THUMB_WIDTH);
  }
  if (backdrop.length === 0 && item.type === 'episode' && thumb.length > 0) {
    backdrop = resizeImageUrl(thumb, BACKDROP_WIDTH);
  }
  item.images.poster = poster;
  item.images.backdrop = backdrop;
  item.images.logo = logo;
  item.images.thumb = thumb;
}

function pickVideoStream(raw: EmbyItem): EmbyMediaStream | undefined {
  let streams: EmbyMediaStream[] | undefined = raw.MediaStreams;
  if ((streams === undefined || streams.length === 0) && raw.MediaSources !== undefined && raw.MediaSources.length > 0) {
    streams = raw.MediaSources[0].MediaStreams;
  }
  if (streams === undefined) {
    return undefined;
  }
  return streams.find((s: EmbyMediaStream) => s.Type === 'Video');
}

export function mapItem(ctx: EmbyContext, raw: EmbyItem): MediaItem {
  const it = new MediaItem();
  it.sourceId = ctx.sourceId;
  it.id = raw.Id ?? '';
  it.type = mapType(raw);
  it.title = raw.Name ?? '';
  it.originalTitle = raw.OriginalTitle ?? '';
  it.overview = raw.Overview ?? '';
  it.premiereDate = raw.PremiereDate ?? '';
  it.year = raw.ProductionYear ?? 0;
  if (it.year === 0 && it.premiereDate.length >= 4) {
    const y = parseInt(it.premiereDate.substring(0, 4), 10);
    it.year = isNaN(y) ? 0 : y;
  }
  it.rating = raw.CommunityRating !== undefined ? Math.round(raw.CommunityRating * 10) / 10 : 0;
  it.officialRating = raw.OfficialRating ?? '';
  it.runtimeMs = ticksToMs(raw.RunTimeTicks);
  it.genres = raw.Genres ?? [];
  it.tags = raw.Tags ?? [];
  it.studios = (raw.Studios ?? []).map((s) => s.Name ?? '').filter((s: string) => s.length > 0);
  it.people = (raw.People ?? []).map((p) => {
    const person = new Person();
    person.name = p.Name ?? '';
    person.role = (p.Role !== undefined && p.Role.length > 0) ? p.Role : personType(p.Type ?? '');
    person.image = imageUrlFor(ctx, p.Id ?? '', 'Primary', -1, p.PrimaryImageTag ?? '', 300);
    return person;
  });
  it.seriesId = raw.SeriesId ?? '';
  it.seriesTitle = raw.SeriesName ?? '';
  it.seasonId = raw.SeasonId ?? '';
  if (it.type === 'season') {
    it.seasonNumber = raw.IndexNumber ?? -1;
  } else {
    it.seasonNumber = raw.ParentIndexNumber ?? -1;
    it.episodeNumber = it.type === 'episode' ? (raw.IndexNumber ?? -1) : -1;
  }
  it.childCount = raw.ChildCount ?? (raw.RecursiveItemCount ?? 0);
  it.tmdbId = providerId(raw.ProviderIds, 'Tmdb');
  it.imdbId = providerId(raw.ProviderIds, 'Imdb');
  it.container = raw.Container ?? '';
  const vs = pickVideoStream(raw);
  it.width = raw.Width ?? (vs !== undefined ? (vs.Width ?? 0) : 0);
  it.height = raw.Height ?? (vs !== undefined ? (vs.Height ?? 0) : 0);
  it.state = mapUserState(raw.UserData);
  mapImages(ctx, raw, it);
  return it;
}

function personType(t: string): string {
  switch (t) {
    case 'Director': return '导演';
    case 'Writer': return '编剧';
    case 'Producer': return '制片人';
    case 'Actor': return '演员';
    case 'GuestStar': return '客串';
    case 'Composer': return '作曲';
    default: return t;
  }
}

export function mapItems(ctx: EmbyContext, raws: EmbyItem[] | undefined): MediaItem[] {
  if (raws === undefined || raws === null) {
    return [];
  }
  return raws.map((r: EmbyItem) => mapItem(ctx, r)).filter((m: MediaItem) => m.id.length > 0);
}

export function mapView(ctx: EmbyContext, raw: EmbyItem): LibraryView {
  const v = new LibraryView();
  v.sourceId = ctx.sourceId;
  v.id = raw.Id ?? '';
  v.name = raw.Name ?? '';
  v.collectionType = raw.CollectionType ?? 'mixed';
  v.image = imageUrlFor(ctx, v.id, 'Primary', -1, tagOf(raw.ImageTags, 'Primary'), THUMB_WIDTH);
  return v;
}

/** Views a video app can show (drops music, books, photos, live tv, playlists). */
export function isVideoView(v: LibraryView): boolean {
  const ct = v.collectionType.toLowerCase();
  return ct === '' || ct === 'movies' || ct === 'tvshows' || ct === 'mixed' || ct === 'homevideos' ||
    ct === 'boxsets' || ct === 'musicvideos' || ct === 'folders';
}
/** Map our sortBy names onto Emby SortBy values (pass-through for names Emby already understands). */
export function mapSortBy(sortBy: string): string {
  switch (sortBy) {
    case '':
    case 'SortName': return 'SortName';
    case 'DateCreated': return 'DateCreated,SortName';
    case 'PremiereDate': return 'PremiereDate,ProductionYear,SortName';
    case 'CommunityRating': return 'CommunityRating,SortName';
    case 'DatePlayed': return 'DatePlayed,SortName';
    case 'ProductionYear': return 'ProductionYear,PremiereDate,SortName';
    case 'Runtime': return 'Runtime,SortName';
    case 'Random': return 'Random';
    default: return sortBy;
  }
}

/** Query parameters for /Users/{uid}/Items. */
export function buildItemsQuery(q: QueryOptions): Record<string, string> {
  const p: Record<string, string> = {};
  if (q.parentId.length > 0) {
    p['ParentId'] = q.parentId;
  }
  if (q.types.length > 0) {
    p['IncludeItemTypes'] = q.types.map((t: MediaType) => embyTypeName(t)).join(',');
  }
  p['Recursive'] = q.recursive ? 'true' : 'false';
  p['SortBy'] = mapSortBy(q.sortBy);
  p['SortOrder'] = q.sortDesc ? 'Descending' : 'Ascending';
  p['StartIndex'] = String(Math.max(0, Math.floor(q.startIndex)));
  if (q.limit > 0) {
    p['Limit'] = String(Math.floor(q.limit));
  }
  if (q.searchTerm.length > 0) {
    p['SearchTerm'] = q.searchTerm;
  }
  if (q.genres.length > 0) {
    p['Genres'] = q.genres.join('|');
  }
  if (q.years.length > 0) {
    p['Years'] = q.years.map((y: number) => String(y)).join(',');
  }
  const filters: string[] = [];
  if (q.favoritesOnly) {
    filters.push('IsFavorite');
  }
  if (q.unplayedOnly) {
    filters.push('IsUnplayed');
  }
  if (filters.length > 0) {
    p['Filters'] = filters.join(',');
  }
  p['Fields'] = LIST_FIELDS;
  p['EnableImageTypes'] = IMAGE_TYPES;
  p['ImageTypeLimit'] = '1';
  p['EnableTotalRecordCount'] = 'true';
  return p;
}

/** Body of POST /Items/{id}/PlaybackInfo (DeviceProfile is attached by the provider). */
export class PlaybackInfoBody {
  UserId: string = '';
  MaxStreamingBitrate: number = 0;
  StartTimeTicks: number = 0;
  AudioStreamIndex?: number;
  SubtitleStreamIndex?: number;
  MediaSourceId?: string;
  EnableDirectPlay: boolean = true;
  EnableDirectStream: boolean = true;
  EnableTranscoding: boolean = true;
  AllowVideoStreamCopy: boolean = true;
  AllowAudioStreamCopy: boolean = true;
  AutoOpenLiveStream: boolean = true;
  IsPlayback: boolean = true;
  DeviceProfile?: Object;
}

export function buildPlaybackBody(userId: string, req: PlaybackRequest, maxBitrate: number,
  mediaSourceId: string): PlaybackInfoBody {
  const b = new PlaybackInfoBody();
  b.UserId = userId;
  b.MaxStreamingBitrate = maxBitrate;
  b.StartTimeTicks = msToTicks(req.startMs);
  if (req.audioIndex >= 0) {
    b.AudioStreamIndex = req.audioIndex;
  }
  if (req.subtitleIndex >= 0) {
    b.SubtitleStreamIndex = req.subtitleIndex;
  }
  if (mediaSourceId.length > 0) {
    b.MediaSourceId = mediaSourceId;
  }
  return b;
}

function firstContainer(c: string | undefined): string {
  const s = (c ?? '').split(',')[0].trim().toLowerCase();
  return s.length > 0 ? s : 'mp4';
}

function langName(code: string): string {
  switch (code.toLowerCase()) {
    case 'chi':
    case 'zho':
    case 'zh':
    case 'chs':
    case 'cht': return '中文';
    case 'eng':
    case 'en': return '英语';
    case 'jpn':
    case 'ja': return '日语';
    case 'kor':
    case 'ko': return '韩语';
    case 'fre':
    case 'fra': return '法语';
    case 'ger':
    case 'deu': return '德语';
    case 'spa': return '西班牙语';
    case 'rus': return '俄语';
    case 'ita': return '意大利语';
    case 'tha': return '泰语';
    case 'und': return '';
    default: return code;
  }
}

function absUrl(ctx: EmbyContext, u: string): string {
  if (/^https?:\/\//i.test(u)) {
    return u;
  }
  return ctx.baseUrl + (u.startsWith('/') ? u : '/' + u);
}

function withApiKey(ctx: EmbyContext, u: string): string {
  if (ctx.token.length === 0 || /[?&]api_key=/i.test(u)) {
    return u;
  }
  return u + (u.indexOf('?') >= 0 ? '&' : '?') + 'api_key=' + enc(ctx.token);
}

export function subtitleUrl(ctx: EmbyContext, itemId: string, mediaSourceId: string, index: number,
  format: string): string {
  return ctx.baseUrl + '/Videos/' + enc(itemId) + '/' + enc(mediaSourceId) + '/Subtitles/' + index + '/Stream.' +
    format + '?api_key=' + enc(ctx.token);
}

export function mapAudioTracks(streams: EmbyMediaStream[]): AudioTrack[] {
  return streams.filter((s: EmbyMediaStream) => s.Type === 'Audio').map((s: EmbyMediaStream) => {
    const a = new AudioTrack();
    a.index = s.Index ?? 0;
    a.language = s.Language ?? '';
    a.codec = s.Codec ?? '';
    a.channels = s.Channels ?? 0;
    a.isDefault = s.IsDefault === true;
    const t = s.DisplayTitle ?? (s.Title ?? '');
    a.title = t.length > 0 ? t : (langName(a.language) + ' ' + a.codec.toUpperCase()).trim();
    return a;
  });
}

export function mapSubtitles(ctx: EmbyContext, itemId: string, mediaSourceId: string,
  streams: EmbyMediaStream[]): SubtitleTrack[] {
  return streams.filter((s: EmbyMediaStream) => s.Type === 'Subtitle').map((s: EmbyMediaStream) => {
    const t = new SubtitleTrack();
    t.index = s.Index ?? 0;
    t.language = s.Language ?? '';
    t.codec = (s.Codec ?? '').toLowerCase();
    t.isDefault = s.IsDefault === true;
    const title = s.DisplayTitle ?? (s.Title ?? '');
    t.title = title.length > 0 ? title : (langName(t.language).length > 0 ? langName(t.language) : '字幕 ' + t.index);
    if (s.IsForced === true && t.title.indexOf('强制') < 0) {
      t.title += ' (强制)';
    }
    const isText = s.IsTextSubtitleStream === true || isTextCodec(t.codec);
    if (isText) {
      // Text subtitles (embedded or external) are extracted/converted to SRT server-side.
      t.url = subtitleUrl(ctx, itemId, mediaSourceId, t.index, 'srt');
      t.isExternal = true;
    } else if (s.DeliveryMethod === 'External' && s.DeliveryUrl !== undefined && s.DeliveryUrl.length > 0) {
      t.url = withApiKey(ctx, absUrl(ctx, s.DeliveryUrl));
      t.isExternal = true;
    } else {
      t.url = '';
      t.isExternal = false;
    }
    return t;
  });
}

function isTextCodec(c: string): boolean {
  return c === 'srt' || c === 'subrip' || c === 'ass' || c === 'ssa' || c === 'vtt' || c === 'webvtt' ||
    c === 'mov_text' || c === 'text' || c === 'smi' || c === 'sami';
}

/** Choose the media source the server prepared (the requested one, else the first). */
export function pickMediaSource(res: EmbyPlaybackInfoResult, mediaSourceId: string): EmbyMediaSource | undefined {
  const list = res.MediaSources ?? [];
  if (list.length === 0) {
    return undefined;
  }
  if (mediaSourceId.length > 0) {
    const m = list.find((s: EmbyMediaSource) => s.Id === mediaSourceId);
    if (m !== undefined) {
      return m;
    }
  }
  return list[0];
}

/** Human-readable message for PlaybackInfo ErrorCode values. */
export function playbackErrorMessage(code: string): string {
  switch (code) {
    case 'NotAllowed': return '服务器不允许此用户播放该媒体';
    case 'NoCompatibleStream': return '没有可兼容的播放流，且服务器无法转码';
    case 'RateLimitExceeded': return '服务器播放次数受限，请稍后再试';
    default: return '无法获取播放信息: ' + code;
  }
}

/** Build PlaybackInfo from the server's PlaybackInfo response. Throws Error with Chinese message on failure. */
export function mapPlayback(ctx: EmbyContext, itemId: string, res: EmbyPlaybackInfoResult,
  mediaSourceId: string, fallbackDurationMs: number): PlaybackInfo {
  if (res.ErrorCode !== undefined && res.ErrorCode !== null && res.ErrorCode.length > 0) {
    throw new Error(playbackErrorMessage(res.ErrorCode));
  }
  const src = pickMediaSource(res, mediaSourceId);
  if (src === undefined) {
    throw new Error('服务器没有返回可用的媒体源');
  }
  const info = new PlaybackInfo();
  const msid = src.Id ?? '';
  info.mediaSourceId = msid;
  info.playSessionId = res.PlaySessionId ?? '';
  info.durationMs = ticksToMs(src.RunTimeTicks);
  if (info.durationMs === 0) {
    info.durationMs = fallbackDurationMs;
  }
  const direct = src.SupportsDirectPlay === true || src.SupportsDirectStream === true;
  const transcodeUrl = src.TranscodingUrl ?? '';
  if (direct) {
    const remote = src.IsRemote === true && (src.Protocol ?? '').toLowerCase() === 'http' &&
      /^https?:\/\//i.test(src.Path ?? '');
    if (remote && src.SupportsDirectPlay === true) {
      info.url = src.Path ?? '';
      info.container = firstContainer(src.Container);
    } else {
      const container = firstContainer(src.Container);
      info.container = container;
      info.url = ctx.baseUrl + '/Videos/' + enc(itemId) + '/stream.' + container + '?Static=true&MediaSourceId=' +
        enc(msid) + '&DeviceId=' + enc(ctx.deviceId) + (info.playSessionId.length > 0 ?
          '&PlaySessionId=' + enc(info.playSessionId) : '') + '&api_key=' + enc(ctx.token);
    }
    info.isTranscode = false;
  } else if (transcodeUrl.length > 0) {
    info.url = withApiKey(ctx, absUrl(ctx, transcodeUrl));
    info.isTranscode = true;
    const sub = (src.TranscodingSubProtocol ?? '').toLowerCase();
    info.container = sub === 'hls' || transcodeUrl.indexOf('.m3u8') >= 0 ? 'hls' :
      firstContainer(src.TranscodingContainer);
  } else {
    throw new Error('该视频格式不受支持，且服务器未提供转码');
  }
  const hdrs = src.RequiredHttpHeaders;
  if (hdrs !== undefined && hdrs !== null) {
    Object.keys(hdrs).forEach((k: string) => {
      info.headers[k] = hdrs[k];
    });
  }
  const streams = src.MediaStreams ?? [];
  info.audioTracks = mapAudioTracks(streams);
  info.subtitles = mapSubtitles(ctx, itemId, msid, streams);
  applyStreamInfo(info, src, -1);
  return info;
}

/**
 * Fill PlaybackInfo.deliveryMode / codec / size / range / bitrate / transcodeReasons from the media source.
 * audioIndex: requested audio stream (-1 = server default).
 */
export function applyStreamInfo(info: PlaybackInfo, src: EmbyMediaSource, audioIndex: number): void {
  const streams = src.MediaStreams ?? [];
  const video = streams.find((s: EmbyMediaStream) => s.Type === 'Video');
  const audios = streams.filter((s: EmbyMediaStream) => s.Type === 'Audio');
  const wanted = audioIndex >= 0 ? audioIndex : (src.DefaultAudioStreamIndex ?? -1);
  let audio = audios.find((s: EmbyMediaStream) => s.Index === wanted);
  if (audio === undefined) {
    audio = audios.find((s: EmbyMediaStream) => s.IsDefault === true);
  }
  if (audio === undefined && audios.length > 0) {
    audio = audios[0];
  }
  info.videoCodec = video !== undefined ? normCodec(video.Codec ?? '') : '';
  info.audioCodec = audio !== undefined ? normCodec(audio.Codec ?? '') : '';
  info.videoWidth = video !== undefined ? (video.Width ?? 0) : 0;
  info.videoHeight = video !== undefined ? (video.Height ?? 0) : 0;
  info.videoRange = video !== undefined ? rangeLabel(video.VideoRangeType ?? '', video.VideoRange ?? '',
    (video.ColorTransfer ?? '').toLowerCase(), video.ExtendedVideoType ?? '') : '';
  info.transcodeReasons = info.isTranscode ? transcodeReasons(info.url, src.TranscodeReasons ?? []) : [];
  info.deliveryMode = detectDelivery(info.url, info.isTranscode, info.videoCodec, info.transcodeReasons);
  const outRate = info.deliveryMode === 'transcode' ? urlBitrate(info.url) : 0;
  info.bitrate = outRate > 0 ? outRate : (src.Bitrate ?? 0);
}

/** Body for /Sessions/Playing, /Progress and /Stopped. */
export class PlaybackReport {
  ItemId: string = '';
  MediaSourceId: string = '';
  PlaySessionId: string = '';
  PositionTicks: number = 0;
  IsPaused: boolean = false;
  CanSeek: boolean = true;
  PlayMethod: string = 'DirectStream';
  EventName?: string;
}

export function buildReport(itemId: string, info: PlaybackInfo, positionMs: number, paused: boolean): PlaybackReport {
  const r = new PlaybackReport();
  r.ItemId = itemId;
  r.MediaSourceId = info.mediaSourceId;
  r.PlaySessionId = info.playSessionId;
  r.PositionTicks = msToTicks(positionMs);
  r.IsPaused = paused;
  r.PlayMethod = info.isTranscode ? 'Transcode' : 'DirectStream';
  return r;
}
