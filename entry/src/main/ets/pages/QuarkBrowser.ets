import { router, promptAction } from '@kit.ArkUI';
import { SourceConfig } from '../common/Models';
import { SourceStore } from '../common/SourceStore';
import { Theme } from '../common/Theme';
import { Nav, QuarkBrowserParams } from '../common/Nav';
import { ProviderRegistry } from '../providers/ProviderRegistry';
import { Scraper, ScanProgress } from '../scraper/Scraper';
import { QuarkProvider } from '../quark/QuarkProvider';
import { QuarkFile } from '../quark/QuarkTypes';
import { formatSize, isVideoName, isSubtitleName, fileExt } from '../quark/CookieUtil';
import { AppLog } from '../common/AppLog';

class Crumb {
  fid: string = '';
  name: string = '';
}

@Entry
@Component
struct QuarkBrowserPage {
  @State sourceId: string = '';
  @State pick: boolean = false;
  @State crumbs: Crumb[] = [];
  @State files: QuarkFile[] = [];
  @State loading: boolean = false;
  @State refreshing: boolean = false;
  @State error: string = '';
  @State onlyMedia: boolean = false;
  @State rootFid: string = '0';
  @State scanning: boolean = false;
  @State scanDone: boolean = false;
  @State scanText: string = '';
  @State scanTotal: number = 0;
  @State scanMatched: number = 0;
  @State scanFailed: number = 0;
  @State askScan: boolean = false;
  private provider: QuarkProvider | undefined = undefined;
  private loadSeq: number = 0;

  aboutToAppear(): void {
    const p = router.getParams() as QuarkBrowserParams;
    if (p !== undefined && p !== null) {
      this.sourceId = p.sourceId ? p.sourceId : '';
      this.pick = p.pick === true;
    }
    const root = new Crumb();
    root.fid = '0';
    root.name = '全部文件';
    this.crumbs = [root];
    this.init();
  }

  private async init(): Promise<void> {
    try {
      await SourceStore.load();
    } catch (e) {
      AppLog.warn('[QuarkBrowser] load sources: ' + (e as Error).message);
    }
    const cfg = SourceStore.get(this.sourceId);
    if (cfg === undefined || cfg.kind !== 'quark') {
      this.error = '未找到夸克网盘账号，请先登录';
      return;
    }
    this.rootFid = cfg.rootFid ? cfg.rootFid : '0';
    const prov = ProviderRegistry.get(this.sourceId);
    this.provider = prov instanceof QuarkProvider ? prov as QuarkProvider : new QuarkProvider(cfg);
    await this.load(false);
  }

  private current(): Crumb {
    return this.crumbs[this.crumbs.length - 1];
  }

  private async load(pull: boolean): Promise<void> {
    const prov = this.provider;
    if (prov === undefined) {
      this.refreshing = false;
      return;
    }
    const seq = ++this.loadSeq;
    if (!pull) {
      this.loading = true;
    }
    this.error = '';
    try {
      const list = await prov.drive.listAll(this.current().fid);
      if (seq !== this.loadSeq) {
        return;
      }
      list.forEach((f: QuarkFile) => QuarkProvider.rememberFile(this.sourceId, f));
      this.files = list;
    } catch (e) {
      if (seq === this.loadSeq) {
        this.error = (e as Error).message;
        this.files = [];
      }
    } finally {
      if (seq === this.loadSeq) {
        this.loading = false;
        this.refreshing = false;
      }
    }
  }

  private visible(): QuarkFile[] {
    if (!this.onlyMedia) {
      return this.files;
    }
    return this.files.filter((f: QuarkFile) => f.isDir || f.category === 1 || isVideoName(f.name));
  }

  private openDir(f: QuarkFile): void {
    const c = new Crumb();
    c.fid = f.fid;
    c.name = f.name;
    const next = this.crumbs.slice();
    next.push(c);
    this.crumbs = next;
    this.files = [];
    this.load(false);
  }

  private goTo(index: number): void {
    if (index >= this.crumbs.length - 1) {
      return;
    }
    this.crumbs = this.crumbs.slice(0, index + 1);
    this.files = [];
    this.load(false);
  }

  private goUp(): boolean {
    if (this.crumbs.length > 1) {
      this.goTo(this.crumbs.length - 2);
      return true;
    }
    return false;
  }

  private tapFile(f: QuarkFile): void {
    if (f.isDir) {
      this.openDir(f);
      return;
    }
    if (f.category === 1 || isVideoName(f.name)) {
      if (fileExt(f.name) === 'iso') {
        this.toast('暂不支持播放 ISO 镜像');
        return;
      }
      QuarkProvider.rememberFile(this.sourceId, f);
      Nav.play(this.sourceId, QuarkProvider.fileItemId(f.fid), 0);
      return;
    }
    this.toast('该文件类型不支持预览');
  }

