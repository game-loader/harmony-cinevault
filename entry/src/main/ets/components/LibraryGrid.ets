import { MediaItem, MediaType, QueryOptions, PagedItems } from '../common/Models';
import { MediaProvider } from '../common/MediaProvider';
import { Theme } from '../common/Theme';
import { Nav } from '../common/Nav';
import { ProviderRegistry } from '../providers/ProviderRegistry';
import { MediaCard } from './MediaCard';
import { LoadingView, EmptyView, ErrorView, InlineWarning, LoadMoreFooter } from './StateViews';
import {
  settleAll, Settled, mergeSorted, gridColumns, itemKey, SORT_OPTIONS, SortOption, sortLabel, defaultSortDesc,
  yearOptions, errMessage
} from './MediaLogic';

const PAGE = 60;

class Cursor {
  prov: MediaProvider;
  start: number = 0;
  total: number = -1;
  done: boolean = false;
  constructor(prov: MediaProvider) {
    this.prov = prov;
  }
}

/**
 * Paged poster grid for one library view, an aggregated type (movies / tvshows) across all sources,
 * favorites, or a genre. Shared by pages/Library and the Index tabs.
 */
@Component
export struct LibraryGrid {
  @Prop sourceId: string = '';
  @Prop viewId: string = '';
  @Prop mode: string = '';
  @Prop genre: string = '';
  @Prop title: string = '';
  @Prop showBack: boolean = true;
  @Prop sidePad: number = Theme.pagePad;
  /** Increment from the parent to force a reload (e.g. sources changed). */
  @Prop @Watch('onReloadToken') reloadToken: number = 0;

  @State private items: MediaItem[] = [];
  @State private total: number = 0;
  @State private loading: boolean = true;
  @State private loadingMore: boolean = false;
  @State private refreshing: boolean = false;
  @State private error: string = '';
  @State private moreError: string = '';
  @State private warnings: string[] = [];
  @State private hasMore: boolean = false;
  @State private sortBy: string = 'SortName';
  @State private sortDesc: boolean = false;
  @State private unplayedOnly: boolean = false;
  @State private favoritesOnly: boolean = false;
  @State private genreFilter: string = '';
  @State private yearFilter: number = 0;
  @State private genres: string[] = [];
  @State private gridWidth: number = 0;
  private cursors: Cursor[] = [];
  private generation: number = 0;

  aboutToAppear(): void {
    if (this.genre.length > 0) {
      this.genreFilter = this.genre;
    }
    if (this.mode === 'favorites') {
      this.sortBy = 'DateCreated';
      this.sortDesc = true;
    }
    this.reload(false);
    this.loadGenres();
  }

  onReloadToken(): void {
    this.reload(false);
    this.loadGenres();
  }

  private types(): MediaType[] {
    if (this.mode === 'movies') {
      return ['movie'] as MediaType[];
    }
    if (this.mode === 'tvshows') {
      return ['series'] as MediaType[];
    }
    if (this.mode === 'favorites') {
      return ['movie', 'series', 'episode'] as MediaType[];
    }
    if (this.viewId.length > 0) {
      return [] as MediaType[];
    }
    return ['movie', 'series'] as MediaType[];
  }

  private providers(): MediaProvider[] {
    if (this.sourceId.length > 0) {
      const p = ProviderRegistry.get(this.sourceId);
      return p !== undefined ? [p] : [];
    }
    return ProviderRegistry.all();
  }

  private query(c: Cursor): QueryOptions {
    const q = new QueryOptions();
    q.parentId = this.viewId;
    q.types = this.types();
    q.recursive = true;
    q.sortBy = this.sortBy;
    q.sortDesc = this.sortDesc;
    q.startIndex = c.start;
    q.limit = PAGE;
    q.favoritesOnly = this.favoritesOnly || this.mode === 'favorites';
    q.unplayedOnly = this.unplayedOnly;
    q.genres = this.genreFilter.length > 0 ? [this.genreFilter] : [];
    q.years = this.yearFilter > 0 ? [this.yearFilter] : [];
    return q;
  }

