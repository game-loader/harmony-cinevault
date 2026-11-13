// Pure subtitle parsing (SRT, WebVTT, ASS/SSA). No @kit imports: unit-tested under node.

export class SubtitleCue {
  startMs: number = 0;
  endMs: number = 0;
  text: string = '';
}

export type SubtitleFormat = 'srt' | 'vtt' | 'ass' | 'unknown';

/** Parse "hh:mm:ss,mmm", "mm:ss.mmm", "h:mm:ss.cc" (ASS centiseconds). Returns -1 when invalid. */
export function parseTimestamp(raw: string): number {
  const s = raw.trim().replace(',', '.');
  const m = /^(?:(\d+):)?(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?$/.exec(s);
  if (!m) {
    return -1;
  }
  const h = m[1] !== undefined ? parseInt(m[1], 10) : 0;
  const min = parseInt(m[2], 10);
  const sec = parseInt(m[3], 10);
  let frac = 0;
  if (m[4] !== undefined) {
    const f = m[4];
    frac = f.length === 1 ? parseInt(f, 10) * 100 : f.length === 2 ? parseInt(f, 10) * 10 : parseInt(f, 10);
  }
  return ((h * 60 + min) * 60 + sec) * 1000 + frac;
}

/** Remove HTML-ish tags used by SRT/VTT (<i>, <b>, <font>, <c.x>, <v Name>, timestamps) and decode basic entities. */
export function stripHtmlTags(text: string): string {
  return text.replace(/<[^>]*>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, '\'')
    .replace(/&amp;/g, '&');
}

/** ASS dialogue text: drop {\override} blocks, \N and \n -> newline, \h -> space. */
export function cleanAssText(text: string): string {
  return text.replace(/\{[^}]*\}/g, '')
    .replace(/\\N/g, '\n')
    .replace(/\\n/g, '\n')
    .replace(/\\h/g, ' ')
    .trim();
}

function normalizeNewlines(content: string): string {
  let c = content;
  if (c.length > 0 && c.charCodeAt(0) === 0xFEFF) {
    c = c.substring(1);
  }
  return c.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
}

export function detectFormat(content: string, hint: string): SubtitleFormat {
  const h = hint.toLowerCase();
  if (h.indexOf('ass') >= 0 || h.indexOf('ssa') >= 0) {
    return 'ass';
  }
  if (h.indexOf('vtt') >= 0) {
    return 'vtt';
  }
  if (h.indexOf('srt') >= 0 || h.indexOf('subrip') >= 0) {
    return 'srt';
  }
  const c = normalizeNewlines(content).trimStart();
  if (c.startsWith('WEBVTT')) {
    return 'vtt';
  }
  if (c.indexOf('[Script Info]') >= 0 || /^Dialogue:/m.test(c) || c.indexOf('[Events]') >= 0) {
    return 'ass';
  }
  if (/\d{1,2}:\d{2}:\d{2}[,.]\d{1,3}\s*-->/.test(c)) {
    return 'srt';
  }
  if (/\d{1,2}:\d{2}[,.]\d{1,3}\s*-->/.test(c)) {
    return 'vtt';
  }
  return 'unknown';
}

const ARROW_RE: RegExp = /^\s*([\d:.,]+)\s*-->\s*([\d:.,]+)/;

/** Shared SRT / WebVTT block parser: blocks split by blank lines, a timing line, then text lines. */
function parseTimedBlocks(content: string, isVtt: boolean): SubtitleCue[] {
  const cues: SubtitleCue[] = [];
  const blocks = normalizeNewlines(content).split(/\n\s*\n/);
  for (let b = 0; b < blocks.length; b++) {
    const lines = blocks[b].split('\n');
    let i = 0;
    while (i < lines.length && lines[i].trim().length === 0) {
      i++;
    }
    if (i >= lines.length) {
      continue;
    }
    if (isVtt) {
      const first = lines[i].trim();
      if (first.startsWith('WEBVTT') || first.startsWith('NOTE') || first === 'STYLE' || first === 'REGION' ||
        first.startsWith('STYLE ') || first.startsWith('REGION ')) {
        continue;
      }
    }
    // find timing line (cue identifier / sequence number may precede it)
    let t = -1;
    for (let k = i; k < lines.length && k <= i + 1; k++) {
      if (lines[k].indexOf('-->') >= 0) {
        t = k;
        break;
      }
    }
    if (t < 0) {
      continue;
    }
    const m = ARROW_RE.exec(lines[t]);
    if (!m) {
      continue;
    }
    const start = parseTimestamp(m[1]);
    const end = parseTimestamp(m[2]);
    if (start < 0 || end < 0) {
      continue;
    }
    const textLines: string[] = [];
    for (let k = t + 1; k < lines.length; k++) {
      const ln = stripHtmlTags(lines[k]).trim();
      if (ln.length > 0) {
        textLines.push(ln);
      }
    }
    if (textLines.length === 0) {
      continue;
    }
    const cue = new SubtitleCue();
    cue.startMs = start;
    cue.endMs = end;
    cue.text = textLines.join('\n');
    cues.push(cue);
  }
  return cues;
}

