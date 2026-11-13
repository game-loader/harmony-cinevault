import { Theme } from '../../common/Theme';

/** Progress of a Quark library scrape. Parent passes @Link state so it updates live. */
@CustomDialog
export struct ScanProgressDialog {
  controller?: CustomDialogController;
  @Link sourceName: string;
  @Link done: number;
  @Link total: number;
  @Link matched: number;
  @Link failed: number;
  @Link current: string;
  @Link finished: boolean;
  @Link error: string;

  build() {
    Column() {
      Text(this.finished ? '刮削完成' : `正在刮削：${this.sourceName}`)
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor(Theme.text)
      if (!this.finished) {
        Progress({ value: this.done, total: this.total > 0 ? this.total : 1, type: ProgressType.Linear })
          .color(Theme.accent).width('100%').margin({ top: 16 })
        Text(this.total > 0 ? `${this.done} / ${this.total}` : '正在列出网盘文件…')
          .fontSize(14).fontColor(Theme.text2).margin({ top: 8 })
        if (this.current) {
          Text(this.current).fontSize(12).fontColor(Theme.text3).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 6 })
        }
      }
      if (this.error) {
        Text(this.error).fontSize(14).fontColor(Theme.accent).margin({ top: 12 })
      }
      Text(`已匹配 ${this.matched}，未匹配 ${this.failed}`)
        .fontSize(14).fontColor(Theme.text2).margin({ top: 12 })
      if (this.finished) {
        Button('完成')
          .backgroundColor(Theme.accent).fontColor(Color.White)
          .width('100%').margin({ top: 20 })
          .onClick(() => {
            if (this.controller) {
              this.controller.close();
            }
          })
      } else {
        Text('刮削在后台进行，请勿退出此页面').fontSize(12).fontColor(Theme.text3).margin({ top: 16 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(24)
    .width('86%')
    .constraintSize({ maxWidth: 480 })
    .backgroundColor(Theme.surface)
    .borderRadius(Theme.radius)
  }
}
