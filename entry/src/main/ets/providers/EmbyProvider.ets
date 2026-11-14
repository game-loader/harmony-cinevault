import { MediaProvider } from '../common/MediaProvider';
import {
  SourceConfig, SourceKind, MediaItem, LibraryView, QueryOptions, PagedItems, PlaybackInfo, PlaybackRequest
} from '../common/Models';
import { request, buildQuery, HttpError, HttpResponse } from '../common/Http';
import {
  EmbyItem, EmbyItemsResult, EmbyAuthResult, EmbyPublicInfo, EmbyPlaybackInfoResult
} from './EmbyTypes';
import {
  EmbyContext, makeContext, mapItem, mapItems, mapView, isVideoView, buildItemsQuery, buildPlaybackBody,
  mapPlayback, buildReport, authHeaders, candidateBaseUrls, detectKind, resizeImageUrl, LIST_FIELDS,
  DETAIL_FIELDS, IMAGE_TYPES, PlaybackReport, pickMediaSource, applyStreamInfo, PlaybackInfoBody
} from './EmbyMapper';
import { DEFAULT_MAX_BITRATE } from './DeviceProfile';
import { buildProfile, ProfileOptions } from '../media/ProfileBuilder';
import { CodecCaps } from '../media/CodecCaps';
import { Settings, AppSettings } from '../common/Settings';

/** Bitrate cap for a forced transcode when the user hasn't chosen one. */
const FORCED_TRANSCODE_BITRATE: number = 8000000;

/** Result of EmbyProvider.login, used by the server-edit page. */
export class EmbyLoginResult {
  userId: string = '';
  token: string = '';
  serverName: string = '';
  /** Base URL that worked (normalised, possibly with /emby prefix). */
  baseUrl: string = '';
  kind: SourceKind = 'emby';
  userName: string = '';
}

/** Result of EmbyProvider.probe. */
export class EmbyProbeResult {
  baseUrl: string = '';
  kind: SourceKind = 'emby';
  serverName: string = '';
  version: string = '';
  serverId: string = '';
}

class AuthBody {
  Username: string = '';
  Pw: string = '';
}

class GenreNameItem {
  Name?: string;
}

interface GenresResult {
  Items?: GenreNameItem[];
}

function describeError(e: Object, context: string): Error {
  if (e instanceof HttpError) {
    const he = e as HttpError;
    if (he.status === 401 || he.status === 403) {
      return new Error(context + '：认证失败，请检查用户名、密码或重新登录');
    }
    if (he.status === 404) {
      return new Error(context + '：服务器未找到该资源 (404)');
    }
    if (he.status >= 500) {
      return new Error(context + '：服务器内部错误 (' + he.status + ')');
    }
    if (he.status === 0) {
      return new Error(context + '：无法连接服务器，请检查地址和网络');
    }
    return new Error(context + '：请求失败 (HTTP ' + he.status + ')');
  }
  const err = e as Error;
  return new Error(context + '：' + (err.message ?? String(e)));
}

function parseJson<T>(r: HttpResponse): T {
  const body = r.body.trim();
  if (body.length === 0) {
    throw new Error('服务器返回空响应');
  }
  try {
    return JSON.parse(body) as T;
  } catch (e) {
    throw new Error('服务器响应不是有效的 JSON');
  }
}

async function fetchPublicInfo(base: string): Promise<EmbyPublicInfo> {
  const r = await request('GET', base + '/System/Info/Public', authHeaders('', ''), undefined, 8000);
  const info = parseJson<EmbyPublicInfo>(r);
  if ((info.Id ?? '').length === 0 && (info.ServerName ?? '').length === 0 && (info.Version ?? '').length === 0) {
    throw new Error('不是 Emby/Jellyfin 服务器');
  }
  return info;
}

export class EmbyProvider implements MediaProvider {
  readonly config: SourceConfig;

  constructor(config: SourceConfig) {
    this.config = config;
  }

  // ---------- static helpers for the server-edit page ----------

