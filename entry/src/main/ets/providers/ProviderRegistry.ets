import { MediaProvider } from '../common/MediaProvider';
import { SourceConfig } from '../common/Models';
import { SourceStore } from '../common/SourceStore';
import { EmbyProvider } from './EmbyProvider';
import { QuarkProvider } from '../quark/QuarkProvider';
import { FlicxProvider } from '../flicx/FlicxProvider';
import { FLICX_ID } from '../flicx/FlicxMapper';
import { AppLog } from '../common/AppLog';

class CacheEntry {
  provider: MediaProvider;
  fingerprint: string;

  constructor(provider: MediaProvider, fingerprint: string) {
    this.provider = provider;
    this.fingerprint = fingerprint;
  }
}

/** OWNER: settings agent. Creates and caches one MediaProvider per SourceConfig. */
export class ProviderRegistry {
  private static readonly flicx: FlicxProvider = new FlicxProvider();
  private static cache: Map<string, CacheEntry> = new Map<string, CacheEntry>();
  private static subscribed: boolean = false;

  private static fingerprint(cfg: SourceConfig): string {
    return JSON.stringify(cfg);
  }

  private static ensureSubscribed(): void {
    if (ProviderRegistry.subscribed) {
      return;
    }
    ProviderRegistry.subscribed = true;
    SourceStore.onChange(() => {
      ProviderRegistry.prune();
    });
  }

  /** Drop providers whose source was removed or whose config changed. */
  private static prune(): void {
    const stale: string[] = [];
    ProviderRegistry.cache.forEach((entry: CacheEntry, id: string) => {
      const cfg = SourceStore.get(id);
      if (cfg === undefined || ProviderRegistry.fingerprint(cfg) !== entry.fingerprint) {
        stale.push(id);
      }
    });
    for (let i = 0; i < stale.length; i++) {
      ProviderRegistry.cache.delete(stale[i]);
    }
  }

  /** Provider for an enabled or disabled source; undefined if the source does not exist. */
  static get(sourceId: string): MediaProvider | undefined {
    if (sourceId === FLICX_ID) {
      return ProviderRegistry.flicx;
    }
    ProviderRegistry.ensureSubscribed();
    const cfg = SourceStore.get(sourceId);
    if (cfg === undefined) {
      ProviderRegistry.cache.delete(sourceId);
      return undefined;
    }
    const fp = ProviderRegistry.fingerprint(cfg);
    const hit = ProviderRegistry.cache.get(sourceId);
    if (hit !== undefined && hit.fingerprint === fp) {
      return hit.provider;
    }
    try {
      const p = ProviderRegistry.create(cfg);
      ProviderRegistry.cache.set(sourceId, new CacheEntry(p, fp));
      return p;
    } catch (e) {
      AppLog.error(`[ProviderRegistry] create failed for ${sourceId}: ${(e as Error).message}`);
      return undefined;
    }
  }

  /** Providers for all enabled sources, in SourceStore order. */
  static all(): MediaProvider[] {
    const out: MediaProvider[] = [];
    const list = SourceStore.list();
    for (let i = 0; i < list.length; i++) {
      if (!list[i].enabled) {
        continue;
      }
      const p = ProviderRegistry.get(list[i].id);
      if (p !== undefined) {
        out.push(p);
      }
    }
    out.push(ProviderRegistry.flicx);
    return out;
  }

  /** New, uncached provider instance for a config (also usable for unsaved configs). */
  static create(cfg: SourceConfig): MediaProvider {
    if (cfg.kind === 'emby' || cfg.kind === 'jellyfin') {
      return new EmbyProvider(cfg);
    }
    if (cfg.kind === 'quark') {
      return new QuarkProvider(cfg);
    }
    throw new Error(`不支持的媒体源类型: ${cfg.kind}`);
  }

  static invalidate(sourceId: string): void {
    ProviderRegistry.cache.delete(sourceId);
  }
}
