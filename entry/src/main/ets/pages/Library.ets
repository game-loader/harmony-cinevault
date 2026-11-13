import { router } from '@kit.ArkUI';
import { LibraryParams } from '../common/Nav';
import { Theme } from '../common/Theme';
import { SourceStore } from '../common/SourceStore';
import { Settings } from '../common/Settings';
import { LibraryGrid } from '../components/LibraryGrid';
import { LoadingView } from '../components/StateViews';

@Entry
@Component
struct LibraryPage {
  @State private params: LibraryParams = new LibraryParams();
  @State private ready: boolean = false;
  @State private reloadToken: number = 0;
  private unsub: () => void = () => {};

  aboutToAppear(): void {
    const p = router.getParams() as LibraryParams;
    if (p !== undefined && p !== null) {
      const lp = new LibraryParams();
      lp.sourceId = p.sourceId ?? '';
      lp.viewId = p.viewId ?? '';
      lp.title = p.title ?? '';
      lp.mode = p.mode ?? '';
      lp.genre = p.genre ?? '';
      if (lp.title.length === 0) {
        lp.title = lp.mode === 'movies' ? '电影' : (lp.mode === 'tvshows' ? '剧集' :
          (lp.mode === 'favorites' ? '收藏' : (lp.genre.length > 0 ? lp.genre : '媒体库')));
      }
      this.params = lp;
    }
    this.init();
    this.unsub = SourceStore.onChange(() => { this.reloadToken++; });
  }

  aboutToDisappear(): void {
    this.unsub();
  }

  private async init(): Promise<void> {
    try {
      await SourceStore.load();
      await Settings.load();
    } finally {
      this.ready = true;
    }
  }

  build() {
    Column() {
      if (!this.ready) {
        LoadingView()
      } else {
        LibraryGrid({
          sourceId: this.params.sourceId,
          viewId: this.params.viewId,
          mode: this.params.mode,
          genre: this.params.genre,
          title: this.params.title,
          showBack: true,
          reloadToken: this.reloadToken
        })
      }
    }
    .width('100%').height('100%')
    .backgroundColor(Theme.bg)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