  /** Detect server type and name via /System/Info/Public, trying with and without the /emby prefix. */
  static async probe(baseUrl: string): Promise<EmbyProbeResult> {
    const candidates = candidateBaseUrls(baseUrl);
    if (candidates.length === 0) {
      throw new Error('请输入服务器地址');
    }
    let lastErr: Object = new Error('无法连接服务器');
    for (let i = 0; i < candidates.length; i++) {
      const base = candidates[i];
      try {
        const info = await fetchPublicInfo(base);
        const res = new EmbyProbeResult();
        res.baseUrl = base;
        res.kind = detectKind(info);
        res.serverName = info.ServerName ?? '';
        res.version = info.Version ?? '';
        res.serverId = info.Id ?? '';
        return res;
      } catch (e) {
        lastErr = e as Object;
      }
    }
    throw describeError(lastErr, '连接服务器失败');
  }

  /** Authenticate by name. Returns user id + access token; throws Error with a Chinese message. */
  static async login(baseUrl: string, user: string, pass: string, kind: SourceKind,
    deviceId: string): Promise<EmbyLoginResult> {
    if (user.trim().length === 0) {
      throw new Error('请输入用户名');
    }
    let base = '';
    let serverName = '';
    let detected: SourceKind = kind === 'jellyfin' ? 'jellyfin' : 'emby';
    try {
      const p = await EmbyProvider.probe(baseUrl);
      base = p.baseUrl;
      serverName = p.serverName;
      detected = p.kind;
    } catch (e) {
      // Some reverse proxies block the public info endpoint; fall back to the first candidate.
      const c = candidateBaseUrls(baseUrl);
      if (c.length === 0) {
        throw new Error('请输入服务器地址');
      }
      base = c[0];
    }
    const body = new AuthBody();
    body.Username = user.trim();
    body.Pw = pass;
    const headers = authHeaders(deviceId, '');
    headers['Content-Type'] = 'application/json';
    let auth: EmbyAuthResult;
    try {
      const r = await request('POST', base + '/Users/AuthenticateByName', headers, JSON.stringify(body));
      auth = parseJson<EmbyAuthResult>(r);
    } catch (e) {
      if (e instanceof HttpError && ((e as HttpError).status === 401 || (e as HttpError).status === 403)) {
        throw new Error('登录失败：用户名或密码错误');
      }
      throw describeError(e as Object, '登录失败');
    }
    const token = auth.AccessToken ?? '';
    const uid = auth.User !== undefined ? (auth.User.Id ?? '') : '';
    if (token.length === 0 || uid.length === 0) {
      throw new Error('登录失败：服务器未返回访问令牌');
    }
    const res = new EmbyLoginResult();
    res.userId = uid;
    res.token = token;
    res.serverName = serverName.length > 0 ? serverName : (detected === 'jellyfin' ? 'Jellyfin' : 'Emby');
    res.baseUrl = base;
    res.kind = detected;
    res.userName = auth.User !== undefined ? (auth.User.Name ?? user) : user;
    return res;
  }
  // ---------- internals ----------

  private ctx(): EmbyContext {
    return makeContext(this.config.id, this.base(), this.config.token, this.config.userId, this.config.deviceId);
  }

  private base(): string {
    const c = candidateBaseUrls(this.config.baseUrl);
    return c.length > 0 ? c[0] : this.config.baseUrl;
  }

  private headers(): Record<string, string> {
    return authHeaders(this.config.deviceId, this.config.token);
  }

  private uid(): string {
    if (this.config.userId.length === 0 || this.config.token.length === 0) {
      throw new Error('尚未登录该服务器，请在设置中重新登录');
    }
    return encodeURIComponent(this.config.userId);
  }

  private url(path: string, params: Record<string, string>): string {
    const q = buildQuery(params);
    return this.base() + path + (q.length > 0 ? '?' + q : '');
  }

  private async get<T>(path: string, params: Record<string, string>, context: string): Promise<T> {
    try {
      const r = await request('GET', this.url(path, params), this.headers());
      return parseJson<T>(r);
    } catch (e) {
      throw describeError(e as Object, context);
    }
  }

  private async send(method: 'POST' | 'DELETE', path: string, params: Record<string, string>, body: Object | undefined,
    context: string): Promise<HttpResponse> {
    const h = this.headers();
    let payload: string | undefined = undefined;
    if (body !== undefined) {
      h['Content-Type'] = 'application/json';
      payload = JSON.stringify(body);
    }
    try {
      return await request(method, this.url(path, params), h, payload);
    } catch (e) {
      throw describeError(e as Object, context);
    }
  }