  private toast(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 2000 });
    } catch (e) {
      AppLog.error('[QuarkBrowser] toast: ' + (e as Error).message);
    }
  }

  private pathText(): string {
    return this.crumbs.map((c: Crumb) => c.name).join(' / ');
  }

  private async setRoot(): Promise<void> {
    const cfg = SourceStore.get(this.sourceId);
    if (cfg === undefined) {
      this.toast('账号不存在');
      return;
    }
    cfg.rootFid = this.current().fid;
    try {
      await SourceStore.upsert(cfg);
      ProviderRegistry.invalidate(cfg.id);
      this.rootFid = cfg.rootFid;
      this.toast('已设为媒体库根目录');
      this.askScan = true;
    } catch (e) {
      this.toast('保存失败：' + (e as Error).message);
    }
  }

  private async startScan(force: boolean): Promise<void> {
    const prov = this.provider;
    if (prov === undefined || this.scanning) {
      return;
    }
    this.askScan = false;
    this.scanning = true;
    this.scanDone = false;
    this.scanText = '正在遍历网盘目录…';
    this.scanTotal = 0;
    this.scanMatched = 0;
    this.scanFailed = 0;
    const onProgress = (p: ScanProgress) => {
      this.scanTotal = p.total;
      this.scanMatched = p.matched;
      this.scanFailed = p.failed;
      this.scanText = p.current;
    };
    try {
      const r = await Scraper.scan(this.sourceId, this.rootFid, prov, force, onProgress);
      this.scanTotal = r.total;
      this.scanMatched = r.matched;
      this.scanFailed = r.failed;
      this.scanText = '刮削完成';
      this.scanDone = true;
    } catch (e) {
      this.scanText = '刮削失败：' + (e as Error).message;
      this.scanDone = true;
    } finally {
      this.scanning = false;
    }
  }

  onBackPress(): boolean {
    if (this.scanning) {
      this.toast('刮削将在后台继续');
    }
    return this.goUp();
  }

  @Builder
  FileIcon(f: QuarkFile) {
    Stack() {
      if (!f.isDir && f.thumbnail.length > 0) {
        Image(f.thumbnail).width(56).height(40).objectFit(ImageFit.Cover).borderRadius(4)
      } else {
        Text(this.iconText(f)).fontSize(13).fontWeight(FontWeight.Bold).fontColor(Color.White)
      }
    }
    .width(56).height(40).borderRadius(6).backgroundColor(this.iconColor(f))
  }

  private iconText(f: QuarkFile): string {
    if (f.isDir) {
      return '📁';
    }
    if (f.category === 1 || isVideoName(f.name)) {
      return '▶';
    }
    if (isSubtitleName(f.name)) {
      return '字幕';
    }
    const e = fileExt(f.name);
    return e.length > 0 ? e.substring(0, 4).toUpperCase() : '文件';
  }

  private iconColor(f: QuarkFile): string {
    if (f.isDir) {
      return '#3B4A6B';
    }
    if (f.category === 1 || isVideoName(f.name)) {
      return '#7A2E2E';
    }
    if (isSubtitleName(f.name)) {
      return '#2E5A47';
    }
    return Theme.surface2;
  }

  private subText(f: QuarkFile): string {
    const d = f.updatedAt > 0 ? new Date(f.updatedAt) : undefined;
    const ds = d !== undefined ? (d.getFullYear() + '-' + (d.getMonth() + 1).toString().padStart(2, '0') + '-' +
      d.getDate().toString().padStart(2, '0')) : '';
    if (f.isDir) {
      return ds;
    }
    return formatSize(f.size) + (ds.length > 0 ? '  ·  ' + ds : '');
  }

  @Builder
  TopBar() {
    Row({ space: 10 }) {
      Text('‹').fontSize(30).fontColor(Theme.text).padding({ left: 4, right: 8 })
        .onClick(() => {
          if (!this.goUp()) {
            Nav.back();
          }
        })
      Column() {
        Text(this.pick ? '选择媒体库目录' : '夸克网盘').fontSize(18).fontWeight(FontWeight.Bold).fontColor(Theme.text)
        if (this.rootFid !== '0' || this.pick) {
          Text(this.rootFid === this.current().fid ? '当前目录是媒体库根目录' : '浏览文件夹，进入目标目录后点击右侧按钮')
            .fontSize(12).fontColor(Theme.text2).maxLines(1)
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Toggle({ type: ToggleType.Button, isOn: this.onlyMedia }) {
        Text('仅视频').fontSize(12).fontColor(Theme.text)
      }
      .height(30).selectedColor(Theme.accent).backgroundColor(Theme.surface2)
      .onChange((on: boolean) => { this.onlyMedia = on; })
      if (this.pick) {
        Button('设为媒体库根目录').fontSize(13).height(32).backgroundColor(Theme.accent).fontColor(Color.White)
          .enabled(!this.scanning && this.provider !== undefined)
          .onClick(() => { this.setRoot(); })
      } else {
        Button('刮削').fontSize(13).height(32).backgroundColor(Theme.surface2).fontColor(Theme.text)
          .enabled(!this.scanning && this.provider !== undefined)
          .onClick(() => { this.askScan = true; })
      }
    }
    .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 }).backgroundColor(Theme.surface)
  }

  @Builder
  Breadcrumbs() {
    Scroll() {
      Row() {
        ForEach(this.crumbs, (c: Crumb, i: number) => {
          Row() {
            if (i > 0) {
              Text(' › ').fontSize(14).fontColor(Theme.text3)
            }
            Text(c.name).fontSize(14).maxLines(1).constraintSize({ maxWidth: 220 })
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(i === this.crumbs.length - 1 ? Theme.text : Theme.accent)
              .onClick(() => { this.goTo(i); })
          }
        }, (c: Crumb, i: number) => c.fid + '_' + i)
      }.padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    .width('100%').height(40).align(Alignment.Start)
  }

  @Builder
  ScanPanel() {
    Column({ space: 8 }) {
      if (this.askScan && !this.scanning) {
        Text('开始刮削媒体库？').fontSize(15).fontWeight(FontWeight.Bold).fontColor(Theme.text)
        Text('将遍历「' + this.pathText() + '」下所有视频，从 TMDB 匹配海报和简介。文件较多时需要几分钟。')
          .fontSize(12).fontColor(Theme.text2)
        Row({ space: 10 }) {
          Button('稍后').fontSize(13).height(32).backgroundColor(Theme.surface2).fontColor(Theme.text)
            .onClick(() => { this.askScan = false; })
          Button('全量重刮').fontSize(13).height(32).backgroundColor(Theme.surface2).fontColor(Theme.text)
            .onClick(() => { this.startScan(true); })
          Button('开始刮削').fontSize(13).height(32).backgroundColor(Theme.accent).fontColor(Color.White)
            .onClick(() => { this.startScan(false); })
        }
      } else if (this.scanning || this.scanDone) {
        Row({ space: 10 }) {
          if (this.scanning) {
            LoadingProgress().width(20).height(20).color(Theme.accent)
          }
          Text(this.scanning ? '正在刮削' : this.scanText).fontSize(14).fontWeight(FontWeight.Bold)
            .fontColor(Theme.text).layoutWeight(1)
          if (this.scanDone) {
            Button('完成').fontSize(13).height(30).backgroundColor(Theme.accent).fontColor(Color.White)
              .onClick(() => {
                this.scanDone = false;
                if (this.pick) {
                  Nav.back();
                }
              })
          }
        }.width('100%')
        if (this.scanning) {
          Text(this.scanText).fontSize(12).fontColor(Theme.text2).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Text('文件 ' + this.scanTotal + '  ·  已匹配 ' + this.scanMatched + '  ·  未识别 ' + this.scanFailed)
          .fontSize(12).fontColor(Theme.text2)
        if (this.scanning && this.scanTotal > 0) {
          Progress({ value: this.scanMatched + this.scanFailed, total: Math.max(this.scanTotal, 1),
            type: ProgressType.Linear }).color(Theme.accent).width('100%')
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%').padding(14).backgroundColor(Theme.surface)
    .visibility(this.askScan || this.scanning || this.scanDone ? Visibility.Visible : Visibility.None)
  }

  @Builder
  StateView(icon: string, msg: string, action: string) {
    Column({ space: 12 }) {
      Text(icon).fontSize(40)
      Text(msg).fontSize(14).fontColor(Theme.text2).textAlign(TextAlign.Center).padding({ left: 24, right: 24 })
      if (action.length > 0) {
        Button(action).backgroundColor(Theme.accent).fontColor(Color.White)
          .onClick(() => {
            if (this.error.indexOf('登录') >= 0) {
              Nav.quarkLogin(this.sourceId);
            } else {
              this.load(false);
            }
          })
      }
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      this.TopBar()
      this.Breadcrumbs()
      this.ScanPanel()
      Refresh({ refreshing: $$this.refreshing }) {
        if (this.loading && this.files.length === 0) {
          Column() {
            LoadingProgress().width(40).height(40).color(Theme.accent)
            Text('加载中…').fontSize(13).fontColor(Theme.text2).margin({ top: 8 })
          }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        } else if (this.error.length > 0) {
          this.StateView('⚠', this.error, this.error.indexOf('登录') >= 0 ? '重新登录' : '重试')
        } else if (this.visible().length === 0) {
          this.StateView('📂', this.onlyMedia ? '该文件夹中没有视频' : '空文件夹', '')
        } else {
          List() {
            ForEach(this.visible(), (f: QuarkFile) => {
              ListItem() {
                Row({ space: 12 }) {
                  this.FileIcon(f)
                  Column({ space: 4 }) {
                    Text(f.name).fontSize(15).fontColor(Theme.text).maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.subText(f)).fontSize(12).fontColor(Theme.text3)
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  if (f.isDir) {
                    Text('›').fontSize(22).fontColor(Theme.text3)
                  }
                }
                .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .onClick(() => { this.tapFile(f); })
              }
            }, (f: QuarkFile) => f.fid)
          }
          .width('100%').height('100%')
          .divider({ strokeWidth: 0.5, color: Theme.surface2, startMargin: 84 })
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        }
      }
      .layoutWeight(1)
      .onRefreshing(() => { this.load(true); })
    }
    .width('100%').height('100%').backgroundColor(Theme.bg)
  }
}
