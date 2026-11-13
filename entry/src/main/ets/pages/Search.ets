import { MediaItem, HomeRow } from '../common/Models';
import { MediaProvider } from '../common/MediaProvider';
import { Theme } from '../common/Theme';
import { Nav } from '../common/Nav';
import { SourceStore } from '../common/SourceStore';
import { Settings } from '../common/Settings';
import { ProviderRegistry } from '../providers/ProviderRegistry';
import { MediaRow } from '../components/MediaRow';
import { LoadingView, EmptyView, ErrorView, InlineWarning } from '../components/StateViews';
import { RecentSearches } from '../components/RecentSearches';
import { settleAll, Settled, groupSearch, SearchGroup, itemKey } from '../components/MediaLogic';

const DEBOUNCE_MS = 400;
const PER_SOURCE = 40;

@Entry
@Component
struct SearchPage {
  @State private term: string = '';
  @State private searched: string = '';
  @State private loading: boolean = false;
  @State private error: string = '';
  @State private warnings: string[] = [];
  @State private rows: HomeRow[] = [];
  @State private recent: string[] = [];
  @State private pageW: number = 0;
  @State private noSources: boolean = false;
  private timer: number = -1;
  private seq: number = 0;
  private inputCtl: TextInputController = new TextInputController();

  aboutToAppear(): void {
    this.init();
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
    }
  }

  private async init(): Promise<void> {
    try {
      await SourceStore.load();
      await Settings.load();
    } catch (e) {
      // providers() below reports the empty state
    }
    this.noSources = ProviderRegistry.all().length === 0;
    this.recent = await RecentSearches.list();
  }

  private onInput(v: string): void {
    this.term = v;
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    if (v.trim().length === 0) {
      this.seq++;
      this.searched = '';
      this.rows = [];
      this.error = '';
      this.warnings = [];
      this.loading = false;
      return;
    }
    this.timer = setTimeout(() => {
      this.timer = -1;
      this.run(v, false);
    }, DEBOUNCE_MS);
  }

  private async run(raw: string, remember: boolean): Promise<void> {
    const t = raw.trim();
    if (t.length === 0) {
      return;
    }
    const mySeq = ++this.seq;
    this.loading = true;
    this.error = '';
    this.warnings = [];
    this.searched = t;
    const provs = ProviderRegistry.all();
    this.noSources = provs.length === 0;
    const res: Settled<MediaItem[]>[] = await settleAll<MediaItem[]>(
      provs.map((p: MediaProvider) => p.search(t, PER_SOURCE)));
    if (mySeq !== this.seq) {
      return;
    }
    const all: MediaItem[] = [];
    const warns: string[] = [];
    let ok = 0;
    for (let i = 0; i < res.length; i++) {
      const r = res[i];
      if (r.ok && r.value !== undefined) {
        ok++;
        r.value.forEach((it: MediaItem) => { all.push(it); });
      } else {
        warns.push(provs[i].config.name + '：' + r.error);
      }
    }
    if (provs.length > 0 && ok === 0) {
      this.error = warns.join('\n');
    }
    this.warnings = ok > 0 ? warns : [];
    this.rows = groupSearch(all).map((g: SearchGroup) => {
      const r = new HomeRow();
      r.key = 'search:' + g.key;
      r.title = g.title + '（' + g.items.length.toString() + '）';
      r.style = g.key === 'episode' ? 'landscape' : 'poster';
      r.items = g.items;
      return r;
    });
    this.loading = false;
    if (remember || all.length > 0) {
      this.recent = await RecentSearches.add(t);
    }
  }

  private submit(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    this.run(this.term, true);
  }

  private pickRecent(s: string): void {
    this.term = s;
    this.run(s, true);
  }

  private posterWidth(): number {
    return this.pageW >= Theme.bpLg ? 150 : (this.pageW >= Theme.bpMd ? 130 : 112);
  }

  private onItemChanged(n: MediaItem): void {
    const k = itemKey(n);
    this.rows = this.rows.map((r: HomeRow) => {
      const idx = r.items.findIndex((it: MediaItem) => itemKey(it) === k);
      if (idx < 0) {
        return r;
      }
      const nr = new HomeRow();
      nr.key = r.key;
      nr.title = r.title;
      nr.style = r.style;
      nr.items = r.items.slice();
      nr.items[idx] = n;
      return nr;
    });
  }

  @Builder
  searchBar() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(24).fontColor([Theme.text]).padding(6)
        .onClick(() => Nav.back())
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(18).fontColor([Theme.text2])
        TextInput({ text: this.term, placeholder: '搜索电影、剧集、单集', controller: this.inputCtl })
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Color.Transparent)
          .fontColor(Theme.text)
          .placeholderColor(Theme.text3)
          .caretColor(Theme.accent)
          .enterKeyType(EnterKeyType.Search)
          .defaultFocus(true)
          .padding({ left: 0, right: 0 })
          .onChange((v: string) => this.onInput(v))
          .onSubmit(() => this.submit())
        if (this.term.length > 0) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([Theme.text2]).padding(4)
            .onClick(() => { this.onInput(''); })
        }
      }
      .layoutWeight(1)
      .height(44)
      .padding({ left: 14, right: 10 })
      .borderRadius(22)
      .backgroundColor(Theme.surface2)
    }
    .width('100%')
    .padding({ left: Theme.pagePad - 8, right: Theme.pagePad, top: 12, bottom: 10 })
  }

  @Builder
  recentView() {
    Column({ space: 12 }) {
      if (this.recent.length > 0) {
        Row() {
          Text('最近搜索').fontSize(16).fontWeight(FontWeight.Medium).fontColor(Theme.text).layoutWeight(1)
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.trash')).fontSize(14).fontColor([Theme.text3])
            Text('清空').fontSize(13).fontColor(Theme.text3)
          }
          .onClick(async () => {
            await RecentSearches.clear();
            this.recent = [];
          })
        }
        .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.recent, (s: string) => {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.clock')).fontSize(13).fontColor([Theme.text3])
              Text(s).fontSize(14).fontColor(Theme.text2).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 220 })
            }
            .height(34).padding({ left: 12, right: 12 })
            .borderRadius(17).backgroundColor(Theme.surface2)
            .margin({ right: 8, bottom: 8 })
            .onClick(() => this.pickRecent(s))
            .bindContextMenu(this.recentMenu(s), ResponseType.LongPress)
          }, (s: string) => s)
        }
        .width('100%')
      } else {
        EmptyView({
          title: this.noSources ? '还没有媒体源' : '搜索全部媒体源',
          message: this.noSources ? '请先在设置中添加 Emby / Jellyfin 服务器或登录夸克网盘'
            : '输入片名、剧名或单集名称，结果会按电影 / 剧集 / 单集分组显示',
          actionText: this.noSources ? '前往设置' : '',
          onAction: () => Nav.settings()
        })
          .height(360)
      }
    }
    .width('100%')
    .padding({ left: Theme.pagePad, right: Theme.pagePad, top: 8 })
  }

  @Builder
  recentMenu(s: string) {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.trash')).fontSize(16).fontColor([Theme.text])
      Text('删除此记录').fontSize(14).fontColor(Theme.text)
    }
    .height(44).padding({ left: 14, right: 14 })
    .backgroundColor(Theme.surface)
    .onClick(async () => { this.recent = await RecentSearches.remove(s); })
  }

  build() {
    Column() {
      this.searchBar()
      if (this.searched.length === 0 && !this.loading) {
        Scroll() {
          this.recentView()
        }
        .layoutWeight(1)
        .align(Alignment.Top)
      } else if (this.loading) {
        LoadingView({ message: '正在搜索“' + this.searched + '”…' }).layoutWeight(1)
      } else if (this.error.length > 0) {
        ErrorView({ title: '搜索失败', message: this.error, onRetry: () => { this.run(this.searched, false); } })
          .layoutWeight(1)
      } else if (this.rows.length === 0) {
        EmptyView({ title: '没有找到“' + this.searched + '”', message: '换个关键词试试，或检查媒体源是否已扫描' })
          .layoutWeight(1)
      } else {
        List({ space: 22 }) {
          if (this.warnings.length > 0) {
            ListItem() {
              InlineWarning({ text: '部分媒体源搜索失败：' + this.warnings.join('；'),
                onClose: () => { this.warnings = []; } })
                .padding({ left: Theme.pagePad, right: Theme.pagePad })
            }
          }
          ForEach(this.rows, (r: HomeRow) => {
            ListItem() {
              MediaRow({ row: r, posterWidth: this.posterWidth(), onChanged: (n: MediaItem) => this.onItemChanged(n) })
            }
          }, (r: HomeRow) => r.key + ':' + r.items.length.toString() + ':' + this.searched)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .padding({ top: 6, bottom: 28 })
      }
    }
    .width('100%').height('100%')
    .backgroundColor(Theme.bg)
    .onAreaChange((o: Area, n: Area) => { this.pageW = Number(n.width); })
  }
}