  private listParams(limit: number): Record<string, string> {
    const p: Record<string, string> = {};
    p['Fields'] = LIST_FIELDS;
    p['EnableImageTypes'] = IMAGE_TYPES;
    p['ImageTypeLimit'] = '1';
    p['EnableUserData'] = 'true';
    if (limit > 0) {
      p['Limit'] = String(Math.floor(limit));
    }
    return p;
  }

  // ---------- MediaProvider ----------

  async connect(): Promise<void> {
    const uid = this.uid();
    await this.get<EmbyItem>('/Users/' + uid, {}, '连接 ' + (this.config.name || '服务器') + ' 失败');
  }

  async getViews(): Promise<LibraryView[]> {
    const res = await this.get<EmbyItemsResult>('/Users/' + this.uid() + '/Views', {}, '获取媒体库失败');
    const ctx = this.ctx();
    return (res.Items ?? []).map((r: EmbyItem) => mapView(ctx, r)).filter((v: LibraryView) => isVideoView(v));
  }

  async getResume(limit: number): Promise<MediaItem[]> {
    const p = this.listParams(limit);
    p['MediaTypes'] = 'Video';
    p['Recursive'] = 'true';
    const res = await this.get<EmbyItemsResult>('/Users/' + this.uid() + '/Items/Resume', p, '获取继续观看失败');
    return mapItems(this.ctx(), res.Items);
  }

  async getNextUp(limit: number): Promise<MediaItem[]> {
    const p = this.listParams(limit);
    p['UserId'] = this.config.userId;
    p['EnableTotalRecordCount'] = 'false';
    const res = await this.get<EmbyItemsResult>('/Shows/NextUp', p, '获取下一集失败');
    return mapItems(this.ctx(), res.Items);
  }

  async getLatest(parentId: string, limit: number): Promise<MediaItem[]> {
    const p = this.listParams(limit);
    if (parentId.length > 0) {
      p['ParentId'] = parentId;
    }
    p['IncludeItemTypes'] = 'Movie,Series,Episode,Video';
    p['GroupItems'] = 'true';
    const raws = await this.get<EmbyItem[]>('/Users/' + this.uid() + '/Items/Latest', p, '获取最新内容失败');
    return mapItems(this.ctx(), Array.isArray(raws) ? raws : []);
  }

  async getItems(q: QueryOptions): Promise<PagedItems> {
    const p = buildItemsQuery(q);
    p['EnableUserData'] = 'true';
    const res = await this.get<EmbyItemsResult>('/Users/' + this.uid() + '/Items', p, '获取列表失败');
    const out = new PagedItems();
    out.items = mapItems(this.ctx(), res.Items);
    out.total = res.TotalRecordCount ?? out.items.length;
    return out;
  }

  async getItem(id: string): Promise<MediaItem> {
    const p: Record<string, string> = {};
    p['Fields'] = DETAIL_FIELDS;
    const raw = await this.get<EmbyItem>('/Users/' + this.uid() + '/Items/' + encodeURIComponent(id), p,
      '获取详情失败');
    return mapItem(this.ctx(), raw);
  }

  async getSeasons(seriesId: string): Promise<MediaItem[]> {
    const p = this.listParams(0);
    p['UserId'] = this.config.userId;
    const res = await this.get<EmbyItemsResult>('/Shows/' + encodeURIComponent(seriesId) + '/Seasons', p,
      '获取季列表失败');
    return mapItems(this.ctx(), res.Items);
  }

  async getEpisodes(seriesId: string, seasonId: string): Promise<MediaItem[]> {
    const p = this.listParams(0);
    p['UserId'] = this.config.userId;
    p['Fields'] = LIST_FIELDS + ',MediaStreams';
    if (seasonId.length > 0) {
      p['SeasonId'] = seasonId;
    }
    const res = await this.get<EmbyItemsResult>('/Shows/' + encodeURIComponent(seriesId) + '/Episodes', p,
      '获取剧集失败');
    return mapItems(this.ctx(), res.Items);
  }

