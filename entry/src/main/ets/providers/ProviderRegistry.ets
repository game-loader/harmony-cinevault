import { MediaProvider } from '../common/MediaProvider';
import { SourceConfig } from '../common/Models';

/** OWNER: settings agent. Creates and caches one MediaProvider per SourceConfig. */
export class ProviderRegistry {
  static get(sourceId: string): MediaProvider | undefined { return undefined; }
  static all(): MediaProvider[] { return []; }
  static create(cfg: SourceConfig): MediaProvider { throw new Error('not implemented'); }
  static invalidate(sourceId: string): void {}
}
