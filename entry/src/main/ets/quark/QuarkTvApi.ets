import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { request, HttpError, HttpResponse } from '../common/Http';
import {
  QuarkDrive, QuarkFile, QuarkLink, QuarkQuality, QuarkError, QuarkTvEnvelope, QuarkTvAuthResp, QuarkTvCodeResp,
  QuarkTvTokenResp, QuarkTvListResp, QuarkTvFileJson, QuarkTvDownloadResp, QuarkTvStreamResp, QuarkTvUserResp, QuarkTvQr
} from './QuarkTypes';
import {
  QuarkTvConst, signRequest, apiQuery, tokenBody, encodeQuery, isTokenInvalid, isLoginPending, qrDataUri, tvToFile,
  hasMorePages, tvQualities, tvNickname, newDeviceId
} from './QuarkTvSign';

const RELOGIN_MSG: string = '夸克登录已失效，请重新登录';

/** Result of a code exchange / refresh. */
export class QuarkTvTokens {
  accessToken: string = '';
  refreshToken: string = '';
}

/** Hex digest of the UTF-8 bytes of s. alg: 'SHA256' | 'MD5'. */
function hashHex(alg: string, s: string): string {
  const md = cryptoFramework.createMd(alg);
  const blob: cryptoFramework.DataBlob = { data: new util.TextEncoder().encodeInto(s) };
  md.updateSync(blob);
  const out = md.digestSync().data;
  let hex = '';
  for (let i = 0; i < out.length; i++) {
    const h = out[i].toString(16);
    hex += h.length < 2 ? '0' + h : h;
  }
  return hex;
}

function sha256Hex(s: string): string {
  return hashHex('SHA256', s);
}

