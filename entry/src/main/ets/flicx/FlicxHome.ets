// Parses the rails on the server-rendered fli.cx home page. Flicx has no JSON home endpoint,
// so all markup assumptions live here and an unrecognised page yields no rows instead of throwing.
import { HomeRow, Person } from '../common/Models';
import { FlicxTitleItem } from './FlicxModels';
import { FlicxMapper, FLICX_ID } from './FlicxMapper';

const ROW_NAMES: Record<string, string> = {
  'trending this week': '本周热门电影',
  'trending tv this week': '本周热门剧集',
  'trending today': '今日热门电影',
  'trending tv today': '今日热门剧集',
  'top drama': '高分剧情片',
  'just added': '最新上架',
  'in 4k': '4K 专区',
  'all-time greats': '影史经典',
  'oscar winners': '奥斯卡获奖影片',
  'series': '剧集',
  'science fiction': '科幻',
  'horror': '恐怖',
  'comedy': '喜剧',
  'action': '动作',
  'animation': '动画',
  'thriller': '惊悚',
  'romance': '爱情',
  'documentary': '纪录片',
  'crime': '犯罪',
  'family': '家庭'
};

const ENTITIES: Record<string, string> = {
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' '
};

export function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/g, (whole: string, code: string): string => {
    if (code.startsWith('#x') || code.startsWith('#X')) {
      const n = parseInt(code.slice(2), 16);
      return Number.isFinite(n) && n > 0 && n < 0x110000 ? String.fromCodePoint(n) : whole;
    }
    if (code.startsWith('#')) {
      const n = parseInt(code.slice(1), 10);
      return Number.isFinite(n) && n > 0 && n < 0x110000 ? String.fromCodePoint(n) : whole;
    }
    const v = ENTITIES[code.toLowerCase()];
    return v !== undefined ? v : whole;
  });
}

function text(html: string): string {
  return decodeEntities(html.replace(/<[^>]*>/g, ' ')).replace(/\s+/g, ' ').trim();
}

function attrs(tag: string): Map<string, string> {
  const out = new Map<string, string>();
  const re = /([a-zA-Z_:][-a-zA-Z0-9_:.]*)="([^"]*)"/g;
  let m: RegExpExecArray | null = re.exec(tag);
  while (m !== null) {
    out.set(m[1].toLowerCase(), decodeEntities(m[2]));
    m = re.exec(tag);
  }
  return out;
}

function spanText(card: string, cls: string): string {
  const m = new RegExp('<span[^>]*class="' + cls + '"[^>]*>([\\s\\S]*?)</span>').exec(card);
  return m !== null ? text(m[1]) : '';
}

export function rowTitle(label: string): string {
  const key = label.trim().toLowerCase();
  const known = ROW_NAMES[key];
  if (known !== undefined) {
    return known;
  }
  if (key.startsWith('released on ')) {
    return '历史上的今天';
  }
  if (key.startsWith('top ')) {
    const genre = ROW_NAMES[key.slice(4)];
    if (genre !== undefined) {
      return '高分' + genre;
    }
  }
  return label.trim();
}

export class FlicxHome {
  static readonly MAX_ROWS: number = 16;
  static readonly MAX_ITEMS: number = 30;

