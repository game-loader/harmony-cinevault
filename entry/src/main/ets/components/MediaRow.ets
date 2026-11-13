import { HomeRow, MediaItem } from '../common/Models';
import { Theme } from '../common/Theme';
import { MediaCard } from './MediaCard';
import { itemKey } from './MediaLogic';

/** Horizontal row of media cards with a header and optional "查看全部". */
@Component
export struct MediaRow {
  @Prop row: HomeRow = new HomeRow();
  /** Poster width; landscape cards are ~1.8x wider. */
  @Prop posterWidth: number = 130;
  @Prop sidePad: number = Theme.pagePad;
  @Prop showMore: boolean = false;
  onMore: () => void = () => {};
  onChanged: (item: MediaItem) => void = () => {};

  private cardW(): number {
    return this.row.style === 'landscape' ? Math.round(this.posterWidth * 1.85) : this.posterWidth;
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Text(this.row.title)
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(Theme.text)
          .layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.showMore) {
          Row({ space: 2 }) {
            Text('查看全部').fontSize(13).fontColor(Theme.text2)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([Theme.text2])
          }
          .onClick(() => this.onMore())
        }
      }
      .width('100%')
      .padding({ left: this.sidePad, right: this.sidePad })

      List({ space: 14 }) {
        ForEach(this.row.items, (it: MediaItem) => {
          ListItem() {
            MediaCard({
              item: it,
              landscape: this.row.style === 'landscape',
              cardWidth: this.cardW(),
              playOnTap: this.row.key === 'resume' || this.row.key === 'nextup',
              onChanged: (n: MediaItem) => this.onChanged(n)
            })
          }
          .padding({ top: 8, bottom: 4 })
        }, (it: MediaItem) => itemKey(it) + '|' + (it.state.played ? '1' : '0') + (it.state.favorite ? '1' : '0'))
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .contentStartOffset(this.sidePad)
      .contentEndOffset(this.sidePad)
      .cachedCount(4)
      .clip(false)
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
