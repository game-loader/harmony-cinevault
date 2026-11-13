import { router, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { SourceConfig } from '../common/Models';
import { SourceStore } from '../common/SourceStore';
import { Theme } from '../common/Theme';
import { Nav, ServerEditParams, QuarkBrowserParams } from '../common/Nav';
import { ProviderRegistry } from '../providers/ProviderRegistry';
import { QuarkApi } from '../quark/QuarkApi';
import { QuarkConst } from '../quark/QuarkTypes';
import { CookieUtil } from '../quark/CookieUtil';

const COOKIE_URLS: string[] = ['https://pan.quark.cn', 'https://drive-pc.quark.cn', 'https://drive.quark.cn',
  'https://quark.cn'];

@CustomDialog
struct PasteCookieDialog {
  controller: CustomDialogController;
  @State text: string = '';
  onSubmit: (cookie: string) => void = (c: string) => {};

  build() {
    Column({ space: 14 }) {
      Text('粘贴 Cookie').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Theme.text)
      Text('在电脑浏览器登录 pan.quark.cn 后，从开发者工具的网络请求中复制 Cookie 请求头的完整内容。')
        .fontSize(13).fontColor(Theme.text2)
      TextArea({ text: this.text, placeholder: '__pus=...; __puus=...; ...' })
        .height(160).fontSize(13).fontColor(Theme.text)
        .backgroundColor(Theme.surface2).placeholderColor(Theme.text3)
        .onChange((v: string) => { this.text = v; })
      Row({ space: 12 }) {
        Button('取消').backgroundColor(Theme.surface2).fontColor(Theme.text).layoutWeight(1)
          .onClick(() => { this.controller.close(); })
        Button('确定').backgroundColor(Theme.accent).fontColor(Color.White).layoutWeight(1)
          .enabled(this.text.trim().length > 0)
          .onClick(() => {
            const v = this.text;
            this.controller.close();
            this.onSubmit(v);
          })
      }.width('100%')
    }
    .padding(20).width('100%').backgroundColor(Theme.surface).borderRadius(Theme.radius)
  }
}

@Entry
@Component
struct QuarkLoginPage {
  @State sourceId: string = '';
  @State status: string = '请使用夸克 App 扫码或在页面中登录';
  @State busy: boolean = false;
  @State loadProgress: number = 0;
  @State webError: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();
  private pollTimer: number = -1;
  private done: boolean = false;
  private verifying: boolean = false;
  private lastTried: string = '';
  private dialog: CustomDialogController = new CustomDialogController({
    builder: PasteCookieDialog({
      onSubmit: (c: string) => {
        this.submitManual(c);
      }
    }),
    autoCancel: true,
    customStyle: true,
    alignment: DialogAlignment.Center,
    width: '90%'
  });

  aboutToAppear(): void {
    const p = router.getParams() as ServerEditParams;
    if (p !== undefined && p !== null && p.sourceId) {
      this.sourceId = p.sourceId;
    }
    // fresh session: forget cookies from any previous login
    try {
      webview.WebCookieManager.clearAllCookiesSync();
    } catch (e) {
      console.warn('[QuarkLogin] clear cookies: ' + (e as BusinessError).message);
    }
  }

  aboutToDisappear(): void {
    this.stopPoll();
  }

