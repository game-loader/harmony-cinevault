import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppContext } from './AppContext';

/** OWNER: settings agent. App preferences persisted with @kit.ArkData preferences ('settings'). */
export class AppSettings {
  tmdbApiKey: string = '';          // TMDB v3 api key or v4 read token (starts with 'eyJ')
  tmdbLanguage: string = 'zh-CN';
  tmdbImageBase: string = 'https://image.tmdb.org/t/p/';
  tmdbApiBase: string = 'https://api.themoviedb.org/3';
  maxBitrate: number = 0;           // 0 = original
  defaultSpeed: number = 1;
  autoPlayNext: boolean = true;
  preferredAudioLang: string = 'chi';
  preferredSubtitleLang: string = 'chi';
  subtitleScale: number = 1;
  skipIntroMs: number = 0;
  homeSourceId: string = '';        // '' = aggregate all sources
  landscapeHome: boolean = true;    // big-screen hero layout
  deviceId: string = '';            // generated once, sent to Emby/Jellyfin as DeviceId
}

/** Shape of persisted JSON: every field optional so older/partial saves merge with defaults. */
interface StoredSettings {
  tmdbApiKey?: string;
  tmdbLanguage?: string;
  tmdbImageBase?: string;
  tmdbApiBase?: string;
  maxBitrate?: number;
  defaultSpeed?: number;
  autoPlayNext?: boolean;
  preferredAudioLang?: string;
  preferredSubtitleLang?: string;
  subtitleScale?: number;
  skipIntroMs?: number;
  homeSourceId?: string;
  landscapeHome?: boolean;
  deviceId?: string;
}

const PREF_NAME: string = 'settings';
const KEY: string = 'settings';

export class Settings {
  private static cache: AppSettings = new AppSettings();
  private static loaded: boolean = false;
  private static loading: Promise<AppSettings> | undefined = undefined;
  private static store: preferences.Preferences | undefined = undefined;
  private static listeners: Array<() => void> = [];

  static async load(): Promise<AppSettings> {
    if (Settings.loaded) {
      return Settings.cache;
    }
    if (Settings.loading !== undefined) {
      return Settings.loading;
    }
    Settings.loading = Settings.doLoad();
    return Settings.loading;
  }

  private static async doLoad(): Promise<AppSettings> {
    const s = new AppSettings();
    try {
      const pref = await preferences.getPreferences(AppContext.get(), PREF_NAME);
      Settings.store = pref;
      const raw = pref.getSync(KEY, '') as string;
      if (raw && raw.length > 0) {
        Settings.merge(s, JSON.parse(raw) as StoredSettings);
      }
    } catch (e) {
      const err = e as BusinessError;
      console.error(`[Settings] load failed: ${err.code} ${err.message}`);
    }
    let needSave = false;
    if (!s.deviceId) {
      s.deviceId = util.generateRandomUUID(false);
      needSave = true;
    }
    Settings.cache = s;
    Settings.loaded = true;
    Settings.loading = undefined;
    if (needSave) {
      await Settings.persist();
    }
    return s;
  }

  private static merge(dst: AppSettings, src: StoredSettings): void {
    if (typeof src.tmdbApiKey === 'string') { dst.tmdbApiKey = src.tmdbApiKey; }
    if (typeof src.tmdbLanguage === 'string' && src.tmdbLanguage) { dst.tmdbLanguage = src.tmdbLanguage; }
    if (typeof src.tmdbImageBase === 'string' && src.tmdbImageBase) { dst.tmdbImageBase = src.tmdbImageBase; }
    if (typeof src.tmdbApiBase === 'string' && src.tmdbApiBase) { dst.tmdbApiBase = src.tmdbApiBase; }
    if (typeof src.maxBitrate === 'number') { dst.maxBitrate = src.maxBitrate; }
    if (typeof src.defaultSpeed === 'number' && src.defaultSpeed > 0) { dst.defaultSpeed = src.defaultSpeed; }
    if (typeof src.autoPlayNext === 'boolean') { dst.autoPlayNext = src.autoPlayNext; }
    if (typeof src.preferredAudioLang === 'string') { dst.preferredAudioLang = src.preferredAudioLang; }
    if (typeof src.preferredSubtitleLang === 'string') { dst.preferredSubtitleLang = src.preferredSubtitleLang; }
    if (typeof src.subtitleScale === 'number' && src.subtitleScale > 0) { dst.subtitleScale = src.subtitleScale; }
    if (typeof src.skipIntroMs === 'number' && src.skipIntroMs >= 0) { dst.skipIntroMs = src.skipIntroMs; }
    if (typeof src.homeSourceId === 'string') { dst.homeSourceId = src.homeSourceId; }
    if (typeof src.landscapeHome === 'boolean') { dst.landscapeHome = src.landscapeHome; }
    if (typeof src.deviceId === 'string') { dst.deviceId = src.deviceId; }
  }

  /** Synchronous snapshot from memory (defaults until load() resolves). Returns a copy. */
  static get(): AppSettings {
    return Settings.copy(Settings.cache);
  }

  static copy(src: AppSettings): AppSettings {
    const d = new AppSettings();
    d.tmdbApiKey = src.tmdbApiKey;
    d.tmdbLanguage = src.tmdbLanguage;
    d.tmdbImageBase = src.tmdbImageBase;
    d.tmdbApiBase = src.tmdbApiBase;
    d.maxBitrate = src.maxBitrate;
    d.defaultSpeed = src.defaultSpeed;
    d.autoPlayNext = src.autoPlayNext;
    d.preferredAudioLang = src.preferredAudioLang;
    d.preferredSubtitleLang = src.preferredSubtitleLang;
    d.subtitleScale = src.subtitleScale;
    d.skipIntroMs = src.skipIntroMs;
    d.homeSourceId = src.homeSourceId;
    d.landscapeHome = src.landscapeHome;
    d.deviceId = src.deviceId;
    return d;
  }

  static async save(s: AppSettings): Promise<void> {
    const c = Settings.copy(s);
    if (!c.deviceId) {
      c.deviceId = Settings.cache.deviceId || util.generateRandomUUID(false);
    }
    Settings.cache = c;
    await Settings.persist();
    Settings.emit();
  }

  /** Subscribe to settings changes; returns an unsubscribe function. */
  static onChange(cb: () => void): () => void {
    Settings.listeners.push(cb);
    return () => {
      const i = Settings.listeners.indexOf(cb);
      if (i >= 0) {
        Settings.listeners.splice(i, 1);
      }
    };
  }

  private static emit(): void {
    const ls = Settings.listeners.slice();
    for (let i = 0; i < ls.length; i++) {
      try {
        ls[i]();
      } catch (e) {
        console.error(`[Settings] listener error: ${(e as Error).message}`);
      }
    }
  }

  private static async persist(): Promise<void> {
    try {
      if (Settings.store === undefined) {
        Settings.store = await preferences.getPreferences(AppContext.get(), PREF_NAME);
      }
      Settings.store.putSync(KEY, JSON.stringify(Settings.cache));
      await Settings.store.flush();
    } catch (e) {
      const err = e as BusinessError;
      console.error(`[Settings] save failed: ${err.code} ${err.message}`);
    }
  }
}
