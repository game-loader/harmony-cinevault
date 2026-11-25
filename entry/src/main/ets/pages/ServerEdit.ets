import { router, promptAction } from '@kit.ArkUI';
import { SourceConfig, SourceKind } from '../common/Models';
import { SourceStore } from '../common/SourceStore';
import { Settings } from '../common/Settings';
import { Theme } from '../common/Theme';
import { Nav, ServerEditParams } from '../common/Nav';
import { ProviderRegistry } from '../providers/ProviderRegistry';
import { EmbyProvider } from '../providers/EmbyProvider';
import { normalizeServerUrl } from '../components/settings/SettingsLogic';
import { AppLog } from '../common/AppLog';

@Entry
@Component
struct ServerEditPage {
  @State sourceId: string = '';
  @State kind: SourceKind = 'emby';
  @State name: string = '';
  @State url: string = '';
  @State username: string = '';
  @State password: string = '';
  @State busy: boolean = false;
  @State status: string = '';
  @State statusOk: boolean = true;
  @State hasToken: boolean = false;
  private redirected: boolean = false;

  aboutToAppear(): void {
    const p = router.getParams() as ServerEditParams;
    if (p !== undefined && p !== null) {
      this.sourceId = p.sourceId ? p.sourceId : '';
      this.kind = p.kind === 'jellyfin' ? 'jellyfin' : (p.kind === 'quark' ? 'quark' : 'emby');
    }
    if (this.sourceId) {
      const cfg = SourceStore.get(this.sourceId);
      if (cfg !== undefined) {
        this.kind = cfg.kind;
        this.name = cfg.name;
        this.url = cfg.baseUrl;
        this.username = cfg.username;
        this.hasToken = cfg.token.length > 0;
      }
    }
  }

  onPageShow(): void {
    if (this.kind === 'quark' && !this.redirected) {
      this.redirected = true;
      router.back();
      Nav.quarkLogin(this.sourceId);
    }
  }

