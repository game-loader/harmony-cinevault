import { Theme } from '../common/Theme';
import { InfoRow } from './PlayerLogic';

/** "播放信息" overlay (stats for nerds): label/value rows in the top-left corner. */
@Component
export struct PlaybackInfoPanel {
  @Prop rows: InfoRow[] = [];
  onClose: () => void = () => {};

  build() {
    Column() {
      Row() {
        Text('播放信息').fontSize(15).fontWeight(FontWeight.Bold).fontColor(Color.White).layoutWeight(1)
        Text('✕')
          .fontSize(15)
          .fontColor(Theme.text2)
          .padding({ left: 12, right: 4, top: 2, bottom: 2 })
          .onClick(() => this.onClose())
      }
      .width('100%')
      .margin({ bottom: 6 })
      ForEach(this.rows, (r: InfoRow) => {
        Row() {
          Text(r.label).fontSize(12).fontColor(Theme.text2).width(72)
          Text(r.value)
            .fontSize(12)
            .fontColor(Color.White)
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .padding({ top: 2, bottom: 2 })
      }, (r: InfoRow, i: number) => i + ':' + r.label + '=' + r.value)
    }
    .width(380)
    .padding(12)
    .borderRadius(8)
    .backgroundColor('#B3000000')
  }
}