  async getSimilar(id: string, limit: number): Promise<MediaItem[]> {
    const p = this.listParams(limit);
    p['UserId'] = this.config.userId;
    try {
      const res = await this.get<EmbyItemsResult>('/Items/' + encodeURIComponent(id) + '/Similar', p, '获取相似内容失败');
      return mapItems(this.ctx(), res.Items);
    } catch (e) {
      return []; // optional row; never fail the detail page because of it
    }
  }

  async search(term: string, limit: number): Promise<MediaItem[]> {
    const t = term.trim();
    if (t.length === 0) {
      return [];
    }
    const q = new QueryOptions();
    q.searchTerm = t;
    q.recursive = true;
    q.types = ['movie', 'series', 'episode', 'collection', 'video'];
    q.limit = limit > 0 ? limit : 50;
    q.sortBy = 'SortName';
    const r = await this.getItems(q);
    return r.items;
  }

  async getGenres(parentId: string): Promise<string[]> {
    const p: Record<string, string> = {};
    p['UserId'] = this.config.userId;
    p['SortBy'] = 'SortName';
    p['SortOrder'] = 'Ascending';
    p['Recursive'] = 'true';
    if (parentId.length > 0) {
      p['ParentId'] = parentId;
    }
    this.uid();
    const res = await this.get<GenresResult>('/Genres', p, '获取类型失败');
    return (res.Items ?? []).map((g: GenreNameItem) => g.Name ?? '').filter((s: string) => s.length > 0);
  }

  async getPlayback(item: MediaItem, req: PlaybackRequest): Promise<PlaybackInfo> {
    const uid = this.uid();
    const force = req.forceMode;
    let maxBitrate = req.maxBitrate > 0 ? req.maxBitrate : DEFAULT_MAX_BITRATE;
    if (force === 'transcode' && req.maxBitrate <= 0) {
      maxBitrate = FORCED_TRANSCODE_BITRATE;
    }
    const body = buildPlaybackBody(this.config.userId, req, maxBitrate, '');
    body.DeviceProfile = this.deviceProfile(maxBitrate, force);
    EmbyProvider.applyForceMode(body, force);
    const p: Record<string, string> = {};
    p['UserId'] = decodeURIComponent(uid);
    p['StartTimeTicks'] = String(body.StartTimeTicks);
    p['IsPlayback'] = 'true';
    p['AutoOpenLiveStream'] = 'true';
    p['MaxStreamingBitrate'] = String(maxBitrate);
    if (force === 'remux' || force === 'transcode') {
      // Emby reads these from the query string, Jellyfin from the body; send both.
      p['EnableDirectPlay'] = String(body.EnableDirectPlay);
      p['EnableDirectStream'] = String(body.EnableDirectStream);
      p['AllowVideoStreamCopy'] = String(body.AllowVideoStreamCopy);
      p['AllowAudioStreamCopy'] = String(body.AllowAudioStreamCopy);
    }
    if (req.audioIndex >= 0) {
      p['AudioStreamIndex'] = String(req.audioIndex);
    }
    if (req.subtitleIndex >= 0) {
      p['SubtitleStreamIndex'] = String(req.subtitleIndex);
    }
    const r = await this.send('POST', '/Items/' + encodeURIComponent(item.id) + '/PlaybackInfo', p, body,
      '获取播放地址失败');
    const res = parseJson<EmbyPlaybackInfoResult>(r);
    const info = mapPlayback(this.ctx(), item.id, res, '', item.runtimeMs);
    const src = pickMediaSource(res, '');
    if (src !== undefined) {
      applyStreamInfo(info, src, req.audioIndex);
    }
    if (info.isTranscode) {
      // The server already burns in / switches streams based on the indices sent above.
      return info;
    }
    if (req.audioIndex >= 0 && info.url.indexOf('/stream.') >= 0) {
      info.url += '&AudioStreamIndex=' + req.audioIndex;
    }
    return info;
  }