function md5Hex(s: string): string {
  return hashHex('MD5', s);
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

/**
 * Quark drive through the TV-client open api (QR login + refresh token). The access token lives in memory only;
 * the refresh token is reported through onRefreshTokenChanged so the owner can persist it.
 */
export class QuarkTvApi implements QuarkDrive {
  readonly deviceId: string;
  refreshToken: string;
  accessToken: string = '';
  onRefreshTokenChanged: ((rt: string) => void) | undefined = undefined;
  /** Every refresh token this client has held (so a provider re-created after a rotation can reuse it). */
  readonly knownTokens: string[] = [];
  private refreshing: Promise<void> | undefined = undefined;

  constructor(deviceId: string, refreshToken: string) {
    this.deviceId = deviceId;
    this.refreshToken = refreshToken;
    if (refreshToken.length > 0) {
      this.knownTokens.push(refreshToken);
    }
  }

  static newDeviceId(): string {
    return newDeviceId(util.generateRandomUUID(false) + Date.now(), md5Hex);
  }

  static headers(): Record<string, string> {
    const h: Record<string, string> = {};
    h['User-Agent'] = QuarkTvConst.UA;
    return h;
  }

  authMode(): string {
    return 'tv';
  }

  streamHeaders(): Record<string, string> {
    return QuarkTvApi.headers();
  }

  private static parseEnvelope(body: string): QuarkTvEnvelope | undefined {
    try {
      return (body.length > 0 ? JSON.parse(body) : {}) as QuarkTvEnvelope;
    } catch (e) {
      return undefined;
    }
  }

  /** One signed GET against the api host. Throws QuarkError; the envelope errno is kept in QuarkError.code. */
  private static async rawGet(path: string, accessToken: string, deviceId: string,
    extra: Record<string, string>): Promise<string> {
    let attempt = 0;
    while (true) {
      const sig = signRequest('GET', path, String(Date.now()), deviceId, QuarkTvConst.SIGN_KEY, sha256Hex, md5Hex);
      const q = apiQuery(sig, accessToken, deviceId, extra);
      const h: Record<string, string> = {};
      h['Accept'] = 'application/json, text/plain, */*';
      h['User-Agent'] = QuarkTvConst.UA;
      h['x-pan-tm'] = sig.tm;
      h['x-pan-token'] = sig.token;
      h['x-pan-client-id'] = QuarkTvConst.CLIENT_ID;
      let status = 0;
      let body = '';
      try {
        const res: HttpResponse = await request('GET', QuarkTvConst.API + path + '?' + encodeQuery(q), h);
        status = res.status;
        body = res.body;
      } catch (e) {
        const he = e as HttpError;
        const retryable = he.status === 0 || he.status === 429 || he.status >= 500;
        if (retryable && attempt < 2) {
          attempt++;
          await sleep(600 * attempt * attempt);
          continue;
        }
        if (he.status === 0) {
          throw new QuarkError(0, 0, he.message);
        }
        status = he.status;
        body = he.body;
      }
      const env = QuarkTvApi.parseEnvelope(body);
      if (env === undefined) {
        throw new QuarkError(status, 0, status >= 400 ? ('夸克网盘: HTTP ' + status) : '夸克网盘返回了无法解析的数据');
      }
      const st = env.status ?? 0;
      const errno = env.errno ?? 0;
      if (status >= 400 || st >= 400 || st === -1 || errno !== 0) {
        const info = env.error_info ?? ('HTTP ' + status);
        throw new QuarkError(st !== 0 ? st : status, errno, info);
      }
      return body;
    }
  }
  /** POST codeApi/token. Exchanges a login code (isRefresh false) or a refresh token. */
  static async exchangeToken(deviceId: string, value: string, isRefresh: boolean): Promise<QuarkTvTokens> {
    const sig = signRequest('POST', '/token', String(Date.now()), deviceId, QuarkTvConst.SIGN_KEY, sha256Hex, md5Hex);
    const h: Record<string, string> = {};
    h['Content-Type'] = 'application/json';
    h['Accept'] = 'application/json, text/plain, */*';
    h['User-Agent'] = QuarkTvConst.UA;
    let res: HttpResponse;
    try {
      res = await request('POST', QuarkTvConst.CODE_API + '/token',
        h, JSON.stringify(tokenBody(sig.reqId, deviceId, value, isRefresh)));
    } catch (e) {
      const he = e as HttpError;
      throw new QuarkError(he.status, 0, he.status === 0 ? he.message : ('获取令牌失败: HTTP ' + he.status));
    }
    let r: QuarkTvTokenResp;
    try {
      r = JSON.parse(res.body) as QuarkTvTokenResp;
    } catch (e) {
      throw new QuarkError(res.status, 0, '令牌服务返回了无法解析的数据');
    }
    const d = r.data;
    const rt = d?.refresh_token ?? '';
    if (r.code !== 200 || d === undefined || rt.length === 0) {
      const info = d?.error_info ?? r.message ?? '';
      // invalid / expired refresh token means the user must scan again
      throw new QuarkError(401, d?.errno ?? 0, isRefresh ? RELOGIN_MSG : ('登录失败：' + (info || '未获取到令牌')));
    }
    const t = new QuarkTvTokens();
    t.accessToken = d.access_token ?? '';
    t.refreshToken = rt;
    return t;
  }

  // ---------------- QR login (static: no tokens yet) ----------------

  /** Request a new login QR code. */
  static async requestQr(deviceId: string): Promise<QuarkTvQr> {
    const q: Record<string, string> = {};
    q['auth_type'] = 'code';
    q['client_id'] = QuarkTvConst.CLIENT_ID;
    q['scope'] = 'netdisk';
    q['qrcode'] = '1';
    q['qr_width'] = '460';
    q['qr_height'] = '460';
    const body = await QuarkTvApi.rawGet('/oauth/authorize', '', deviceId, q);
    const r = JSON.parse(body) as QuarkTvAuthResp;
    const out = new QuarkTvQr();
    out.image = qrDataUri(r.qr_data ?? '');
    out.queryToken = r.query_token ?? '';
    if (out.queryToken.length === 0 || (r.qr_data ?? '').length === 0) {
      throw new QuarkError(0, 0, '获取登录二维码失败');
    }
    return out;
  }

  /** One poll of /oauth/code. Returns '' while the user has not confirmed yet; throws on other errors. */
  static async pollCode(deviceId: string, queryToken: string): Promise<string> {
    const q: Record<string, string> = {};
    q['client_id'] = QuarkTvConst.CLIENT_ID;
    q['scope'] = 'netdisk';
    q['query_token'] = queryToken;
    try {
      const body = await QuarkTvApi.rawGet('/oauth/code', '', deviceId, q);
      const r = JSON.parse(body) as QuarkTvCodeResp;
      return r.code ?? '';
    } catch (e) {
      const qe = e as QuarkError;
      if (qe.code !== undefined && isLoginPending(qe.code, qe.message ?? '')) {
        return '';
      }
      throw e as Error;
    }
  }

  // ---------------- authenticated calls ----------------

  /** Adopt tokens (from exchangeToken after login, or a refresh). Reports a rotated refresh token. */
  setTokens(t: QuarkTvTokens): void {
    this.accessToken = t.accessToken;
    if (t.refreshToken.length > 0 && t.refreshToken !== this.refreshToken) {
      this.refreshToken = t.refreshToken;
      this.knownTokens.push(t.refreshToken);
      const cb = this.onRefreshTokenChanged;
      if (cb) {
        cb(t.refreshToken);
      }
    }
  }

  /** Single-flight access-token refresh: concurrent callers share one request. */
  refreshAccess(): Promise<void> {
    const pending = this.refreshing;
    if (pending !== undefined) {
      return pending;
    }
    const p = (async (): Promise<void> => {
      try {
        if (this.refreshToken.length === 0) {
          throw new QuarkError(401, 0, '尚未登录夸克网盘');
        }
        const t = await QuarkTvApi.exchangeToken(this.deviceId, this.refreshToken, true);
        this.setTokens(t);
      } finally {
        this.refreshing = undefined;
      }
    })();
    this.refreshing = p;
    return p;
  }

  /** Authenticated GET; refreshes the access token when missing or rejected and retries once. */
  async call(path: string, extra: Record<string, string>): Promise<string> {
    if (this.accessToken.length === 0) {
      await this.refreshAccess();
    }
    const used = this.accessToken;
    try {
      return await QuarkTvApi.rawGet(path, used, this.deviceId, extra);
    } catch (e) {
      const qe = e as QuarkError;
      if (!isTokenInvalid(qe.status ?? 0, qe.code ?? 0, qe.message ?? '')) {
        throw QuarkTvApi.friendly(qe);
      }
    }
    // another caller may already have refreshed while we were waiting
    if (this.accessToken === used) {
      await this.refreshAccess();
    }
    try {
      return await QuarkTvApi.rawGet(path, this.accessToken, this.deviceId, extra);
    } catch (e) {
      const qe = e as QuarkError;
      if (isTokenInvalid(qe.status ?? 0, qe.code ?? 0, qe.message ?? '')) {
        throw new QuarkError(401, qe.code ?? 0, RELOGIN_MSG);
      }
      throw QuarkTvApi.friendly(qe);
    }
  }

  private static friendly(e: QuarkError): QuarkError {
    const m = e.message ?? '';
    if (e.status === 0 || m.startsWith('夸克') || m.startsWith('网络')) {
      return e;
    }
    return new QuarkError(e.status, e.code, '夸克网盘: ' + m);
  }

  /** Account nickname ('' when the server does not report one). Throws when not logged in. */
  async userInfo(): Promise<string> {
    const q: Record<string, string> = {};
    q['method'] = 'user_info';
    const body = await this.call('/user', q);
    const r = JSON.parse(body) as QuarkTvUserResp;
    return tvNickname(r.data);
  }

  async accountName(): Promise<string> {
    const n = await this.userInfo();
    return n.length > 0 ? n : '夸克用户';
  }

  async ensureFresh(): Promise<void> {
    if (this.accessToken.length > 0) {
      return;
    }
    try {
      await this.refreshAccess();
    } catch (e) {
      console.warn('[quarktv] refresh failed: ' + (e as Error).message);
    }
  }

  async listAll(fid: string): Promise<QuarkFile[]> {
    const all: QuarkFile[] = [];
    let page = 0;
    while (true) {
      const q: Record<string, string> = {};
      q['method'] = 'list';
      q['parent_fid'] = fid;
      q['order_by'] = '3';
      q['desc'] = '1';
      q['category'] = '';
      q['source'] = '';
      q['ex_source'] = '';
      q['list_all'] = '0';
      q['page_size'] = String(QuarkTvConst.PAGE_SIZE);
      q['page_index'] = String(page);
      const body = await this.call('/file', q);
      const r = JSON.parse(body) as QuarkTvListResp;
      const files = r.data?.files ?? [];
      files.forEach((j: QuarkTvFileJson) => all.push(tvToFile(j, fid)));
      if (!hasMorePages(page, QuarkTvConst.PAGE_SIZE, files.length, r.data?.total_count ?? 0)) {
        break;
      }
      page++;
      if (page >= 200) {
        break; // 20k entries: safety stop
      }
    }
    return all;
  }

  private static fileQuery(method: string, fid: string): Record<string, string> {
    const q: Record<string, string> = {};
    q['method'] = method;
    q['group_by'] = 'source';
    q['fid'] = fid;
    q['resolution'] = QuarkTvConst.RESOLUTIONS;
    q['support'] = 'dolby_vision';
    return q;
  }

  /** Original file link. AList/OpenList send no headers for it; we send the TV UA only. */
  async downloadLink(fid: string): Promise<QuarkLink> {
    const body = await this.call('/file', QuarkTvApi.fileQuery('download', fid));
    const r = JSON.parse(body) as QuarkTvDownloadResp;
    const url = r.data?.download_url ?? '';
    if (url.length === 0) {
      throw new QuarkError(0, 0, '未获取到下载地址');
    }
    const link = new QuarkLink();
    link.url = url;
    link.headers = QuarkTvApi.headers();
    return link;
  }

  /** Server transcodes via method=streaming (as in OpenList's "streaming" link method), best first. */
  async playQualities(fid: string): Promise<QuarkQuality[]> {
    const body = await this.call('/file', QuarkTvApi.fileQuery('streaming', fid));
    const r = JSON.parse(body) as QuarkTvStreamResp;
    return tvQualities(r.data?.video_info ?? []);
  }
}
