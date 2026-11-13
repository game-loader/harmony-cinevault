import { http } from '@kit.NetworkKit';

export class HttpResponse {
  status: number = 0;
  body: string = '';
  headers: Record<string, string> = {};
  /** Raw Set-Cookie header values, if any */
  setCookies: string[] = [];
}

export class HttpError extends Error {
  status: number;
  body: string;
  constructor(status: number, body: string, message: string) {
    super(message);
    this.status = status;
    this.body = body;
  }
}

export type HttpMethod = 'GET' | 'POST' | 'DELETE' | 'PUT';

function toMethod(m: HttpMethod): http.RequestMethod {
  switch (m) {
    case 'POST': return http.RequestMethod.POST;
    case 'DELETE': return http.RequestMethod.DELETE;
    case 'PUT': return http.RequestMethod.PUT;
    default: return http.RequestMethod.GET;
  }
}

/** Build "a=1&b=2" with encodeURIComponent. Empty values are skipped. */
export function buildQuery(params: Record<string, string>): string {
  const parts: string[] = [];
  Object.keys(params).forEach((k: string) => {
    const v = params[k];
    if (v !== undefined && v !== null && v !== '') {
      parts.push(encodeURIComponent(k) + '=' + encodeURIComponent(v));
    }
  });
  return parts.join('&');
}

export function joinUrl(base: string, path: string): string {
  const b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  const p = path.startsWith('/') ? path : '/' + path;
  return b + p;
}

/**
 * Thin wrapper over @kit.NetworkKit http. Body may be a string (sent as-is) or undefined.
 * Throws HttpError for status >= 400 or network failure (status 0).
 */
export async function request(method: HttpMethod, url: string, headers: Record<string, string>,
  body?: string, timeoutMs: number = 20000): Promise<HttpResponse> {
  const req = http.createHttp();
  try {
    const opts: http.HttpRequestOptions = {
      method: toMethod(method),
      header: headers,
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: timeoutMs,
      readTimeout: timeoutMs * 3,
      usingCache: false
    };
    const r = await req.request(url, opts);
    const res = new HttpResponse();
    res.status = r.responseCode;
    res.body = typeof r.result === 'string' ? r.result as string : '';
    const hdr = r.header as Record<string, Object>;
    if (hdr) {
      Object.keys(hdr).forEach((k: string) => {
        res.headers[k.toLowerCase()] = String(hdr[k]);
      });
    }
    if (r.cookies) {
      res.setCookies = r.cookies.split('\r\n').filter((c: string) => c.length > 0);
    }
    if (res.status >= 400) {
      throw new HttpError(res.status, res.body, `HTTP ${res.status}`);
    }
    return res;
  } catch (e) {
    if (e instanceof HttpError) {
      throw e;
    }
    const err = e as Error;
    throw new HttpError(0, '', '网络错误: ' + (err.message ?? String(e)));
  } finally {
    req.destroy();
  }
}

export async function getJson<T>(url: string, headers: Record<string, string>): Promise<T> {
  const r = await request('GET', url, headers);
  return JSON.parse(r.body) as T;
}

export async function postJson<T>(url: string, headers: Record<string, string>, body: Object): Promise<T> {
  const h: Record<string, string> = {};
  Object.keys(headers).forEach((k: string) => { h[k] = headers[k]; });
  h['Content-Type'] = 'application/json';
  const r = await request('POST', url, h, JSON.stringify(body));
  return (r.body.length > 0 ? JSON.parse(r.body) : {}) as T;
}
