import { router, promptAction } from '@kit.ArkUI';
import { BusinessError, deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { Theme } from '../common/Theme';
import { AppLog, LogLine, formatLine } from '../common/AppLog';

const APP_VERSION: string = '1.1.0-flicx';

@Entry
@Component
struct LogViewPage {
  @State lines: LogLine[] = [];
  @State onlyProblems: boolean = false;
  private unsub: () => void = () => {};
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.refresh();
    this.unsub = AppLog.onChange(() => this.refresh());
  }

  aboutToDisappear(): void {
    this.unsub();
  }

  private refresh(): void {
    this.lines = AppLog.all();
  }

  private shown(): LogLine[] {
    return this.onlyProblems ? this.lines.filter((l: LogLine) => l.level !== 'I') : this.lines;
  }

  private toast(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 2000 });
    } catch (e) {
      // toast is best effort
    }
  }

  private header(): string[] {
    const out: string[] = ['影库 ' + APP_VERSION + ' 运行日志'];
    try {
      out.push('设备: ' + deviceInfo.marketName + ' (' + deviceInfo.productModel + ')');
      out.push('系统: ' + deviceInfo.osFullName + ' / API ' + deviceInfo.sdkApiVersion);
    } catch (e) {
      out.push('设备: 未知');
    }
    out.push('----');
    return out;
  }

  private copy(): void {
    if (this.lines.length === 0) {
      this.toast('还没有日志');
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, AppLog.dump(this.header()));
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.toast('已复制 ' + this.lines.length + ' 行日志');
      }).catch((e: BusinessError) => {
        this.toast('复制失败：' + e.message);
      });
    } catch (e) {
      this.toast('复制失败');
    }
  }

  private levelColor(level: string): ResourceColor {
    return level === 'E' ? '#FF6B6B' : (level === 'W' ? '#FFC107' : Theme.text2);
  }

  build() {
    Column() {
      Row() {
        Text('‹').fontSize(30).fontColor(Theme.text).padding({ right: 12 }).onClick(() => router.back())
        Text('运行日志').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Theme.text).layoutWeight(1)
        Text(this.lines.length + ' 行').fontSize(12).fontColor(Theme.text3)
      }
      .width('100%').height(56).padding({ left: Theme.pagePad, right: Theme.pagePad })

      Row({ space: 10 }) {
        Button('复制全部').fontSize(14).fontColor(Color.White).backgroundColor(Theme.accent).height(36)
          .onClick(() => this.copy())
        Button(this.onlyProblems ? '显示全部' : '只看警告/错误').fontSize(14).fontColor(Theme.text)
          .backgroundColor(Theme.surface2).height(36)
          .onClick(() => { this.onlyProblems = !this.onlyProblems; })
        Button('清空').fontSize(14).fontColor(Theme.text).backgroundColor(Theme.surface2).height(36)
          .onClick(() => AppLog.clear())
      }
      .width('100%').padding({ left: Theme.pagePad, right: Theme.pagePad, bottom: 8 })

      Text('日志只保存在内存里，退出应用后清空。链接里的签名和令牌已隐去。复现问题后再来这里复制。')
        .fontSize(12).fontColor(Theme.text3).width('100%')
        .padding({ left: Theme.pagePad, right: Theme.pagePad, bottom: 8 })

      if (this.shown().length === 0) {
        Text(this.onlyProblems ? '没有警告或错误' : '还没有日志').fontSize(14).fontColor(Theme.text2)
          .width('100%').textAlign(TextAlign.Center).padding({ top: 48 })
      } else {
        List({ scroller: this.scroller, initialIndex: Math.max(0, this.shown().length - 1) }) {
          ForEach(this.shown(), (l: LogLine) => {
            ListItem() {
              Text(formatLine(l))
                .fontSize(12).fontFamily('monospace').fontColor(this.levelColor(l.level))
                .copyOption(CopyOptions.LocalDevice)
                .width('100%').padding({ left: Theme.pagePad, right: Theme.pagePad, top: 3, bottom: 3 })
            }
          }, (l: LogLine, i: number) => l.time + ':' + i)
        }
        .layoutWeight(1).width('100%')
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%').height('100%')
    .backgroundColor(Theme.bg)
  }
}
