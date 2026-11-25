import { router, promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppLog } from './AppLog';

/** Router params. Pages read them with `router.getParams() as DetailParams` etc. */
export class DetailParams {
  sourceId: string = '';
  itemId: string = '';
}

export class PlayerParams {
  sourceId: string = '';
  itemId: string = '';
  /** -1 = resume from saved position, 0 = from start, otherwise ms */
  startMs: number = -1;
  /** Episode ids in play order for auto-next (optional) */
  queue: string[] = [];
}

export class LibraryParams {
  sourceId: string = '';
  viewId: string = '';
  title: string = '';
  /** 'movies' | 'tvshows' | 'favorites' | 'genre' | '' */
  mode: string = '';
  genre: string = '';
}

export class ServerEditParams {
  /** '' = add new */
  sourceId: string = '';
  kind: string = 'emby';
}

export class QuarkBrowserParams {
  sourceId: string = '';
  /** pick = choose the library root folder and return */
  pick: boolean = false;
}

export class Nav {
  static detail(sourceId: string, itemId: string): void {
    const p = new DetailParams();
    p.sourceId = sourceId;
    p.itemId = itemId;
    router.pushUrl({ url: 'pages/Detail', params: p });
  }

  static play(sourceId: string, itemId: string, startMs: number = -1, queue: string[] = []): void {
    const p = new PlayerParams();
    p.sourceId = sourceId;
    p.itemId = itemId;
    p.startMs = startMs;
    p.queue = queue;
    AppLog.info(`[Nav] play ${sourceId} ${itemId} start=${startMs} queue=${queue.length}`);
    try {
      router.pushUrl({ url: 'pages/Player', params: p }).catch((e: BusinessError) => {
        AppLog.error(`[Nav] open player failed: ${e.code} ${e.message}`);
        promptAction.showToast({ message: '无法打开播放器 (' + e.code + ')：' + e.message, duration: 3500 });
      });
    } catch (e) {
      const err = e as BusinessError;
      AppLog.error(`[Nav] open player threw: ${err.code} ${err.message}`);
      promptAction.showToast({ message: '无法打开播放器：' + err.message, duration: 3500 });
    }
  }

  static library(p: LibraryParams): void {
    router.pushUrl({ url: 'pages/Library', params: p });
  }

  static search(): void {
    router.pushUrl({ url: 'pages/Search' });
  }

  static settings(): void {
    router.pushUrl({ url: 'pages/Settings' });
  }

  static editServer(sourceId: string, kind: string): void {
    const p = new ServerEditParams();
    p.sourceId = sourceId;
    p.kind = kind;
    router.pushUrl({ url: 'pages/ServerEdit', params: p });
  }

  static quarkLogin(sourceId: string): void {
    const p = new ServerEditParams();
    p.sourceId = sourceId;
    p.kind = 'quark';
    router.pushUrl({ url: 'pages/QuarkLogin', params: p });
  }

  static quarkBrowser(sourceId: string, pick: boolean): void {
    const p = new QuarkBrowserParams();
    p.sourceId = sourceId;
    p.pick = pick;
    router.pushUrl({ url: 'pages/QuarkBrowser', params: p });
  }

  static codecInfo(): void {
    router.pushUrl({ url: 'pages/CodecInfo' });
  }

  static logs(): void {
    router.pushUrl({ url: 'pages/LogView' });
  }

  static back(): void {
    router.back();
  }
}
