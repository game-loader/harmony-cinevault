import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { SourceConfig, SourceKind } from './Models';
import { AppContext } from './AppContext';
import { Settings } from './Settings';
import { AppLog } from './AppLog';

interface StoredSource {
  id?: string;
  kind?: string;
  name?: string;
  baseUrl?: string;
  username?: string;
  userId?: string;
  token?: string;
  deviceId?: string;
  cookie?: string;
  rootFid?: string;
  enabled?: boolean;
  quarkAuth?: string;
  quarkRefreshToken?: string;
  quarkDeviceId?: string;
}

const PREF_NAME: string = 'sources';
const KEY: string = 'sources';

function toKind(k: string | undefined): SourceKind {
  if (k === 'jellyfin') {
    return 'jellyfin';
  }
  if (k === 'quark') {
    return 'quark';
  }
  return 'emby';
}

function str(v: string | undefined, def: string): string {
  return typeof v === 'string' ? v : def;
}

/** OWNER: settings agent. Persists SourceConfig list (preferences, key 'sources'). */
export class SourceStore {
  private static items: SourceConfig[] = [];
  private static loaded: boolean = false;
  private static loading: Promise<SourceConfig[]> | undefined = undefined;
  private static store: preferences.Preferences | undefined = undefined;
  private static listeners: Array<() => void> = [];

  static async load(): Promise<SourceConfig[]> {
    if (SourceStore.loaded) {
      return SourceStore.list();
    }
    if (SourceStore.loading !== undefined) {
      return SourceStore.loading;
    }
    SourceStore.loading = SourceStore.doLoad();
    return SourceStore.loading;
  }

  private static async doLoad(): Promise<SourceConfig[]> {
    const out: SourceConfig[] = [];
    try {
      const pref = await preferences.getPreferences(AppContext.get(), PREF_NAME);
      SourceStore.store = pref;
      const raw = pref.getSync(KEY, '') as string;
      if (raw && raw.length > 0) {
        const arr = JSON.parse(raw) as StoredSource[];
        if (Array.isArray(arr)) {
          for (let i = 0; i < arr.length; i++) {
            const c = SourceStore.fromStored(arr[i]);
            if (c.id) {
              out.push(c);
            }
          }
        }
      }
    } catch (e) {
      const err = e as BusinessError;
      AppLog.error(`[SourceStore] load failed: ${err.code} ${err.message}`);
    }
    SourceStore.items = out;
    SourceStore.loaded = true;
    SourceStore.loading = undefined;
    return SourceStore.list();
  }

  private static fromStored(s: StoredSource): SourceConfig {
    const c = new SourceConfig();
    c.id = str(s.id, '');
    c.kind = toKind(s.kind);
    c.name = str(s.name, '');
    c.baseUrl = str(s.baseUrl, '');
    c.username = str(s.username, '');
    c.userId = str(s.userId, '');
    c.token = str(s.token, '');
    c.deviceId = str(s.deviceId, '');
    c.cookie = str(s.cookie, '');
    c.rootFid = str(s.rootFid, '0') || '0';
    c.enabled = typeof s.enabled === 'boolean' ? s.enabled : true;
    c.quarkAuth = str(s.quarkAuth, 'cookie') || 'cookie';
    c.quarkRefreshToken = str(s.quarkRefreshToken, '');
    c.quarkDeviceId = str(s.quarkDeviceId, '');
    return c;
  }

  static copy(src: SourceConfig): SourceConfig {
    const c = new SourceConfig();
    c.id = src.id;
    c.kind = src.kind;
    c.name = src.name;
    c.baseUrl = src.baseUrl;
    c.username = src.username;
    c.userId = src.userId;
    c.token = src.token;
    c.deviceId = src.deviceId;
    c.cookie = src.cookie;
    c.rootFid = src.rootFid;
    c.enabled = src.enabled;
    c.quarkAuth = src.quarkAuth;
    c.quarkRefreshToken = src.quarkRefreshToken;
    c.quarkDeviceId = src.quarkDeviceId;
    return c;
  }

  /** Copies of all sources, in insertion order. */
  static list(): SourceConfig[] {
    return SourceStore.items.map((c: SourceConfig) => SourceStore.copy(c));
  }

  static get(id: string): SourceConfig | undefined {
    for (let i = 0; i < SourceStore.items.length; i++) {
      if (SourceStore.items[i].id === id) {
        return SourceStore.copy(SourceStore.items[i]);
      }
    }
    return undefined;
  }

  /** Insert or replace by id. Fills id / deviceId / name when empty. */
  static async upsert(cfg: SourceConfig): Promise<void> {
    const c = SourceStore.copy(cfg);
    if (!c.id) {
      c.id = SourceStore.newId();
    }
    if (!c.deviceId) {
      c.deviceId = Settings.get().deviceId || util.generateRandomUUID(false);
    }
    if (!c.name) {
      c.name = c.kind === 'quark' ? '夸克网盘' : (c.kind === 'jellyfin' ? 'Jellyfin' : 'Emby');
    }
    if (!c.rootFid) {
      c.rootFid = '0';
    }
    const next = SourceStore.items.slice();
    let idx = -1;
    for (let i = 0; i < next.length; i++) {
      if (next[i].id === c.id) {
        idx = i;
        break;
      }
    }
    if (idx >= 0) {
      next[idx] = c;
    } else {
      next.push(c);
    }
    SourceStore.items = next;
    cfg.id = c.id;
    cfg.deviceId = c.deviceId;
    cfg.name = c.name;
    await SourceStore.persist();
    SourceStore.emit();
  }

  static async remove(id: string): Promise<void> {
    const next = SourceStore.items.filter((c: SourceConfig) => c.id !== id);
    if (next.length === SourceStore.items.length) {
      return;
    }
    SourceStore.items = next;
    await SourceStore.persist();
    SourceStore.emit();
  }

  static newId(): string {
    return 's' + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36);
  }

  /** Subscribe to list changes; returns an unsubscribe function. */
  static onChange(cb: () => void): () => void {
    SourceStore.listeners.push(cb);
    return () => {
      const i = SourceStore.listeners.indexOf(cb);
      if (i >= 0) {
        SourceStore.listeners.splice(i, 1);
      }
    };
  }

  private static emit(): void {
    const ls = SourceStore.listeners.slice();
    for (let i = 0; i < ls.length; i++) {
      try {
        ls[i]();
      } catch (e) {
        AppLog.error(`[SourceStore] listener error: ${(e as Error).message}`);
      }
    }
  }

  private static async persist(): Promise<void> {
    try {
      if (SourceStore.store === undefined) {
        SourceStore.store = await preferences.getPreferences(AppContext.get(), PREF_NAME);
      }
      SourceStore.store.putSync(KEY, JSON.stringify(SourceStore.items));
      await SourceStore.store.flush();
    } catch (e) {
      const err = e as BusinessError;
      AppLog.error(`[SourceStore] save failed: ${err.code} ${err.message}`);
    }
  }
}
