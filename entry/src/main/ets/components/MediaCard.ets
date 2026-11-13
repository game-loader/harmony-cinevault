import { MediaItem } from '../common/Models';
import { Theme } from '../common/Theme';
import { Nav } from '../common/Nav';
import { NetImage } from './NetImage';
import { imageFor, landscapeFor, MediaActions } from './MediaActions';
import { progressOf, ratingText, cardTitle, cardSubtitle, remainingText } from './MediaLogic';

/**
 * Poster (2:3) or landscape (16:9) media card.
 * Tap opens detail (or plays directly when playOnTap). Long-press / right-click opens a context menu.
 * Hover and keyboard/remote focus scale the card up.
 */
@Component
export struct MediaCard {
  @Prop @Watch('onItemChange') item: MediaItem = new MediaItem();
  @Prop landscape: boolean = false;
  @Prop cardWidth: number = 140;
  @Prop playOnTap: boolean = false;
  @Prop showSubtitle: boolean = true;
  /** Called after the user changed played/favorite from the context menu. */
  onChanged: (item: MediaItem) => void = () => {};
  /** Override tap behaviour (optional). Return true when handled. */
  onTap: (item: MediaItem) => boolean = () => false;
  @State private cur: MediaItem = new MediaItem();
  @State private active: boolean = false;
  @State private busy: boolean = false;

  aboutToAppear(): void {
    this.cur = this.item;
  }

  onItemChange(): void {
    this.cur = this.item;
  }

  private imgHeight(): number {
    return this.landscape ? this.cardWidth * 9 / 16 : this.cardWidth * 1.5;
  }

  private imageUrl(): string {
    const w = Math.round(this.cardWidth * 2.5);
    return this.landscape ? landscapeFor(this.cur, w) : imageFor(this.cur, 'poster', w);
  }

