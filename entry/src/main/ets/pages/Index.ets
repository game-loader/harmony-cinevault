import { MediaItem, HomeRow, LibraryView, SourceConfig } from '../common/Models';
import { Theme } from '../common/Theme';
import { Nav, LibraryParams } from '../common/Nav';
import { SourceStore } from '../common/SourceStore';
import { Settings, AppSettings } from '../common/Settings';
import { HomeData, HomeResult, SourceWarning } from '../common/HomeData';
import { HeroBanner } from '../components/HeroBanner';
import { MediaRow } from '../components/MediaRow';
import { Sidebar, NavEntry, navEntries } from '../components/Sidebar';
import { LibraryGrid } from '../components/LibraryGrid';
import { LoadingView, EmptyView, ErrorView, InlineWarning } from '../components/StateViews';
import { itemKey, errMessage } from '../components/MediaLogic';

type Phase = 'init' | 'welcome' | 'home';

@Entry
@Component
struct IndexPage {
  @State private phase: Phase = 'init';
  @State private tab: string = 'home';
  @State private winW: number = 0;
  @State private winH: number = 0;
  @State private home: HomeResult | undefined = undefined;
  @State private loading: boolean = false;
  @State private refreshing: boolean = false;
  @State private error: string = '';
  @State private warnings: SourceWarning[] = [];
  @State private sources: SourceConfig[] = [];
  @State private homeSourceId: string = '';
  @State private reloadToken: number = 0;
  @State private hasTmdbKey: boolean = true;
  private unsubSources: () => void = () => {};
  private unsubSettings: () => void = () => {};
  private firstShow: boolean = true;
  private lastHomeSource: string = '';

  aboutToAppear(): void {
    this.unsubSources = SourceStore.onChange(() => {
      HomeData.invalidate();
      this.reloadToken++;
      this.boot(true);
    });
    this.unsubSettings = Settings.onChange(() => {
      const s = Settings.get();
      this.hasTmdbKey = s.tmdbApiKey.length > 0;
      if (s.homeSourceId !== this.lastHomeSource) {
        this.lastHomeSource = s.homeSourceId;
        this.homeSourceId = s.homeSourceId;
        this.reloadToken++;
        HomeData.invalidate();
        this.loadHome(true, false);
      }
    });
    this.boot(false);
  }

  aboutToDisappear(): void {
    this.unsubSources();
    this.unsubSettings();
  }

  onPageShow(): void {
    if (this.firstShow) {
      this.firstShow = false;
      return;
    }
    // back from detail / player: refresh resume & played state silently
    if (this.phase === 'home' && this.tab === 'home') {
      this.loadHome(true, true);
    }
  }

  onBackPress(): boolean | void {
    if (this.phase === 'home' && this.tab !== 'home') {
      this.tab = 'home';
      return true;
    }
    return false;
  }

  private async boot(silent: boolean): Promise<void> {
    if (!silent) {
      this.phase = 'init';
    }
    let st: AppSettings = new AppSettings();
    try {
      await SourceStore.load();
      st = await Settings.load();
    } catch (e) {
      this.error = errMessage(e as Error);
    }
    this.sources = SourceStore.list();
    this.homeSourceId = st.homeSourceId;
    this.lastHomeSource = st.homeSourceId;
    this.hasTmdbKey = st.tmdbApiKey.length > 0;
    if (this.sources.length === 0) {
      this.phase = 'welcome';
      this.home = undefined;
      return;
    }
    this.phase = 'home';
    const cached = HomeData.cached();
    if (cached !== undefined && !silent) {
      this.applyResult(cached);
      this.loadHome(true, true);
    } else {
      this.loadHome(!silent ? false : true, false);
    }
  }

  private applyResult(r: HomeResult): void {
    this.home = r;
    this.warnings = r.warnings;
  }