  private toast(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 2000 });
    } catch (e) {
      AppLog.error(`[ServerEdit] toast: ${(e as Error).message}`);
    }
  }

  private setStatus(msg: string, ok: boolean): void {
    this.status = msg;
    this.statusOk = ok;
  }

  private validUrl(): string {
    const u = normalizeServerUrl(this.url);
    if (!u) {
      this.setStatus('请输入有效的服务器地址，例如 http://192.168.1.10:8096', false);
    }
    return u;
  }

  private async testConnection(): Promise<void> {
    const u = this.validUrl();
    if (!u || this.busy) {
      return;
    }
    this.busy = true;
    this.setStatus('正在连接…', true);
    try {
      const info = await EmbyProvider.probe(u);
      this.url = info.baseUrl || u;
      if (!this.sourceId && (info.kind === 'emby' || info.kind === 'jellyfin')) {
        this.kind = info.kind;
      }
      if (!this.name && info.serverName) {
        this.name = info.serverName;
      }
      const ver = info.version ? ` ${info.version}` : '';
      this.setStatus(`连接成功：${info.serverName || '服务器'}${ver}`, true);
    } catch (e) {
      this.setStatus(`连接失败：${(e as Error).message}`, false);
    } finally {
      this.busy = false;
    }
  }

  private async loginAndSave(): Promise<void> {
    const u = this.validUrl();
    if (!u || this.busy) {
      return;
    }
    if (!this.username.trim()) {
      this.setStatus('请输入用户名', false);
      return;
    }
    this.busy = true;
    this.setStatus('正在登录…', true);
    try {
      const old = this.sourceId ? SourceStore.get(this.sourceId) : undefined;
      const cfg = old !== undefined ? old : new SourceConfig();
      if (!cfg.deviceId) {
        cfg.deviceId = Settings.get().deviceId;
      }
      const res = await EmbyProvider.login(u, this.username.trim(), this.password, this.kind, cfg.deviceId);
      cfg.kind = res.kind === 'jellyfin' ? 'jellyfin' : (res.kind === 'emby' ? 'emby' : this.kind);
      cfg.baseUrl = res.baseUrl || u;
      cfg.username = this.username.trim();
      cfg.userId = res.userId;
      cfg.token = res.token;
      cfg.name = this.name.trim() || res.serverName || (this.kind === 'jellyfin' ? 'Jellyfin' : 'Emby');
      cfg.enabled = true;
      await SourceStore.upsert(cfg);
      ProviderRegistry.invalidate(cfg.id);
      this.sourceId = cfg.id;
      this.toast('已登录并保存');
      router.back();
    } catch (e) {
      this.setStatus(`登录失败：${(e as Error).message}`, false);
    } finally {
      this.busy = false;
    }
  }

  /** Save name / URL edits without re-login (keeps existing token). */
  private async saveOnly(): Promise<void> {
    const cfg = this.sourceId ? SourceStore.get(this.sourceId) : undefined;
    if (cfg === undefined) {
      return;
    }
    const u = this.validUrl();
    if (!u) {
      return;
    }
    cfg.name = this.name.trim() || cfg.name;
    cfg.baseUrl = u;
    await SourceStore.upsert(cfg);
    ProviderRegistry.invalidate(cfg.id);
    this.toast('已保存');
    router.back();
  }

  private confirmDelete(): void {
    this.getUIContext().showAlertDialog({
      title: '删除媒体源',
      message: `确定删除“${this.name || this.url}”吗？此操作不可撤销。`,
      autoCancel: true,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        fontColor: Theme.accent,
        action: () => {
          this.doDelete();
        }
      }
    });
  }

  private async doDelete(): Promise<void> {
    const id = this.sourceId;
    await SourceStore.remove(id);
    ProviderRegistry.invalidate(id);
    const s = Settings.get();
    if (s.homeSourceId === id) {
      s.homeSourceId = '';
      await Settings.save(s);
    }
    this.toast('已删除');
    router.back();
  }

  @Builder
  KindChip(k: SourceKind, label: string) {
    Text(label)
      .fontSize(15)
      .fontColor(this.kind === k ? Color.White : Theme.text2)
      .backgroundColor(this.kind === k ? Theme.accent : Theme.surface2)
      .borderRadius(18)
      .padding({ left: 18, right: 18, top: 8, bottom: 8 })
      .margin({ right: 10 })
      .onClick(() => {
        if (!this.sourceId) {
          this.kind = k;
          if (k === 'quark') {
            this.redirected = true;
            router.back();
            Nav.quarkLogin('');
          }
        }
      })
  }

  @Builder
  Field(label: string, hint: string) {
    Text(label).fontSize(14).fontColor(Theme.text2).margin({ top: 18, bottom: 6 })
    if (hint) {
      Text(hint).fontSize(12).fontColor(Theme.text3).margin({ bottom: 6 })
    }
  }

  build() {
    Column() {
      Row() {
        Text('‹').fontSize(30).fontColor(Theme.text).padding({ right: 12 }).onClick(() => router.back())
        Text(this.sourceId ? '编辑服务器' : '添加服务器').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Theme.text)
          .layoutWeight(1)
        if (this.sourceId) {
          Text('删除').fontSize(15).fontColor(Theme.accent).onClick(() => this.confirmDelete())
        }
      }
      .width('100%').height(56).padding({ left: Theme.pagePad, right: Theme.pagePad })

      Scroll() {
        Column() {
          Text('服务器类型').fontSize(14).fontColor(Theme.text2).margin({ bottom: 8 })
          Row() {
            this.KindChip('emby', 'Emby')
            this.KindChip('jellyfin', 'Jellyfin')
            if (!this.sourceId) {
              this.KindChip('quark', '夸克网盘')
            }
          }

          this.Field('服务器地址', '包含协议和端口，如 http://192.168.1.10:8096 或 https://emby.example.com')
          TextInput({ text: this.url, placeholder: 'http://192.168.1.10:8096' })
            .type(InputType.URL)
            .fontColor(Theme.text).placeholderColor(Theme.text3).backgroundColor(Theme.surface2)
            .onChange((v: string) => { this.url = v; })

          this.Field('显示名称（可选）', '')
          TextInput({ text: this.name, placeholder: '默认使用服务器名称' })
            .fontColor(Theme.text).placeholderColor(Theme.text3).backgroundColor(Theme.surface2)
            .onChange((v: string) => { this.name = v; })

          this.Field('用户名', '')
          TextInput({ text: this.username, placeholder: '用户名' })
            .fontColor(Theme.text).placeholderColor(Theme.text3).backgroundColor(Theme.surface2)
            .onChange((v: string) => { this.username = v; })

          this.Field('密码', this.hasToken ? '已登录；修改账号或令牌失效时请重新登录' : '无密码可留空')
          TextInput({ text: this.password, placeholder: '密码' })
            .type(InputType.Password)
            .fontColor(Theme.text).placeholderColor(Theme.text3).backgroundColor(Theme.surface2)
            .onChange((v: string) => { this.password = v; })

          if (this.status) {
            Text(this.status)
              .fontSize(14)
              .fontColor(this.statusOk ? '#4CAF50' : Theme.accent)
              .margin({ top: 16 })
          }

          Row() {
            if (this.busy) {
              LoadingProgress().width(28).height(28).color(Theme.text2).margin({ right: 12 })
            }
            Button('测试连接')
              .backgroundColor(Theme.surface2).fontColor(Theme.text)
              .enabled(!this.busy)
              .layoutWeight(1).margin({ right: 12 })
              .onClick(() => { this.testConnection(); })
            Button('登录并保存')
              .backgroundColor(Theme.accent).fontColor(Color.White)
              .enabled(!this.busy)
              .layoutWeight(1)
              .onClick(() => { this.loginAndSave(); })
          }
          .width('100%').margin({ top: 28 })

          if (this.sourceId && this.hasToken) {
            Button('仅保存名称和地址')
              .backgroundColor(Color.Transparent).fontColor(Theme.text2)
              .width('100%').margin({ top: 12 })
              .enabled(!this.busy)
              .onClick(() => { this.saveOnly(); })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .constraintSize({ maxWidth: 640 })
        .padding({ left: Theme.pagePad, right: Theme.pagePad, bottom: 40 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%').height('100%').backgroundColor(Theme.bg)
  }
}
