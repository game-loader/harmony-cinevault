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
}

export class Settings {
  static async load(): Promise<AppSettings> { return new AppSettings(); }
  static get(): AppSettings { return new AppSettings(); }
  static async save(s: AppSettings): Promise<void> {}
}