export function parseSrt(content: string): SubtitleCue[] {
  return sortCues(parseTimedBlocks(content, false));
}

export function parseVtt(content: string): SubtitleCue[] {
  return sortCues(parseTimedBlocks(content, true));
}

/** ASS/SSA: reads the [Events] Format line (defaults to the v4+ layout) and every Dialogue line. */
export function parseAss(content: string): SubtitleCue[] {
  const lines = normalizeNewlines(content).split('\n');
  let fields: string[] = ['layer', 'start', 'end', 'style', 'name', 'marginl', 'marginr', 'marginv', 'effect', 'text'];
  let inEvents = false;
  let sawSection = false;
  const cues: SubtitleCue[] = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.startsWith('[')) {
      sawSection = true;
      inEvents = line.toLowerCase() === '[events]';
      continue;
    }
    if (sawSection && !inEvents) {
      continue;
    }
    const lower = line.toLowerCase();
    if (lower.startsWith('format:')) {
      fields = line.substring(7).split(',').map((f: string) => f.trim().toLowerCase());
      continue;
    }
    if (!lower.startsWith('dialogue:')) {
      continue;
    }
    const body = line.substring(9).trimStart();
    // split into fields.length parts, the last (text) keeps its commas
    const parts: string[] = [];
    let rest = body;
    for (let f = 0; f < fields.length - 1; f++) {
      const idx = rest.indexOf(',');
      if (idx < 0) {
        break;
      }
      parts.push(rest.substring(0, idx).trim());
      rest = rest.substring(idx + 1);
    }
    parts.push(rest);
    if (parts.length < fields.length) {
      continue;
    }
    const si = fields.indexOf('start');
    const ei = fields.indexOf('end');
    const ti = fields.indexOf('text');
    if (si < 0 || ei < 0 || ti < 0) {
      continue;
    }
    const start = parseTimestamp(parts[si]);
    const end = parseTimestamp(parts[ei]);
    if (start < 0 || end < 0) {
      continue;
    }
    // drawing commands (\p1 .. \p0) are not text
    if (/\{[^}]*\\p[1-9][^}]*\}/.test(parts[ti])) {
      continue;
    }
    const text = cleanAssText(parts[ti]);
    if (text.length === 0) {
      continue;
    }
    const cue = new SubtitleCue();
    cue.startMs = start;
    cue.endMs = end;
    cue.text = text;
    cues.push(cue);
  }
  return mergeSameTime(sortCues(cues));
}

function sortCues(cues: SubtitleCue[]): SubtitleCue[] {
  return cues.sort((a: SubtitleCue, b: SubtitleCue) => a.startMs - b.startMs || a.endMs - b.endMs);
}

/** ASS often has several layers with identical timing; join them so one Text shows both. */
function mergeSameTime(cues: SubtitleCue[]): SubtitleCue[] {
  const out: SubtitleCue[] = [];
  for (let i = 0; i < cues.length; i++) {
    const c = cues[i];
    const last = out.length > 0 ? out[out.length - 1] : undefined;
    if (last !== undefined && last.startMs === c.startMs && last.endMs === c.endMs) {
      if (last.text !== c.text) {
        last.text = last.text + '\n' + c.text;
      }
    } else {
      out.push(c);
    }
  }
  return out;
}

/** Parse by format hint (codec / url extension) with content sniffing as fallback. */
export function parseSubtitle(content: string, hint: string): SubtitleCue[] {
  const fmt = detectFormat(content, hint);
  if (fmt === 'ass') {
    return parseAss(content);
  }
  if (fmt === 'vtt') {
    return parseVtt(content);
  }
  if (fmt === 'srt') {
    return parseSrt(content);
  }
  // unknown: try all, keep the best
  const a = parseSrt(content);
  if (a.length > 0) {
    return a;
  }
  return parseAss(content);
}

/** Text active at positionMs ('' if none). Overlapping cues are joined. Cues must be sorted by start. */
export function cueTextAt(cues: SubtitleCue[], positionMs: number): string {
  if (cues.length === 0) {
    return '';
  }
  // binary search last cue with start <= position
  let lo = 0;
  let hi = cues.length - 1;
  let idx = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (cues[mid].startMs <= positionMs) {
      idx = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  if (idx < 0) {
    return '';
  }
  const parts: string[] = [];
  // look back a bounded window for long overlapping cues
  for (let i = idx; i >= 0 && i >= idx - 20; i--) {
    const c = cues[i];
    if (c.startMs <= positionMs && positionMs < c.endMs) {
      parts.unshift(c.text);
    }
  }
  return parts.join('\n');
}

/** "mm:ss" or "h:mm:ss" */
export function formatDuration(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const ss = s < 10 ? '0' + s : '' + s;
  if (h > 0) {
    const mm = m < 10 ? '0' + m : '' + m;
    return h + ':' + mm + ':' + ss;
  }
  const mm2 = m < 10 ? '0' + m : '' + m;
  return mm2 + ':' + ss;
}
