import { Theme } from '../common/Theme';

/** One selectable row in a player side panel (speed / quality / audio / subtitle / aspect / episodes). */
export class SheetItem {
  key: string = '';
  label: string = '';
  sub: string = '';
  selected: boolean = false;
  image: string = '';

  constructor(key: string, label: string, sub: string, selected: boolean) {
    this.key = key;
    this.label = label;
    this.sub = sub;
    this.selected = selected;
  }
}

/** Extra +/- stepper row shown on top of a sheet (subtitle delay / size). */
export class SheetStepper {
  key: string = '';
  label: string = '';
  value: string = '';

  constructor(key: string, label: string, value: string) {
    this.key = key;
    this.label = label;
    this.value = value;
  }
}

/** Right-side panel listing options; tapping outside closes it. */
@Component
export struct TrackSheet {
  @Prop title: string = '';
  @Prop items: SheetItem[] = [];
  @Prop steppers: SheetStepper[] = [];
  @Prop loading: boolean = false;
  @Prop emptyText: string = '暂无可选项';
  @Prop panelWidth: number = 320;
  @Prop showImages: boolean = false;
  onPick: (key: string) => void = (k: string) => {};
  onStep: (key: string, delta: number) => void = (k: string, d: number) => {};
  onClose: () => void = () => {};

  build() {
    Row() {
      Blank()
        .layoutWeight(1)
        .height('100%')
        .onClick(() => this.onClose())
      Column() {
        Text(this.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text)
          .width('100%')
          .padding({ left: 20, right: 20, top: 20, bottom: 12 })
        ForEach(this.steppers, (s: SheetStepper) => {
          Row() {
            Text(s.label).fontSize(14).fontColor(Theme.text2).layoutWeight(1)
            Button('-')
              .type(ButtonType.Circle)
              .width(32).height(32)
              .fontSize(18)
              .backgroundColor(Theme.surface2)
              .fontColor(Theme.text)
              .onClick(() => this.onStep(s.key, -1))
            Text(s.value)
              .fontSize(14)
              .fontColor(Theme.text)
              .width(72)
              .textAlign(TextAlign.Center)
            Button('+')
              .type(ButtonType.Circle)
              .width(32).height(32)
              .fontSize(18)
              .backgroundColor(Theme.surface2)
              .fontColor(Theme.text)
              .onClick(() => this.onStep(s.key, 1))
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 6, bottom: 6 })
        }, (s: SheetStepper) => s.key + s.value)
        if (this.loading) {
          Column() {
            LoadingProgress().width(36).height(36).color(Theme.text2)
            Text('加载中…').fontSize(13).fontColor(Theme.text2).margin({ top: 8 })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.items.length === 0) {
          Text(this.emptyText)
            .fontSize(14)
            .fontColor(Theme.text3)
            .layoutWeight(1)
            .width('100%')
            .textAlign(TextAlign.Center)
        } else {
          List() {
            ForEach(this.items, (it: SheetItem) => {
              ListItem() {
                Row() {
                  if (this.showImages && it.image.length > 0) {
                    Image(it.image)
                      .width(96)
                      .height(54)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(6)
                      .backgroundColor(Theme.surface2)
                      .margin({ right: 12 })
                  }
                  Column() {
                    Text(it.label)
                      .fontSize(15)
                      .fontColor(it.selected ? Theme.accent : Theme.text)
                      .fontWeight(it.selected ? FontWeight.Bold : FontWeight.Normal)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (it.sub.length > 0) {
                      Text(it.sub)
                        .fontSize(12)
                        .fontColor(Theme.text3)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .margin({ top: 2 })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  if (it.selected) {
                    Text('✓').fontSize(16).fontColor(Theme.accent)
                  }
                }
                .width('100%')
                .padding({ left: 20, right: 20, top: 12, bottom: 12 })
                .backgroundColor(it.selected ? '#22FFFFFF' : Color.Transparent)
                .onClick(() => this.onPick(it.key))
              }
            }, (it: SheetItem) => it.key + (it.selected ? '1' : '0'))
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Auto)
        }
      }
      .width(this.panelWidth)
      .height('100%')
      .backgroundColor('#F2151925')
      .padding({ bottom: 12 })
    }
    .width('100%')
    .height('100%')
  }
}
