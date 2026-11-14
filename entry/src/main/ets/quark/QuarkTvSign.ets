// Pure request-signing and mapping helpers for the Quark TV-client api. No @kit imports: unit-tested under node.
// Protocol reimplemented from the behaviour of AList/OpenList drivers/quark_uc_tv (not copied).
import {
  QuarkFile, QuarkQuality, QuarkTvFileJson, QuarkTvVideoInfo, QuarkTvUserData, resolutionLabel, resolutionRank
} from './QuarkTypes';
import { htmlUnescape } from './CookieUtil';

export type HashFn = (input: string) => string;

export class QuarkTvConst {
  static readonly API: string = 'https://open-api-drive.quark.cn';
  /** Token exchange service. Also served over https (checked 2026-11-15), so no cleartext exception is needed. */
  static readonly CODE_API: string = 'https://api.extscreen.com/quarkdrive';
  static readonly CLIENT_ID: string = 'd3194e61504e493eb6222857bccfed94';
  static readonly SIGN_KEY: string = 'kw2dvtd7p4t3pjl2d9ed9yc8yej8kw2d';
  static readonly APP_VER: string = '1.5.6';
  static readonly CHANNEL: string = 'CP';
  static readonly UA: string = 'Mozilla/5.0 (Linux; U; Android 13; zh-cn; M2004J7AC Build/UKQ1.231108.001) ' +
    'AppleWebKit/533.1 (KHTML, like Gecko) Mobile Safari/533.1';
  static readonly DEVICE_BRAND: string = 'Xiaomi';
  static readonly PLATFORM: string = 'tv';
  static readonly DEVICE_MODEL: string = 'M2004J7AC';
  static readonly DEVICE_GPU: string = 'Adreno (TM) 550';
  static readonly ACTIVITY_RECT: string = '{}';
  static readonly PAGE_SIZE: number = 100;
  static readonly RESOLUTIONS: string = 'low,normal,high,super,2k,4k';
  /** errno of /oauth/code while the user has not confirmed on the phone ("用户未确认授权") */
  static readonly ERRNO_PENDING: number = 11003;
  static readonly QR_TIMEOUT_MS: number = 5 * 60 * 1000;
  static readonly QR_POLL_MS: number = 2000;
}

export class QuarkTvSignature {
  tm: string = '';
  token: string = '';
  reqId: string = '';
}

/** x-pan-tm / x-pan-token / req_id for one request. tm is a 13-digit ms timestamp string. */
export function signRequest(method: string, pathname: string, tm: string, deviceId: string, key: string,
  sha256Hex: HashFn, md5Hex: HashFn): QuarkTvSignature {
  const s = new QuarkTvSignature();
  s.tm = tm;
  s.token = sha256Hex(method.toUpperCase() + '&' + pathname + '&' + tm + '&' + key);
  s.reqId = md5Hex(deviceId + tm);
  return s;
}

/** Device fields shared by api queries and the token body. */
function deviceFields(out: Record<string, string>, deviceId: string): void {
  out['app_ver'] = QuarkTvConst.APP_VER;
  out['device_id'] = deviceId;
  out['device_brand'] = QuarkTvConst.DEVICE_BRAND;
  out['platform'] = QuarkTvConst.PLATFORM;
  out['device_name'] = QuarkTvConst.DEVICE_MODEL;
  out['device_model'] = QuarkTvConst.DEVICE_MODEL;
  out['build_device'] = QuarkTvConst.DEVICE_MODEL;
  out['build_product'] = QuarkTvConst.DEVICE_MODEL;
  out['device_gpu'] = QuarkTvConst.DEVICE_GPU;
  out['activity_rect'] = QuarkTvConst.ACTIVITY_RECT;
  out['channel'] = QuarkTvConst.CHANNEL;
}

/** Query every api call carries, followed by the call specific params (which win on clashes). */
export function apiQuery(sig: QuarkTvSignature, accessToken: string, deviceId: string,
  extra: Record<string, string>): Record<string, string> {
  const q: Record<string, string> = {};
  q['req_id'] = sig.reqId;
  q['access_token'] = accessToken;
  deviceFields(q, deviceId);
  Object.keys(extra).forEach((k: string) => {
    q[k] = extra[k];
  });
  return q;
}

