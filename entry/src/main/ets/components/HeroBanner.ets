import { MediaItem } from '../common/Models';
import { Theme } from '../common/Theme';
import { Nav } from '../common/Nav';
import { NetImage } from './NetImage';
import { imageFor } from './MediaActions';
import { ratingText, typeLabel, itemKey } from './MediaLogic';

/** Auto-rotating backdrop banner with gradient scrim, logo/title, meta and 播放 / 详情 buttons. */
@Component
export struct HeroBanner {
  @Prop items: MediaItem[] = [];
  @Prop bannerHeight: number = 420;
  /** Large-screen layout: bigger type, overview, left-aligned content block. */
  @Prop large: boolean = true;
  @Prop sidePad: number = Theme.pagePad;
  @State private index: number = 0;
  @State private zoom: boolean = false;
  private controller: SwiperController = new SwiperController();

  aboutToAppear(): void {
    this.zoom = true;
  }

  private meta(it: MediaItem): string {
    const parts: string[] = [];
    parts.push(typeLabel(it.type));
    if (it.year > 0) {
      parts.push(it.year.toString());
    }
    if (it.officialRating.length > 0) {
      parts.push(it.officialRating);
    }
    if (it.runtimeMs > 0 && it.type === 'movie') {
      const m = Math.round(it.runtimeMs / 60000);
      parts.push(m >= 60 ? Math.floor(m / 60).toString() + '小时' + (m % 60).toString() + '分' : m.toString() + '分钟');
    }
    if (it.genres.length > 0) {
      parts.push(it.genres.slice(0, 3).join(' / '));
    }
    return parts.join('  ·  ');
  }

  @Builder
  slide(it: MediaItem, idx: number) {
    Stack({ alignContent: Alignment.BottomStart }) {
      Stack() {
        NetImage({
          src: imageFor(it, 'backdrop', this.large ? 1920 : 1080).length > 0
            ? imageFor(it, 'backdrop', this.large ? 1920 : 1080) : imageFor(it, 'poster', 900),
          placeholderColor: Theme.surface
        })
      }
      .width('100%').height('100%')
      .scale({ x: this.zoom && idx === this.index ? 1.08 : 1, y: this.zoom && idx === this.index ? 1.08 : 1 })
      .animation({ duration: 9000, curve: Curve.Linear })

      // bottom scrim into the page background
      Column()
        .width('100%').height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [['#000B0D12', 0.35], ['#990B0D12', 0.7], [Theme.bg, 1.0]]
        })
      if (this.large) {
        // left scrim for text legibility
        Column()
          .width('100%').height('100%')
          .linearGradient({
            direction: GradientDirection.Right,
            colors: [['#CC0B0D12', 0.0], ['#660B0D12', 0.4], ['#000B0D12', 0.75]]
          })
      }

      Column({ space: this.large ? 12 : 8 }) {
        if (it.images.logo.length > 0 || imageFor(it, 'logo', 800).length > 0) {
          Image(imageFor(it, 'logo', 800))
            .height(this.large ? 110 : 64)
            .width(this.large ? '42%' : '70%')
            .objectFit(ImageFit.Contain)
            .objectRepeat(ImageRepeat.NoRepeat)
            .alignSelf(ItemAlign.Start)
            .draggable(false)
        } else {
          Text(it.title)
            .fontSize(this.large ? 42 : 26).fontWeight(FontWeight.Bolder).fontColor(Color.White)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Row({ space: 10 }) {
          if (ratingText(it.rating).length > 0) {
            Row({ space: 3 }) {
              SymbolGlyph($r('sys.symbol.star_fill')).fontSize(13).fontColor(['#FFC107'])
              Text(ratingText(it.rating)).fontSize(14).fontColor('#FFC107').fontWeight(FontWeight.Medium)
            }
          }
          Text(this.meta(it)).fontSize(this.large ? 14 : 12).fontColor(Theme.text2)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }
        if (this.large && it.overview.length > 0) {
          Text(it.overview)
            .fontSize(14).fontColor('#D0D4DC').lineHeight(21)
            .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('46%')
        }
        Row({ space: 12 }) {
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.play_fill')).fontSize(16).fontColor([Color.Black])
              Text('播放').fontSize(15).fontColor(Color.Black).fontWeight(FontWeight.Medium)
            }
          }
          .type(ButtonType.Capsule)
          .backgroundColor(Color.White)
          .height(this.large ? 44 : 38).padding({ left: 22, right: 24 })
          .onClick(() => {
            if (it.type === 'series') {
              Nav.detail(it.sourceId, it.id);
            } else {
              Nav.play(it.sourceId, it.id, -1);
            }
          })
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.info_circle')).fontSize(16).fontColor([Color.White])
              Text('详情').fontSize(15).fontColor(Color.White)
            }
          }
          .type(ButtonType.Capsule)
          .backgroundColor('#40FFFFFF')
          .height(this.large ? 44 : 38).padding({ left: 20, right: 22 })
          .onClick(() => Nav.detail(it.sourceId, it.id))
        }
        .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: this.sidePad, right: this.sidePad, bottom: this.large ? 56 : 36 })
    }
    .width('100%').height('100%')
    .clip(true)
    .onClick(() => Nav.detail(it.sourceId, it.id))
  }

  build() {
    Stack() {
      if (this.items.length > 0) {
        Swiper(this.controller) {
          ForEach(this.items, (it: MediaItem, idx: number) => {
            this.slide(it, idx)
          }, (it: MediaItem) => itemKey(it))
        }
        .index(this.index)
        .autoPlay(this.items.length > 1)
        .interval(7000)
        .loop(this.items.length > 1)
        .duration(700)
        .curve(Curve.EaseInOut)
        .indicator(this.items.length > 1 ? new DotIndicator()
          .itemWidth(7).itemHeight(7).selectedItemWidth(20).selectedItemHeight(7)
          .color('#66FFFFFF').selectedColor(Color.White)
          .right(this.sidePad).bottom(this.large ? 22 : 12) : false)
        .onChange((i: number) => {
          this.zoom = false;
          this.index = i;
          setTimeout(() => { this.zoom = true; }, 30);
        })
        .width('100%').height('100%')
      }
    }
    .width('100%').height(this.bannerHeight)
    .backgroundColor(Theme.surface)
  }
}
