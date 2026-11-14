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
import { QuarkTvApi, QuarkTvTokens } from '../quark/QuarkTvApi';
import { QuarkTvConst } from '../quark/QuarkTvSign';
import { QuarkTvQr } from '../quark/QuarkTypes';

/** Any error carrying an HTTP-like status (QuarkError). */
interface HttpLikeError {
  status?: number;
}

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
  @State tab: number = 0;            // 0 = TV QR login, 1 = web login
  @State qrImage: string = '';
  @State qrStatus: string = '';
  @State qrRemain: number = 0;       // seconds until the QR expires
  @State qrExpired: boolean = false;
  @State qrLoading: boolean = false;
  private tabs: TabsController = new TabsController();
  private tvTimer: number = -1;
  private tvDeviceId: string = '';
  private queryToken: string = '';
  private qrDeadline: number = 0;
  private qrSeq: number = 0;
  private tvPolling: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private pollTimer: number = -1;
  private done: boolean = false;
  private disposed: boolean = false; // page left: no more QR polling or navigation
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
    this.startTv();
    // fresh session: forget cookies from any previous login
    try {
      webview.WebCookieManager.clearAllCookiesSync();
    } catch (e) {
      console.warn('[QuarkLogin] clear cookies: ' + (e as BusinessError).message);
    }
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.qrSeq++; // invalidate any in-flight startTv / tvTick
    this.stopPoll();
    this.stopTv();
  }

  // ---------------- TV QR login ----------------

  private stopTv(): void {
    if (this.tvTimer >= 0) {
      clearInterval(this.tvTimer);
      this.tvTimer = -1;
    }
  }

  /** Device id of the source being re-logged in, or a new one (the refresh token is bound to it). */
  private ensureDeviceId(): string {
    if (this.tvDeviceId.length > 0) {
      return this.tvDeviceId;
    }
    const cfg: SourceConfig | undefined = this.sourceId ? SourceStore.get(this.sourceId) : undefined;
    this.tvDeviceId = cfg !== undefined && cfg.quarkDeviceId.length > 0 ? cfg.quarkDeviceId : QuarkTvApi.newDeviceId();
    return this.tvDeviceId;
  }

  private async startTv(): Promise<void> {
    if (this.disposed) {
      return;
    }
    this.stopTv();
    const seq = ++this.qrSeq;
    this.qrExpired = false;
    this.qrLoading = true;
    this.qrImage = '';
    this.qrStatus = '正在获取二维码…';
    try {
      await SourceStore.load();
      const qr: QuarkTvQr = await QuarkTvApi.requestQr(this.ensureDeviceId());
      if (seq !== this.qrSeq || this.done || this.disposed) {
        return;
      }
      this.qrImage = qr.image;
      this.queryToken = qr.queryToken;
      this.qrDeadline = Date.now() + QuarkTvConst.QR_TIMEOUT_MS;
      this.qrRemain = Math.round(QuarkTvConst.QR_TIMEOUT_MS / 1000);
      this.qrStatus = '等待扫码确认…';
      this.tvTimer = setInterval(() => {
        this.tvTick(seq);
      }, QuarkTvConst.QR_POLL_MS);
    } catch (e) {
      if (seq === this.qrSeq) {
        this.qrStatus = '获取二维码失败：' + (e as Error).message;
        this.qrExpired = true;
      }
    } finally {
      if (seq === this.qrSeq) {
        this.qrLoading = false;
      }
    }
  }

  private async tvTick(seq: number): Promise<void> {
    if (seq !== this.qrSeq || this.done || this.disposed) {
      this.stopTv();
      return;
    }
    const left = this.qrDeadline - Date.now();
    this.qrRemain = Math.max(0, Math.ceil(left / 1000));
    if (left <= 0) {
      this.stopTv();
      this.qrExpired = true;
      this.qrStatus = '二维码已过期，请刷新';
      return;
    }
    if (this.tvPolling) {
      return;
    }
    this.tvPolling = true;
    try {
      const code = await QuarkTvApi.pollCode(this.tvDeviceId, this.queryToken);
      if (code.length > 0 && seq === this.qrSeq && !this.done && !this.disposed) {
        this.stopTv();
        await this.finishTv(code);
      }
    } catch (e) {
      const qe = e as Error;
      // network hiccups: keep polling; server rejection (e.g. token expired): stop
      const st = (e as HttpLikeError).status;
      if (st !== undefined && st !== 0 && seq === this.qrSeq) {
        this.stopTv();
        this.qrExpired = true;
        this.qrStatus = '登录失败：' + qe.message;
      }
    } finally {
      this.tvPolling = false;
    }
  }

  private async finishTv(code: string): Promise<void> {
    this.busy = true;
    this.qrStatus = '已确认，正在登录…';
    try {
      const deviceId = this.tvDeviceId;
      const tokens: QuarkTvTokens = await QuarkTvApi.exchangeToken(deviceId, code, false);
      const api = new QuarkTvApi(deviceId, tokens.refreshToken);
      api.setTokens(tokens);
      let nick = '';
      try {
        nick = await api.userInfo();
      } catch (e) {
        console.warn('[QuarkLogin] user_info: ' + (e as Error).message);
      }
      let cfg: SourceConfig | undefined = this.sourceId ? SourceStore.get(this.sourceId) : undefined;
      if (cfg === undefined) {
        cfg = new SourceConfig();
        cfg.id = this.sourceId ? this.sourceId : SourceStore.newId();
        cfg.kind = 'quark';
        cfg.name = '夸克网盘';
        cfg.rootFid = '0';
      }
      if (nick.length > 0 && (cfg.name === '' || cfg.name.startsWith('夸克网盘'))) {
        cfg.name = '夸克网盘 (' + nick + ')';
      }
      cfg.quarkAuth = 'tv';
      cfg.quarkDeviceId = deviceId;
      // the api may have rotated the token during user_info
      cfg.quarkRefreshToken = api.refreshToken;
      if (nick.length > 0) {
        cfg.username = nick;
      }
      cfg.enabled = true;
      await SourceStore.upsert(cfg);
      ProviderRegistry.invalidate(cfg.id);
      this.done = true;
      this.stopPoll();
      this.status = '登录成功' + (nick.length > 0 ? '：' + nick : '');
      this.qrStatus = this.status;
      if (this.disposed) {
        return; // page already left: keep the login, but don't navigate from a dead page
      }
      this.toast('登录成功，请选择媒体库目录');
      router.replaceUrl({ url: 'pages/QuarkBrowser', params: QuarkLoginPage.browserParams(cfg.id) });
    } catch (e) {
      this.qrExpired = true;
      this.qrStatus = '登录失败：' + (e as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private countdownText(): string {
    const m = Math.floor(this.qrRemain / 60);
    const sec = this.qrRemain % 60;
    return m + ':' + (sec < 10 ? '0' + sec : String(sec));
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
      cfg.quarkAuth = 'cookie';
      cfg.username = nick;
      cfg.enabled = true;
      await SourceStore.upsert(cfg);
      ProviderRegistry.invalidate(cfg.id);
      this.done = true;
      this.stopPoll();
      this.stopTv();
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

  @Builder
  TvPane() {
    Scroll() {
      Column({ space: 14 }) {
        Text('打开夸克 App 扫一扫').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Theme.text)
        Text('在夸克 App 首页点击右上角扫一扫，扫描下方二维码并确认登录。')
          .fontSize(13).fontColor(Theme.text2).textAlign(TextAlign.Center)
        Stack() {
          if (this.qrImage.length > 0) {
            Image(this.qrImage).width(230).height(230).objectFit(ImageFit.Contain)
              .opacity(this.qrExpired ? 0.15 : 1)
          }
          if (this.qrLoading) {
            LoadingProgress().width(40).height(40).color(Theme.accent)
          }
          if (this.qrExpired && !this.qrLoading) {
            Button('刷新二维码').backgroundColor(Theme.accent).fontColor(Color.White)
              .onClick(() => { this.startTv(); })
          }
        }
        .width(250).height(250).backgroundColor(Color.White).borderRadius(Theme.radius)
        Text(this.qrStatus).fontSize(14).fontColor(Theme.text).textAlign(TextAlign.Center)
        if (!this.qrExpired && this.qrImage.length > 0 && !this.done) {
          Text('二维码有效期 ' + this.countdownText()).fontSize(12).fontColor(Theme.text3)
        }
        Text('该方式模拟夸克 TV 客户端登录，登录状态可长期保持；如无法使用，请切换到“网页登录”。')
          .fontSize(11).fontColor(Theme.text3).textAlign(TextAlign.Center).padding({ left: 24, right: 24 })
      }
      .width('100%').padding({ top: 24, bottom: 24 }).alignItems(HorizontalAlign.Center)
    }
    .width('100%').height('100%')
  }

  @Builder
  WebPane() {
    Column() {
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
    }
    .width('100%').height('100%')
  }

  build() {
    Column() {
      // top bar
      Row({ space: 12 }) {
        Text('‹').fontSize(30).fontColor(Theme.text).padding({ left: 4, right: 8 })
          .onClick(() => { Nav.back(); })
        Column() {
          Text('登录夸克网盘').fontSize(18).fontWeight(FontWeight.Bold).fontColor(Theme.text)
          Text(this.tab === 0 ? this.qrStatus : this.status).fontSize(12).fontColor(Theme.text2).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (this.busy) {
          LoadingProgress().width(24).height(24).color(Theme.accent)
        }
        if (this.tab === 0) {
          Button('刷新').fontSize(13).height(32).backgroundColor(Theme.surface2).fontColor(Theme.text)
            .enabled(!this.qrLoading && !this.done)
            .onClick(() => { this.startTv(); })
        } else {
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
      }
      .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 }).backgroundColor(Theme.surface)

      Tabs({ barPosition: BarPosition.Start, index: 0, controller: this.tabs }) {
        TabContent() {
          this.TvPane()
        }.tabBar('TV 扫码登录')

        TabContent() {
          this.WebPane()
        }.tabBar('网页登录')
      }
      .layoutWeight(1).width('100%')
      .scrollable(false)
      .barHeight(44)
      .onChange((i: number) => {
        this.tab = i;
        // a QR that expired while the user was on the web tab is renewed on return
        if (i === 0 && this.qrExpired && !this.qrLoading && !this.done) {
          this.startTv();
        }
      })

      Text('提示：登录信息仅保存在本机，用于访问你自己的网盘文件。')
        .fontSize(11).fontColor(Theme.text3).padding(8)
    }
    .width('100%').height('100%').backgroundColor(Theme.bg)
  }
}
