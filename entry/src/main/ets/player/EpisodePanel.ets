import { MediaItem } from '../common/Models';
import { Theme } from '../common/Theme';
import { formatRuntime, progressFraction, seasonLabel } from '../components/detail/DetailLogic';

/** Episode card data with the thumbnail URL already resolved by the provider. */
export class EpisodeCard {
  item: MediaItem = new MediaItem();
  thumb: string = '';
}

/**
 * Netflix-style episode picker over the video: season tabs, then one card per episode with
 * still, progress, runtime and synopsis. The playing episode is highlighted and scrolled into view.
 */
@Component
export struct EpisodePanel {
  @Prop seriesTitle: string = '';
  @Prop seasons: MediaItem[] = [];
  @Prop seasonId: string = '';
  @Prop cards: EpisodeCard[] = [];
  @Prop currentId: string = '';
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop panelWidth: number = 440;
  onPickSeason: (seasonId: string) => void = (s: string) => {};
  onPickEpisode: (episodeId: string) => void = (e: string) => {};
  onClose: () => void = () => {};
  private scroller: Scroller = new Scroller();

  private currentIndex(): number {
    const i = this.cards.findIndex((c: EpisodeCard) => c.item.id === this.currentId);
    return i < 0 ? 0 : i;
  }

  private thumbWidth(): number {
    return this.panelWidth >= 420 ? 152 : 128;
  }

  @Builder
  seasonTabs() {
    if (this.seasons.length > 1) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.seasons, (s: MediaItem) => {
            Text(seasonLabel(s))
              .fontSize(14)
              .fontColor(s.id === this.seasonId ? Color.Black : Theme.text)
              .fontWeight(s.id === this.seasonId ? FontWeight.Bold : FontWeight.Normal)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .borderRadius(16)
              .backgroundColor(s.id === this.seasonId ? Color.White : '#26FFFFFF')
              .onClick(() => {
                if (s.id !== this.seasonId) {
                  this.onPickSeason(s.id);
                }
              })
          }, (s: MediaItem) => s.id)
        }
        .padding({ left: 20, right: 20 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .margin({ bottom: 8 })
    }
  }

  @Builder
  card(c: EpisodeCard) {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.Center }) {
          if (c.thumb.length > 0) {
            Image(c.thumb).width('100%').height('100%').objectFit(ImageFit.Cover)
          }
          Row() {
            SymbolGlyph($r('sys.symbol.play_fill')).fontSize(16).fontColor([Color.White])
          }
          .width(34).height(34).borderRadius(17)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#80000000')
          .border({ width: 1.5, color: '#CCFFFFFF', radius: 17 })
          if (progressFraction(c.item) > 0 && !c.item.state.played) {
            Column() {
              Blank()
              Progress({ value: progressFraction(c.item) * 100, total: 100, type: ProgressType.Linear })
                .color(Theme.accent).backgroundColor('#66FFFFFF').width('100%').height(3)
            }
            .width('100%').height('100%')
          }
        }
        .width(this.thumbWidth()).height(this.thumbWidth() * 9 / 16)
        .borderRadius(6).clip(true)
        .backgroundColor(Theme.surface2)

        Column({ space: 4 }) {
          Text((c.item.episodeNumber >= 0 ? c.item.episodeNumber + '. ' : '') +
            (c.item.title.length > 0 ? c.item.title : '第 ' + c.item.episodeNumber + ' 集'))
            .fontSize(15).fontWeight(FontWeight.Bold)
            .fontColor(c.item.id === this.currentId ? Theme.accent : Theme.text)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 8 }) {
            if (c.item.id === this.currentId) {
              Text('正在播放').fontSize(11).fontColor(Color.White)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(4).backgroundColor(Theme.accent)
            } else if (c.item.state.played) {
              Text('已看').fontSize(11).fontColor(Theme.text2)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(4).backgroundColor('#26FFFFFF')
            }
            if (c.item.runtimeMs > 0) {
              Text(formatRuntime(c.item.runtimeMs)).fontSize(12).fontColor(Theme.text3)
            }
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (c.item.overview.length > 0) {
        Text(c.item.overview)
          .fontSize(13).fontColor(Theme.text2).lineHeight(19)
          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .borderRadius(10)
    .backgroundColor(c.item.id === this.currentId ? '#1FFFFFFF' : Color.Transparent)
    .onClick(() => this.onPickEpisode(c.item.id))
  }

  build() {
    Row() {
      Blank()
        .layoutWeight(1)
        .height('100%')
        .onClick(() => this.onClose())
      Column() {
        Row() {
          Column({ space: 2 }) {
            Text('选集').fontSize(12).fontColor(Theme.text3)
            Text(this.seriesTitle)
              .fontSize(19).fontWeight(FontWeight.Bold).fontColor(Theme.text)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Row() {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([Theme.text2])
          }
          .width(36).height(36).borderRadius(18).justifyContent(FlexAlign.Center)
          .backgroundColor('#1FFFFFFF')
          .onClick(() => this.onClose())
        }
        .width('100%')
        .padding({ left: 20, right: 16, top: 20, bottom: 12 })

        this.seasonTabs()

        if (this.loading) {
          Column() {
            LoadingProgress().width(36).height(36).color(Theme.text2)
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
        } else if (this.error.length > 0 || this.cards.length === 0) {
          Text(this.error.length > 0 ? this.error : '这一季暂无剧集')
            .fontSize(14).fontColor(Theme.text3).textAlign(TextAlign.Center)
            .layoutWeight(1).width('100%').padding(24)
        } else {
          List({ scroller: this.scroller, initialIndex: this.currentIndex(), space: 2 }) {
            ForEach(this.cards, (c: EpisodeCard) => {
              ListItem() {
                this.card(c)
              }
              .padding({ left: 4, right: 4 })
            }, (c: EpisodeCard) => c.item.id + '|' + (c.item.id === this.currentId ? '1' : '0') +
              (c.item.state.played ? 'p' : '') + Math.round(c.item.state.positionMs / 1000))
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .contentEndOffset(16)
        }
      }
      .width(this.panelWidth)
      .height('100%')
      .backgroundColor('#F20E1118')
      .backdropBlur(30)
    }
    .width('100%')
    .height('100%')
  }
}