  private open(): void {
    if (this.onTap(this.cur)) {
      return;
    }
    const it = this.cur;
    if (this.playOnTap && (it.type === 'episode' || it.type === 'movie' || it.type === 'video')) {
      Nav.play(it.sourceId, it.id, -1);
      return;
    }
    Nav.detail(it.sourceId, it.id);
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1600 });
    } catch (e) {
      // no UI context (e.g. during teardown)
    }
  }

  private async togglePlayed(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const target = !this.cur.state.played;
    try {
      const next = await MediaActions.setPlayed(this.cur, target);
      this.cur = next;
      this.onChanged(next);
      this.toast(target ? '已标记为已看' : '已标记为未看');
    } catch (e) {
      this.toast('操作失败：' + ((e as Error).message ?? ''));
    } finally {
      this.busy = false;
    }
  }

  private async toggleFavorite(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const target = !this.cur.state.favorite;
    try {
      const next = await MediaActions.setFavorite(this.cur, target);
      this.cur = next;
      this.onChanged(next);
      this.toast(target ? '已加入收藏' : '已取消收藏');
    } catch (e) {
      this.toast('操作失败：' + ((e as Error).message ?? ''));
    } finally {
      this.busy = false;
    }
  }

  @Builder
  menuItemBuilder(label: string, sym: Resource, action: () => void) {
    Row({ space: 10 }) {
      SymbolGlyph(sym).fontSize(18).fontColor([Theme.text])
      Text(label).fontSize(15).fontColor(Theme.text)
    }
    .width(180).height(44).padding({ left: 14, right: 14 })
    .onClick(action)
  }

  @Builder
  contextMenu() {
    Column() {
      this.menuItemBuilder(this.cur.state.played ? '标记为未看' : '标记为已看',
        $r('sys.symbol.checkmark'), () => { this.togglePlayed(); })
      Divider().color(Theme.surface2)
      this.menuItemBuilder(this.cur.state.favorite ? '取消收藏' : '收藏',
        this.cur.state.favorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
        () => { this.toggleFavorite(); })
      Divider().color(Theme.surface2)
      this.menuItemBuilder('查看详情', $r('sys.symbol.info_circle'), () => {
        Nav.detail(this.cur.sourceId, this.cur.id);
      })
      if (this.cur.type === 'episode' && this.cur.seriesId.length > 0) {
        Divider().color(Theme.surface2)
        this.menuItemBuilder('前往剧集', $r('sys.symbol.film'), () => {
          Nav.detail(this.cur.sourceId, this.cur.seriesId);
        })
      }
    }
    .backgroundColor(Theme.surface)
    .borderRadius(12)
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  badges() {
    if (this.cur.state.played) {
      SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
        .fontSize(20).fontColor([Theme.accent]).margin(6)
    } else if (!this.landscape && ratingText(this.cur.rating).length > 0) {
      Row({ space: 2 }) {
        SymbolGlyph($r('sys.symbol.star_fill')).fontSize(10).fontColor(['#FFC107'])
        Text(ratingText(this.cur.rating)).fontSize(11).fontColor(Color.White)
      }
      .padding({ left: 5, right: 5, top: 2, bottom: 2 })
      .borderRadius(4).backgroundColor('#AA000000').margin(6)
    }
  }

  build() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        NetImage({ src: this.imageUrl(), placeholderText: cardTitle(this.cur) })
        this.badges()
        if (this.cur.state.favorite) {
          Column() {
            SymbolGlyph($r('sys.symbol.heart_fill')).fontSize(14).fontColor([Theme.accent])
          }
          .position({ x: 6, y: 6 })
        }
        if (progressOf(this.cur) > 0 && !this.cur.state.played) {
          Column() {
            Progress({ value: progressOf(this.cur) * 100, total: 100, type: ProgressType.Linear })
              .color(Theme.accent).backgroundColor('#66FFFFFF')
              .width('100%').height(4)
          }
          .width('100%')
          .padding({ left: 8, right: 8, bottom: 8 })
          .position({ x: 0, y: this.imgHeight() - 12 })
        }
        if (this.landscape) {
          Column() {
            SymbolGlyph($r('sys.symbol.play_fill')).fontSize(18).fontColor([Color.White])
          }
          .width(40).height(40).borderRadius(20)
          .backgroundColor('#88000000')
          .justifyContent(FlexAlign.Center)
          .position({ x: this.cardWidth / 2 - 20, y: this.imgHeight() / 2 - 20 })
          .opacity(this.active ? 1 : 0)
        }
      }
      .width(this.cardWidth).height(this.imgHeight())
      .borderRadius(Theme.radius).clip(true)
      .backgroundColor(Theme.surface2)
      .border({ width: this.active ? 2 : 0, color: Color.White, radius: Theme.radius })
      .shadow(this.active ? { radius: 18, color: '#80000000', offsetY: 6 } : { radius: 0, color: Color.Transparent })

      Text(cardTitle(this.cur))
        .fontSize(this.landscape ? 14 : 13).fontColor(this.active ? Color.White : Theme.text)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(this.cardWidth)
      if (this.showSubtitle) {
        Text(this.landscape && progressOf(this.cur) > 0 ? cardSubtitle(this.cur) + (cardSubtitle(this.cur).length > 0 ? ' · ' : '') + remainingText(this.cur)
          : (cardSubtitle(this.cur).length > 0 ? cardSubtitle(this.cur) : ' '))
          .fontSize(11).fontColor(Theme.text3)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(this.cardWidth)
      }
    }
    .width(this.cardWidth)
    .alignItems(HorizontalAlign.Start)
    .scale({ x: this.active ? 1.06 : 1, y: this.active ? 1.06 : 1 })
    .animation({ duration: 180, curve: Curve.EaseOut })
    .zIndex(this.active ? 1 : 0)
    .focusable(true)
    .onFocus(() => { this.active = true; })
    .onBlur(() => { this.active = false; })
    .onHover((h: boolean) => { this.active = h; })
    .onClick(() => this.open())
    .bindContextMenu(this.contextMenu, ResponseType.LongPress)
    .bindContextMenu(this.contextMenu, ResponseType.RightClick)
  }
}
