import { MediaItem, Person } from '../../common/Models';
import { Theme } from '../../common/Theme';
import { episodeCode, formatRuntime, progressFraction, formatRating } from './DetailLogic';

/** Poster card for the 相似推荐 row. */
@Component
export struct DetailPosterCard {
  @Prop item: MediaItem = new MediaItem();
  @Prop imageUrl: string = '';
  @Prop cardWidth: number = 120;
  onTap: () => void = () => {};

  build() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (this.imageUrl.length > 0) {
          Image(this.imageUrl)
            .width('100%').height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            Text(this.item.title.substring(0, 1))
              .fontSize(32).fontColor(Theme.text3).fontWeight(FontWeight.Bold)
          }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        }
        if (this.item.state.played) {
          Text('✓')
            .fontSize(11).fontColor(Color.White)
            .width(20).height(20).textAlign(TextAlign.Center)
            .borderRadius(10).backgroundColor(Theme.accent)
            .margin(6)
        } else if (this.item.rating > 0) {
          Text(formatRating(this.item.rating))
            .fontSize(11).fontColor(Color.White)
            .padding({ left: 5, right: 5, top: 2, bottom: 2 })
            .borderRadius(4).backgroundColor('#99000000')
            .margin(6)
        }
      }
      .width(this.cardWidth).height(this.cardWidth * 1.5)
      .borderRadius(Theme.radius).clip(true)
      .backgroundColor(Theme.surface2)

      Text(this.item.title)
        .fontSize(13).fontColor(Theme.text)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(this.cardWidth)
      Text(this.item.year > 0 ? this.item.year.toString() : ' ')
        .fontSize(11).fontColor(Theme.text3).width(this.cardWidth)
    }
    .alignItems(HorizontalAlign.Start)
    .onClick(() => this.onTap())
  }
}

/** Cast member with circular avatar. */
@Component
export struct PersonAvatar {
  @Prop person: Person = new Person();
  @Prop avatarSize: number = 72;

  build() {
    Column({ space: 4 }) {
      Stack() {
        Text(this.person.name.substring(0, 1))
          .fontSize(this.avatarSize * 0.36).fontColor(Theme.text2)
        if (this.person.image.length > 0) {
          Image(this.person.image)
            .width('100%').height('100%')
            .objectFit(ImageFit.Cover)
        }
      }
      .width(this.avatarSize).height(this.avatarSize)
      .borderRadius(this.avatarSize / 2).clip(true)
      .backgroundColor(Theme.surface2)

      Text(this.person.name)
        .fontSize(12).fontColor(Theme.text)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center).width(this.avatarSize + 16)
      Text(this.person.role)
        .fontSize(11).fontColor(Theme.text3)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center).width(this.avatarSize + 16)
    }
  }
}

/** One episode in the season list. */
@Component
export struct EpisodeRow {
  @Prop ep: MediaItem = new MediaItem();
  @Prop thumbUrl: string = '';
  @Prop wide: boolean = false;
  @Prop current: boolean = false;
  onTap: () => void = () => {};
  onLong: () => void = () => {};

  build() {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Bottom }) {
        if (this.thumbUrl.length > 0) {
          Image(this.thumbUrl)
            .width('100%').height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            Text('▶').fontSize(20).fontColor(Theme.text3)
          }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        }
        if (progressFraction(this.ep) > 0 && !this.ep.state.played) {
          Progress({ value: progressFraction(this.ep) * 100, total: 100, type: ProgressType.Linear })
            .color(Theme.accent).backgroundColor('#66000000')
            .width('100%').height(3)
        }
        if (this.ep.state.played) {
          Row() {
            Text('✓')
              .fontSize(11).fontColor(Color.White)
              .width(20).height(20).textAlign(TextAlign.Center)
              .borderRadius(10).backgroundColor(Theme.accent)
          }.width('100%').height('100%')
          .justifyContent(FlexAlign.End).alignItems(VerticalAlign.Top).padding(6)
        }
      }
      .width(this.wide ? 200 : 140).height(this.wide ? 112 : 79)
      .borderRadius(8).clip(true)
      .backgroundColor(Theme.surface2)

      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(episodeCode(this.ep.seasonNumber, this.ep.episodeNumber))
            .fontSize(12).fontColor(this.current ? Theme.accent : Theme.text2)
          Text(formatRuntime(this.ep.runtimeMs))
            .fontSize(12).fontColor(Theme.text3)
        }
        Text(this.ep.title)
          .fontSize(15).fontColor(Theme.text).fontWeight(FontWeight.Medium)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.ep.overview)
          .fontSize(12).fontColor(Theme.text2)
          .maxLines(this.wide ? 3 : 2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(8)
    .borderRadius(Theme.radius)
    .backgroundColor(this.current ? Theme.surface2 : Color.Transparent)
    .alignItems(VerticalAlign.Top)
    .onClick(() => this.onTap())
    .gesture(LongPressGesture({ repeat: false }).onAction(() => this.onLong()))
  }
}