  /** Capability-driven profile; a forced remux always lists the copyable HLS codecs. */
  private deviceProfile(maxBitrate: number, force: string): Object {
    const s: AppSettings = Settings.get();
    const o = new ProfileOptions();
    o.maxBitrate = maxBitrate;
    // A forced transcode targets the safest output (H.264/AAC in HLS-TS) regardless of the probed decoders.
    o.codecMode = s.codecMode === 'compat' || force === 'transcode' ? 'compat' : 'auto';
    o.preferRemux = force === 'remux' ? true : s.preferRemux;
    o.kind = this.config.kind === 'jellyfin' ? 'jellyfin' : 'emby';
    return buildProfile(CodecCaps.entries(), o);
  }

  /**
   * 'remux': no direct play or direct stream (both would hand back the original file the player just failed on),
   * but stream copy stays allowed, so the server repackages into HLS without re-encoding where it can.
   * 'transcode': no direct play/stream and no video copy.
   */
  private static applyForceMode(body: PlaybackInfoBody, force: string): void {
    if (force === 'remux') {
      body.EnableDirectPlay = false;
      body.EnableDirectStream = false;
      body.AllowVideoStreamCopy = true;
      body.AllowAudioStreamCopy = true;
    } else if (force === 'transcode') {
      body.EnableDirectPlay = false;
      body.EnableDirectStream = false;
      body.AllowVideoStreamCopy = false;
    }
  }

  private async report(path: string, item: MediaItem, info: PlaybackInfo, positionMs: number, paused: boolean,
    eventName: string): Promise<void> {
    const body: PlaybackReport = buildReport(item.id, info, positionMs, paused);
    if (eventName.length > 0) {
      body.EventName = eventName;
    }
    try {
      await this.send('POST', path, {}, body, '上报播放进度失败');
    } catch (e) {
      // Reporting is best effort: a flaky network must not interrupt playback.
      console.warn('[EmbyProvider] report ' + path + ' failed: ' + (e as Error).message);
    }
  }

  async reportStart(item: MediaItem, info: PlaybackInfo, positionMs: number): Promise<void> {
    await this.report('/Sessions/Playing', item, info, positionMs, false, '');
  }

  async reportProgress(item: MediaItem, info: PlaybackInfo, positionMs: number, paused: boolean): Promise<void> {
    await this.report('/Sessions/Playing/Progress', item, info, positionMs, paused, paused ? 'Pause' : 'TimeUpdate');
  }

  async reportStopped(item: MediaItem, info: PlaybackInfo, positionMs: number): Promise<void> {
    await this.report('/Sessions/Playing/Stopped', item, info, positionMs, false, '');
    if (info.isTranscode && info.playSessionId.length > 0) {
      const p: Record<string, string> = {};
      p['DeviceId'] = this.config.deviceId;
      p['PlaySessionId'] = info.playSessionId;
      try {
        await this.send('DELETE', '/Videos/ActiveEncodings', p, undefined, '停止转码失败');
      } catch (e) {
        console.warn('[EmbyProvider] stop encoding failed: ' + (e as Error).message);
      }
    }
  }

  async setPlayed(item: MediaItem, played: boolean): Promise<void> {
    await this.send(played ? 'POST' : 'DELETE', '/Users/' + this.uid() + '/PlayedItems/' + encodeURIComponent(item.id),
      {}, undefined, played ? '标记已看失败' : '标记未看失败');
    item.state.played = played;
    if (played) {
      item.state.positionMs = 0;
    }
  }

  async setFavorite(item: MediaItem, favorite: boolean): Promise<void> {
    await this.send(favorite ? 'POST' : 'DELETE',
      '/Users/' + this.uid() + '/FavoriteItems/' + encodeURIComponent(item.id), {}, undefined,
      favorite ? '收藏失败' : '取消收藏失败');
    item.state.favorite = favorite;
  }

  imageUrl(item: MediaItem, kind: 'poster' | 'backdrop' | 'logo' | 'thumb', maxWidth: number): string {
    let u = '';
    switch (kind) {
      case 'poster': u = item.images.poster; break;
      case 'backdrop': u = item.images.backdrop; break;
      case 'logo': u = item.images.logo; break;
      default: u = item.images.thumb.length > 0 ? item.images.thumb : item.images.backdrop; break;
    }
    return resizeImageUrl(u, maxWidth);
  }

  imageHeaders(): Record<string, string> {
    return {};
  }
}
