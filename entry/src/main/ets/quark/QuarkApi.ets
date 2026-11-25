import { request, buildQuery, HttpError, HttpResponse, HttpMethod } from '../common/Http';
import { CookieUtil, htmlUnescape } from './CookieUtil';
import {
  QuarkConst, QuarkEnvelope, QuarkSortResp, QuarkFileJson, QuarkFile, QuarkDownloadResp, QuarkDownloadBody,
  QuarkPlayBody, QuarkPlayResp, QuarkVideoEntry, QuarkQuality, QuarkLink, QuarkError, QuarkAccountResp, resolutionLabel, resolutionRank,
  QuarkDrive
} from './QuarkTypes';
import { AppLog } from '../common/AppLog';

/** Cookies the server re-issues and that we merge back into the stored cookie. */
const ROLLING_COOKIES: string[] = ['__puus', '__pus'];

/**
 * Quark cloud drive HTTP client. Keeps the cookie up to date from Set-Cookie and notifies the owner
 * through onCookieChanged so it can be persisted.
 */
export class QuarkApi implements QuarkDrive {
  cookie: string;
  apiBase: string;
  onCookieChanged: ((cookie: string) => void) | undefined = undefined;
  private lastRefresh: number = 0;
  private refreshing: Promise<void> | undefined = undefined;

  constructor(cookie: string, apiBase: string = QuarkConst.API_PC) {
    this.cookie = cookie;
    this.apiBase = apiBase;
  }

  static baseHeaders(cookie: string): Record<string, string> {
    const h: Record<string, string> = {};
    h['Cookie'] = cookie;
    h['Accept'] = 'application/json, text/plain, */*';
    h['Referer'] = QuarkConst.REFERER;
    h['Origin'] = QuarkConst.ORIGIN;
    h['User-Agent'] = QuarkConst.UA;
    return h;
  }

  /** Headers the player must send with download / subtitle URLs. */
  static playHeaders(cookie: string): Record<string, string> {
    const h: Record<string, string> = {};
    h['Cookie'] = cookie;
    h['Referer'] = QuarkConst.REFERER;
    h['User-Agent'] = QuarkConst.UA;
    return h;
  }

  private mergeCookies(setCookies: string[]): void {
    if (setCookies.length === 0) {
      return;
    }
    const next = CookieUtil.applySetCookies(this.cookie, setCookies, ROLLING_COOKIES, Date.now());
    if (next !== this.cookie) {
      this.cookie = next;
      const cb = this.onCookieChanged;
      if (cb) {
        cb(next);
      }
    }
  }

  private static errorFromBody(status: number, body: string, fallback: string): QuarkError {
    let code = 0;
    let msg = fallback;
    let st = status;
    try {
      const e = JSON.parse(body) as QuarkEnvelope;
      if (e.code !== undefined) {
        code = e.code;
      }
      if (e.status !== undefined && e.status > 0) {
        st = e.status;
      }
      if (e.message) {
        msg = e.message;
      }
    } catch (err) {
      // non-json body
    }
    if (st === 401 || code === 31001 || msg === 'require login [guest]' || msg.indexOf('login') >= 0) {
      return new QuarkError(st, code, '夸克登录已失效，请重新登录');
    }
    if (st === 429) {
      return new QuarkError(st, code, '请求过于频繁，请稍后再试');
    }
    return new QuarkError(st, code, '夸克网盘: ' + msg);
  }