  private async loadGenres(): Promise<void> {
    const provs = this.providers();
    const r: Settled<string[]>[] = await settleAll<string[]>(
      provs.map((p: MediaProvider) => p.getGenres(this.viewId)));
    const set = new Set<string>();
    r.forEach((s: Settled<string[]>) => {
      if (s.ok && s.value !== undefined) {
        s.value.forEach((g: string) => { set.add(g); });
      }
    });
    const arr: string[] = [];
    set.forEach((g: string) => { arr.push(g); });
    arr.sort((a: string, b: string) => a.localeCompare(b));
    this.genres = arr;
  }

  private async reload(pull: boolean): Promise<void> {
    this.generation++;
    this.cursors = this.providers().map((p: MediaProvider) => new Cursor(p));
    this.error = '';
    this.moreError = '';
    this.warnings = [];
    if (!pull) {
      this.loading = true;
      this.items = [];
    }
    if (this.cursors.length === 0) {
      this.items = [];
      this.total = 0;
      this.hasMore = false;
      this.loading = false;
      this.refreshing = false;
      this.error = this.sourceId.length > 0 ? '媒体源不存在或已被禁用' : '';
      return;
    }
    const gen = this.generation;
    try {
      const batch = await this.fetchNext(gen);
      if (gen !== this.generation) {
        return;
      }
      this.items = batch;
    } catch (e) {
      if (gen === this.generation) {
        this.error = errMessage(e as Error);
      }
    } finally {
      if (gen === this.generation) {
        this.loading = false;
        this.refreshing = false;
      }
    }
  }

  /** Fetch the next page from every cursor that isn't done; throws only if all sources failed. */
  private async fetchNext(gen: number): Promise<MediaItem[]> {
    const live = this.cursors.filter((c: Cursor) => !c.done);
    const res: Settled<PagedItems>[] = await settleAll<PagedItems>(
      live.map((c: Cursor) => c.prov.getItems(this.query(c))));
    if (gen !== this.generation) {
      return [];
    }
    const lists: MediaItem[][] = [];
    const warns: string[] = [];
    let okCount = 0;
    for (let i = 0; i < live.length; i++) {
      const c = live[i];
      const r = res[i];
      if (r.ok && r.value !== undefined) {
        okCount++;
        const page = r.value;
        c.start += page.items.length;
        c.total = page.total;
        c.done = page.items.length === 0 || c.start >= page.total;
        lists.push(page.items);
      } else {
        c.done = true;
        warns.push(c.prov.config.name + '：' + r.error);
      }
    }
    if (live.length > 0 && okCount === 0) {
      throw new Error(warns.join('\n'));
    }
    if (warns.length > 0) {
      const w = this.warnings.slice();
      warns.forEach((s: string) => { w.push(s); });
      this.warnings = w;
    }
    let total = 0;
    this.cursors.forEach((c: Cursor) => { total += Math.max(0, c.total); });
    this.total = total;
    this.hasMore = this.cursors.some((c: Cursor) => !c.done);
    return mergeSorted(lists, this.sortBy, this.sortDesc);
  }

  private async loadMore(): Promise<void> {
    if (this.loading || this.loadingMore || !this.hasMore) {
      return;
    }
    this.loadingMore = true;
    this.moreError = '';
    const gen = this.generation;
    try {
      const batch = await this.fetchNext(gen);
      if (gen !== this.generation) {
        return;
      }
      const seen = new Set<string>(this.items.map((it: MediaItem) => itemKey(it)));
      const merged = this.items.slice();
      batch.forEach((it: MediaItem) => {
        if (!seen.has(itemKey(it))) {
          merged.push(it);
        }
      });
      this.items = merged;
    } catch (e) {
      if (gen === this.generation) {
        this.moreError = errMessage(e as Error);
        // let the user retry the failed cursors
        this.cursors.forEach((c: Cursor) => { if (c.total < 0 || c.start < c.total) { c.done = false; } });
        this.hasMore = true;
      }
    } finally {
      this.loadingMore = false;
    }
  }

  private onItemChanged(n: MediaItem): void {
    const k = itemKey(n);
    const idx = this.items.findIndex((it: MediaItem) => itemKey(it) === k);
    if (idx < 0) {
      return;
    }
    const removeNow = (this.mode === 'favorites' || this.favoritesOnly) && !n.state.favorite ||
      this.unplayedOnly && n.state.played;
    const copy = this.items.slice();
    if (removeNow) {
      copy.splice(idx, 1);
      this.total = Math.max(0, this.total - 1);
    } else {
      copy[idx] = n;
    }
    this.items = copy;
  }

