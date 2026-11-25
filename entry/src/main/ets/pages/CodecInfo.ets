import { router, promptAction } from '@kit.ArkUI';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { Theme } from '../common/Theme';
import { CodecCaps, CodecEntry } from '../media/CodecCaps';
import {
  CodecRow, SummaryChip, buildRows, summaryChips, groupCount, statusText, statusColor, statusBgColor
} from '../components/settings/CodecInfoLogic';
import { AppLog } from '../common/AppLog';

@Entry
@Component
struct CodecInfoPage {
  @State videoRows: CodecRow[] = [];
  @State audioRows: CodecRow[] = [];
  @State chips: SummaryChip[] = [];
  @State probing: boolean = false;
  /** Bumped on every probe so ForEach keys change and rows rebuild */
  @State gen: number = 0;

  aboutToAppear(): void {
    this.apply(CodecCaps.entries());
    if (this.videoRows.every((r: CodecRow) => r.status === 'none') &&
      this.audioRows.every((r: CodecRow) => r.status === 'none')) {
      this.reprobe(false);
    }
  }

  private apply(entries: CodecEntry[]): void {
    this.videoRows = buildRows(entries, true);
    this.audioRows = buildRows(entries, false);
    this.chips = summaryChips(entries);
    this.gen++;
  }

  private toast(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 2000 });
    } catch (e) {
      AppLog.error(`[CodecInfo] toast: ${(e as Error).message}`);
    }
  }

  private reprobe(notify: boolean): void {
    if (this.probing) {
      return;
    }
    this.probing = true;
    // Defer so the spinner renders before the synchronous native probe runs.
    setTimeout(() => {
      let entries: CodecEntry[] = [];
      try {
        entries = CodecCaps.load();
      } catch (e) {
        AppLog.error(`[CodecInfo] probe failed: ${(e as Error).message}`);
      }
      this.apply(entries);
      this.probing = false;
      if (notify) {
        this.toast(entries.length > 0 ? '已重新检测' : '检测失败，未获取到解码器信息');
      }
    }, 16);
  }

  private copyReport(): void {
    try {
      const text = CodecCaps.report();
      if (!text) {
        this.toast('暂无检测结果');
        return;
      }
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.toast('报告已复制到剪贴板');
      }).catch((e: BusinessError) => {
        AppLog.error(`[CodecInfo] setData: ${e.code} ${e.message}`);
        this.toast('复制失败');
      });
    } catch (e) {
      const err = e as BusinessError;
      AppLog.error(`[CodecInfo] copy: ${err.code} ${err.message}`);
      this.toast('复制失败');
    }
  }

  @Builder
  Chip(c: SummaryChip) {
    Text(c.text)
      .fontSize(13).fontColor(statusColor(c.status))
      .backgroundColor(statusBgColor(c.status)).borderRadius(14)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .margin({ right: 8, bottom: 8 })
  }

  @Builder
  GroupHeader(title: string, count: string) {
    Row() {
      Text(title).fontSize(13).fontColor(Theme.text3).layoutWeight(1)
      Text(count).fontSize(12).fontColor(Theme.text3)
    }
    .padding({ left: 16, right: 16, top: 20, bottom: 8 })
    .width('100%')
    .backgroundColor(Theme.bg)
  }

  @Builder
  EmptyFooter() {
    Blank().height(1)
  }

  @Builder
  CodecRowView(r: CodecRow) {
    Row() {
      Column() {
        Text(r.label).fontSize(16).fontColor(r.status === 'none' ? Theme.text2 : Theme.text)
        if (r.decoderName) {
          Text(r.decoderName).fontSize(12).fontColor(Theme.text3).margin({ top: 2 }).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (r.details.length > 0) {
          Text(r.details.join(' · ')).fontSize(12).fontColor(Theme.text2).margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text(statusText(r.status))
        .fontSize(12).fontColor(statusColor(r.status))
        .backgroundColor(statusBgColor(r.status)).borderRadius(4)
        .padding({ left: 8, right: 8, top: 3, bottom: 3 }).margin({ left: 8 })
    }
    .width('100%').constraintSize({ minHeight: 52 }).padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor(Theme.surface)
  }
  build() {
    Column() {
      Row() {
        Text('‹').fontSize(30).fontColor(Theme.text).padding({ right: 12 }).onClick(() => router.back())
        Text('解码能力').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Theme.text).layoutWeight(1)
        if (this.probing) {
          LoadingProgress().width(24).height(24).color(Theme.text2)
        }
      }
      .width('100%').height(56).padding({ left: Theme.pagePad, right: Theme.pagePad })

      List({ space: 1 }) {
        ListItem() {
          Column() {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.chips, (c: SummaryChip) => {
                this.Chip(c)
              }, (c: SummaryChip, i: number) => `chip-${this.gen}-${i}`)
            }
            .width('100%')
            Row() {
              Button('复制报告').fontSize(14).fontColor(Theme.text).backgroundColor(Theme.surface2)
                .height(36).onClick(() => this.copyReport())
              Button(this.probing ? '检测中…' : '重新检测').fontSize(14).fontColor(Color.White)
                .backgroundColor(Theme.accent).height(36).margin({ left: 12 }).enabled(!this.probing)
                .onClick(() => this.reprobe(true))
            }
            .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%').padding(16).backgroundColor(Theme.surface).borderRadius(Theme.radius)
        }

        ListItemGroup({ header: this.GroupHeader('视频解码', groupCount(this.videoRows)), footer: this.EmptyFooter() }) {
          ForEach(this.videoRows, (r: CodecRow) => {
            ListItem() { this.CodecRowView(r) }
          }, (r: CodecRow) => `v-${this.gen}-${r.codec}`)
        }

        ListItemGroup({ header: this.GroupHeader('音频解码', groupCount(this.audioRows)), footer: this.EmptyFooter() }) {
          ForEach(this.audioRows, (r: CodecRow) => {
            ListItem() { this.CodecRowView(r) }
          }, (r: CodecRow) => `a-${this.gen}-${r.codec}`)
        }

        ListItem() {
          Text('播放时系统播放器（AVPlayer）会自动优先使用硬件解码器，硬件不支持时才使用软件解码。' +
            '能否直接播放还取决于文件的容器格式（mkv / ts / mp4 等）是否被本机支持；' +
            '直接播放失败时，应用会自动改为让服务器转封装（不重新编码）或转码后再播放。')
            .fontSize(12).fontColor(Theme.text3).lineHeight(18)
            .padding({ left: 16, right: 16, top: 12 }).width('100%')
        }
      }
      .layoutWeight(1)
      .width('100%')
      .constraintSize({ maxWidth: 900 })
      .padding({ left: 12, right: 12, bottom: 32 })
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%').height('100%').backgroundColor(Theme.bg)
  }
}