  /** quiet = keep current content on screen while loading. */
  private async loadHome(force: boolean, quiet: boolean): Promise<void> {
    if (!quiet) {
      this.loading = this.home === undefined;
      this.error = '';
    }
    try {
      const r = await HomeData.load(force);
      this.applyResult(r);
      this.error = '';
    } catch (e) {
      if (!quiet || this.home === undefined) {
        this.error = errMessage(e as Error);
      }
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private isLarge(): boolean {
    return this.winW >= Theme.bpLg || (this.winW >= Theme.bpMd && this.winW > this.winH);
  }

  private sidePad(): number {
    return this.winW >= Theme.bpLg ? 40 : (this.winW >= Theme.bpMd ? 28 : 16);
  }

  private posterWidth(): number {
    if (this.winW >= 1400) {
      return 168;
    }
    return this.winW >= Theme.bpLg ? 150 : (this.winW >= Theme.bpMd ? 132 : 112);
  }

  private heroHeight(): number {
    if (this.isLarge()) {
      return Math.max(360, Math.round(this.winH * 0.62));
    }
    return Math.min(Math.round(this.winW * 0.95), Math.round(this.winH * 0.55));
  }

  private onNav(key: string): void {
    if (key === 'search') {
      Nav.search();
      return;
    }
    if (key === 'settings') {
      Nav.settings();
      return;
    }
    this.tab = key;
  }

  private async onSourceSelect(id: string): Promise<void> {
    const s = Settings.copy(Settings.get());
    s.homeSourceId = id;
    this.homeSourceId = id;
    this.lastHomeSource = id;
    this.reloadToken++;
    HomeData.invalidate();
    this.home = undefined;
    this.loading = true;
    try {
      await Settings.save(s);
    } catch (e) {
      // keep in-memory choice
    }
    this.loadHome(true, false);
  }

  private onItemChanged(n: MediaItem): void {
    const cur = this.home;
    if (cur === undefined) {
      return;
    }
    const k = itemKey(n);
    const r = new HomeResult();
    r.featured = cur.featured;
    r.views = cur.views;
    r.warnings = cur.warnings;
    r.sourceCount = cur.sourceCount;
    r.loadedAt = cur.loadedAt;
    r.rows = cur.rows.map((row: HomeRow) => {
      const idx = row.items.findIndex((it: MediaItem) => itemKey(it) === k);
      if (idx < 0) {
        return row;
      }
      const nr = new HomeRow();
      nr.key = row.key;
      nr.title = row.title;
      nr.style = row.style;
      nr.items = row.items.slice();
      if (row.key === 'favorites' && !n.state.favorite) {
        nr.items.splice(idx, 1);
      } else {
        nr.items[idx] = n;
      }
      return nr;
    }).filter((row: HomeRow) => row.items.length > 0);
    this.home = r;
  }

  private openView(v: LibraryView): void {
    const p = new LibraryParams();
    p.sourceId = v.sourceId;
    p.viewId = v.id;
    p.title = v.name;
    Nav.library(p);
  }

  private openMode(mode: string, title: string): void {
    const p = new LibraryParams();
    p.mode = mode;
    p.title = title;
    p.sourceId = this.homeSourceId;
    Nav.library(p);
  }

  private moreFor(row: HomeRow): void {
    if (row.key === 'favorites') {
      this.openMode('favorites', '收藏');
      return;
    }
    if (row.key.startsWith('latest:') && this.home !== undefined) {
      const parts = row.key.split(':');
      const sid = parts.length > 1 ? parts[1] : '';
      const vid = parts.length > 2 ? parts.slice(2).join(':') : '';
      const v = this.home.views.find((x: LibraryView) => x.sourceId === sid && x.id === vid);
      if (v !== undefined) {
        this.openView(v);
      }
    }
  }
  @Builder
  welcome() {
    Column({ space: 18 }) {
      Text('影')
        .fontSize(44).fontWeight(FontWeight.Bolder).fontColor(Color.White)
        .width(88).height(88).textAlign(TextAlign.Center)
        .borderRadius(22).backgroundColor(Theme.accent)
      Text('欢迎使用影库').fontSize(28).fontWeight(FontWeight.Bold).fontColor(Theme.text)
      Text('使用内置 Flicx 搜索电影和剧集，也可以连接 Emby / Jellyfin 服务器或登录夸克网盘。')
        .fontSize(14).fontColor(Theme.text2).textAlign(TextAlign.Center).lineHeight(22)
        .constraintSize({ maxWidth: 460 })
      Column({ space: 12 }) {
        Button() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(18).fontColor([Color.White])
            Text('搜索电影和剧集').fontSize(16).fontColor(Color.White).fontWeight(FontWeight.Medium)
          }
        }
        .type(ButtonType.Capsule).backgroundColor(Theme.accent)
        .width('100%').height(48)
        .defaultFocus(true)
        .onClick(() => Nav.search())
        Button() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.cloud')).fontSize(18).fontColor([Theme.text])
            Text('添加 Emby / Jellyfin').fontSize(16).fontColor(Theme.text).fontWeight(FontWeight.Medium)
          }
        }
        .type(ButtonType.Capsule).backgroundColor(Theme.surface2)
        .width('100%').height(48)
        .onClick(() => Nav.editServer('', 'emby'))
        Button() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.folder')).fontSize(18).fontColor([Theme.text])
            Text('登录夸克网盘').fontSize(16).fontColor(Theme.text).fontWeight(FontWeight.Medium)
          }
        }
        .type(ButtonType.Capsule).backgroundColor(Theme.surface2)
        .width('100%').height(48)
        .onClick(() => Nav.quarkLogin(''))
      }
      .width('100%')
      .constraintSize({ maxWidth: 360 })
      .margin({ top: 8 })
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.info_circle')).fontSize(14).fontColor([Theme.text3])
        Text(this.hasTmdbKey ? '已启用中文片名搜索'
          : '可直接搜英文片名。在「设置 › 刮削」填写 TMDB 密钥即可搜中文片名。')
          .fontSize(12).fontColor(Theme.text3)
      }
      .margin({ top: 8 })
      .onClick(() => Nav.settings())
      Text('打开设置').fontSize(13).fontColor(Theme.accent)
        .onClick(() => Nav.settings())
    }
    .width('100%').height('100%')
    .padding(32)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Theme.bg)
  }

  @Builder
  libraryChips() {
    if (this.home !== undefined) {
      Column({ space: 10 }) {
        Text('媒体库').fontSize(18).fontWeight(FontWeight.Bold).fontColor(Theme.text)
          .padding({ left: this.sidePad() })
        List({ space: 10 }) {
          ListItem() {
            this.chip('全部电影', $r('sys.symbol.film'), () => this.openMode('movies', '电影'))
          }
          ListItem() {
            this.chip('全部剧集', $r('sys.symbol.tv_badge_clock'), () => this.openMode('tvshows', '剧集'))
          }
          ForEach(this.home.views, (v: LibraryView) => {
            ListItem() {
              this.chip(v.name + (this.sources.length > 1 && this.homeSourceId.length === 0
                ? ' · ' + this.sourceName(v.sourceId) : ''),
                v.collectionType === 'tvshows' ? $r('sys.symbol.tv_badge_clock') :
                  (v.collectionType === 'movies' ? $r('sys.symbol.film') : $r('sys.symbol.folder')),
                () => this.openView(v))
            }
          }, (v: LibraryView) => v.sourceId + '|' + v.id)
          ListItem() {
            this.chip('收藏', $r('sys.symbol.heart'), () => this.openMode('favorites', '收藏'))
          }
        }
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .contentStartOffset(this.sidePad())
        .contentEndOffset(this.sidePad())
        .height(44)
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  private sourceName(id: string): string {
    const s = this.sources.find((x: SourceConfig) => x.id === id);
    return s !== undefined ? s.name : '';
  }

  @Builder
  chip(label: string, icon: Resource, action: () => void) {
    Row({ space: 8 }) {
      SymbolGlyph(icon).fontSize(16).fontColor([Theme.text2])
      Text(label).fontSize(14).fontColor(Theme.text).maxLines(1)
    }
    .height(42).padding({ left: 16, right: 18 })
    .borderRadius(21).backgroundColor(Theme.surface2)
    .focusable(true)
    .onClick(action)
  }

  @Builder
  homeHeader() {
    // floating top bar on phones (sidebar handles this on large screens)
    Row({ space: 12 }) {
      Text('影库').fontSize(22).fontWeight(FontWeight.Bolder).fontColor(Color.White)
      Blank()
      SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(22).fontColor([Color.White])
        .onClick(() => Nav.search())
      SymbolGlyph($r('sys.symbol.gearshape')).fontSize(22).fontColor([Color.White])
        .onClick(() => Nav.settings())
    }
    .width('100%')
    .padding({ left: this.sidePad(), right: this.sidePad(), top: 12, bottom: 12 })
    .linearGradient({ direction: GradientDirection.Bottom, colors: [['#AA000000', 0], ['#00000000', 1]] })
  }

  @Builder
  homeContent() {
    if (this.loading && this.home === undefined) {
      LoadingView({ message: '正在加载首页…' })
    } else if (this.error.length > 0 && this.home === undefined) {
      ErrorView({ message: this.error, onRetry: () => { this.loadHome(true, false); } })
    } else if (this.home !== undefined) {
      Stack({ alignContent: Alignment.Top }) {
        Refresh({ refreshing: $$this.refreshing, promptText: '正在刷新…' }) {
          List({ space: 26 }) {
            if (this.home.featured.length > 0) {
              ListItem() {
                HeroBanner({
                  items: this.home.featured,
                  bannerHeight: this.heroHeight(),
                  large: this.isLarge(),
                  sidePad: this.sidePad()
                })
              }
            } else {
              ListItem() {
                Column().height(this.isLarge() ? 24 : 56)
              }
            }
            if (this.warnings.length > 0) {
              ListItem() {
                Column({ space: 6 }) {
                  ForEach(this.warnings, (w: SourceWarning) => {
                    InlineWarning({
                      text: w.sourceName + '：' + w.message,
                      onClose: () => {
                        this.warnings = this.warnings.filter((x: SourceWarning) => x.sourceId !== w.sourceId);
                      }
                    })
                  }, (w: SourceWarning) => w.sourceId)
                }
                .padding({ left: this.sidePad(), right: this.sidePad() })
              }
            }
            ListItem() {
              this.libraryChips()
            }
            ForEach(this.home.rows, (row: HomeRow) => {
              ListItem() {
                MediaRow({
                  row: row,
                  posterWidth: this.posterWidth(),
                  sidePad: this.sidePad(),
                  showMore: row.key === 'favorites' || row.key.startsWith('latest:'),
                  onMore: () => this.moreFor(row),
                  onChanged: (n: MediaItem) => this.onItemChanged(n)
                })
              }
            }, (row: HomeRow) => row.key + ':' + row.items.map((it: MediaItem) =>
              it.id + (it.state.played ? 'p' : '') + (it.state.favorite ? 'f' : '') +
              Math.round(it.state.positionMs / 1000).toString()).join(','))
            if (this.home.rows.length === 0) {
              ListItem() {
                EmptyView({
                  title: '媒体库还没有内容',
                  message: '服务器上暂无影片，或夸克网盘尚未扫描。可在设置中选择媒体文件夹并开始扫描。',
                  actionText: '打开设置',
                  onAction: () => Nav.settings()
                }).height(320)
              }
            }
            ListItem() {
              Text(this.home.loadedAt > 0 ? '下拉可刷新' : '').fontSize(11).fontColor(Theme.text3)
                .width('100%').textAlign(TextAlign.Center).padding({ bottom: 24 })
            }
          }
          .width('100%').height('100%')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .cachedCount(2)
        }
        .onRefreshing(() => {
          HomeData.invalidate();
          this.loadHome(true, true);
        })
        .width('100%').height('100%')

        if (!this.isLarge()) {
          this.homeHeader()
        }
      }
      .width('100%').height('100%')
    }
  }
  private currentTabIndex(): number {
    const keys = ['home', 'movies', 'tvshows', 'favorites'];
    const i = keys.indexOf(this.tab);
    return i < 0 ? 0 : i;
  }

  @Builder
  tabsContent() {
    Tabs({ index: this.currentTabIndex() }) {
      TabContent() {
        this.homeContent()
      }
      TabContent() {
        LibraryGrid({
          mode: 'movies', title: '电影', showBack: false, sourceId: this.homeSourceId,
          sidePad: this.sidePad(), reloadToken: this.reloadToken
        })
      }
      TabContent() {
        LibraryGrid({
          mode: 'tvshows', title: '剧集', showBack: false, sourceId: this.homeSourceId,
          sidePad: this.sidePad(), reloadToken: this.reloadToken
        })
      }
      TabContent() {
        LibraryGrid({
          mode: 'favorites', title: '收藏', showBack: false, sourceId: this.homeSourceId,
          sidePad: this.sidePad(), reloadToken: this.reloadToken
        })
      }
    }
    .barHeight(0)
    .scrollable(false)
    .animationDuration(0)
    .width('100%').height('100%')
  }

  @Builder
  bottomBar() {
    Row() {
      ForEach(navEntries(), (e: NavEntry) => {
        Column({ space: 3 }) {
          SymbolGlyph(e.icon).fontSize(22)
            .fontColor([e.key === this.tab ? Theme.accent : Theme.text2])
          Text(e.label).fontSize(10)
            .fontColor(e.key === this.tab ? Theme.accent : Theme.text2)
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.onNav(e.key))
      }, (e: NavEntry) => e.key)
    }
    .width('100%').height(56)
    .backgroundColor(Theme.surface)
    .border({ width: { top: 0.5 }, color: Theme.surface2 })
  }

  build() {
    Stack() {
      if (this.phase === 'init') {
        LoadingView({ message: '正在启动…' })
      } else if (this.phase === 'welcome') {
        this.welcome()
      } else if (this.isLarge()) {
        Row() {
          Sidebar({
            selectedKey: this.tab,
            sources: this.sources,
            homeSourceId: this.homeSourceId,
            compact: this.winW < Theme.bpLg,
            onSelect: (k: string) => this.onNav(k),
            onSourceSelect: (id: string) => { this.onSourceSelect(id); }
          })
          Column() {
            this.tabsContent()
          }
          .layoutWeight(1).height('100%')
        }
        .width('100%').height('100%')
      } else {
        Column() {
          Column() {
            this.tabsContent()
          }
          .layoutWeight(1).width('100%')
          this.bottomBar()
        }
        .width('100%').height('100%')
      }
    }
    .width('100%').height('100%')
    .backgroundColor(Theme.bg)
    .onAreaChange((o: Area, n: Area) => {
      const w = Number(n.width);
      const h = Number(n.height);
      if (Math.abs(w - this.winW) >= 1 || Math.abs(h - this.winH) >= 1) {
        this.winW = w;
        this.winH = h;
      }
    })
  }
}