  private toast(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 2000 });
    } catch (e) {
      console.error('[QuarkLogin] toast: ' + (e as BusinessError).message);
    }
  }

  private startPoll(): void {
    if (this.pollTimer >= 0) {
      return;
    }
    this.pollTimer = setInterval(() => {
      this.checkLogin();
    }, 2000);
  }

  private stopPoll(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  /** Cookies from all quark hosts merged into one string. */
  private readCookies(): string {
    let merged = '';
    COOKIE_URLS.forEach((u: string) => {
      try {
        const c = webview.WebCookieManager.fetchCookieSync(u);
        if (c) {
          merged = CookieUtil.merge(merged, c);
        }
      } catch (e) {
        // 17100002: no cookie for this url
      }
    });
    return merged;
  }

  private checkLogin(): void {
    if (this.done || this.verifying) {
      return;
    }
    const c = this.readCookies();
    // __pus is the login session cookie set after QR / password login
    if (CookieUtil.get(c, '__pus').length === 0 || c === this.lastTried) {
      return;
    }
    this.lastTried = c;
    this.verifyAndSave(c, false);
  }

  private submitManual(raw: string): void {
    const c = CookieUtil.normalize(raw);
    if (c.length === 0 || c.indexOf('=') < 0) {
      this.toast('Cookie 格式不正确');
      return;
    }
    this.verifyAndSave(c, true);
  }

  private async verifyAndSave(cookie: string, manual: boolean): Promise<void> {
    this.verifying = true;
    this.busy = true;
    this.status = '正在验证登录状态…';
    try {
      const api = new QuarkApi(cookie);
      const nick = await api.accountInfo();
      try {
        await api.config(); // obtains / rolls __puus for the drive api
      } catch (e) {
        console.warn('[QuarkLogin] config: ' + (e as Error).message);
      }
      let cfg: SourceConfig | undefined = this.sourceId ? SourceStore.get(this.sourceId) : undefined;
      if (cfg === undefined) {
        cfg = new SourceConfig();
        cfg.id = this.sourceId ? this.sourceId : SourceStore.newId();
        cfg.kind = 'quark';
        cfg.name = '夸克网盘';
        cfg.rootFid = '0';
      }
      cfg.cookie = api.cookie;
      cfg.username = nick;
      cfg.enabled = true;
      await SourceStore.upsert(cfg);
      ProviderRegistry.invalidate(cfg.id);
      this.done = true;
      this.stopPoll();
      this.status = '登录成功：' + nick;
      this.toast('登录成功，请选择媒体库目录');
      router.replaceUrl({ url: 'pages/QuarkBrowser', params: QuarkLoginPage.browserParams(cfg.id) });
    } catch (e) {
      const msg = (e as Error).message;
      this.status = manual ? ('验证失败：' + msg) : '等待登录完成…';
      if (manual) {
        this.toast(msg);
      }
    } finally {
      this.verifying = false;
      this.busy = false;
    }
  }

  private static browserParams(id: string): Object {
    const p = new QuarkBrowserParams();
    p.sourceId = id;
    p.pick = true;
    return p;
  }

  build() {
    Column() {
      // top bar
      Row({ space: 12 }) {
        Text('‹').fontSize(30).fontColor(Theme.text).padding({ left: 4, right: 8 })
          .onClick(() => { Nav.back(); })
        Column() {
          Text('登录夸克网盘').fontSize(18).fontWeight(FontWeight.Bold).fontColor(Theme.text)
          Text(this.status).fontSize(12).fontColor(Theme.text2).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (this.busy) {
          LoadingProgress().width(24).height(24).color(Theme.accent)
        }
        Button('刷新').fontSize(13).height(32).backgroundColor(Theme.surface2).fontColor(Theme.text)
          .onClick(() => {
            this.webError = '';
            try {
              this.controller.refresh();
            } catch (e) {
              this.controller.loadUrl(QuarkConst.REFERER);
            }
          })
        Button('粘贴 Cookie').fontSize(13).height(32).backgroundColor(Theme.accent).fontColor(Color.White)
          .onClick(() => { this.dialog.open(); })
      }
      .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 }).backgroundColor(Theme.surface)

      if (this.loadProgress > 0 && this.loadProgress < 100) {
        Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
          .color(Theme.accent).width('100%').height(2)
      }

      Stack() {
        Web({ src: QuarkConst.REFERER, controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(false)
          .width('100%').height('100%')
          .onControllerAttached(() => {
            try {
              this.controller.setCustomUserAgent(QuarkConst.WEB_UA);
            } catch (e) {
              console.warn('[QuarkLogin] UA: ' + (e as BusinessError).message);
            }
            this.startPoll();
          })
          .onProgressChange((ev: OnProgressChangeEvent) => {
            this.loadProgress = ev.newProgress;
          })
          .onPageEnd((ev: OnPageEndEvent) => {
            this.webError = '';
            this.checkLogin();
          })
          .onErrorReceive((ev: OnErrorReceiveEvent) => {
            if (ev.request.isMainFrame()) {
              this.webError = '页面加载失败：' + ev.error.getErrorInfo();
            }
          })
        if (this.webError.length > 0) {
          Column({ space: 12 }) {
            Text(this.webError).fontSize(14).fontColor(Theme.text2).textAlign(TextAlign.Center)
            Button('重试').backgroundColor(Theme.accent).fontColor(Color.White)
              .onClick(() => {
                this.webError = '';
                this.controller.loadUrl(QuarkConst.REFERER);
              })
          }
          .width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor(Theme.bg)
        }
      }.layoutWeight(1).width('100%')

      Text('提示：登录信息仅保存在本机，用于访问你自己的网盘文件。')
        .fontSize(11).fontColor(Theme.text3).padding(8)
    }
    .width('100%').height('100%').backgroundColor(Theme.bg)
  }
}