/** JSON body for POST codeApi/token: exchange a login code, or refresh with a refresh token. */
export function tokenBody(reqId: string, deviceId: string, value: string, isRefresh: boolean): Record<string, string> {
  const b: Record<string, string> = {};
  b['req_id'] = reqId;
  deviceFields(b, deviceId);
  if (isRefresh) {
    b['refresh_token'] = value;
  } else {
    b['code'] = value;
  }
  return b;
}

/** "a=1&b=" with encodeURIComponent. Unlike Http.buildQuery, empty values are kept (the TV client sends them). */
export function encodeQuery(params: Record<string, string>): string {
  const parts: string[] = [];
  Object.keys(params).forEach((k: string) => {
    const v = params[k];
    parts.push(encodeURIComponent(k) + '=' + encodeURIComponent(v === undefined || v === null ? '' : v));
  });
  return parts.join('&');
}
/**
 * True when an error envelope means the access token expired / is invalid (refresh and retry once).
 * Observed: errno 11001 "Access Token无效"; AList also checks 10001.
 */
export function isTokenInvalid(status: number, errno: number, errorInfo: string): boolean {
  if (status === -1 && (errno === 10001 || errno === 11001)) {
    return true;
  }
  const s = errorInfo.trim().toLowerCase();
  return s.length > 0 && (s.indexOf('access token') >= 0 || s.indexOf('access_token') >= 0 ||
    s.indexOf('token无效') >= 0 || s.indexOf('token 无效') >= 0) && s.indexOf('refresh') < 0;
}

/** True when /oauth/code says the QR has not been confirmed yet (keep polling). */
export function isLoginPending(errno: number, errorInfo: string): boolean {
  return errno === QuarkTvConst.ERRNO_PENDING || errorInfo.indexOf('未确认') >= 0;
}

/** qr_data is base64 image data (observed PNG, AList assumes JPEG): build a data URI with the right subtype. */
export function qrDataUri(b64: string): string {
  const d = b64.trim();
  if (d.startsWith('data:')) {
    return d;
  }
  let sub = 'jpeg';
  if (d.startsWith('iVBOR')) {
    sub = 'png';
  } else if (d.startsWith('R0lG')) {
    sub = 'gif';
  }
  return 'data:image/' + sub + ';base64,' + d;
}

/** Map a TV list entry to the shared QuarkFile. updated_at is epoch ms. */
export function tvToFile(j: QuarkTvFileJson, parent: string): QuarkFile {
  const f = new QuarkFile();
  f.fid = j.fid ?? '';
  f.name = htmlUnescape(j.filename ?? '');
  f.parentFid = j.parent_fid ?? parent;
  f.isDir = j.isdir === 1;
  f.category = j.category ?? 0;
  f.size = j.size ?? 0;
  f.updatedAt = j.updated_at ?? j.created_at ?? 0;
  f.formatType = typeof j.file_type === 'string' ? j.file_type as string : '';
  f.thumbnail = j.thumbnail_url ?? '';
  f.duration = j.duration ?? 0;
  return f;
}

/** True when another page must be fetched (page_index is 0-based). */
export function hasMorePages(pageIndex: number, pageSize: number, got: number, total: number): boolean {
  if (got === 0) {
    return false;
  }
  return (pageIndex + 1) * pageSize < total;
}

/** Map method=streaming video_info to qualities, best first. Entries without url are dropped. */
export function tvQualities(list: QuarkTvVideoInfo[]): QuarkQuality[] {
  const out: QuarkQuality[] = [];
  list.forEach((v: QuarkTvVideoInfo) => {
    if (!v.url || v.accessable === 0) {
      return;
    }
    const q = new QuarkQuality();
    q.resolution = v.resolution ?? '';
    q.label = resolutionLabel(q.resolution);
    q.url = v.url;
    q.width = v.width ?? 0;
    q.height = v.height ?? 0;
    q.durationSec = v.duration ?? 0;
    out.push(q);
  });
  out.sort((a: QuarkQuality, c: QuarkQuality) => resolutionRank(a.resolution) - resolutionRank(c.resolution));
  return out;
}

export function tvNickname(d: QuarkTvUserData | undefined): string {
  if (d === undefined) {
    return '';
  }
  return d.nickname ?? d.nick_name ?? d.user_name ?? d.name ?? '';
}

/** 32-char hex device id, derived from a seed (time + random) through the injected md5. */
export function newDeviceId(seed: string, md5Hex: HashFn): string {
  return md5Hex(seed);
}