  private columns(): number {
    return gridColumns(this.gridWidth - this.sidePad * 2, this.gridWidth >= Theme.bpLg ? 150 : 104, 14);
  }

  private cardWidth(): number {
    const n = this.columns();
    const w = this.gridWidth - this.sidePad * 2 - 14 * (n - 1);
    return Math.max(80, Math.floor(w / n));
  }

  private template(): string {
    const parts: string[] = [];
    for (let i = 0; i < this.columns(); i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }
  private applyAndReload(): void {
    this.reload(false);
  }

  private sortMenu(): MenuElement[] {
    const out: MenuElement[] = [];
    SORT_OPTIONS.forEach((o: SortOption) => {
      const key = o.key;
      const mark = this.sortBy === key ? (key === 'Random' ? '✓ ' : (this.sortDesc ? '↓ ' : '↑ ')) : '   ';
      const e: MenuElement = {
        value: mark + o.label,
        action: () => {
          if (this.sortBy === key && key !== 'Random') {
            this.sortDesc = !this.sortDesc;
          } else {
            this.sortBy = key;
            this.sortDesc = defaultSortDesc(key);
          }
          this.applyAndReload();
        }
      };
      out.push(e);
    });
    return out;
  }

  private genreMenu(): MenuElement[] {
    const out: MenuElement[] = [];
    const all: MenuElement = {
      value: (this.genreFilter.length === 0 ? '✓ ' : '   ') + '全部类型',
      action: () => { this.genreFilter = ''; this.applyAndReload(); }
    };
    out.push(all);
    this.genres.forEach((g: string) => {
      const e: MenuElement = {
        value: (this.genreFilter === g ? '✓ ' : '   ') + g,
        action: () => { this.genreFilter = g; this.applyAndReload(); }
      };
      out.push(e);
    });
    return out;
  }

  private yearMenu(): MenuElement[] {
    const out: MenuElement[] = [];
    const all: MenuElement = {
      value: (this.yearFilter === 0 ? '✓ ' : '   ') + '全部年份',
      action: () => { this.yearFilter = 0; this.applyAndReload(); }
    };
    out.push(all);
    yearOptions(new Date().getFullYear(), 40).forEach((y: number) => {
      const e: MenuElement = {
        value: (this.yearFilter === y ? '✓ ' : '   ') + y.toString(),
        action: () => { this.yearFilter = y; this.applyAndReload(); }
      };
      out.push(e);
    });
    return out;
  }

  @Builder
  chip(label: string, on: boolean, withArrow: boolean) {
    Row({ space: 4 }) {
      Text(label).fontSize(13).fontColor(on ? Color.White : Theme.text2)
      if (withArrow) {
        SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(12).fontColor([on ? Color.White : Theme.text2])
      }
    }
    .height(32).padding({ left: 12, right: 10 })
    .borderRadius(16)
    .backgroundColor(on ? Theme.accent : Theme.surface2)
  }

  @Builder
  header() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        if (this.showBack) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24).fontColor([Theme.text])
            .padding(6)
            .onClick(() => Nav.back())
        }
        Text(this.title.length > 0 ? this.title : '媒体库')
          .fontSize(24).fontWeight(FontWeight.Bold).fontColor(Theme.text)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (!this.loading && this.error.length === 0) {
          Text(this.total.toString() + ' 项').fontSize(13).fontColor(Theme.text3)
        }
        Blank()
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(20).fontColor([Theme.text2]).padding(6)
          .onClick(() => { this.reload(false); })
      }
      .width('100%')

      Scroll() {
        Row({ space: 8 }) {
          Row() {
            this.chip('排序：' + sortLabel(this.sortBy) + (this.sortBy === 'Random' ? '' : (this.sortDesc ? ' ↓' : ' ↑')),
              false, true)
          }
          .bindMenu(this.sortMenu())
          Row() {
            this.chip('未看', this.unplayedOnly, false)
          }
          .onClick(() => { this.unplayedOnly = !this.unplayedOnly; this.applyAndReload(); })
          if (this.mode !== 'favorites') {
            Row() {
              this.chip('收藏', this.favoritesOnly, false)
            }
            .onClick(() => { this.favoritesOnly = !this.favoritesOnly; this.applyAndReload(); })
          }
          if (this.genres.length > 0) {
            Row() {
              this.chip(this.genreFilter.length > 0 ? this.genreFilter : '类型', this.genreFilter.length > 0, true)
            }
            .bindMenu(this.genreMenu())
          }
          Row() {
            this.chip(this.yearFilter > 0 ? this.yearFilter.toString() : '年份', this.yearFilter > 0, true)
          }
          .bindMenu(this.yearMenu())
          if (this.unplayedOnly || this.favoritesOnly || this.genreFilter.length > 0 || this.yearFilter > 0) {
            Text('清除筛选').fontSize(13).fontColor(Theme.text3).padding({ left: 6, right: 6 })
              .onClick(() => {
                this.unplayedOnly = false;
                this.favoritesOnly = false;
                this.genreFilter = '';
                this.yearFilter = 0;
                this.applyAndReload();
              })
          }
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .align(Alignment.Start)

      if (this.warnings.length > 0) {
        InlineWarning({ text: '部分媒体源加载失败：' + this.warnings.join('；'), onClose: () => { this.warnings = []; } })
      }
    }
    .width('100%')
    .padding({ left: this.sidePad, right: this.sidePad, top: 12, bottom: 8 })
  }

  private hasFilter(): boolean {
    return this.unplayedOnly || this.favoritesOnly || this.genreFilter.length > 0 || this.yearFilter > 0;
  }

  build() {
    Column() {
      this.header()
      if (this.loading) {
        LoadingView()
          .layoutWeight(1)
      } else if (this.error.length > 0) {
        ErrorView({ message: this.error, onRetry: () => { this.reload(false); } })
          .layoutWeight(1)
      } else if (this.items.length === 0) {
        EmptyView({
          title: this.hasFilter() ? '没有符合条件的内容' : (this.mode === 'favorites' ? '还没有收藏' : '媒体库为空'),
          message: this.hasFilter() ? '试试调整或清除筛选条件' :
            (this.mode === 'favorites' ? '长按海报即可加入收藏' : '请确认媒体源中已有内容，或在设置中扫描夸克网盘'),
          actionText: this.hasFilter() ? '清除筛选' : '',
          onAction: () => {
            this.unplayedOnly = false;
            this.favoritesOnly = false;
            this.genreFilter = '';
            this.yearFilter = 0;
            this.applyAndReload();
          }
        })
          .layoutWeight(1)
      } else {
        Refresh({ refreshing: $$this.refreshing, promptText: '正在刷新…' }) {
          Grid() {
            ForEach(this.items, (it: MediaItem) => {
              GridItem() {
                MediaCard({
                  item: it,
                  cardWidth: this.cardWidth(),
                  onChanged: (n: MediaItem) => this.onItemChanged(n)
                })
              }
            }, (it: MediaItem) => itemKey(it) + '|' + (it.state.played ? '1' : '0') + (it.state.favorite ? '1' : '0'))
            GridItem() {
              LoadMoreFooter({
                loading: this.loadingMore,
                hasMore: this.hasMore,
                error: this.moreError,
                onRetry: () => { this.loadMore(); }
              })
            }
            .columnStart(0)
            .columnEnd(this.columns() - 1)
          }
          .columnsTemplate(this.template())
          .columnsGap(14)
          .rowsGap(18)
          .cachedCount(2)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .padding({ left: this.sidePad, right: this.sidePad, top: 6, bottom: 24 })
          .onScrollIndex((first: number, last: number) => {
            if (last >= this.items.length - this.columns() * 3) {
              this.loadMore();
            }
          })
          .onReachEnd(() => { this.loadMore(); })
          .width('100%').height('100%')
        }
        .onRefreshing(() => { this.reload(true); })
        .layoutWeight(1)
      }
    }
    .width('100%').height('100%')
    .backgroundColor(Theme.bg)
    .onAreaChange((o: Area, n: Area) => {
      const w = Number(n.width);
      if (Math.abs(w - this.gridWidth) >= 1) {
        this.gridWidth = w;
      }
    })
  }
}