  /** Low-level call. path relative to apiBase; pr/fr are added automatically. */
  async call(method: HttpMethod, path: string, query: Record<string, string>, body: Object | undefined,
    cookieOverride?: string): Promise<string> {
    const q: Record<string, string> = {};
    q['pr'] = 'ucpro';
    q['fr'] = 'pc';
    Object.keys(query).forEach((k: string) => { q[k] = query[k]; });
    const url = this.apiBase + path + '?' + buildQuery(q);
    const cookie = cookieOverride !== undefined ? cookieOverride : this.cookie;
    const h = QuarkApi.baseHeaders(cookie);
    let payload: string | undefined = undefined;
    if (body !== undefined) {
      h['Content-Type'] = 'application/json;charset=UTF-8';
      payload = JSON.stringify(body);
    }
    let attempt = 0;
    while (true) {
      let res: HttpResponse;
      try {
        res = await request(method, url, h, payload);
      } catch (e) {
        const he = e as HttpError;
        const retryable = he.status === 0 || he.status === 429 || he.status >= 500;
        // only retry idempotent reads
        if (retryable && method === 'GET' && attempt < 2) {
          attempt++;
          await QuarkApi.sleep(600 * attempt * attempt);
          continue;
        }
        if (he.status === 0) {
          throw new QuarkError(0, 0, he.message);
        }
        throw QuarkApi.errorFromBody(he.status, he.body, he.message);
      }
      this.mergeCookies(res.setCookies);
      let env: QuarkEnvelope;
      try {
        env = (res.body.length > 0 ? JSON.parse(res.body) : {}) as QuarkEnvelope;
      } catch (err) {
        throw new QuarkError(res.status, 0, '夸克网盘返回了无法解析的数据');
      }
      const st = env.status !== undefined ? env.status : res.status;
      const code = env.code !== undefined ? env.code : 0;
      if (st >= 400 || code !== 0) {
        throw QuarkApi.errorFromBody(st, res.body, env.message ? env.message : ('错误码 ' + code));
      }
      return res.body;
    }
  }

  static noQuery(): Record<string, string> {
    const r: Record<string, string> = {};
    return r;
  }

