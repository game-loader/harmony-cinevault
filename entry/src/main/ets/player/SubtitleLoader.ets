import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { SubtitleCue, parseSubtitle } from './SubtitleParser';

/** Decode subtitle bytes: UTF-8 (BOM aware, strict) first, then GB18030 (common for Chinese .srt/.ass), then UTF-16. */
export function decodeSubtitleBytes(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf);
  if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
    return util.TextDecoder.create('utf-16le', { ignoreBOM: true }).decodeToString(bytes.subarray(2));
  }
  if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
    return util.TextDecoder.create('utf-16be', { ignoreBOM: true }).decodeToString(bytes.subarray(2));
  }
  try {
    return util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: true }).decodeToString(bytes);
  } catch (e) {
    try {
      return util.TextDecoder.create('gb18030', { ignoreBOM: true }).decodeToString(bytes);
    } catch (e2) {
      return util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(bytes);
    }
  }
}

/** Download an external subtitle (with the playback headers) and parse it. Throws Error with a Chinese message. */
export async function loadSubtitle(url: string, headers: Record<string, string>, hint: string): Promise<SubtitleCue[]> {
  const req = http.createHttp();
  try {
    const opts: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 15000,
      readTimeout: 30000,
      usingCache: true
    };
    const r = await req.request(url, opts);
    if (r.responseCode >= 400) {
      throw new Error(`字幕下载失败 (HTTP ${r.responseCode})`);
    }
    let text = '';
    if (r.result instanceof ArrayBuffer) {
      text = decodeSubtitleBytes(r.result as ArrayBuffer);
    } else if (typeof r.result === 'string') {
      text = r.result as string;
    }
    const cues = parseSubtitle(text, hint + ' ' + url);
    if (cues.length === 0) {
      throw new Error('字幕格式不支持或内容为空');
    }
    return cues;
  } catch (e) {
    if (e instanceof Error && (e as Error).message.startsWith('字幕')) {
      throw e as Error;
    }
    const be = e as BusinessError;
    throw new Error('字幕下载失败: ' + (be.message ?? String(e)));
  } finally {
    req.destroy();
  }
}
