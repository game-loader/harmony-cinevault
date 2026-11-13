import { SourceConfig } from './Models';

/** OWNER: settings agent. Persists SourceConfig list (preferences, key 'sources'). */
export class SourceStore {
  static async load(): Promise<SourceConfig[]> { return []; }
  static list(): SourceConfig[] { return []; }
  static get(id: string): SourceConfig | undefined { return undefined; }
  static async upsert(cfg: SourceConfig): Promise<void> {}
  static async remove(id: string): Promise<void> {}
  static newId(): string { return 's' + Date.now().toString(36); }
  /** Subscribe to list changes; returns an unsubscribe function. */
  static onChange(cb: () => void): () => void { return () => {}; }
}