  static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }

  static toFile(j: QuarkFileJson, parent: string): QuarkFile {
    const f = new QuarkFile();
    f.fid = j.fid ?? '';
    f.name = htmlUnescape(j.file_name ?? '');
    f.parentFid = j.pdir_fid ?? parent;
    // `file` true = regular file; fall back to file_type (0 = folder)
    if (j.file !== undefined) {
      f.isDir = !j.file;
    } else if (j.dir !== undefined) {
      f.isDir = j.dir;
    } else {
      f.isDir = j.file_type === 0;
    }
    f.category = j.category ?? 0;
    f.size = j.size ?? 0;
    const upd = j.l_updated_at ?? j.updated_at ?? 0;
    f.updatedAt = upd;
    f.formatType = j.format_type ?? '';
    f.thumbnail = j.big_thumbnail ?? j.thumbnail ?? '';
    f.duration = j.duration ?? 0;
    return f;
  }

  /** One page (1-based). Returns files and total count. */
  async listPage(pdirFid: string, page: number, size: number = QuarkConst.PAGE_SIZE): Promise<QuarkListPage> {
    const q: Record<string, string> = {};
    q['pdir_fid'] = pdirFid;
    q['_page'] = String(page);
    q['_size'] = String(size);
    q['_fetch_total'] = '1';
    q['_sort'] = 'file_type:asc,file_name:asc';
    q['fetch_all_file'] = '1';
    q['fetch_risk_file_name'] = '1';
    const body = await this.call('GET', '/file/sort', q, undefined);
    const r = JSON.parse(body) as QuarkSortResp;
    const out = new QuarkListPage();
    const list = r.data?.list ?? [];
    out.files = list.map((j: QuarkFileJson) => QuarkApi.toFile(j, pdirFid));
    out.total = r.metadata?._total ?? out.files.length;
    return out;
  }

  /** All entries of a folder (follows paging). */
  async listAll(pdirFid: string): Promise<QuarkFile[]> {
    const all: QuarkFile[] = [];
    let page = 1;
    while (true) {
      const p = await this.listPage(pdirFid, page);
      p.files.forEach((f: QuarkFile) => all.push(f));
      if (p.files.length === 0 || page * QuarkConst.PAGE_SIZE >= p.total) {
        break;
      }
      page++;
      if (page > 200) {
        break; // 20k entries: safety stop
      }
    }
    return all;
  }

  /** Original-quality download link. The returned headers carry the exact cookie the url was signed with. */
  async downloadLink(fid: string): Promise<QuarkLink> {
    const cookieSnap = this.cookie;
    const b = new QuarkDownloadBody();
    b.fids = [fid];
    const body = await this.call('POST', '/file/download', QuarkApi.noQuery(), b, cookieSnap);
    const r = JSON.parse(body) as QuarkDownloadResp;
    const d = r.data ?? [];
    if (d.length === 0 || !d[0].download_url) {
      throw new QuarkError(0, 0, '未获取到下载地址');
    }
    const link = new QuarkLink();
    link.url = d[0].download_url ?? '';
    link.headers = QuarkApi.playHeaders(cookieSnap);
    return link;
  }

  /** Transcoded qualities, best first. Empty when the file has no transcodes (non-video, too new, or not VIP). */
  async playQualities(fid: string): Promise<QuarkQuality[]> {
    const b = new QuarkPlayBody();
    b.fid = fid;
    const body = await this.call('POST', '/file/v2/play/project', QuarkApi.noQuery(), b);
    const r = JSON.parse(body) as QuarkPlayResp;
    const out: QuarkQuality[] = [];
    const list = r.data?.video_list ?? [];
    list.forEach((v: QuarkVideoEntry) => {
      const info = v.video_info;
      if (!info || !info.url) {
        return;
      }
      const q = new QuarkQuality();
      q.resolution = v.resolution ?? info.resolution ?? '';
      q.label = resolutionLabel(q.resolution);
      q.url = info.url;
      q.width = info.width ?? 0;
      q.height = info.height ?? 0;
      q.durationSec = info.duration ?? 0;
      out.push(q);
    });
    out.sort((a: QuarkQuality, c: QuarkQuality) => resolutionRank(a.resolution) - resolutionRank(c.resolution));
    return out;
  }

  /** Account nickname; throws when the cookie is not logged in. */
  async accountInfo(): Promise<string> {
    let res: HttpResponse;
    try {
      res = await request('GET', QuarkConst.ACCOUNT_INFO, QuarkApi.baseHeaders(this.cookie));
    } catch (e) {
      const he = e as HttpError;
      throw new QuarkError(he.status, 0, he.status === 0 ? he.message : '夸克登录已失效，请重新登录');
    }
    this.mergeCookies(res.setCookies);
    let r: QuarkAccountResp;
    try {
      r = JSON.parse(res.body) as QuarkAccountResp;
    } catch (err) {
      throw new QuarkError(res.status, 0, '账号信息解析失败');
    }
    const nick = r.data?.nickname ?? '';
    if (!r.data || (r.success === false) || nick.length === 0) {
      throw new QuarkError(401, 0, '未登录或 Cookie 已失效');
    }
    return nick;
  }

  authMode(): string {
    return 'cookie';
  }

  streamHeaders(): Record<string, string> {
    return QuarkApi.playHeaders(this.cookie);
  }

  accountName(): Promise<string> {
    return this.accountInfo();
  }

  /** Touch /config to validate the cookie for the drive api. */
  async config(): Promise<void> {
    await this.call('GET', '/config', QuarkApi.noQuery(), undefined);
  }

  /** Server only re-issues __puus when the request lacks it. */
  async refreshPuus(): Promise<void> {
    const stripped = CookieUtil.strip(this.cookie, ['__puus']);
    const before = CookieUtil.get(this.cookie, '__puus');
    await this.call('GET', '/config', QuarkApi.noQuery(), undefined, stripped);
    this.lastRefresh = Date.now();
    if (CookieUtil.get(this.cookie, '__puus') === before) {
      AppLog.info('[quark] __puus not re-issued, keeping existing value');
    }
  }

  /** Refresh __puus if it is older than the refresh interval. Never throws. */
  async ensureFresh(): Promise<void> {
    if (Date.now() - this.lastRefresh < QuarkConst.PUUS_REFRESH_MS) {
      return;
    }
    if (this.refreshing) {
      return this.refreshing;
    }
    this.refreshing = (async (): Promise<void> => {
      try {
        await this.refreshPuus();
      } catch (e) {
        AppLog.warn('[quark] refresh __puus failed: ' + (e as Error).message);
        this.lastRefresh = Date.now() - QuarkConst.PUUS_REFRESH_MS + 5 * 60 * 1000; // retry in 5 min
      } finally {
        this.refreshing = undefined;
      }
    })();
    return this.refreshing;
  }
}

export class QuarkListPage {
  files: QuarkFile[] = [];
  total: number = 0;
}