  /** One card (`<div role="listitem">…`) to a title, or undefined when it lacks an IMDb poster or a title link. */
  static card(html: string): FlicxTitleItem | undefined {
    const poster = /\/a\/poster\/(?:small|medium|large|original)\/(tt[0-9]{7,12})\/img/.exec(html);
    const link = /<a\b[^>]*class="card-link"[^>]*>/.exec(html);
    if (poster === null || link === null) {
      return undefined;
    }
    const a = attrs(link[0]);
    const href = /^\/(movie|tv)\/([^/?#"]+)$/.exec(a.get('href') ?? '');
    if (href === null) {
      return undefined;
    }
    const series = href[1] === 'tv';
    const label = a.get('aria-label') ?? '';
    const yearInLabel = /\s\(([0-9]{4})\)$/.exec(label);
    const title = (yearInLabel !== null ? label.slice(0, yearInLabel.index) : label).trim() ||
      spanText(html, 'card-over-title');
    if (!title) {
      return undefined;
    }
    const item = new FlicxTitleItem();
    item.imdbId = poster[1];
    item.id = FlicxMapper.mediaId(series ? 'tv' : 'movie', item.imdbId);
    item.sourceId = FLICX_ID;
    item.type = series ? 'series' : 'movie';
    item.slug = href[2];
    item.title = title;
    const year = Number(spanText(html, 'card-over-year') || (yearInLabel !== null ? yearInLabel[1] : ''));
    item.year = Number.isInteger(year) && year > 1800 && year < 3000 ? year : 0;
    const score = /aria-label="Rated ([0-9]+(?:\.[0-9]+)?) out of 10"/.exec(html);
    item.rating = score !== null ? Number(score[1]) : 0;
    const genre = /<(?:span|a)\b[^>]*class="card-over-genre"[^>]*>([\s\S]*?)<\/(?:span|a)>/.exec(html);
    item.genres = genre !== null && text(genre[1]) ? [text(genre[1])] : [];
    item.images.poster = 'https://s.fli.cx/a/poster/medium/' + item.imdbId + '/img';
    item.images.backdrop = FlicxMapper.absoluteUrl(a.get('data-still'));
    return item;
  }

  /** Home page rails in page order; empty rails, duplicates and unparseable cards are dropped. */
  static parse(html: string): HomeRow[] {
    const rows: HomeRow[] = [];
    if (typeof html !== 'string' || html.length === 0) {
      return rows;
    }
    const re = /<div\b[^>]*role="list"[^>]*aria-label="([^"]*)"[^>]*>/g;
    const starts: number[] = [];
    const labels: string[] = [];
    let m: RegExpExecArray | null = re.exec(html);
    while (m !== null) {
      starts.push(m.index + m[0].length);
      labels.push(decodeEntities(m[1]));
      m = re.exec(html);
    }
    for (let i = 0; i < starts.length && rows.length < FlicxHome.MAX_ROWS; i++) {
      let end = i + 1 < starts.length ? starts[i + 1] : html.length;
      const close = html.indexOf('</section>', starts[i]);
      if (close >= 0 && close < end) {
        end = close;
      }
      const parts = html.slice(starts[i], end).split('role="listitem"');
      const row = new HomeRow();
      row.key = 'flicx:' + rows.length + ':' + labels[i].toLowerCase().replace(/[^a-z0-9]+/g, '-');
      row.title = rowTitle(labels[i]);
      row.style = 'poster';
      const seen = new Set<string>();
      for (let k = 1; k < parts.length && row.items.length < FlicxHome.MAX_ITEMS; k++) {
        const item = FlicxHome.card(parts[k]);
        if (item !== undefined && !seen.has(item.id)) {
          seen.add(item.id);
          row.items.push(item);
        }
      }
      if (row.items.length > 0) {
        rows.push(row);
      }
    }
    return rows;
  }
}

// ---------- title page (schema.org JSON-LD) ----------

interface LdThing {
  name?: string;
}

interface LdTitle {
  /** schema.org "@type", renamed before parsing (ArkTS has no indexed field access). */
  ldType?: string;
  description?: string;
  datePublished?: string;
  startDate?: string;
  duration?: string;
  genre?: string[] | string;
  contentRating?: string;
  director?: LdThing[];
  creator?: LdThing[];
  actor?: LdThing[];
  productionCompany?: LdThing[];
  image?: string[] | string;
}

export class FlicxTitlePage {
  overview: string = '';
  premiereDate: string = '';
  runtimeMs: number = 0;
  genres: string[] = [];
  officialRating: string = '';
  directors: string[] = [];
  actors: string[] = [];
  studios: string[] = [];
  backdrop: string = '';
  /** Cast/Crew rails with photos: key crew (director, writer) first, then cast in billing order. */
  people: Person[] = [];
}

const CREW_ROLES: Record<string, string> = {
  'director': '导演', 'directing': '导演', 'creator': '主创', 'writer': '编剧', 'screenplay': '编剧',
  'writing': '编剧', 'story': '故事', 'novel': '原著', 'producer': '制片', 'executive producer': '监制',
  'music': '配乐', 'original music composer': '配乐', 'director of photography': '摄影', 'cinematography': '摄影',
  'editor': '剪辑', 'editing': '剪辑', 'production design': '美术', 'costumes': '服装', 'costume design': '服装',
  'casting': '选角'
};
const KEY_CREW: string[] = ['导演', '主创', '编剧', '原著'];

function rail(html: string, label: string): string {
  const i = html.indexOf('role="list" aria-label="' + label + '"');
  if (i < 0) {
    return '';
  }
  const end = html.indexOf('</section>', i);
  return html.slice(i, end > i ? end : html.length);
}

