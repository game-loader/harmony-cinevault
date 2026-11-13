import { SourceConfig } from '../common/Models';
import { Theme } from '../common/Theme';

export class NavEntry {
  key: string = '';
  label: string = '';
  icon: Resource;
  constructor(key: string, label: string, icon: Resource) {
    this.key = key;
    this.label = label;
    this.icon = icon;
  }
}

/** Shared navigation entries (sidebar on large screens, bottom tabs on phones). */
export function navEntries(): NavEntry[] {
  return [
    new NavEntry('home', '首页', $r('sys.symbol.house')),
    new NavEntry('movies', '电影', $r('sys.symbol.film')),
    new NavEntry('tvshows', '剧集', $r('sys.symbol.tv_badge_clock')),
    new NavEntry('favorites', '收藏', $r('sys.symbol.heart')),
    new NavEntry('search', '搜索', $r('sys.symbol.magnifyingglass')),
    new NavEntry('settings', '设置', $r('sys.symbol.gearshape'))
  ];
}

export function kindName(kind: string): string {
  switch (kind) {
    case 'emby': return 'Emby';
    case 'jellyfin': return 'Jellyfin';
    case 'quark': return '夸克网盘';
    default: return kind;
  }
}

@Component
struct SidebarItem {
  @Prop entry: NavEntry;
  @Prop selected: boolean = false;
  @Prop compact: boolean = false;
  onPick: () => void = () => {};
  @State private hot: boolean = false;

  build() {
    Row({ space: 12 }) {
      SymbolGlyph(this.entry.icon)
        .fontSize(20)
        .fontColor([this.selected ? Color.White : Theme.text2])
      if (!this.compact) {
        Text(this.entry.label)
          .fontSize(15)
          .fontColor(this.selected ? Color.White : Theme.text2)
          .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Normal)
      }
    }
    .width('100%').height(46)
    .padding({ left: this.compact ? 0 : 16 })
    .justifyContent(this.compact ? FlexAlign.Center : FlexAlign.Start)
    .borderRadius(10)
    .backgroundColor(this.selected ? Theme.accent : (this.hot ? Theme.surface2 : Color.Transparent))
    .animation({ duration: 150 })
    .focusable(true)
    .onFocus(() => { this.hot = true; })
    .onBlur(() => { this.hot = false; })
    .onHover((h: boolean) => { this.hot = h; })
    .onClick(() => this.onPick())
  }
}

/** Left vertical navigation for large screens, with a source switcher at the bottom. */
@Component
export struct Sidebar {
  @Prop selectedKey: string = 'home';
  @Prop sources: SourceConfig[] = [];
  /** '' = all sources aggregated */
  @Prop homeSourceId: string = '';
  /** Icon-only rail (md widths). */
  @Prop compact: boolean = false;
  onSelect: (key: string) => void = () => {};
  onSourceSelect: (sourceId: string) => void = () => {};

  private sourceLabel(): string {
    if (this.homeSourceId.length === 0) {
      return '全部媒体源';
    }
    for (const s of this.sources) {
      if (s.id === this.homeSourceId) {
        return s.name.length > 0 ? s.name : kindName(s.kind);
      }
    }
    return '全部媒体源';
  }

  private menu(): MenuElement[] {
    const out: MenuElement[] = [];
    const all: MenuElement = { value: (this.homeSourceId.length === 0 ? '✓ ' : '   ') + '全部媒体源', action: () => {
      this.onSourceSelect('');
    } };
    out.push(all);
    this.sources.filter((s: SourceConfig) => s.enabled).forEach((s: SourceConfig) => {
      const id = s.id;
      const e: MenuElement = {
        value: (this.homeSourceId === id ? '✓ ' : '   ') + (s.name.length > 0 ? s.name : kindName(s.kind)) +
          '（' + kindName(s.kind) + '）',
        action: () => { this.onSourceSelect(id); }
      };
      out.push(e);
    });
    return out;
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text('影')
          .fontSize(18).fontWeight(FontWeight.Bolder).fontColor(Color.White)
          .width(32).height(32).textAlign(TextAlign.Center)
          .borderRadius(8).backgroundColor(Theme.accent)
        if (!this.compact) {
          Text('影库').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Theme.text)
        }
      }
      .width('100%')
      .justifyContent(this.compact ? FlexAlign.Center : FlexAlign.Start)
      .padding({ left: this.compact ? 0 : 12, top: 28, bottom: 24 })

      Column({ space: 6 }) {
        ForEach(navEntries(), (e: NavEntry) => {
          SidebarItem({
            entry: e,
            selected: e.key === this.selectedKey,
            compact: this.compact,
            onPick: () => this.onSelect(e.key)
          })
        }, (e: NavEntry) => e.key)
      }
      .width('100%')

      Blank()

      if (this.sources.length > 0) {
        Column({ space: 4 }) {
          if (!this.compact) {
            Text('媒体源').fontSize(12).fontColor(Theme.text3).padding({ left: 4 })
          }
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.cloud')).fontSize(18).fontColor([Theme.text2])
            if (!this.compact) {
              Text(this.sourceLabel()).fontSize(14).fontColor(Theme.text)
                .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              SymbolGlyph($r('sys.symbol.chevron_up')).fontSize(14).fontColor([Theme.text2])
            }
          }
          .width('100%').height(44)
          .padding({ left: this.compact ? 0 : 12, right: 10 })
          .justifyContent(this.compact ? FlexAlign.Center : FlexAlign.Start)
          .borderRadius(10)
          .backgroundColor(Theme.surface2)
          .bindMenu(this.menu())
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ bottom: 20 })
      }
    }
    .width(this.compact ? 72 : 200)
    .height('100%')
    .padding({ left: this.compact ? 10 : 14, right: this.compact ? 10 : 14 })
    .backgroundColor(Theme.surface)
  }
}
