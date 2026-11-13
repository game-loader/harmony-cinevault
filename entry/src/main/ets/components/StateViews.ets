import { Theme } from '../common/Theme';

@Component
export struct LoadingView {
  @Prop message: string = '加载中…';

  build() {
    Column({ space: 12 }) {
      LoadingProgress().width(40).height(40).color(Theme.accent)
      Text(this.message).fontSize(14).fontColor(Theme.text2)
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct EmptyView {
  @Prop title: string = '这里空空如也';
  @Prop message: string = '';
  @Prop actionText: string = '';
  onAction: () => void = () => {};

  build() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.film')).fontSize(48).fontColor([Theme.text3])
      Text(this.title).fontSize(17).fontColor(Theme.text).fontWeight(FontWeight.Medium)
      if (this.message.length > 0) {
        Text(this.message).fontSize(13).fontColor(Theme.text2).textAlign(TextAlign.Center).maxLines(4)
      }
      if (this.actionText.length > 0) {
        Button(this.actionText)
          .fontSize(14).fontColor(Color.White).backgroundColor(Theme.accent)
          .height(38).padding({ left: 20, right: 20 }).margin({ top: 6 })
          .onClick(() => this.onAction())
      }
    }
    .width('100%').height('100%')
    .padding(Theme.pagePad)
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct ErrorView {
  @Prop title: string = '加载失败';
  @Prop message: string = '';
  @Prop retryText: string = '重试';
  onRetry: () => void = () => {};

  build() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle')).fontSize(44).fontColor([Theme.accent])
      Text(this.title).fontSize(17).fontColor(Theme.text).fontWeight(FontWeight.Medium)
      if (this.message.length > 0) {
        Text(this.message).fontSize(13).fontColor(Theme.text2).textAlign(TextAlign.Center).maxLines(5)
      }
      Button(this.retryText)
        .fontSize(14).fontColor(Color.White).backgroundColor(Theme.surface2)
        .height(38).padding({ left: 20, right: 20 }).margin({ top: 6 })
        .onClick(() => this.onRetry())
    }
    .width('100%').height('100%')
    .padding(Theme.pagePad)
    .justifyContent(FlexAlign.Center)
  }
}

/** Small inline warning strip (per-source failures). */
@Component
export struct InlineWarning {
  @Prop text: string = '';
  onClose: () => void = () => {};

  build() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle')).fontSize(16).fontColor(['#FFB74D'])
      Text(this.text).fontSize(12).fontColor('#FFE0B2').layoutWeight(1)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      SymbolGlyph($r('sys.symbol.xmark')).fontSize(14).fontColor([Theme.text2])
        .onClick(() => this.onClose())
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .borderRadius(8)
    .backgroundColor('#33FF9800')
  }
}

/** Footer for paged lists. */
@Component
export struct LoadMoreFooter {
  @Prop loading: boolean = false;
  @Prop hasMore: boolean = true;
  @Prop error: string = '';
  onRetry: () => void = () => {};

  build() {
    Row({ space: 8 }) {
      if (this.loading) {
        LoadingProgress().width(22).height(22).color(Theme.text2)
        Text('加载中…').fontSize(13).fontColor(Theme.text2)
      } else if (this.error.length > 0) {
        Text('加载失败，点击重试').fontSize(13).fontColor(Theme.accent).onClick(() => this.onRetry())
      } else if (!this.hasMore) {
        Text('— 已经到底了 —').fontSize(12).fontColor(Theme.text3)
      }
    }
    .width('100%').height(56)
    .justifyContent(FlexAlign.Center)
  }
}