function railPeople(seg: string, crew: boolean): Person[] {
  const out: Person[] = [];
  const re = /<a\b[^>]*class="person"[^>]*>([\s\S]*?)<\/a>/g;
  let m: RegExpExecArray | null = re.exec(seg);
  while (m !== null) {
    const body = m[1];
    const p = new Person();
    p.name = spanDiv(body, 'person-name');
    const role = spanDiv(body, 'person-role');
    // crew roles can be combined: "Director · Writer · Producer" -> "导演 / 编剧 / 制片"
    p.role = crew ? role.split(/\s*[·,\/]\s*/).filter((r: string) => r.length > 0)
      .map((r: string) => CREW_ROLES[r.toLowerCase()] ?? r).join(' / ') : role;
    const img = /<img\b[^>]*\bsrc="([^"]+)"/.exec(body);
    p.image = img !== null ? FlicxMapper.absoluteUrl(decodeEntities(img[1])) : '';
    if (p.name) {
      out.push(p);
    }
    m = re.exec(seg);
  }
  return out;
}

function spanDiv(html: string, cls: string): string {
  const m = new RegExp('<(?:div|span)[^>]*class="' + cls + '"[^>]*>([\\s\\S]*?)</(?:div|span)>').exec(html);
  return m !== null ? text(m[1]) : '';
}

/** Key crew first (director/creator/writer), then cast; one entry per person, at most 30. */
export function titlePeople(html: string): Person[] {
  const crew = railPeople(rail(html, 'Crew'), true)
    .filter((p: Person) => p.role.split(' / ').some((r: string) => KEY_CREW.indexOf(r) >= 0));
  const cast = railPeople(rail(html, 'Cast'), false);
  const out: Person[] = [];
  const seen = new Set<string>();
  for (const p of crew.concat(cast)) {
    const k = p.name + '|' + p.role;
    if (!seen.has(k) && out.length < 30) {
      seen.add(k);
      out.push(p);
    }
  }
  return out;
}

function names(list: LdThing[] | undefined, max: number): string[] {
  if (!Array.isArray(list)) {
    return [];
  }
  return list.map((p: LdThing) => typeof p?.name === 'string' ? p.name.trim() : '')
    .filter((n: string) => n.length > 0).slice(0, max);
}

/** Synopsis and credits from a /movie/<slug> or /tv/<slug> page; undefined when no Movie/TVSeries block is found. */
export function parseTitlePage(html: string): FlicxTitlePage | undefined {
  if (typeof html !== 'string') {
    return undefined;
  }
  const re = /<script type="application\/ld\+json">([\s\S]*?)<\/script>/g;
  let m: RegExpExecArray | null = re.exec(html);
  while (m !== null) {
    let ld: LdTitle | undefined = undefined;
    try {
      ld = JSON.parse(m[1].replace(/"@type"\s*:/g, '"ldType":')) as LdTitle;
    } catch (e) {
      ld = undefined;
    }
    if (ld !== undefined && ld !== null && (ld.ldType === 'Movie' || ld.ldType === 'TVSeries')) {
      const page = new FlicxTitlePage();
      page.overview = typeof ld.description === 'string' ? ld.description.trim() : '';
      const date = typeof ld.datePublished === 'string' ? ld.datePublished : (ld.startDate ?? '');
      page.premiereDate = /^[0-9]{4}-[0-9]{2}-[0-9]{2}/.test(date) ? date.slice(0, 10) : '';
      const dur = /^PT(?:([0-9]+)H)?(?:([0-9]+)M)?$/.exec(typeof ld.duration === 'string' ? ld.duration : '');
      if (dur !== null) {
        page.runtimeMs = ((Number(dur[1] ?? '0') * 60) + Number(dur[2] ?? '0')) * 60000;
      }
      const g = ld.genre;
      page.genres = Array.isArray(g) ? g.filter((x: string) => typeof x === 'string') : (typeof g === 'string' ? [g] : []);
      page.officialRating = typeof ld.contentRating === 'string' ? ld.contentRating : '';
      page.directors = names(ld.ldType === 'Movie' ? ld.director : ld.creator, 3);
      page.actors = names(ld.actor, 12);
      page.studios = names(ld.productionCompany, 3);
      const imgs: string[] = Array.isArray(ld.image) ? ld.image : (typeof ld.image === 'string' ? [ld.image] : []);
      page.backdrop = imgs.find((u: string) => typeof u === 'string' && u.indexOf('/background/') >= 0) ?? '';
      page.people = titlePeople(html);
      return page;
    }
    m = re.exec(html);
  }
  return undefined;
}
