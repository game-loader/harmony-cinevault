import { relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { MediaItem, QueryOptions, PagedItems, UserState, MediaType, ImageSet, Person } from '../common/Models';
import { AppContext } from '../common/AppContext';

/** A video file in a Quark source, linked to a scraped MediaItem. */
export class LocalFile {
  sourceId: string = '';
  fid: string = '';
  parentFid: string = '';
  path: string = '';          // display path relative to library root
  name: string = '';
  size: number = 0;
  updatedAt: number = 0;
  itemId: string = '';        // MediaItem.id (movie or episode) it was matched to, '' if unmatched
}

const DB_VERSION: number = 1;

const DDL: string[] = [
  'CREATE TABLE IF NOT EXISTS items (source_id TEXT NOT NULL, id TEXT NOT NULL, type TEXT NOT NULL, ' +
    'parent_id TEXT NOT NULL DEFAULT \'\', title TEXT NOT NULL DEFAULT \'\', original_title TEXT NOT NULL DEFAULT \'\', ' +
    'sort_title TEXT NOT NULL DEFAULT \'\', year INTEGER NOT NULL DEFAULT 0, premiere TEXT NOT NULL DEFAULT \'\', ' +
    'rating REAL NOT NULL DEFAULT 0, season_no INTEGER NOT NULL DEFAULT -1, episode_no INTEGER NOT NULL DEFAULT -1, ' +
    'series_id TEXT NOT NULL DEFAULT \'\', genres TEXT NOT NULL DEFAULT \'\', added_at INTEGER NOT NULL DEFAULT 0, ' +
    'json TEXT NOT NULL, PRIMARY KEY (source_id, id))',
  'CREATE INDEX IF NOT EXISTS idx_items_parent ON items(source_id, parent_id)',
  'CREATE INDEX IF NOT EXISTS idx_items_type ON items(source_id, type)',
  'CREATE INDEX IF NOT EXISTS idx_items_series ON items(source_id, series_id)',
  'CREATE TABLE IF NOT EXISTS files (source_id TEXT NOT NULL, fid TEXT NOT NULL, parent_fid TEXT NOT NULL DEFAULT \'\', ' +
    'path TEXT NOT NULL DEFAULT \'\', name TEXT NOT NULL DEFAULT \'\', size INTEGER NOT NULL DEFAULT 0, ' +
    'updated_at INTEGER NOT NULL DEFAULT 0, item_id TEXT NOT NULL DEFAULT \'\', PRIMARY KEY (source_id, fid))',
  'CREATE INDEX IF NOT EXISTS idx_files_item ON files(source_id, item_id)',
  'CREATE TABLE IF NOT EXISTS states (source_id TEXT NOT NULL, item_id TEXT NOT NULL, played INTEGER NOT NULL DEFAULT 0, ' +
    'favorite INTEGER NOT NULL DEFAULT 0, position_ms INTEGER NOT NULL DEFAULT 0, play_count INTEGER NOT NULL DEFAULT 0, ' +
    'last_played INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (source_id, item_id))'
];

/** JSON shape of a stored MediaItem (all optional so old rows still load). */
interface StoredImages {
  poster?: string;
  backdrop?: string;
  logo?: string;
  thumb?: string;
}

interface StoredPerson {
  name?: string;
  role?: string;
  image?: string;
}

interface StoredItem {
  sourceId?: string;
  id?: string;
  type?: string;
  title?: string;
  originalTitle?: string;
  overview?: string;
  year?: number;
  premiereDate?: string;
  rating?: number;
  officialRating?: string;
  runtimeMs?: number;
  genres?: string[];
  studios?: string[];
  tags?: string[];
  people?: StoredPerson[];
  images?: StoredImages;
  seriesId?: string;
  seriesTitle?: string;
  seasonId?: string;
  seasonNumber?: number;
  episodeNumber?: number;
  childCount?: number;
  tmdbId?: string;
  imdbId?: string;
  container?: string;
  width?: number;
  height?: number;
}

const ITEM_COLS: string = 'i.json, IFNULL(s.played,0) AS played, IFNULL(s.favorite,0) AS favorite, ' +
  'IFNULL(s.position_ms,0) AS position_ms, IFNULL(s.play_count,0) AS play_count, IFNULL(s.last_played,0) AS last_played';
const ITEM_FROM: string = ' FROM items i LEFT JOIN states s ON s.source_id = i.source_id AND s.item_id = i.id ';
/** Episode counts for container rows (series by series_id, season by parent_id). */
const CHILD_COLS: string = ', CASE WHEN i.type IN (\'series\',\'season\') THEN (SELECT COUNT(*) FROM items c WHERE ' +
  'c.source_id = i.source_id AND c.type = \'episode\' AND (c.series_id = i.id OR c.parent_id = i.id)) ELSE 0 END AS ep_count, ' +
  'CASE WHEN i.type IN (\'series\',\'season\') THEN (SELECT COUNT(*) FROM items c LEFT JOIN states cs ON ' +
  'cs.source_id = c.source_id AND cs.item_id = c.id WHERE c.source_id = i.source_id AND c.type = \'episode\' AND ' +
  '(c.series_id = i.id OR c.parent_id = i.id) AND IFNULL(cs.played,0) = 0) ELSE 0 END AS ep_unplayed';

const SELECT_ITEMS: string = 'SELECT ' + ITEM_COLS + CHILD_COLS + ITEM_FROM;

/** Played expression usable in WHERE: containers count as played when all episodes are. */
const PLAYED_EXPR: string = '(CASE WHEN i.type IN (\'series\',\'season\') THEN (NOT EXISTS (SELECT 1 FROM items c ' +
  'LEFT JOIN states cs ON cs.source_id = c.source_id AND cs.item_id = c.id WHERE c.source_id = i.source_id AND ' +
  'c.type = \'episode\' AND (c.series_id = i.id OR c.parent_id = i.id) AND IFNULL(cs.played,0) = 0)) ' +
  'ELSE IFNULL(s.played,0) END)';

function strArr(a: string[] | undefined): string[] {
  return a !== undefined && a !== null ? a.filter((x: string) => typeof x === 'string') : [];
}

function s0(v: string | undefined): string {
  return v !== undefined && v !== null ? v : '';
}

function n0(v: number | undefined, d: number): number {
  return v !== undefined && v !== null && !isNaN(v) ? v : d;
}

function toType(t: string | undefined): MediaType {
  switch (t) {
    case 'movie':
    case 'series':
    case 'season':
    case 'episode':
    case 'folder':
    case 'collection':
    case 'video':
      return t as MediaType;
    default:
      return 'video';
  }
}

function itemFromJson(json: string): MediaItem {
  const o = JSON.parse(json) as StoredItem;
  const m = new MediaItem();
  m.sourceId = s0(o.sourceId);
  m.id = s0(o.id);
  m.type = toType(o.type);
  m.title = s0(o.title);
  m.originalTitle = s0(o.originalTitle);
  m.overview = s0(o.overview);
  m.year = n0(o.year, 0);
  m.premiereDate = s0(o.premiereDate);
  m.rating = n0(o.rating, 0);
  m.officialRating = s0(o.officialRating);
  m.runtimeMs = n0(o.runtimeMs, 0);
  m.genres = strArr(o.genres);
  m.studios = strArr(o.studios);
  m.tags = strArr(o.tags);
  m.people = (o.people !== undefined && o.people !== null ? o.people : []).map((p: StoredPerson) => {
    const r = new Person();
    r.name = s0(p.name);
    r.role = s0(p.role);
    r.image = s0(p.image);
    return r;
  });
  const img = new ImageSet();
  if (o.images !== undefined && o.images !== null) {
    img.poster = s0(o.images.poster);
    img.backdrop = s0(o.images.backdrop);
    img.logo = s0(o.images.logo);
    img.thumb = s0(o.images.thumb);
  }
  m.images = img;
  m.seriesId = s0(o.seriesId);
  m.seriesTitle = s0(o.seriesTitle);
  m.seasonId = s0(o.seasonId);
  m.seasonNumber = n0(o.seasonNumber, -1);
  m.episodeNumber = n0(o.episodeNumber, -1);
  m.childCount = n0(o.childCount, 0);
  m.tmdbId = s0(o.tmdbId);
  m.imdbId = s0(o.imdbId);
  m.container = s0(o.container);
  m.width = n0(o.width, 0);
  m.height = n0(o.height, 0);
  return m;
}

/** Sort key: lowercase, leading articles dropped, so "The Matrix" sorts under M. */
export function sortTitleOf(t: string): string {
  return t.trim().toLowerCase().replace(new RegExp('^(?:the|a|an)\\s+'), '');
}

function escapeLike(s: string): string {
  return s.replace(new RegExp('[\\\\%_]', 'g'), (c: string) => '\\' + c);
}

function errMsg(e: Object): string {
  const be = e as BusinessError;
  return be.message !== undefined ? be.message + (be.code !== undefined ? ' (' + be.code + ')' : '') : String(e);
}

/** Effective "date added": containers use their newest episode so new episodes bubble the show up. */
const ADDED_EXPR: string = '(CASE WHEN i.type IN (\'series\',\'season\') THEN IFNULL((SELECT MAX(c.added_at) FROM items c ' +
  'WHERE c.source_id = i.source_id AND c.type = \'episode\' AND (c.series_id = i.id OR c.parent_id = i.id)), i.added_at) ' +
  'ELSE i.added_at END)';
const PLAYED_AT_EXPR: string = '(CASE WHEN i.type IN (\'series\',\'season\') THEN IFNULL((SELECT MAX(cs.last_played) FROM items c ' +
  'JOIN states cs ON cs.source_id = c.source_id AND cs.item_id = c.id WHERE c.source_id = i.source_id AND ' +
  'c.type = \'episode\' AND (c.series_id = i.id OR c.parent_id = i.id)), 0) ELSE IFNULL(s.last_played,0) END)';

class SqlWhere {
  clauses: string[] = [];
  args: relationalStore.ValueType[] = [];

  add(clause: string, args: relationalStore.ValueType[]): void {
    this.clauses.push(clause);
    args.forEach((a: relationalStore.ValueType) => this.args.push(a));
  }

  sql(): string {
    return this.clauses.length > 0 ? ' WHERE ' + this.clauses.join(' AND ') : '';
  }
}

/**
 * OWNER: scraper agent. Local catalogue for Quark sources (relationalStore 'library.db').
 * MediaItem rows are stored with sourceId; ids are stable strings, e.g. 'tmdb-movie-603',
 * 'tmdb-tv-1399', 'tmdb-tv-1399-s1', 'tmdb-tv-1399-s1e2', or 'file-<fid>' for unmatched videos.
 */
export class LibraryDb {
  private static store: relationalStore.RdbStore | undefined = undefined;
  private static opening: Promise<relationalStore.RdbStore> | undefined = undefined;

  static async open(): Promise<void> {
    await LibraryDb.db();
  }

  private static async db(): Promise<relationalStore.RdbStore> {
    if (LibraryDb.store !== undefined) {
      return LibraryDb.store;
    }
    if (LibraryDb.opening === undefined) {
      LibraryDb.opening = LibraryDb.doOpen();
      LibraryDb.opening.catch(() => {
        LibraryDb.opening = undefined;
      });
    }
    return LibraryDb.opening;
  }

  private static async doOpen(): Promise<relationalStore.RdbStore> {
    try {
      const cfg: relationalStore.StoreConfig = {
        name: 'library.db',
        securityLevel: relationalStore.SecurityLevel.S1
      };
      const st = await relationalStore.getRdbStore(AppContext.get(), cfg);
      for (let i = 0; i < DDL.length; i++) {
        await st.executeSql(DDL[i]);
      }
      if (st.version < DB_VERSION) {
        st.version = DB_VERSION;
      }
      LibraryDb.store = st;
      return st;
    } catch (e) {
      throw new Error('打开本地媒体库失败：' + errMsg(e as Object));
    }
  }

  private static async rows<T>(sql: string, args: relationalStore.ValueType[],
    map: (rs: relationalStore.ResultSet) => T): Promise<T[]> {
    const st = await LibraryDb.db();
    const rs = await st.querySql(sql, args);
    const out: T[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push(map(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  private static async exec(sql: string, args: relationalStore.ValueType[]): Promise<void> {
    const st = await LibraryDb.db();
    await st.executeSql(sql, args);
  }

  private static async count(sql: string, args: relationalStore.ValueType[]): Promise<number> {
    const r = await LibraryDb.rows<number>(sql, args, (rs: relationalStore.ResultSet) => rs.getLong(0));
    return r.length > 0 ? r[0] : 0;
  }

  private static mapItem(rs: relationalStore.ResultSet): MediaItem {
    const m = itemFromJson(rs.getString(rs.getColumnIndex('json')));
    const st = new UserState();
    st.favorite = rs.getLong(rs.getColumnIndex('favorite')) !== 0;
    st.positionMs = rs.getLong(rs.getColumnIndex('position_ms'));
    st.playCount = rs.getLong(rs.getColumnIndex('play_count'));
    st.lastPlayed = rs.getLong(rs.getColumnIndex('last_played'));
    st.played = rs.getLong(rs.getColumnIndex('played')) !== 0;
    if (m.type === 'series' || m.type === 'season') {
      const total = rs.getLong(rs.getColumnIndex('ep_count'));
      const unplayed = rs.getLong(rs.getColumnIndex('ep_unplayed'));
      m.childCount = total;
      if (total > 0) {
        st.played = unplayed === 0;
      }
    }
    m.state = st;
    return m;
  }

  private static selectItems(where: SqlWhere, order: string, limit: number, offset: number): Promise<MediaItem[]> {
    let sql = SELECT_ITEMS + where.sql() + (order.length > 0 ? ' ORDER BY ' + order : '');
    if (limit > 0) {
      sql += ' LIMIT ' + Math.floor(limit) + ' OFFSET ' + Math.max(0, Math.floor(offset));
    }
    return LibraryDb.rows<MediaItem>(sql, where.args, (rs: relationalStore.ResultSet) => LibraryDb.mapItem(rs));
  }

  // ---------------- items ----------------

  static async upsertItem(item: MediaItem): Promise<void> {
    let parent = '';
    if (item.type === 'season') {
      parent = item.seriesId;
    } else if (item.type === 'episode') {
      parent = item.seasonId.length > 0 ? item.seasonId : item.seriesId;
    }
    const copy = itemFromJson(JSON.stringify(item));
    copy.state = new UserState();   // state lives in the states table
    const now = Date.now();
    await LibraryDb.exec('INSERT OR REPLACE INTO items (source_id, id, type, parent_id, title, original_title, sort_title, ' +
      'year, premiere, rating, season_no, episode_no, series_id, genres, added_at, json) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,' +
      'IFNULL((SELECT added_at FROM items WHERE source_id = ? AND id = ?), ?),?)', [
      item.sourceId, item.id, item.type, parent, item.title, item.originalTitle, sortTitleOf(item.title),
      item.year, item.premiereDate, item.rating, item.seasonNumber, item.episodeNumber,
      item.type === 'series' ? '' : item.seriesId, '|' + item.genres.join('|') + '|',
      item.sourceId, item.id, now, JSON.stringify(copy)
    ]);
  }

  static async getItem(sourceId: string, id: string): Promise<MediaItem | undefined> {
    const w = new SqlWhere();
    w.add('i.source_id = ? AND i.id = ?', [sourceId, id]);
    const r = await LibraryDb.selectItems(w, '', 1, 0);
    return r.length > 0 ? r[0] : undefined;
  }

  static async removeItem(sourceId: string, id: string): Promise<void> {
    await LibraryDb.exec('DELETE FROM items WHERE source_id = ? AND id = ?', [sourceId, id]);
  }

  private static orderBy(sortBy: string, desc: boolean): string {
    const dir = desc ? ' DESC' : ' ASC';
    switch (sortBy) {
      case 'DateCreated':
        return ADDED_EXPR + dir + ', i.sort_title ASC';
      case 'PremiereDate':
        return 'i.premiere' + dir + ', i.year' + dir + ', i.sort_title ASC';
      case 'ProductionYear':
        return 'i.year' + dir + ', i.sort_title ASC';
      case 'CommunityRating':
        return 'i.rating' + dir + ', i.sort_title ASC';
      case 'DatePlayed':
        return PLAYED_AT_EXPR + dir + ', i.sort_title ASC';
      case 'Random':
        return 'RANDOM()';
      case 'IndexNumber':
        return 'i.season_no' + dir + ', i.episode_no' + dir;
      default:
        return 'i.sort_title' + dir + ', i.year ASC, i.season_no ASC, i.episode_no ASC';
    }
  }

  static async query(sourceId: string, q: QueryOptions): Promise<PagedItems> {
    const w = new SqlWhere();
    w.add('i.source_id = ?', [sourceId]);
    if (q.parentId.length > 0) {
      if (q.recursive) {
        w.add('(i.parent_id = ? OR i.series_id = ?)', [q.parentId, q.parentId]);
      } else {
        w.add('i.parent_id = ?', [q.parentId]);
      }
    }
    if (q.types.length > 0) {
      w.add('i.type IN (' + q.types.map(() => '?').join(',') + ')', q.types.map((t: MediaType) => t as relationalStore.ValueType));
    } else if (q.parentId.length === 0) {
      w.add('i.type IN (\'movie\',\'series\',\'video\')', []);
    }
    const term = q.searchTerm.trim();
    if (term.length > 0) {
      const like = '%' + escapeLike(term) + '%';
      w.add('(i.title LIKE ? ESCAPE \'\\\' OR i.original_title LIKE ? ESCAPE \'\\\')', [like, like]);
    }
    if (q.genres.length > 0) {
      const parts: string[] = [];
      const args: relationalStore.ValueType[] = [];
      q.genres.forEach((g: string) => {
        parts.push('i.genres LIKE ? ESCAPE \'\\\'');
        args.push('%|' + escapeLike(g) + '|%');
      });
      w.add('(' + parts.join(' OR ') + ')', args);
    }
    if (q.years.length > 0) {
      w.add('i.year IN (' + q.years.map(() => '?').join(',') + ')', q.years.map((y: number) => y as relationalStore.ValueType));
    }
    if (q.favoritesOnly) {
      w.add('IFNULL(s.favorite,0) = 1', []);
    }
    if (q.unplayedOnly) {
      w.add(PLAYED_EXPR + ' = 0', []);
    }
    const total = await LibraryDb.count('SELECT COUNT(*)' + ITEM_FROM + w.sql(), w.args);
    let order = LibraryDb.orderBy(q.sortBy, q.sortDesc);
    if (q.parentId.length > 0 && (q.sortBy === '' || q.sortBy === 'SortName')) {
      // children of a series/season read naturally in season/episode order
      order = 'CASE WHEN i.season_no = 0 THEN 1 ELSE 0 END, i.season_no' + (q.sortDesc ? ' DESC' : ' ASC') +
        ', i.episode_no' + (q.sortDesc ? ' DESC' : ' ASC') + ', i.sort_title ASC';
    }
    const res = new PagedItems();
    res.total = total;
    res.items = await LibraryDb.selectItems(w, order, q.limit > 0 ? q.limit : 1000000, q.startIndex);
    return res;
  }

  static async children(sourceId: string, parentId: string): Promise<MediaItem[]> {
    const w = new SqlWhere();
    w.add('i.source_id = ? AND i.parent_id = ?', [sourceId, parentId]);
    return LibraryDb.selectItems(w, 'CASE WHEN i.season_no = 0 THEN 1 ELSE 0 END, i.season_no ASC, i.episode_no ASC, i.sort_title ASC', 0, 0);
  }

  static async search(sourceId: string, term: string, limit: number): Promise<MediaItem[]> {
    const t = term.trim();
    if (t.length === 0) {
      return [];
    }
    const like = '%' + escapeLike(t) + '%';
    const w = new SqlWhere();
    w.add('i.source_id = ?', [sourceId]);
    w.add('i.type IN (\'movie\',\'series\',\'video\',\'episode\')', []);
    w.add('(i.title LIKE ? ESCAPE \'\\\' OR i.original_title LIKE ? ESCAPE \'\\\')', [like, like]);
    const order = 'CASE WHEN i.title = ? OR i.original_title = ? THEN 0 WHEN i.title LIKE ? ESCAPE \'\\\' THEN 1 ELSE 2 END, ' +
      'CASE i.type WHEN \'series\' THEN 0 WHEN \'movie\' THEN 0 WHEN \'video\' THEN 1 ELSE 2 END, i.rating DESC, i.sort_title ASC';
    // ORDER BY args come after WHERE args
    w.args.push(t);
    w.args.push(t);
    w.args.push(escapeLike(t) + '%');
    return LibraryDb.selectItems(w, order, limit > 0 ? limit : 50, 0);
  }

  static async genres(sourceId: string): Promise<string[]> {
    const rows = await LibraryDb.rows<string>('SELECT DISTINCT genres FROM items WHERE source_id = ? AND type IN (\'movie\',\'series\')',
      [sourceId], (rs: relationalStore.ResultSet) => rs.getString(0));
    const set = new Set<string>();
    rows.forEach((g: string) => {
      g.split('|').forEach((x: string) => {
        if (x.trim().length > 0) {
          set.add(x.trim());
        }
      });
    });
    const out: string[] = [];
    set.forEach((g: string) => out.push(g));
    return out.sort((a: string, b: string) => a.localeCompare(b, 'zh'));
  }

  // ---------------- files ----------------

  private static mapFile(rs: relationalStore.ResultSet): LocalFile {
    const f = new LocalFile();
    f.sourceId = rs.getString(rs.getColumnIndex('source_id'));
    f.fid = rs.getString(rs.getColumnIndex('fid'));
    f.parentFid = rs.getString(rs.getColumnIndex('parent_fid'));
    f.path = rs.getString(rs.getColumnIndex('path'));
    f.name = rs.getString(rs.getColumnIndex('name'));
    f.size = rs.getLong(rs.getColumnIndex('size'));
    f.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
    f.itemId = rs.getString(rs.getColumnIndex('item_id'));
    return f;
  }

  static async upsertFile(f: LocalFile): Promise<void> {
    await LibraryDb.exec('INSERT OR REPLACE INTO files (source_id, fid, parent_fid, path, name, size, updated_at, item_id) ' +
      'VALUES (?,?,?,?,?,?,?,?)', [f.sourceId, f.fid, f.parentFid, f.path, f.name, f.size, f.updatedAt, f.itemId]);
  }

  static async getFile(sourceId: string, fid: string): Promise<LocalFile | undefined> {
    const r = await LibraryDb.rows<LocalFile>('SELECT * FROM files WHERE source_id = ? AND fid = ?', [sourceId, fid],
      (rs: relationalStore.ResultSet) => LibraryDb.mapFile(rs));
    return r.length > 0 ? r[0] : undefined;
  }

  static async filesForItem(sourceId: string, itemId: string): Promise<LocalFile[]> {
    return LibraryDb.rows<LocalFile>('SELECT * FROM files WHERE source_id = ? AND item_id = ? ORDER BY size DESC',
      [sourceId, itemId], (rs: relationalStore.ResultSet) => LibraryDb.mapFile(rs));
  }

  /** Files of every episode below a series or season id (for re-matching a whole show). */
  static async filesUnder(sourceId: string, parentId: string): Promise<LocalFile[]> {
    return LibraryDb.rows<LocalFile>('SELECT f.* FROM files f JOIN items i ON i.source_id = f.source_id AND i.id = f.item_id ' +
      'WHERE f.source_id = ? AND (i.series_id = ? OR i.parent_id = ?) ORDER BY f.path', [sourceId, parentId, parentId],
      (rs: relationalStore.ResultSet) => LibraryDb.mapFile(rs));
  }

  static async allFiles(sourceId: string): Promise<LocalFile[]> {
    return LibraryDb.rows<LocalFile>('SELECT * FROM files WHERE source_id = ? ORDER BY path', [sourceId],
      (rs: relationalStore.ResultSet) => LibraryDb.mapFile(rs));
  }

  static async removeFile(sourceId: string, fid: string): Promise<void> {
    await LibraryDb.exec('DELETE FROM files WHERE source_id = ? AND fid = ?', [sourceId, fid]);
  }

  /**
   * Delete playable items no file points to any more, then seasons without episodes and series without seasons.
   * User states are kept so a re-added file keeps its watch history.
   */
  static async pruneOrphans(sourceId: string): Promise<void> {
    await LibraryDb.exec('DELETE FROM items WHERE source_id = ? AND type IN (\'movie\',\'episode\',\'video\') AND id NOT IN ' +
      '(SELECT item_id FROM files WHERE source_id = ? AND item_id <> \'\')', [sourceId, sourceId]);
    await LibraryDb.exec('DELETE FROM items WHERE source_id = ? AND type = \'season\' AND id NOT IN ' +
      '(SELECT parent_id FROM items WHERE source_id = ? AND type = \'episode\')', [sourceId, sourceId]);
    await LibraryDb.exec('DELETE FROM items WHERE source_id = ? AND type = \'series\' AND id NOT IN ' +
      '(SELECT series_id FROM items WHERE source_id = ? AND type IN (\'season\',\'episode\'))', [sourceId, sourceId]);
  }

  static async stats(sourceId: string): Promise<Record<string, number>> {
    const out: Record<string, number> = { 'movie': 0, 'series': 0, 'episode': 0, 'video': 0, 'files': 0 };
    const rows = await LibraryDb.rows<string>('SELECT type || \':\' || COUNT(*) FROM items WHERE source_id = ? GROUP BY type',
      [sourceId], (rs: relationalStore.ResultSet) => rs.getString(0));
    rows.forEach((r: string) => {
      const i = r.lastIndexOf(':');
      out[r.substring(0, i)] = parseInt(r.substring(i + 1), 10);
    });
    out['files'] = await LibraryDb.count('SELECT COUNT(*) FROM files WHERE source_id = ?', [sourceId]);
    return out;
  }

  // ---------------- user state ----------------

  private static async writeState(sourceId: string, itemId: string, s: UserState): Promise<void> {
    await LibraryDb.exec('INSERT OR REPLACE INTO states (source_id, item_id, played, favorite, position_ms, play_count, last_played) ' +
      'VALUES (?,?,?,?,?,?,?)', [sourceId, itemId, s.played ? 1 : 0, s.favorite ? 1 : 0, Math.max(0, Math.floor(s.positionMs)),
      Math.max(0, Math.floor(s.playCount)), Math.floor(s.lastPlayed)]);
  }

  private static async readState(sourceId: string, itemId: string): Promise<UserState> {
    const r = await LibraryDb.rows<UserState>('SELECT * FROM states WHERE source_id = ? AND item_id = ?', [sourceId, itemId],
      (rs: relationalStore.ResultSet) => {
        const s = new UserState();
        s.played = rs.getLong(rs.getColumnIndex('played')) !== 0;
        s.favorite = rs.getLong(rs.getColumnIndex('favorite')) !== 0;
        s.positionMs = rs.getLong(rs.getColumnIndex('position_ms'));
        s.playCount = rs.getLong(rs.getColumnIndex('play_count'));
        s.lastPlayed = rs.getLong(rs.getColumnIndex('last_played'));
        return s;
      });
    return r.length > 0 ? r[0] : new UserState();
  }

  /**
   * Store user state. For a series/season, a change of `played` is applied to every episode below it
   * (position cleared), mirroring Emby's "mark played" on a show.
   */
  static async setState(sourceId: string, itemId: string, s: UserState): Promise<void> {
    const before = await LibraryDb.getItem(sourceId, itemId);
    await LibraryDb.writeState(sourceId, itemId, s);
    if (before !== undefined && (before.type === 'series' || before.type === 'season') && before.state.played !== s.played) {
      const eps = await LibraryDb.rows<string>('SELECT id FROM items WHERE source_id = ? AND type = \'episode\' AND ' +
        '(series_id = ? OR parent_id = ?)', [sourceId, itemId, itemId], (rs: relationalStore.ResultSet) => rs.getString(0));
      const now = Date.now();
      for (let i = 0; i < eps.length; i++) {
        const es = await LibraryDb.readState(sourceId, eps[i]);
        es.played = s.played;
        es.positionMs = 0;
        if (s.played) {
          es.playCount = Math.max(1, es.playCount);
          es.lastPlayed = es.lastPlayed > 0 ? es.lastPlayed : now;
        }
        await LibraryDb.writeState(sourceId, eps[i], es);
      }
    }
  }

  static async resume(sourceId: string, limit: number): Promise<MediaItem[]> {
    const w = new SqlWhere();
    w.add('i.source_id = ?', [sourceId]);
    w.add('i.type IN (\'movie\',\'episode\',\'video\')', []);
    w.add('IFNULL(s.position_ms,0) > 0 AND IFNULL(s.played,0) = 0', []);
    return LibraryDb.selectItems(w, 's.last_played DESC', limit > 0 ? limit : 20, 0);
  }

  static async nextUp(sourceId: string, limit: number): Promise<MediaItem[]> {
    const max = limit > 0 ? limit : 20;
    // series with at least one played episode, most recently watched first
    const series = await LibraryDb.rows<string>('SELECT i.series_id FROM items i JOIN states s ON s.source_id = i.source_id ' +
      'AND s.item_id = i.id WHERE i.source_id = ? AND i.type = \'episode\' AND i.series_id <> \'\' AND ' +
      '(s.played = 1 OR s.position_ms > 0) GROUP BY i.series_id ORDER BY MAX(s.last_played) DESC LIMIT ?',
      [sourceId, max * 2], (rs: relationalStore.ResultSet) => rs.getString(0));
    const out: MediaItem[] = [];
    for (let k = 0; k < series.length && out.length < max; k++) {
      const sid = series[k];
      // last played episode in (season, episode) order, specials (season 0) ignored
      const last = await LibraryDb.rows<number>('SELECT MAX(i.season_no * 100000 + i.episode_no) FROM items i JOIN states s ' +
        'ON s.source_id = i.source_id AND s.item_id = i.id WHERE i.source_id = ? AND i.series_id = ? AND ' +
        'i.type = \'episode\' AND i.season_no > 0 AND s.played = 1', [sourceId, sid],
        (rs: relationalStore.ResultSet) => rs.isColumnNull(0) ? -1 : rs.getLong(0));
      const key = last.length > 0 ? last[0] : -1;
      const w = new SqlWhere();
      w.add('i.source_id = ? AND i.series_id = ? AND i.type = \'episode\' AND i.season_no > 0', [sourceId, sid]);
      w.add('(i.season_no * 100000 + i.episode_no) > ?', [key]);
      w.add('IFNULL(s.played,0) = 0', []);
      const next = await LibraryDb.selectItems(w, 'i.season_no ASC, i.episode_no ASC', 1, 0);
      if (next.length > 0) {
        out.push(next[0]);
      }
    }
    return out;
  }

  static async latest(sourceId: string, limit: number): Promise<MediaItem[]> {
    const w = new SqlWhere();
    w.add('i.source_id = ?', [sourceId]);
    w.add('i.type IN (\'movie\',\'series\')', []);
    return LibraryDb.selectItems(w, ADDED_EXPR + ' DESC, i.sort_title ASC', limit > 0 ? limit : 20, 0);
  }

  static async clearSource(sourceId: string): Promise<void> {
    await LibraryDb.exec('DELETE FROM items WHERE source_id = ?', [sourceId]);
    await LibraryDb.exec('DELETE FROM files WHERE source_id = ?', [sourceId]);
    await LibraryDb.exec('DELETE FROM states WHERE source_id = ?', [sourceId]);
  }
}
