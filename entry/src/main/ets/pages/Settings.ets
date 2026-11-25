import { router, promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { SourceConfig } from '../common/Models';
import { SourceStore } from '../common/SourceStore';
import { Settings, AppSettings } from '../common/Settings';
import { Theme } from '../common/Theme';
import { Nav } from '../common/Nav';
import { AppContext } from '../common/AppContext';
import { ProviderRegistry } from '../providers/ProviderRegistry';
import { QuarkProvider } from '../quark/QuarkProvider';
import { Scraper, ScanProgress, FileLister } from '../scraper/Scraper';
import { LibraryDb } from '../library/LibraryDb';
import {
  LabeledNumber, LabeledString, BITRATE_OPTIONS, SPEED_OPTIONS, SUBTITLE_SCALE_OPTIONS, TRACK_LANG_OPTIONS,
  TMDB_LANG_OPTIONS, TMDB_IMAGE_BASE_OPTIONS, indexOfNumber, indexOfString, kindLabel, sourceStatusText,
  tmdbKeyLooksValid
} from '../components/settings/SettingsLogic';
import { CODEC_MODE_OPTIONS, codecModeIndex } from '../components/settings/CodecInfoLogic';
import { ScanProgressDialog } from '../components/settings/ScanProgressDialog';
import { AppLog } from '../common/AppLog';

const APP_VERSION: string = '1.1.0';

class SelectItem implements SelectOption {
  value: ResourceStr;

  constructor(v: string) {
    this.value = v;
  }
}

function numOpts(o: LabeledNumber[]): SelectOption[] {
  return o.map((x: LabeledNumber) => new SelectItem(x.label) as SelectOption);
}

function strOpts(o: LabeledString[]): SelectOption[] {
  return o.map((x: LabeledString) => new SelectItem(x.label) as SelectOption);
}

@Entry
@Component
struct SettingsPage {
  @State sources: SourceConfig[] = [];
  @State s: AppSettings = new AppSettings();
  @State loading: boolean = true;
  @State tmdbKeyDraft: string = '';
  @State showKey: boolean = false;
  @State scanning: boolean = false;
  @State scanSourceName: string = '';
  @State scanDone: number = 0;
  @State scanTotal: number = 0;
  @State scanMatched: number = 0;
  @State scanFailed: number = 0;
  @State scanCurrent: string = '';
  @State scanFinished: boolean = false;
  @State scanError: string = '';
  private unsubSources: () => void = () => {};
  private unsubSettings: () => void = () => {};
  private scanDialog: CustomDialogController = new CustomDialogController({
    builder: ScanProgressDialog({
      sourceName: this.scanSourceName,
      done: this.scanDone,
      total: this.scanTotal,
      matched: this.scanMatched,
      failed: this.scanFailed,
      current: this.scanCurrent,
      finished: this.scanFinished,
      error: this.scanError
    }),
    autoCancel: false,
    customStyle: true,
    alignment: DialogAlignment.Center
  });

  aboutToAppear(): void {
    this.unsubSources = SourceStore.onChange(() => {
      this.sources = SourceStore.list();
    });
    this.unsubSettings = Settings.onChange(() => {
      this.s = Settings.get();
    });
    this.init();
  }

  aboutToDisappear(): void {
    this.unsubSources();
    this.unsubSettings();
  }

  onPageShow(): void {
    if (!this.loading) {
      this.sources = SourceStore.list();
      this.s = Settings.get();
    }
  }

  private async init(): Promise<void> {
    await SourceStore.load();
    await Settings.load();
    this.sources = SourceStore.list();
    this.s = Settings.get();
    this.tmdbKeyDraft = this.s.tmdbApiKey;
    this.loading = false;
  }

  private toast(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 2000 });
    } catch (e) {
      AppLog.error(`[Settings] toast: ${(e as Error).message}`);
    }
  }

  /** Mutate a copy of the settings and persist it. */
  private async update(fn: (s: AppSettings) => void): Promise<void> {
    const c = Settings.get();
    fn(c);
    this.s = c;
    await Settings.save(c);
  }

  private editSource(c: SourceConfig): void {
    if (c.kind === 'quark') {
      Nav.quarkLogin(c.id);
    } else {
      Nav.editServer(c.id, c.kind);
    }
  }

  private confirmDelete(c: SourceConfig): void {
    this.getUIContext().showAlertDialog({
      title: '删除媒体源',
      message: c.kind === 'quark'
        ? `确定删除“${c.name}”吗？本地刮削数据也会一并清除。`
        : `确定删除“${c.name}”吗？`,
      autoCancel: true,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        fontColor: Theme.accent,
        action: () => {
          this.deleteSource(c);
        }
      }
    });
  }

  private async deleteSource(c: SourceConfig): Promise<void> {
    try {
      await SourceStore.remove(c.id);
      ProviderRegistry.invalidate(c.id);
      if (c.kind === 'quark') {
        await LibraryDb.clearSource(c.id);
      }
      if (this.s.homeSourceId === c.id) {
        await this.update((s: AppSettings) => { s.homeSourceId = ''; });
      }
      this.toast('已删除');
    } catch (e) {
      this.toast(`删除失败：${(e as Error).message}`);
    }
  }

  private async toggleEnabled(c: SourceConfig, on: boolean): Promise<void> {
    const cur = SourceStore.get(c.id);
    if (cur === undefined) {
      return;
    }
    cur.enabled = on;
    await SourceStore.upsert(cur);
  }

  private async rescan(c: SourceConfig, force: boolean): Promise<void> {
    if (this.scanning) {
      return;
    }
    if (!Settings.get().tmdbApiKey) {
      this.toast('请先在“刮削”中填写 TMDB API Key');
      return;
    }
    const p = ProviderRegistry.get(c.id);
    if (p === undefined || !(p instanceof QuarkProvider)) {
      this.toast('该媒体源不支持刮削');
      return;
    }
    const lister: FileLister = p as QuarkProvider;
    this.scanning = true;
    this.scanSourceName = c.name;
    this.scanDone = 0;
    this.scanTotal = 0;
    this.scanMatched = 0;
    this.scanFailed = 0;
    this.scanCurrent = '';
    this.scanError = '';
    this.scanFinished = false;
    this.scanDialog.open();
    try {
      const r = await Scraper.scan(c.id, c.rootFid || '0', lister, force, (pr: ScanProgress) => {
        this.applyProgress(pr);
      });
      this.applyProgress(r);
    } catch (e) {
      const err = e as BusinessError;
      this.scanError = `刮削失败：${err.message ? err.message : String(e)}`;
    } finally {
      this.scanning = false;
      this.scanFinished = true;
      this.scanCurrent = '';
    }
  }

  private applyProgress(pr: ScanProgress): void {
    this.scanDone = pr.done;
    this.scanTotal = pr.total;
    this.scanMatched = pr.matched;
    this.scanFailed = pr.failed;
    this.scanCurrent = pr.current;
  }

  private confirmClearCache(c: SourceConfig): void {
    this.getUIContext().showAlertDialog({
      title: '清除刮削数据',
      message: `将清除“${c.name}”的本地媒体库，之后需要重新刮削。`,
      autoCancel: true,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '清除',
        fontColor: Theme.accent,
        action: () => {
          this.clearCache(c);
        }
      }
    });
  }

  private async clearCache(c: SourceConfig): Promise<void> {
    try {
      await LibraryDb.clearSource(c.id);
      ProviderRegistry.invalidate(c.id);
      this.toast('已清除');
    } catch (e) {
      this.toast(`清除失败：${(e as Error).message}`);
    }
  }

  private async saveTmdbKey(): Promise<void> {
    const k = this.tmdbKeyDraft.trim();
    if (k && !tmdbKeyLooksValid(k)) {
      this.toast('API Key 格式看起来不正确（应为 32 位 v3 Key 或 eyJ 开头的读访问令牌），已仍然保存');
    }
    await this.update((s: AppSettings) => { s.tmdbApiKey = k; });
    if (!k || tmdbKeyLooksValid(k)) {
      this.toast('已保存');
    }
  }

  private openUrl(url: string): void {
    try {
      AppContext.get().openLink(url, { appLinkingOnly: false }).catch((e: BusinessError) => {
        this.toast(`无法打开链接：${url}`);
        AppLog.error(`[Settings] openLink: ${e.code} ${e.message}`);
      });
    } catch (e) {
      this.toast(`无法打开链接：${url}`);
    }
  }

  private homeSourceNames(): string[] {
    const out: string[] = ['聚合全部媒体源'];
    for (let i = 0; i < this.sources.length; i++) {
      out.push(this.sources[i].name);
    }
    return out;
  }

  private homeSourceIndex(): number {
    if (!this.s.homeSourceId) {
      return 0;
    }
    for (let i = 0; i < this.sources.length; i++) {
      if (this.sources[i].id === this.s.homeSourceId) {
        return i + 1;
      }
    }
    return 0;
  }

  private quarkSources(): SourceConfig[] {
    return this.sources.filter((c: SourceConfig) => c.kind === 'quark');
  }

  @Builder
  GroupHeader(title: string) {
    Text(title)
      .fontSize(13).fontColor(Theme.text3)
      .padding({ left: 16, top: 20, bottom: 8 })
      .width('100%')
      .backgroundColor(Theme.bg)
  }

  @Builder
  GroupFooter(text: string) {
    Text(text)
      .fontSize(12).fontColor(Theme.text3)
      .padding({ left: 16, right: 16, top: 6 })
      .width('100%')
  }

  @Builder
  EmptyFooter() {
    Blank().height(1)
  }

  @Builder
  NavRow(title: string, value: string, onTap: () => void) {
    Row() {
      Text(title).fontSize(16).fontColor(Theme.text).layoutWeight(1)
      if (value) {
        Text(value).fontSize(14).fontColor(Theme.text2).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '55%' })
      }
      Text('›').fontSize(20).fontColor(Theme.text3).margin({ left: 8 })
    }
    .width('100%').height(52).padding({ left: 16, right: 16 })
    .backgroundColor(Theme.surface)
    .onClick(onTap)
  }

  @Builder
  InfoRow(title: string, value: string) {
    Row() {
      Text(title).fontSize(16).fontColor(Theme.text).layoutWeight(1)
      Text(value).fontSize(14).fontColor(Theme.text2)
    }
    .width('100%').height(52).padding({ left: 16, right: 16 })
    .backgroundColor(Theme.surface)
  }

  @Builder
  ToggleRow(title: string, sub: string, on: boolean, cb: (v: boolean) => void) {
    Row() {
      Column() {
        Text(title).fontSize(16).fontColor(Theme.text)
        if (sub) {
          Text(sub).fontSize(12).fontColor(Theme.text3).margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: on })
        .selectedColor(Theme.accent)
        .onChange((v: boolean) => cb(v))
    }
    .width('100%').constraintSize({ minHeight: 52 }).padding({ left: 16, right: 12, top: 6, bottom: 6 })
    .backgroundColor(Theme.surface)
  }

  @Builder
  SelectRow(title: string, opts: SelectOption[], idx: number, cb: (i: number) => void) {
    Row() {
      Text(title).fontSize(16).fontColor(Theme.text).layoutWeight(1)
      Select(opts)
        .selected(idx >= 0 ? idx : 0)
        .value(idx >= 0 && idx < opts.length ? (opts[idx].value as string) : '请选择')
        .font({ size: 14 })
        .fontColor(Theme.text2)
        .selectedOptionFontColor(Theme.accent)
        .optionFontColor(Theme.text)
        .optionBgColor(Theme.surface2)
        .backgroundColor(Color.Transparent)
        .onSelect((i: number, v: string) => cb(i))
    }
    .width('100%').height(52).padding({ left: 16, right: 8 })
    .backgroundColor(Theme.surface)
  }

  @Builder
  SliderRow(title: string, value: number, min: number, max: number, step: number, unit: string,
    cb: (v: number) => void) {
    Column() {
      Row() {
        Text(title).fontSize(16).fontColor(Theme.text).layoutWeight(1)
        Text(value > 0 ? `${value} ${unit}` : '关闭').fontSize(14).fontColor(Theme.text2)
      }
      .width('100%')
      Slider({ value: value, min: min, max: max, step: step, style: SliderStyle.OutSet })
        .selectedColor(Theme.accent)
        .trackColor(Theme.surface2)
        .width('100%')
        .onChange((v: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            cb(Math.round(v));
          }
        })
    }
    .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 4 })
    .backgroundColor(Theme.surface)
  }

  @Builder
  SourceRow(c: SourceConfig) {
    Column() {
      Row() {
        Column() {
          Row() {
            Text(c.name).fontSize(16).fontColor(Theme.text).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(kindLabel(c.kind)).fontSize(11).fontColor(Theme.text2)
              .backgroundColor(Theme.surface2).borderRadius(4)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 }).margin({ left: 8 })
          }
          Text(`${sourceStatusText(c.kind, c.enabled, c.token, c.cookie, c.quarkAuth, c.quarkRefreshToken)}${c.baseUrl ? ' · ' + c.baseUrl : ''}`)
            .fontSize(12).fontColor(Theme.text3).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: c.enabled })
          .selectedColor(Theme.accent)
          .onChange((v: boolean) => { this.toggleEnabled(c, v); })
      }
      .width('100%')
      Row() {
        Text('编辑').fontSize(14).fontColor(Theme.text2).padding(6)
          .onClick(() => this.editSource(c))
        if (c.kind === 'quark') {
          Text('更改媒体库目录').fontSize(14).fontColor(Theme.text2).padding(6).margin({ left: 10 })
            .onClick(() => Nav.quarkBrowser(c.id, true))
          Text('重新刮削').fontSize(14).fontColor(Theme.text2).padding(6).margin({ left: 10 })
            .onClick(() => { this.rescan(c, false); })
          Text('全量刮削').fontSize(14).fontColor(Theme.text2).padding(6).margin({ left: 10 })
            .onClick(() => { this.rescan(c, true); })
        }
        Blank()
        Text('删除').fontSize(14).fontColor(Theme.accent).padding(6)
          .onClick(() => this.confirmDelete(c))
      }
      .width('100%').margin({ top: 6 })
    }
    .width('100%').padding({ left: 16, right: 12, top: 10, bottom: 8 })
    .backgroundColor(Theme.surface)
  }

  build() {
    Column() {
      Row() {
        Text('‹').fontSize(30).fontColor(Theme.text).padding({ right: 12 }).onClick(() => router.back())
        Text('设置').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Theme.text)
      }
      .width('100%').height(56).padding({ left: Theme.pagePad, right: Theme.pagePad })

      if (this.loading) {
        Column() {
          LoadingProgress().width(40).height(40).color(Theme.text2)
          Text('加载中…').fontSize(14).fontColor(Theme.text2).margin({ top: 8 })
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        this.Body()
      }
    }
    .width('100%').height('100%').backgroundColor(Theme.bg)
  }

  @Builder
  Body() {
    List({ space: 1 }) {
      ListItemGroup({ header: this.GroupHeader('媒体源'), footer: this.GroupFooter('关闭开关可暂时隐藏对应的私人媒体源') }) {
        ListItem() { this.InfoRow('Flicx', '内置电影和剧集搜索源') }
        if (this.sources.length === 0) {
          ListItem() {
            Text('还没有添加私人媒体源，可从下方添加 Emby、Jellyfin 服务器或夸克网盘')
              .fontSize(14).fontColor(Theme.text2).padding(16).width('100%').backgroundColor(Theme.surface)
          }
        }
        ForEach(this.sources, (c: SourceConfig) => {
          ListItem() {
            this.SourceRow(c)
          }
        }, (c: SourceConfig) => `${c.id}-${c.enabled}-${c.name}-${c.token.length}-${c.cookie.length}-${c.quarkAuth}-${c.quarkRefreshToken.length}-${c.rootFid}`)
        ListItem() { this.NavRow('添加 Emby 服务器', '', () => Nav.editServer('', 'emby')) }
        ListItem() { this.NavRow('添加 Jellyfin 服务器', '', () => Nav.editServer('', 'jellyfin')) }
        ListItem() { this.NavRow('添加夸克网盘', '', () => Nav.quarkLogin('')) }
      }

      ListItemGroup({
        header: this.GroupHeader('刮削'),
        footer: this.GroupFooter('此密钥用于 Flicx 中文片名搜索、影片资料和夸克网盘刮削。' +
          'API Key 可在 themoviedb.org/settings/api 免费申请')
      }) {
        ListItem() {
          Column() {
            Text('TMDB API Key / 读访问令牌').fontSize(16).fontColor(Theme.text)
            Row() {
              TextInput({ text: this.tmdbKeyDraft, placeholder: '32 位 v3 API Key 或 eyJ… 令牌' })
                .type(this.showKey ? InputType.Normal : InputType.Password)
                .fontColor(Theme.text).placeholderColor(Theme.text3).backgroundColor(Theme.surface2)
                .layoutWeight(1)
                .onChange((v: string) => { this.tmdbKeyDraft = v; })
              Button('保存').backgroundColor(Theme.accent).fontColor(Color.White).margin({ left: 10 })
                .onClick(() => { this.saveTmdbKey(); })
            }
            .width('100%').margin({ top: 8 })
            Row() {
              Text(this.showKey ? '隐藏' : '显示').fontSize(13).fontColor(Theme.text2).padding({ top: 8, right: 16 })
                .onClick(() => { this.showKey = !this.showKey; })
              Text('获取 API Key').fontSize(13).fontColor(Theme.accent).padding({ top: 8 })
                .onClick(() => this.openUrl('https://www.themoviedb.org/settings/api'))
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%').padding(16).backgroundColor(Theme.surface)
        }
        ListItem() {
          this.SelectRow('元数据语言', strOpts(TMDB_LANG_OPTIONS), indexOfString(TMDB_LANG_OPTIONS, this.s.tmdbLanguage),
            (i: number) => { this.update((s: AppSettings) => { s.tmdbLanguage = TMDB_LANG_OPTIONS[i].value; }); })
        }
        ListItem() {
          this.SelectRow('图片服务器', strOpts(TMDB_IMAGE_BASE_OPTIONS),
            indexOfString(TMDB_IMAGE_BASE_OPTIONS, this.s.tmdbImageBase),
            (i: number) => { this.update((s: AppSettings) => { s.tmdbImageBase = TMDB_IMAGE_BASE_OPTIONS[i].value; }); })
        }
      }

      ListItemGroup({ header: this.GroupHeader('播放'), footer: this.EmptyFooter() }) {
        ListItem() {
          this.SelectRow('默认最高码率', numOpts(BITRATE_OPTIONS), indexOfNumber(BITRATE_OPTIONS, this.s.maxBitrate),
            (i: number) => { this.update((s: AppSettings) => { s.maxBitrate = BITRATE_OPTIONS[i].value; }); })
        }
        ListItem() {
          this.SelectRow('默认倍速', numOpts(SPEED_OPTIONS), indexOfNumber(SPEED_OPTIONS, this.s.defaultSpeed),
            (i: number) => { this.update((s: AppSettings) => { s.defaultSpeed = SPEED_OPTIONS[i].value; }); })
        }
        ListItem() {
          this.ToggleRow('自动播放下一集', '', this.s.autoPlayNext,
            (v: boolean) => { this.update((s: AppSettings) => { s.autoPlayNext = v; }); })
        }
        ListItem() {
          this.SelectRow('首选音轨语言', strOpts(TRACK_LANG_OPTIONS),
            indexOfString(TRACK_LANG_OPTIONS, this.s.preferredAudioLang),
            (i: number) => { this.update((s: AppSettings) => { s.preferredAudioLang = TRACK_LANG_OPTIONS[i].value; }); })
        }
        ListItem() {
          this.SelectRow('首选字幕语言', strOpts(TRACK_LANG_OPTIONS),
            indexOfString(TRACK_LANG_OPTIONS, this.s.preferredSubtitleLang),
            (i: number) => {
              this.update((s: AppSettings) => { s.preferredSubtitleLang = TRACK_LANG_OPTIONS[i].value; });
            })
        }
        ListItem() {
          this.SelectRow('字幕大小', numOpts(SUBTITLE_SCALE_OPTIONS),
            indexOfNumber(SUBTITLE_SCALE_OPTIONS, this.s.subtitleScale),
            (i: number) => { this.update((s: AppSettings) => { s.subtitleScale = SUBTITLE_SCALE_OPTIONS[i].value; }); })
        }
        ListItem() {
          this.SliderRow('跳过片头', Math.round(this.s.skipIntroMs / 1000), 0, 180, 5, '秒',
            (v: number) => { this.update((s: AppSettings) => { s.skipIntroMs = v * 1000; }); })
        }
        ListItem() { this.NavRow('解码能力', '查看本机硬件/软件解码器', () => Nav.codecInfo()) }
        ListItem() { this.NavRow('运行日志', '播放出错时可在这里复制日志发给开发者', () => Nav.logs()) }
        ListItem() {
          this.SelectRow('编码兼容模式', strOpts(CODEC_MODE_OPTIONS), codecModeIndex(this.s.codecMode),
            (i: number) => { this.update((s: AppSettings) => { s.codecMode = CODEC_MODE_OPTIONS[i].value; }); })
        }
        ListItem() {
          this.ToggleRow('优先转封装', '容器不支持时让服务器只换封装、不重新编码，画质无损且几乎不占服务器 CPU',
            this.s.preferRemux, (v: boolean) => { this.update((s: AppSettings) => { s.preferRemux = v; }); })
        }
        ListItem() {
          this.ToggleRow('超分辨率', '低于 1080p 的视频用 GPU/NPU 超分增强', this.s.superResolution,
            (v: boolean) => { this.update((s: AppSettings) => { s.superResolution = v; }); })
        }
        ListItem() {
          this.ToggleRow('HDR 输出', '片源为 HDR 时按 HDR 输出（需屏幕支持）', this.s.preferHdr,
            (v: boolean) => { this.update((s: AppSettings) => { s.preferHdr = v; }); })
        }
      }

      ListItemGroup({ header: this.GroupHeader('首页'), footer: this.EmptyFooter() }) {
        ListItem() {
          this.SelectRow('首页内容来源', this.homeSourceNames().map((n: string) => new SelectItem(n) as SelectOption),
            this.homeSourceIndex(),
            (i: number) => {
              const id = i <= 0 || i > this.sources.length ? '' : this.sources[i - 1].id;
              this.update((s: AppSettings) => { s.homeSourceId = id; });
            })
        }
        ListItem() {
          this.ToggleRow('大屏海报布局', '首页顶部显示大幅背景横幅，适合平板和大屏', this.s.landscapeHome,
            (v: boolean) => { this.update((s: AppSettings) => { s.landscapeHome = v; }); })
        }
      }

      ListItemGroup({ header: this.GroupHeader('缓存'), footer: this.GroupFooter('清除后需要重新刮削才能浏览该网盘媒体库') }) {
        if (this.quarkSources().length === 0) {
          ListItem() { this.InfoRow('本地媒体库', '无') }
        }
        ForEach(this.quarkSources(), (c: SourceConfig) => {
          ListItem() {
            this.NavRow(`清除“${c.name}”的刮削数据`, '', () => this.confirmClearCache(c))
          }
        }, (c: SourceConfig) => 'cache-' + c.id)
      }

      ListItemGroup({ header: this.GroupHeader('关于'), footer: this.EmptyFooter() }) {
        ListItem() { this.InfoRow('影库 CineVault', `版本 ${APP_VERSION}`) }
        ListItem() {
          Column() {
            Text('开源与数据声明').fontSize(16).fontColor(Theme.text)
            Text('本应用不托管影视内容。私人媒体来自用户配置的 Emby / Jellyfin 服务器或夸克网盘，' +
              '内置在线搜索和播放线路由 Flicx 提供。' +
              '影视元数据与图片由 TMDB 提供（This product uses the TMDB API but is not endorsed or certified by TMDB）。' +
              'Emby、Jellyfin、夸克网盘为其各自所有者的商标。')
              .fontSize(13).fontColor(Theme.text2).margin({ top: 6 }).lineHeight(20)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%').padding(16).backgroundColor(Theme.surface)
        }
        ListItem() { this.NavRow('TMDB 官网', 'themoviedb.org', () => this.openUrl('https://www.themoviedb.org')) }
        ListItem() { this.NavRow('Jellyfin 官网', 'jellyfin.org', () => this.openUrl('https://jellyfin.org')) }
      }
    }
    .layoutWeight(1)
    .width('100%')
    .constraintSize({ maxWidth: 900 })
    .padding({ left: 12, right: 12, bottom: 32 })
    .edgeEffect(EdgeEffect.Spring)
  }
}
