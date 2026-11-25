import { router, window, promptAction } from '@kit.ArkUI';
import { audio, AVVolumePanel } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PlayerParams } from '../common/Nav';
import { MediaItem, PlaybackInfo, PlaybackRequest, SubtitleTrack, AudioTrack, QualityOption } from '../common/Models';
import { CodecCaps, CodecEntry, DecoderInfo } from '../media/CodecCaps';
import { MediaProvider } from '../common/MediaProvider';
import { ProviderRegistry } from '../providers/ProviderRegistry';
import { Settings, AppSettings } from '../common/Settings';
import { SourceStore } from '../common/SourceStore';
import { AppContext } from '../common/AppContext';
import { FlicxMapper } from '../flicx/FlicxMapper';
import { Theme } from '../common/Theme';
import { PlayerController, PlayerCallbacks, OpenOptions, EmbeddedTrack, NetStats } from '../player/PlayerController';
import { PlayerOverlay } from '../player/PlayerOverlay';
import { PlaybackInfoPanel } from '../player/PlaybackInfoPanel';
import { TrackSheet, SheetItem, SheetStepper } from '../player/TrackSheet';
import { SubtitleCue, cueTextAt, formatDuration } from '../player/SubtitleParser';
import { loadSubtitle } from '../player/SubtitleLoader';
import {
  VideoBox, computeVideoBox, ASPECT_MODES, aspectLabel, SPEEDS, speedLabel, nearestSpeed, pickByLanguage,
  resolveStartMs, nextInQueue, prevInQueue, clamp, swipeSeekRange, bitrateOptions, BitrateOption, nextCountdown,
  decideFallback, FallbackStep, normCodec, mimeToCodec, CodecMime, InfoRow, TrackStat, DecoderStat, StatsInput,
  buildInfoRows
} from '../player/PlayerLogic';

const HIDE_DELAY_MS: number = 4000;
const REPORT_INTERVAL_MS: number = 10000;
const NEXT_WINDOW_MS: number = 5000;
const INTRO_WINDOW_MS: number = 180000;
const TRANSCODE_BITRATE: number = 8000000;
/** No first video frame this long after open() / after 'prepared' => treat as failure (network streams only) */
const STALL_OPEN_MS: number = 25000;
const STALL_PREPARED_MS: number = 15000;
const FALLBACK_BANNER_MS: number = 5000;

function key2(kind: string, idx: number): string {
  return kind + ':' + idx;
}

@Entry
@Component
struct PlayerPage {
  @State loading: boolean = true;
  @State loadingText: string = '正在加载…';
  @State errorMsg: string = '';
  @State title: string = '';
  @State subTitle: string = '';
  @State playing: boolean = false;
  @State positionMs: number = 0;
  @State durationMs: number = 0;
  @State bufferedMs: number = 0;
  @State buffering: boolean = false;
  @State showControls: boolean = true;
  @State locked: boolean = false;
  @State sheet: string = '';
  @State sheetLoading: boolean = false;
  @State areaW: number = 0;
  @State areaH: number = 0;
  @State videoW: number = 0;
  @State videoH: number = 0;
  @State aspect: string = 'fit';
  @State speed: number = 1;
  @State tempSpeed: boolean = false;
  @State subtitleText: string = '';
  @State subScale: number = 1;
  @State subDelayMs: number = 0;
  @State subKey: string = 'off';
  @State qualityKey: string = '';
  @State private isFlicx: boolean = false;
  @State audioKey: string = '';
  @State gestureHint: string = '';
  @State scrubMs: number = -1;
  @State resumeBannerMs: number = 0;
  @State countdown: number = -1;
  @State showSkipIntro: boolean = false;
  @State episodes: MediaItem[] = [];
  @State embeddedAudio: EmbeddedTrack[] = [];
  @State embeddedSubs: EmbeddedTrack[] = [];
  @State hasNext: boolean = false;
  @State hasPrev: boolean = false;
  @State volumeLevel: number = 0;
  @State showVolumePanel: boolean = false;
  @State showInfo: boolean = false;
  @State infoRows: InfoRow[] = [];
  @State fallbackBanner: string = '';
  @State srStatus: string = 'off';

  private params: PlayerParams = new PlayerParams();
  private settings: AppSettings = new AppSettings();
  private provider: MediaProvider | undefined = undefined;
  private item: MediaItem | undefined = undefined;
  private info: PlaybackInfo | undefined = undefined;
  private req: PlaybackRequest = new PlaybackRequest();
  private ctl: PlayerController = new PlayerController();
  private xc: XComponentController = new XComponentController();
  private surfaceReady: boolean = false;
  private pendingOpen: OpenOptions | undefined = undefined;
  private cues: SubtitleCue[] = [];
  private externalSubActive: boolean = false;
  private started: boolean = false;
  private nextCancelled: boolean = false;
  private hideTimer: number = -1;
  private reportTimer: number = -1;
  private bannerTimer: number = -1;
  private hintTimer: number = -1;
  private win: window.Window | undefined = undefined;
  private prevOrientation: window.Orientation = window.Orientation.UNSPECIFIED;
  private curBrightness: number = 0.5;
  private maxVolume: number = 15;
  private minVolume: number = 0;
  private panAxis: string = '';
  private panStartValue: number = 0;
  private panLeftSide: boolean = false;
  private savedSpeed: number = 1;
  private tracksInitDone: boolean = false;
  private disposed: boolean = false;
  private loadToken: number = 0;
  // automatic fallback chain (per item)
  private fbTried: string[] = [];
  private fbHandledOpen: number = -1;
  private openCount: number = 0;
  private curUrl: string = '';
  /** index into info.qualities of the stream being played, -1 when info.url is not in qualities */
  private curQuality: number = -1;
  private firstFrame: boolean = false;
  private stallTimer: number = -1;
  private fbBannerTimer: number = -1;
  // selection carried across a fallback re-request
  private restoreSubKey: string = '';
  private restoreAudioLang: string = '';
  private restoreSubLang: string = '';
  private restoreSubOff: boolean = false;
  // info panel
  private infoTimer: number = -1;
  private infoBusy: boolean = false;
  private codecMimes: CodecMime[] | undefined = undefined;
  /** subtitles were explicitly off before a fallback switch: don't adopt a track the new player auto-selected */
  private userSubOff: boolean = false;

  aboutToAppear(): void {
    const p = router.getParams() as PlayerParams;
    if (p !== undefined && p !== null) {
      this.params.sourceId = p.sourceId ?? '';
      this.params.itemId = p.itemId ?? '';
      this.params.startMs = p.startMs ?? -1;
      this.params.queue = p.queue ?? [];
    }
    this.bindCallbacks();
    this.reportTimer = setInterval(() => this.periodicReport(), REPORT_INTERVAL_MS);
    this.init();
  }

  aboutToDisappear(): void {
    this.disposed = true;
    clearInterval(this.reportTimer);
    clearTimeout(this.hideTimer);
    clearTimeout(this.bannerTimer);
    clearTimeout(this.hintTimer);
    clearTimeout(this.stallTimer);
    clearTimeout(this.fbBannerTimer);
    clearInterval(this.infoTimer);
    this.stopSubtitleTicker();
    this.reportStoppedNow();
    this.ctl.release();
    this.restoreWindow();
  }

  onPageHide(): void {
    if (this.ctl.isPlaying()) {
      this.ctl.pause();
    }
    this.reportProgressNow(true);
  }

  onPageShow(): void {
    if (this.win !== undefined) {
      this.applyFullscreen(this.win);
    }
  }

  onBackPress(): boolean {
    if (this.sheet.length > 0) {
      this.sheet = '';
      return true;
    }
    if (this.locked) {
      this.toast('屏幕已锁定，请先点击锁形按钮解锁');
      this.revealControls();
      return true;
    }
    return false;
  }

  private async init(): Promise<void> {
    this.setupWindow();
    try {
      this.settings = await Settings.load();
      await SourceStore.load();
    } catch (e) {
      console.warn(`[Player] init load failed: ${(e as Error).message}`);
    }
    this.speed = nearestSpeed(this.settings.defaultSpeed > 0 ? this.settings.defaultSpeed : 1);
    this.subScale = this.settings.subtitleScale > 0 ? this.settings.subtitleScale : 1;
    this.initVolume();
    if (this.params.sourceId.length === 0 || this.params.itemId.length === 0) {
      this.fail('缺少播放参数');
      return;
    }
    this.provider = ProviderRegistry.get(this.params.sourceId);
    if (this.provider === undefined) {
      this.fail('媒体源不存在或已被删除');
      return;
    }
    this.isFlicx = this.provider.config.id === 'flicx';
    await this.loadItem(this.params.itemId, this.params.startMs);
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
    } catch (e) {
      console.warn(`[Player] toast failed: ${msg}`);
    }
  }

  private fail(msg: string): void {
    this.loading = false;
    this.buffering = false;
    this.errorMsg = msg;
    this.showControls = true;
    this.locked = false;
  }

  // ---------- loading ----------

  private async loadItem(itemId: string, startParam: number): Promise<void> {
    const prov = this.provider;
    if (prov === undefined) {
      return;
    }
    const token = ++this.loadToken;
    if (this.isFlicx) {
      this.info = undefined;
    }
    this.loading = true;
    this.loadingText = '正在加载…';
    this.errorMsg = '';
    this.started = false;
    this.nextCancelled = false;
    this.countdown = -1;
    this.resumeBannerMs = 0;
    this.subtitleText = '';
    this.cues = [];
    this.externalSubActive = false;
    this.subKey = 'off';
    this.audioKey = '';
    this.qualityKey = '';
    this.embeddedAudio = [];
    this.embeddedSubs = [];
    this.tracksInitDone = false;
    this.positionMs = 0;
    this.durationMs = 0;
    this.bufferedMs = 0;
    this.videoW = 0;
    this.videoH = 0;
    this.fbTried = [];
    this.fbHandledOpen = -1;
    this.curQuality = -1;
    this.fallbackBanner = '';
    this.userSubOff = false;
    this.clearRestore();
    let item: MediaItem;
    try {
      item = await prov.getItem(itemId);
    } catch (e) {
      if (token === this.loadToken) {
        this.fail('获取影片信息失败: ' + (e as Error).message);
      }
      return;
    }
    if (token !== this.loadToken || this.disposed) {
      return;
    }
    this.item = item;
    this.applyTitles(item);
    const start = resolveStartMs(startParam, item.state.positionMs, item.runtimeMs);
    if (startParam === -1 && start > 0) {
      this.showResumeBanner(start);
    }
    this.req = new PlaybackRequest();
    this.req.maxBitrate = this.isFlicx ? 0 : this.settings.maxBitrate;
    this.req.startMs = start;
    await this.fetchAndOpen(start, token);
    this.loadEpisodes(item);
  }

  private applyTitles(item: MediaItem): void {
    if (item.type === 'episode') {
      this.title = item.seriesTitle.length > 0 ? item.seriesTitle : item.title;
      const code = (item.seasonNumber >= 0 ? `S${item.seasonNumber}` : '') +
        (item.episodeNumber >= 0 ? `E${item.episodeNumber}` : '');
      const parts: string[] = [];
      if (code.length > 0) {
        parts.push(code);
      }
      if (item.title.length > 0 && item.title !== this.title) {
        parts.push(item.title);
      }
      this.subTitle = parts.join(' · ');
    } else {
      this.title = item.title;
      this.subTitle = item.year > 0 ? String(item.year) : '';
    }
  }

  /** getPlayback with this.req, then open the player at startMs. */
  private async fetchAndOpen(startMs: number, token: number): Promise<void> {
    const prov = this.provider;
    const item = this.item;
    if (prov === undefined || item === undefined) {
      return;
    }
    this.loading = true;
    this.loadingText = '正在获取播放地址…';
    this.errorMsg = '';
    let info: PlaybackInfo;
    try {
      this.req.startMs = startMs;
      info = await prov.getPlayback(item, this.req);
    } catch (e) {
      if (token === this.loadToken) {
        this.fail('获取播放地址失败: ' + (e as Error).message);
      }
      return;
    }
    if (token !== this.loadToken || this.disposed) {
      return;
    }
    if (info.url.length === 0) {
      this.fail('没有可播放的地址');
      return;
    }
    this.info = info;
    this.curQuality = info.qualities.findIndex((q: QualityOption) => q.url === info.url);
    if (this.isFlicx) {
      this.qualityKey = 'q:' + this.curQuality;
    }
    if (info.durationMs > 0) {
      this.durationMs = info.durationMs;
    }
    this.chooseServerTracks(info);
    this.openUrl(info.url, info.headers, startMs);
    if (this.restoreSubKey.length > 0) {
      this.restoreSubtitle(info);
      this.restoreSubKey = '';
    } else {
      this.autoPickExternalSubtitle(info);
    }
  }

  /** If the server transcodes, audio must be picked server-side; re-request once when the preferred language differs. */
  private chooseServerTracks(info: PlaybackInfo): void {
    if (this.req.audioIndex < 0 && info.audioTracks.length > 1) {
      const langs: string[] = info.audioTracks.map((a: AudioTrack) => a.language);
      const titles: string[] = info.audioTracks.map((a: AudioTrack) => a.title);
      const i = pickByLanguage(langs, titles, this.settings.preferredAudioLang);
      if (i >= 0) {
        this.audioKey = 'srv:' + info.audioTracks[i].index;
      }
    }
  }

  private openUrl(url: string, headers: Record<string, string>, startMs: number): void {
    const opt = new OpenOptions();
    opt.url = url;
    opt.headers = headers;
    opt.startMs = startMs;
    opt.speed = this.speed;
    opt.autoPlay = true;
    opt.preferredAudioLang = this.restoreAudioLang.length > 0 ? this.restoreAudioLang : this.settings.preferredAudioLang;
    opt.preferredSubtitleLang = this.restoreSubLang.length > 0 ? this.restoreSubLang : this.settings.preferredSubtitleLang;
    opt.superResolution = this.settings.superResolution;
    opt.preferHdr = this.settings.preferHdr;
    const lower = url.toLowerCase();
    opt.isHls = this.isFlicx || lower.indexOf('.m3u8') >= 0 ||
      (this.info !== undefined && this.info.container.toLowerCase() === 'hls');
    this.loadingText = '正在缓冲…';
    this.positionMs = startMs;
    this.openCount++;
    this.curUrl = url;
    this.firstFrame = false;
    this.armStall(STALL_OPEN_MS);
    if (!this.surfaceReady) {
      this.pendingOpen = opt;
      return;
    }
    this.ctl.open(opt);
  }

  // ---------- player callbacks ----------

  private lastTimeMs: number = 0;
  private lastTimeAt: number = 0;
  private subTicker: number = -1;

  private bindCallbacks(): void {
    const cb = new PlayerCallbacks();
    cb.onState = (s: string) => this.onState(s);
    cb.onTime = (ms: number) => this.onTime(ms);
    cb.onDuration = (ms: number) => {
      this.durationMs = ms;
    };
    cb.onBuffering = (b: boolean) => {
      this.buffering = b;
    };
    cb.onCachedMs = (ms: number) => {
      this.bufferedMs = Math.min(this.durationMs > 0 ? this.durationMs : ms, this.positionMs + ms);
    };
    cb.onBufferPercent = (p: number) => {
      if (this.durationMs > 0 && p >= 0 && p <= 100) {
        const b = this.durationMs * p / 100;
        if (b > this.bufferedMs) {
          this.bufferedMs = b;
        }
      }
    };
    cb.onVideoSize = (w: number, h: number) => {
      if (w > 0 && h > 0) {
        this.videoW = w;
        this.videoH = h;
      }
    };
    cb.onFirstFrame = () => {
      this.firstFrame = true;
      clearTimeout(this.stallTimer);
    };
    cb.onSuperRes = (st: string) => {
      this.srStatus = st;
    };
    cb.onSeekDone = (ms: number) => {
      this.buffering = false;
      this.syncSubtitle();
    };
    cb.onError = (m: string) => this.onPlayerError(m);
    cb.onWarn = (m: string) => this.toast(m);
    cb.onTracks = (t: EmbeddedTrack[]) => this.onTracks(t);
    cb.onSubtitle = (text: string, startMs: number, durationMs: number) => {
      // AVPlayer-rendered text: embedded tracks and header-less external URLs
      if (!this.externalSubActive && this.subKey !== 'off') {
        this.subtitleText = text;
      }
    };
    cb.onFirstPlay = () => this.onFirstPlay();
    cb.onInterruptPause = () => {
      this.ctl.pause();
    };
    this.ctl.cb = cb;
  }

  private onState(s: string): void {
    this.playing = s === 'playing';
    if (s === 'playing') {
      this.loading = false;
      this.errorMsg = '';
      this.lastTimeMs = this.ctl.positionMs;
      this.lastTimeAt = Date.now();
      this.startSubtitleTicker();
      this.scheduleHide();
    } else if (s === 'paused') {
      this.stopSubtitleTicker();
      this.revealControls();
      this.reportProgressNow(true);
    } else if (s === 'prepared') {
      this.loading = false;
      if (!this.firstFrame) {
        this.armStall(STALL_PREPARED_MS);
      }
    } else if (s === 'completed') {
      this.stopSubtitleTicker();
      this.onCompleted();
    } else if (s === 'stopped' || s === 'released' || s === 'idle') {
      this.stopSubtitleTicker();
    }
  }

  private onTime(ms: number): void {
    if (this.scrubMs < 0) {
      this.positionMs = ms;
    }
    this.lastTimeMs = ms;
    this.lastTimeAt = Date.now();
    if (this.bufferedMs < ms) {
      this.bufferedMs = ms;
    }
    this.syncSubtitle();
    // skip intro offer in the first 3 minutes
    const skip = this.settings.skipIntroMs;
    this.showSkipIntro = skip > 0 && ms < Math.min(INTRO_WINDOW_MS, skip) && ms < skip - 1000;
    // next episode countdown
    if (this.settings.autoPlayNext && !this.nextCancelled && this.hasNextItem()) {
      this.countdown = nextCountdown(ms, this.durationMs, NEXT_WINDOW_MS);
    } else {
      this.countdown = -1;
    }
  }

  private onFirstPlay(): void {
    if (this.videoW > 0 && this.videoH > 0) {
      // decoder reported a picture size and playback runs: not a stall even if startRenderFrame never arrives
      this.firstFrame = true;
      clearTimeout(this.stallTimer);
    }
    if (this.started) {
      return;
    }
    this.started = true;
    const prov = this.provider;
    const item = this.item;
    const info = this.info;
    if (prov !== undefined && item !== undefined && info !== undefined) {
      prov.reportStart(item, info, this.ctl.positionMs).catch((e: Error) => {
        console.warn(`[Player] reportStart failed: ${e.message}`);
      });
    }
  }

  private onPlayerError(m: string): void {
    if (this.fbHandledOpen === this.openCount) {
      // a second error event for an open that is already being replaced
      return;
    }
    this.fbHandledOpen = this.openCount;
    clearTimeout(this.stallTimer);
    this.playing = false;
    this.stopSubtitleTicker();
    this.reportProgressNow(true);
    if (this.tryFallback(m)) {
      return;
    }
    this.fail(m);
  }

  // ---------- automatic fallback ----------

  private armStall(ms: number): void {
    clearTimeout(this.stallTimer);
    if (!/^https?:\/\//i.test(this.curUrl)) {
      return;
    }
    const open = this.openCount;
    this.stallTimer = setTimeout(() => this.onStall(open), ms);
  }

  /** No video frame in time: switch like on an error, but keep waiting when nothing is left to try. */
  private onStall(open: number): void {
    if (open !== this.openCount || this.firstFrame || this.disposed || this.errorMsg.length > 0 ||
      this.fbHandledOpen === open || this.ctl.state === 'paused') {
      return;
    }
    const step = this.nextFallback();
    if (step.action === 'none') {
      return;
    }
    console.warn(`[Player] no video frame after open, fallback ${step.key}`);
    this.fbHandledOpen = open;
    this.runFallback(step);
  }

  /** Index of the active quality or line, -1 if it isn't listed in info.qualities. */
  private playingQuality(): number {
    const info = this.info;
    if (info === undefined || info.qualities.length === 0) {
      return -1;
    }
    if (this.curQuality >= 0) {
      return this.curQuality;
    }
    return info.qualities.findIndex((q: QualityOption) => q.url === info.url);
  }

  /** Delivery mode of what is actually playing (a Quark transcode quality counts as 'transcode'). */
  private effectiveMode(): string {
    const info = this.info;
    if (info === undefined || this.isFlicx) {
      return 'direct';
    }
    const qi = this.playingQuality();
    if (qi >= 0) {
      return info.qualities[qi].label === '原画' ? 'direct' : 'transcode';
    }
    return info.deliveryMode;
  }

  private nextFallback(): FallbackStep {
    const info = this.info;
    if (info === undefined || this.item === undefined || this.isFlicx) {
      return new FallbackStep();
    }
    const labels: string[] = info.qualities.map((q: QualityOption) => q.label);
    // record the attempt that just failed so it is never retried automatically
    const cur = labels.length > 0 ? 'q:' + this.playingQuality() : info.deliveryMode;
    const tried: string[] = this.fbTried.slice();
    if (tried.indexOf(cur) < 0) {
      tried.push(cur);
    }
    return decideFallback(info.deliveryMode, labels, this.playingQuality(), tried);
  }

  private tryFallback(m: string): boolean {
    const step = this.nextFallback();
    if (step.action === 'none') {
      return false;
    }
    console.warn(`[Player] playback failed (${m}), fallback ${step.key}`);
    this.runFallback(step);
    return true;
  }

  private async runFallback(step: FallbackStep): Promise<void> {
    const info = this.info;
    if (info === undefined) {
      return;
    }
    this.fbTried.push(step.key);
    const pos = this.currentPos() > 0 ? this.currentPos() : this.req.startMs;
    this.showFallbackBanner(step.banner);
    this.errorMsg = '';
    this.loading = true;
    this.loadingText = '正在切换播放方式…';
    if (step.action === 'quality') {
      // same Quark item/session: just a different link, like a manual quality switch
      const q = info.qualities[step.qualityIndex];
      this.curQuality = step.qualityIndex;
      this.qualityKey = 'q:' + step.qualityIndex;
      this.captureSelection(false);
      this.openUrl(q.url, Object.keys(q.headers).length > 0 ? q.headers : info.headers, pos);
      if (this.restoreSubKey.length > 0) {
        this.restoreSubtitle(info);
        this.restoreSubKey = '';
      }
      return;
    }
    this.captureSelection(true);
    this.stopSessionForSwitch(pos);
    this.req.forceMode = step.action;
    await this.fetchAndOpen(pos, this.loadToken);
  }

  /** End the server play session (and its encode job) before a new one is started. */
  private stopSessionForSwitch(pos: number): void {
    const prov = this.provider;
    const item = this.item;
    const info = this.info;
    if (this.started) {
      this.reportStoppedNow();
      return;
    }
    if (prov !== undefined && item !== undefined && info !== undefined &&
      (info.deliveryMode !== 'direct' || info.isTranscode) && info.playSessionId.length > 0) {
      // never reached first play, but the server may already be remuxing / transcoding for it
      prov.reportStopped(item, info, pos).catch((e: Error) => {
        console.warn(`[Player] reportStopped (switch) failed: ${e.message}`);
      });
    }
  }

  private clearRestore(): void {
    this.restoreSubKey = '';
    this.restoreAudioLang = '';
    this.restoreSubLang = '';
    this.restoreSubOff = false;
  }

  /** Remember audio / subtitle choice so the replacement stream starts with the same ones. */
  private captureSelection(serverRequest: boolean): void {
    this.clearRestore();
    const info = this.info;
    if (info === undefined) {
      return;
    }
    let audioLang = '';
    let audioName = '';
    if (this.audioKey.startsWith('emb:')) {
      const idx = Number(this.audioKey.substring(4));
      const t = this.embeddedAudio.find((a: EmbeddedTrack) => a.index === idx);
      if (t !== undefined) {
        audioLang = t.language;
        audioName = t.name;
      }
    } else if (this.audioKey.startsWith('srv:')) {
      const idx = Number(this.audioKey.substring(4));
      const a = info.audioTracks.find((x: AudioTrack) => x.index === idx);
      if (a !== undefined) {
        audioLang = a.language;
        audioName = a.title;
      }
    }
    this.restoreAudioLang = audioLang;
    if (serverRequest && this.req.audioIndex < 0 && audioLang.length > 0 && info.audioTracks.length > 1) {
      // embedded index is container specific: map to the server stream index by language
      const i = pickByLanguage(info.audioTracks.map((a: AudioTrack) => a.language),
        info.audioTracks.map((a: AudioTrack) => a.title), audioLang.length > 0 ? audioLang : audioName);
      if (i >= 0) {
        this.req.audioIndex = info.audioTracks[i].index;
        this.audioKey = 'srv:' + info.audioTracks[i].index;
      }
    }
    if (this.subKey.startsWith('ext:') || this.subKey.startsWith('url:')) {
      this.restoreSubKey = this.subKey;
    } else if (this.subKey.startsWith('emb:')) {
      const idx = Number(this.subKey.substring(4));
      const t = this.embeddedSubs.find((x: EmbeddedTrack) => x.index === idx);
      this.restoreSubLang = t !== undefined ? t.language : '';
      this.restoreSubKey = 'emb';
    } else if (this.subKey === 'off') {
      this.restoreSubOff = true;
      this.restoreSubKey = 'off';
    }
    // srv: subtitles stay in this.req.subtitleIndex
    // the new stream reports its own embedded tracks: re-run the initial track pick with the captured languages
    this.tracksInitDone = false;
    this.embeddedAudio = [];
    this.embeddedSubs = [];
    this.externalSubActive = false;
    this.cues = [];
    this.subtitleText = '';
    this.subKey = this.subKey.startsWith('srv:') ? this.subKey : 'off';
  }

  private restoreSubtitle(info: PlaybackInfo): void {
    const k = this.restoreSubKey;
    if (k.startsWith('ext:') || k.startsWith('url:')) {
      const idx = Number(k.substring(4));
      const t = info.subtitles.find((x: SubtitleTrack) => x.index === idx && x.isExternal && x.url.length > 0);
      if (t !== undefined) {
        this.useExternalSubtitle(t);
      }
    }
    // 'emb' / 'off' are handled in onTracks when the new player reports its tracks
  }

  private showFallbackBanner(text: string): void {
    this.fallbackBanner = text;
    clearTimeout(this.fbBannerTimer);
    this.fbBannerTimer = setTimeout(() => {
      this.fallbackBanner = '';
    }, FALLBACK_BANNER_MS);
  }

  // ---------- subtitles (own rendering) ----------

  private startSubtitleTicker(): void {
    if (this.subTicker >= 0) {
      return;
    }
    this.subTicker = setInterval(() => this.syncSubtitle(), 200);
  }

  private stopSubtitleTicker(): void {
    if (this.subTicker >= 0) {
      clearInterval(this.subTicker);
      this.subTicker = -1;
    }
  }

  private estimatedPosition(): number {
    if (!this.playing) {
      return this.lastTimeMs;
    }
    const elapsed = (Date.now() - this.lastTimeAt) * this.ctl.speed;
    return this.lastTimeMs + Math.min(elapsed, 1500);
  }

  private syncSubtitle(): void {
    if (!this.externalSubActive || this.cues.length === 0) {
      return;
    }
    const t = cueTextAt(this.cues, this.estimatedPosition() - this.subDelayMs);
    if (t !== this.subtitleText) {
      this.subtitleText = t;
    }
  }

  private autoPickExternalSubtitle(info: PlaybackInfo): void {
    if (this.req.subtitleIndex >= 0) {
      const chosen = info.subtitles.find((s: SubtitleTrack) => s.index === this.req.subtitleIndex);
      if (chosen !== undefined && chosen.isExternal && chosen.url.length > 0) {
        this.useExternalSubtitle(chosen);
      }
      return;
    }
    const ext = info.subtitles.filter((s: SubtitleTrack) => s.isExternal && s.url.length > 0);
    if (ext.length === 0) {
      return;
    }
    const langs: string[] = ext.map((s: SubtitleTrack) => s.language);
    const titles: string[] = ext.map((s: SubtitleTrack) => s.title);
    let i = pickByLanguage(langs, titles, this.settings.preferredSubtitleLang);
    if (i < 0) {
      i = ext.findIndex((s: SubtitleTrack) => s.isDefault);
    }
    if (i >= 0) {
      this.useExternalSubtitle(ext[i]);
    }
  }

  private async useExternalSubtitle(t: SubtitleTrack): Promise<void> {
    const info = this.info;
    if (info === undefined) {
      return;
    }
    await this.disableEmbeddedSubs();
    const key = 'ext:' + t.index;
    this.subKey = key;
    this.subtitleText = '';
    this.externalSubActive = false;
    this.cues = [];
    const token = this.loadToken;
    try {
      const cues = await loadSubtitle(t.url, info.headers, t.codec);
      if (token !== this.loadToken || this.subKey !== key) {
        return;
      }
      this.cues = cues;
      this.externalSubActive = true;
      this.syncSubtitle();
    } catch (e) {
      if (token === this.loadToken && this.subKey === key) {
        // header-less URL: let AVPlayer try it natively
        if (Object.keys(info.headers).length === 0 && await this.ctl.addSubtitleUrl(t.url)) {
          this.subKey = 'url:' + t.index;
          return;
        }
        this.subKey = 'off';
        this.toast((e as Error).message);
      }
    }
  }

  private async disableEmbeddedSubs(): Promise<void> {
    const sel = await this.ctl.selectedTracks();
    for (let i = 0; i < this.embeddedSubs.length; i++) {
      if (sel.indexOf(this.embeddedSubs[i].index) >= 0) {
        await this.ctl.deselectTrack(this.embeddedSubs[i].index);
      }
    }
  }

  private async subtitleOff(): Promise<void> {
    this.subKey = 'off';
    this.externalSubActive = false;
    this.cues = [];
    this.subtitleText = '';
    await this.disableEmbeddedSubs();
  }

  // ---------- embedded tracks ----------

  private async onTracks(list: EmbeddedTrack[]): Promise<void> {
    this.embeddedAudio = list.filter((t: EmbeddedTrack) => t.type === 0);
    this.embeddedSubs = list.filter((t: EmbeddedTrack) => t.type === 2);
    const sel = await this.ctl.selectedTracks();
    const curAudio = this.embeddedAudio.find((t: EmbeddedTrack) => sel.indexOf(t.index) >= 0);
    if (curAudio !== undefined && !this.audioKey.startsWith('srv:')) {
      this.audioKey = 'emb:' + curAudio.index;
    }
    if (!this.tracksInitDone) {
      this.tracksInitDone = true;
      // after a fallback switch the captured choice wins over the settings
      const audioPref = this.restoreAudioLang.length > 0 ? this.restoreAudioLang : this.settings.preferredAudioLang;
      const subPref = this.restoreSubLang.length > 0 ? this.restoreSubLang : this.settings.preferredSubtitleLang;
      const subOff = this.restoreSubOff;
      this.userSubOff = subOff;
      if (subOff && this.embeddedSubs.length > 0) {
        await this.disableEmbeddedSubs();
      }
      this.restoreAudioLang = '';
      this.restoreSubLang = '';
      this.restoreSubOff = false;
      // preferred embedded audio
      if (this.embeddedAudio.length > 1 && !this.audioKey.startsWith('srv:')) {
        const i = pickByLanguage(this.embeddedAudio.map((t: EmbeddedTrack) => t.language),
          this.embeddedAudio.map((t: EmbeddedTrack) => t.name), audioPref);
        if (i >= 0 && (curAudio === undefined || curAudio.index !== this.embeddedAudio[i].index)) {
          this.audioKey = 'emb:' + this.embeddedAudio[i].index;
          await this.ctl.selectTrack(this.embeddedAudio[i].index);
        }
      }
      // embedded subtitle only when no external one was chosen
      if (this.subKey === 'off' && this.embeddedSubs.length > 0 && !subOff) {
        const j = pickByLanguage(this.embeddedSubs.map((t: EmbeddedTrack) => t.language),
          this.embeddedSubs.map((t: EmbeddedTrack) => t.name), subPref);
        if (j >= 0) {
          this.subKey = 'emb:' + this.embeddedSubs[j].index;
          await this.ctl.selectTrack(this.embeddedSubs[j].index);
        }
      }
    }
    const curSub = this.embeddedSubs.find((t: EmbeddedTrack) => sel.indexOf(t.index) >= 0);
    if (curSub !== undefined && this.subKey === 'off' && !this.userSubOff) {
      this.subKey = 'emb:' + curSub.index;
    }
  }

  // ---------- episodes / next ----------

  private async loadEpisodes(item: MediaItem): Promise<void> {
    const prov = this.provider;
    this.updateNeighbours();
    if (prov === undefined || item.type !== 'episode' || item.seriesId.length === 0) {
      return;
    }
    try {
      const list = await prov.getEpisodes(item.seriesId, item.seasonId);
      if (this.item === undefined || this.item.id !== item.id) {
        return;
      }
      this.episodes = list;
      this.updateNeighbours();
    } catch (e) {
      console.warn(`[Player] getEpisodes failed: ${(e as Error).message}`);
    }
  }

  private nextId(): string {
    const item = this.item;
    if (item === undefined) {
      return '';
    }
    if (this.params.queue.length > 0) {
      return nextInQueue(this.params.queue, item.id);
    }
    const ids: string[] = this.episodes.map((e: MediaItem) => e.id);
    return nextInQueue(ids, item.id);
  }

  private prevId(): string {
    const item = this.item;
    if (item === undefined) {
      return '';
    }
    if (this.params.queue.length > 0) {
      return prevInQueue(this.params.queue, item.id);
    }
    const ids: string[] = this.episodes.map((e: MediaItem) => e.id);
    return prevInQueue(ids, item.id);
  }

  private hasNextItem(): boolean {
    return this.hasNext;
  }

  private updateNeighbours(): void {
    this.hasNext = this.nextId().length > 0;
    this.hasPrev = this.prevId().length > 0;
  }

  private onCompleted(): void {
    this.reportStoppedNow();
    this.countdown = -1;
    if (this.settings.autoPlayNext && !this.nextCancelled && this.hasNext) {
      this.playNext();
    } else {
      this.playing = false;
      this.revealControls();
    }
  }

  private async switchTo(id: string): Promise<void> {
    if (id.length === 0) {
      return;
    }
    this.sheet = '';
    this.reportStoppedNow();
    await this.loadItem(id, 0);
  }

  private playNext(): void {
    this.switchTo(this.nextId());
  }

  private playPrev(): void {
    this.switchTo(this.prevId());
  }

  // ---------- reporting ----------

  private periodicReport(): void {
    if (this.playing) {
      this.reportProgressNow(false);
    }
  }

  private reportProgressNow(paused: boolean): void {
    const prov = this.provider;
    const item = this.item;
    const info = this.info;
    if (!this.started || prov === undefined || item === undefined || info === undefined) {
      return;
    }
    prov.reportProgress(item, info, this.ctl.positionMs, paused).catch((e: Error) => {
      console.warn(`[Player] reportProgress failed: ${e.message}`);
    });
  }

  private reportStoppedNow(): void {
    const prov = this.provider;
    const item = this.item;
    const info = this.info;
    if (!this.started || prov === undefined || item === undefined || info === undefined) {
      return;
    }
    this.started = false;
    let pos = this.ctl.positionMs;
    if (this.ctl.state === 'completed' && this.durationMs > 0) {
      pos = this.durationMs;
    }
    item.state.positionMs = pos;
    prov.reportStopped(item, info, pos).catch((e: Error) => {
      console.warn(`[Player] reportStopped failed: ${e.message}`);
    });
  }

  // ---------- actions ----------

  private toggle(): void {
    if (this.errorMsg.length > 0) {
      return;
    }
    this.ctl.toggle();
    this.revealControls();
  }

  private seekTo(ms: number): void {
    const d = this.durationMs;
    const target = d > 0 ? clamp(ms, 0, Math.max(0, d - 1000)) : Math.max(0, ms);
    this.positionMs = target;
    this.lastTimeMs = target;
    this.lastTimeAt = Date.now();
    this.subtitleText = '';
    this.ctl.seek(target);
    if (target < d - NEXT_WINDOW_MS - 1000) {
      this.nextCancelled = false;
    }
    this.reportProgressNow(!this.playing);
  }

  private seekRel(delta: number): void {
    this.seekTo(this.ctl.positionMs + delta);
    this.showHint((delta > 0 ? '快进 ' : '快退 ') + Math.abs(delta / 1000) + ' 秒');
  }

  private retry(): void {
    const pos = this.ctl.positionMs > 0 ? this.ctl.positionMs : this.req.startMs;
    this.errorMsg = '';
    if (this.item === undefined) {
      this.loadItem(this.params.itemId, this.params.startMs);
      return;
    }
    // new getPlayback = new play session: close the old one so reportStart fires again
    this.stopSessionForSwitch(pos);
    this.fetchAndOpen(pos, this.loadToken);
  }

  private retryTranscode(): void {
    const pos = this.ctl.positionMs > 0 ? this.ctl.positionMs : this.req.startMs;
    if (this.fbTried.indexOf('transcode') < 0) {
      this.fbTried.push('transcode');
    }
    this.stopSessionForSwitch(pos);
    this.req.forceMode = 'transcode';
    this.req.maxBitrate = TRANSCODE_BITRATE;
    this.qualityKey = 'br:' + TRANSCODE_BITRATE;
    this.errorMsg = '';
    this.toast('正在请求服务器转码…');
    this.fetchAndOpen(pos, this.loadToken);
  }

  private showResumeBanner(ms: number): void {
    this.resumeBannerMs = ms;
    clearTimeout(this.bannerTimer);
    this.bannerTimer = setTimeout(() => {
      this.resumeBannerMs = 0;
    }, 6000);
  }

  private restartFromBeginning(): void {
    this.resumeBannerMs = 0;
    clearTimeout(this.bannerTimer);
    this.seekTo(0);
  }

  private skipIntro(): void {
    this.showSkipIntro = false;
    this.seekTo(this.settings.skipIntroMs);
    this.showHint('已跳过片头');
  }

  private showHint(text: string): void {
    this.gestureHint = text;
    clearTimeout(this.hintTimer);
    this.hintTimer = setTimeout(() => {
      this.gestureHint = '';
    }, 1200);
  }

  private revealControls(): void {
    this.showControls = true;
    this.scheduleHide();
  }

  private scheduleHide(): void {
    clearTimeout(this.hideTimer);
    this.hideTimer = setTimeout(() => {
      if (this.playing && this.sheet.length === 0 && this.scrubMs < 0) {
        this.showControls = false;
      }
    }, HIDE_DELAY_MS);
  }

  private onTap(): void {
    if (this.sheet.length > 0) {
      this.sheet = '';
      return;
    }
    if (this.showControls) {
      this.showControls = false;
      clearTimeout(this.hideTimer);
    } else {
      this.revealControls();
    }
  }

  // ---------- window ----------

  private async setupWindow(): Promise<void> {
    try {
      const w = await window.getLastWindow(AppContext.get());
      if (this.disposed) {
        // Page left before the window resolved: never touch the shared main window.
        return;
      }
      this.win = w;
      try {
        this.prevOrientation = w.getPreferredOrientation();
      } catch (e) {
        this.prevOrientation = window.Orientation.UNSPECIFIED;
      }
      try {
        const b = w.getWindowProperties().brightness;
        this.curBrightness = b >= 0 && b <= 1 ? b : 0.5;
      } catch (e) {
        this.curBrightness = 0.5;
      }
      await this.applyFullscreen(w);
      if (this.disposed) {
        // Page left while fullscreen was being applied: undo it.
        this.restoreWindow();
      }
    } catch (e) {
      console.warn(`[Player] window setup failed: ${(e as BusinessError).message}`);
    }
  }

  private async applyFullscreen(w: window.Window): Promise<void> {
    try {
      await w.setPreferredOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE);
    } catch (e) {
      console.warn(`[Player] orientation failed: ${(e as BusinessError).message}`);
    }
    try {
      w.setImmersiveModeEnabledState(true);
    } catch (e) {
      console.warn(`[Player] immersive failed: ${(e as BusinessError).message}`);
    }
    try {
      await w.setSpecificSystemBarEnabled('status', false);
      await w.setSpecificSystemBarEnabled('navigationIndicator', false);
    } catch (e) {
      console.warn(`[Player] system bar hide failed: ${(e as BusinessError).message}`);
    }
    try {
      await w.setWindowKeepScreenOn(true);
    } catch (e) {
      console.warn(`[Player] keepScreenOn failed: ${(e as BusinessError).message}`);
    }
  }

  private restoreWindow(): void {
    const w = this.win;
    if (w === undefined) {
      return;
    }
    w.setPreferredOrientation(this.prevOrientation).catch((e: BusinessError) => {
      console.warn(`[Player] restore orientation failed: ${e.message}`);
    });
    try {
      w.setImmersiveModeEnabledState(false);
    } catch (e) {
      console.warn('[Player] restore immersive failed');
    }
    w.setSpecificSystemBarEnabled('status', true).catch((e: BusinessError) => {});
    w.setSpecificSystemBarEnabled('navigationIndicator', true).catch((e: BusinessError) => {});
    w.setWindowKeepScreenOn(false).catch((e: BusinessError) => {});
    w.setWindowBrightness(-1).catch((e: BusinessError) => {});
  }

  // ---------- volume ----------

  private initVolume(): void {
    try {
      const vm = audio.getAudioManager().getVolumeManager();
      this.maxVolume = vm.getMaxVolumeByStream(audio.StreamUsage.STREAM_USAGE_MOVIE);
      this.minVolume = vm.getMinVolumeByStream(audio.StreamUsage.STREAM_USAGE_MOVIE);
      this.volumeLevel = vm.getVolumeByStream(audio.StreamUsage.STREAM_USAGE_MOVIE);
    } catch (e) {
      console.warn(`[Player] volume query failed: ${(e as BusinessError).message}`);
      this.maxVolume = 15;
      this.minVolume = 0;
    }
  }

  // ---------- gestures ----------

  private onPanStart(ev: GestureEvent): void {
    if (this.locked || this.errorMsg.length > 0) {
      return;
    }
    this.panAxis = '';
    const x = ev.fingerList.length > 0 ? ev.fingerList[0].localX : this.areaW / 2;
    this.panLeftSide = x < this.areaW / 2;
  }

  private onPanUpdate(ev: GestureEvent): void {
    if (this.locked || this.errorMsg.length > 0 || this.areaW <= 0) {
      return;
    }
    if (this.panAxis === '') {
      if (Math.abs(ev.offsetX) < 12 && Math.abs(ev.offsetY) < 12) {
        return;
      }
      this.panAxis = Math.abs(ev.offsetX) >= Math.abs(ev.offsetY) ? 'h' : (this.panLeftSide ? 'b' : 'v');
      if (this.panAxis === 'h') {
        this.panStartValue = this.ctl.positionMs;
      } else if (this.panAxis === 'b') {
        this.panStartValue = this.curBrightness;
      } else {
        this.panStartValue = this.volumeLevel;
        this.showVolumePanel = true;
      }
    }
    if (this.panAxis === 'h') {
      const range = swipeSeekRange(this.durationMs);
      const target = clamp(this.panStartValue + ev.offsetX / this.areaW * range, 0,
        this.durationMs > 0 ? this.durationMs : this.panStartValue + range);
      this.scrubMs = target;
      const delta = Math.round((target - this.panStartValue) / 1000);
      this.gestureHint = `${formatDuration(target)} / ${formatDuration(this.durationMs)}  (${delta >= 0 ? '+' : ''}${delta}秒)`;
    } else if (this.panAxis === 'b') {
      const v = clamp(this.panStartValue - ev.offsetY / (this.areaH * 0.8), 0.01, 1);
      this.curBrightness = v;
      this.gestureHint = `亮度 ${Math.round(v * 100)}%`;
      const w = this.win;
      if (w !== undefined) {
        w.setWindowBrightness(v).catch((e: BusinessError) => {});
      }
    } else {
      const span = this.maxVolume - this.minVolume;
      const v = Math.round(clamp(this.panStartValue - ev.offsetY / (this.areaH * 0.8) * span,
        this.minVolume, this.maxVolume));
      this.volumeLevel = v;
      this.gestureHint = `音量 ${span > 0 ? Math.round((v - this.minVolume) / span * 100) : 0}%`;
    }
  }

  private onPanEnd(): void {
    if (this.panAxis === 'h' && this.scrubMs >= 0) {
      const t = this.scrubMs;
      this.scrubMs = -1;
      this.seekTo(t);
    }
    this.panAxis = '';
    clearTimeout(this.hintTimer);
    this.hintTimer = setTimeout(() => {
      this.gestureHint = '';
      this.showVolumePanel = false;
    }, 800);
  }

  private onLongPressStart(): void {
    if (this.locked || !this.playing || this.tempSpeed) {
      return;
    }
    this.tempSpeed = true;
    this.savedSpeed = this.speed;
    this.ctl.setSpeed(2);
    this.gestureHint = '2x 倍速播放中';
  }

  private onLongPressEnd(): void {
    if (!this.tempSpeed) {
      return;
    }
    this.tempSpeed = false;
    this.ctl.setSpeed(this.savedSpeed);
    this.gestureHint = '';
  }

  private onScrub(ms: number, active: boolean): void {
    if (active) {
      this.scrubMs = ms;
      this.gestureHint = `${formatDuration(ms)} / ${formatDuration(this.durationMs)}`;
    } else {
      this.scrubMs = -1;
      this.gestureHint = '';
    }
  }

  // ---------- menus ----------

  private openSheet(key: string): void {
    if (key === 'toggle') {
      this.toggle();
      return;
    }
    if (key === 'next') {
      this.playNext();
      return;
    }
    if (key === 'info') {
      this.toggleInfo();
      return;
    }
    this.sheet = key;
    this.showControls = false;
    clearTimeout(this.hideTimer);
    if (key === 'episodes' && this.episodes.length === 0 && this.item !== undefined) {
      this.sheetLoading = true;
      this.loadEpisodes(this.item).finally(() => {
        this.sheetLoading = false;
      });
    }
  }

  // ---------- 播放信息 panel ----------

  private toggleInfo(): void {
    this.sheet = '';
    this.showInfo = !this.showInfo;
    clearInterval(this.infoTimer);
    this.infoTimer = -1;
    if (this.showInfo) {
      this.refreshInfo();
      this.infoTimer = setInterval(() => this.refreshInfo(), 1000);
    }
  }

  private probeMimes(): CodecMime[] {
    const cached = this.codecMimes;
    if (cached !== undefined) {
      return cached;
    }
    const list: CodecMime[] = [];
    try {
      CodecCaps.entries().forEach((e: CodecEntry) => list.push(new CodecMime(e.codec, e.mime)));
    } catch (err) {
      console.warn(`[Player] CodecCaps.load failed: ${(err as Error).message}`);
    }
    if (list.length > 0) {
      this.codecMimes = list;
    }
    return list;
  }

  private decoderStat(codec: string): DecoderStat {
    const d = new DecoderStat();
    d.codec = codec;
    if (codec.length === 0) {
      return d;
    }
    try {
      const dec: DecoderInfo | undefined = CodecCaps.decoderFor(codec);
      if (dec !== undefined) {
        d.known = true;
        d.hw = dec.hw;
        d.name = dec.name;
      }
    } catch (err) {
      console.warn(`[Player] CodecCaps.decoderFor failed: ${(err as Error).message}`);
    }
    return d;
  }

  private async refreshInfo(): Promise<void> {
    if (this.infoBusy || !this.showInfo) {
      return;
    }
    this.infoBusy = true;
    try {
      const tracks: EmbeddedTrack[] = await this.ctl.trackList();
      const selected: number[] = await this.ctl.selectedTracks();
      const net: NetStats = await this.ctl.netStats();
      if (!this.showInfo || this.disposed) {
        return;
      }
      this.infoRows = buildInfoRows(this.statsInput(tracks, selected, net));
    } finally {
      this.infoBusy = false;
    }
  }

  private statsInput(tracks: EmbeddedTrack[], selected: number[], net: NetStats): StatsInput {
    const s = new StatsInput();
    const info = this.info;
    const mimes = this.probeMimes();
    let vMime = '';
    let aMime = '';
    const sel: TrackStat[] = [];
    const audios = tracks.filter((t: EmbeddedTrack) => t.type === 0);
    let curAudio = audios.find((t: EmbeddedTrack) => selected.indexOf(t.index) >= 0);
    if (curAudio === undefined && audios.length > 0) {
      curAudio = audios[0];
    }
    const curAudioIdx = curAudio !== undefined ? curAudio.index : -1;
    for (let i = 0; i < tracks.length; i++) {
      const t = tracks[i];
      if (t.type !== 1 && !(t.type === 0 && t.index === curAudioIdx)) {
        continue;
      }
      const ts = new TrackStat();
      ts.type = t.type;
      ts.mime = t.codec;
      ts.width = t.width;
      ts.height = t.height;
      ts.frameRate = t.frameRate;
      ts.hdrType = t.hdrType;
      ts.bitrate = t.bitrate;
      ts.channels = t.channels;
      ts.sampleRate = t.sampleRate;
      ts.language = t.language;
      if (t.type === 1) {
        if (vMime.length === 0) {
          vMime = t.codec;
        }
        sel.push(ts);
      } else {
        aMime = t.codec;
        sel.push(ts);
      }
    }
    s.tracks = sel;
    if (info !== undefined) {
      s.deliveryMode = this.effectiveMode();
      const qi = this.playingQuality();
      if (this.isFlicx) {
        s.modeNote = 'Flicx · ' + this.flicxLineLabel(info, qi);
      } else if (qi >= 0) {
        s.modeNote = s.deliveryMode === 'transcode' ? '夸克云端 ' + info.qualities[qi].label : '夸克原画';
      }
      s.transcodeReasons = info.transcodeReasons;
      s.container = info.container;
      s.videoCodec = info.videoCodec;
      s.audioCodec = info.audioCodec;
      s.videoWidth = info.videoWidth;
      s.videoHeight = info.videoHeight;
      s.videoRange = info.videoRange;
      s.bitrate = info.bitrate;
    }
    // the decoder sees the delivered stream: prefer the track mime, fall back to the server's source codec
    let vc = mimeToCodec(vMime, mimes);
    if (vc.length === 0 && s.deliveryMode !== 'transcode') {
      vc = normCodec(s.videoCodec);
    }
    let ac = mimeToCodec(aMime, mimes);
    if (ac.length === 0 && s.deliveryMode !== 'transcode') {
      ac = normCodec(s.audioCodec);
    }
    s.videoDecoder = this.decoderStat(vc);
    s.audioDecoder = this.decoderStat(ac);
    s.superRes = this.srStatus;
    s.renderW = this.videoW;
    s.renderH = this.videoH;
    s.downloadRate = net.downloadRate;
    s.avgDownloadRate = net.avgDownloadRate;
    s.bufferSec = net.bufferSec;
    s.downloading = net.downloading;
    s.serverIp = net.serverIp;
    return s;
  }

  private sheetTitle(): string {
    switch (this.sheet) {
      case 'speed': return '播放速度';
      case 'quality': return this.isFlicx ? '播放线路' : '画质';
      case 'audio': return '音轨';
      case 'subtitle': return '字幕';
      case 'aspect': return '画面比例';
      case 'episodes': return '选集';
      case 'more': return '更多';
      default: return '';
    }
  }

  private flicxLineLabel(info: PlaybackInfo, index: number): string {
    if (index < 0) {
      return '默认线路';
    }
    const label = info.qualities[index].label.trim();
    return label.length > 0 ? label : '线路 ' + (index + 1);
  }

  private qualityItems(): SheetItem[] {
    const out: SheetItem[] = [];
    const info = this.info;
    if (this.isFlicx && info === undefined) {
      return out;
    }
    if (info !== undefined && (this.isFlicx || info.qualities.length > 0)) {
      if (!this.isFlicx || !info.qualities.some((q: QualityOption) => q.url === info.url)) {
        out.push(new SheetItem('q:-1', this.isFlicx ? '默认线路' : '默认', '',
          this.qualityKey === '' || this.qualityKey === 'q:-1'));
      }
      for (let i = 0; i < info.qualities.length; i++) {
        const label = this.isFlicx ? this.flicxLineLabel(info, i) : info.qualities[i].label;
        out.push(new SheetItem('q:' + i, label, '', this.qualityKey === 'q:' + i));
      }
      return out;
    }
    const opts: BitrateOption[] = bitrateOptions();
    const cur = this.req.maxBitrate;
    for (let i = 0; i < opts.length; i++) {
      out.push(new SheetItem('br:' + opts[i].bitrate, opts[i].label,
        opts[i].bitrate === 0 ? '直接播放，不转码' : '服务器转码', opts[i].bitrate === cur));
    }
    return out;
  }

  private audioItems(): SheetItem[] {
    const out: SheetItem[] = [];
    const info = this.info;
    if (this.embeddedAudio.length > 1) {
      for (let i = 0; i < this.embeddedAudio.length; i++) {
        const t = this.embeddedAudio[i];
        const label = t.name.length > 0 ? t.name : (t.language.length > 0 ? t.language : `音轨 ${i + 1}`);
        const sub = [t.language, t.codec, t.channels > 0 ? t.channels + '声道' : '']
          .filter((s: string) => s.length > 0).join(' · ');
        out.push(new SheetItem('emb:' + t.index, label, sub, this.audioKey === 'emb:' + t.index));
      }
    } else if (info !== undefined) {
      for (let i = 0; i < info.audioTracks.length; i++) {
        const a = info.audioTracks[i];
        const label = a.title.length > 0 ? a.title : (a.language.length > 0 ? a.language : `音轨 ${i + 1}`);
        const sub = [a.language, a.codec, a.channels > 0 ? a.channels + '声道' : '']
          .filter((s: string) => s.length > 0).join(' · ');
        const sel = this.audioKey === 'srv:' + a.index || (this.audioKey === '' && a.isDefault);
        out.push(new SheetItem('srv:' + a.index, label, sub, sel));
      }
    }
    return out;
  }

  private subtitleItems(): SheetItem[] {
    const out: SheetItem[] = [new SheetItem('off', '关闭字幕', '', this.subKey === 'off')];
    const info = this.info;
    if (info !== undefined) {
      for (let i = 0; i < info.subtitles.length; i++) {
        const s = info.subtitles[i];
        if (!s.isExternal || s.url.length === 0) {
          continue;
        }
        const label = s.title.length > 0 ? s.title : (s.language.length > 0 ? s.language : `外挂字幕 ${i + 1}`);
        const sel = this.subKey === 'ext:' + s.index || this.subKey === 'url:' + s.index;
        out.push(new SheetItem('ext:' + s.index, label, ['外挂', s.language, s.codec]
          .filter((x: string) => x.length > 0).join(' · '), sel));
      }
    }
    for (let i = 0; i < this.embeddedSubs.length; i++) {
      const t = this.embeddedSubs[i];
      const label = t.name.length > 0 ? t.name : (t.language.length > 0 ? t.language : `内嵌字幕 ${i + 1}`);
      out.push(new SheetItem('emb:' + t.index, label, ['内嵌', t.language].filter((x: string) => x.length > 0)
        .join(' · '), this.subKey === 'emb:' + t.index));
    }
    // server-side (burn-in when transcoding) for embedded streams the player could not expose
    if (this.embeddedSubs.length === 0 && info !== undefined) {
      for (let i = 0; i < info.subtitles.length; i++) {
        const s = info.subtitles[i];
        if (s.isExternal && s.url.length > 0) {
          continue;
        }
        const label = s.title.length > 0 ? s.title : (s.language.length > 0 ? s.language : `字幕 ${i + 1}`);
        out.push(new SheetItem('srv:' + s.index, label, '内嵌 · 服务器处理', this.subKey === 'srv:' + s.index));
      }
    }
    return out;
  }

  private subtitleSteppers(): SheetStepper[] {
    const d = this.subDelayMs / 1000;
    return [
      new SheetStepper('delay', '字幕延迟', (d > 0 ? '+' : '') + d.toFixed(1) + 's'),
      new SheetStepper('size', '字幕大小', Math.round(this.subScale * 100) + '%')
    ];
  }

  private episodeItems(): SheetItem[] {
    const out: SheetItem[] = [];
    const prov = this.provider;
    const cur = this.item !== undefined ? this.item.id : '';
    for (let i = 0; i < this.episodes.length; i++) {
      const e = this.episodes[i];
      const num = e.episodeNumber >= 0 ? `第 ${e.episodeNumber} 集` : `第 ${i + 1} 集`;
      const it = new SheetItem('ep:' + e.id, e.title.length > 0 ? `${num}  ${e.title}` : num,
        e.runtimeMs > 0 ? formatDuration(e.runtimeMs) + (e.state.played ? ' · 已看' : '') : (e.state.played ? '已看' : ''),
        e.id === cur);
      if (prov !== undefined) {
        try {
          it.image = prov.imageUrl(e, 'thumb', 320);
        } catch (err) {
          it.image = '';
        }
      }
      out.push(it);
    }
    return out;
  }

  private sheetItems(): SheetItem[] {
    switch (this.sheet) {
      case 'speed':
        return SPEEDS.map((s: number) => new SheetItem('sp:' + s, speedLabel(s), '', s === this.speed));
      case 'quality': return this.qualityItems();
      case 'audio': return this.audioItems();
      case 'subtitle': return this.subtitleItems();
      case 'aspect':
        return ASPECT_MODES.map((m: string) => new SheetItem('as:' + m, aspectLabel(m), '', m === this.aspect));
      case 'episodes': return this.episodeItems();
      case 'more':
        return [new SheetItem('more:info', '播放信息', '解码方式、编码、码率、缓冲', this.showInfo)];
      default: return [];
    }
  }

  private currentPos(): number {
    return this.ctl.positionMs > 0 ? this.ctl.positionMs : this.positionMs;
  }

  private async onSheetPick(key: string): Promise<void> {
    const colon = key.indexOf(':');
    const kind = colon >= 0 ? key.substring(0, colon) : key;
    const val = colon >= 0 ? key.substring(colon + 1) : '';
    const sheet = this.sheet;
    if (sheet !== 'subtitle') {
      this.sheet = '';
    }
    if (sheet === 'speed' && kind === 'sp') {
      this.speed = Number(val);
      this.ctl.setSpeed(this.speed);
      this.showHint('播放速度 ' + speedLabel(this.speed));
    } else if (sheet === 'aspect' && kind === 'as') {
      this.aspect = val;
      this.showHint('画面 ' + aspectLabel(val));
    } else if (sheet === 'episodes' && kind === 'ep') {
      if (this.item === undefined || this.item.id !== val) {
        await this.switchTo(val);
      }
    } else if (sheet === 'quality') {
      await this.pickQuality(kind, val);
    } else if (sheet === 'audio') {
      await this.pickAudio(kind, val);
    } else if (sheet === 'subtitle') {
      await this.pickSubtitle(kind, val);
    } else if (sheet === 'more' && kind === 'more' && val === 'info') {
      this.toggleInfo();
    }
  }

  private async pickQuality(kind: string, val: string): Promise<void> {
    const pos = this.currentPos();
    const info = this.info;
    if (kind === 'q' && info !== undefined) {
      const i = Number(val);
      if (this.isFlicx) {
        if (!Number.isInteger(i) || i < -1 || i >= info.qualities.length ||
          (i === this.curQuality && this.errorMsg.length === 0)) {
          return;
        }
        this.errorMsg = '';
        this.loading = true;
        this.captureSelection(false);
      }
      this.qualityKey = 'q:' + i;
      this.showHint(this.isFlicx ? '正在切换线路…' : '正在切换画质…');
      if (i < 0) {
        this.curQuality = info.qualities.findIndex((x: QualityOption) => x.url === info.url);
        this.openUrl(info.url, info.headers, pos);
      } else if (i < info.qualities.length) {
        this.curQuality = i;
        const q = info.qualities[i];
        this.openUrl(q.url, Object.keys(q.headers).length > 0 ? q.headers : info.headers, pos);
      }
      if (this.isFlicx && this.restoreSubKey.length > 0) {
        this.restoreSubtitle(info);
        this.restoreSubKey = '';
      }
      return;
    }
    if (kind === 'br' && !this.isFlicx) {
      const br = Number(val);
      if (br === this.req.maxBitrate) {
        return;
      }
      this.req.maxBitrate = br;
      if (br === 0) {
        // explicit 原画 choice: let the profile decide again instead of a forced remux / transcode
        this.req.forceMode = '';
      }
      this.qualityKey = 'br:' + br;
      this.showHint('正在切换画质…');
      this.reportStoppedNow();
      await this.fetchAndOpen(pos, this.loadToken);
    }
  }

  private async pickAudio(kind: string, val: string): Promise<void> {
    const idx = Number(val);
    if (kind === 'emb') {
      this.audioKey = key2('emb', idx);
      await this.ctl.selectTrack(idx);
      this.showHint('已切换音轨');
    } else if (kind === 'srv') {
      if (this.audioKey === key2('srv', idx)) {
        return;
      }
      this.audioKey = key2('srv', idx);
      this.req.audioIndex = idx;
      this.reportStoppedNow();
      await this.fetchAndOpen(this.currentPos(), this.loadToken);
    }
  }

  private async pickSubtitle(kind: string, val: string): Promise<void> {
    const info = this.info;
    if (kind === 'off') {
      await this.subtitleOff();
      if (this.req.subtitleIndex >= 0 && info !== undefined && !this.isExternalIndex(this.req.subtitleIndex)) {
        // burned-in subtitle needs a new stream without it
        this.req.subtitleIndex = -1;
        this.reportStoppedNow();
        await this.fetchAndOpen(this.currentPos(), this.loadToken);
      }
      return;
    }
    const idx = Number(val);
    if (kind === 'ext' && info !== undefined) {
      const t = info.subtitles.find((s: SubtitleTrack) => s.index === idx && s.isExternal);
      if (t !== undefined) {
        await this.useExternalSubtitle(t);
      }
    } else if (kind === 'emb') {
      this.externalSubActive = false;
      this.cues = [];
      this.subtitleText = '';
      await this.disableEmbeddedSubs();
      this.subKey = key2('emb', idx);
      await this.ctl.selectTrack(idx);
    } else if (kind === 'srv') {
      this.externalSubActive = false;
      this.cues = [];
      this.subtitleText = '';
      this.subKey = key2('srv', idx);
      this.req.subtitleIndex = idx;
      this.reportStoppedNow();
      await this.fetchAndOpen(this.currentPos(), this.loadToken);
    }
  }

  private isExternalIndex(idx: number): boolean {
    const info = this.info;
    if (info === undefined) {
      return false;
    }
    const t = info.subtitles.find((s: SubtitleTrack) => s.index === idx);
    return t !== undefined && t.isExternal;
  }

  private onSheetStep(key: string, delta: number): void {
    if (key === 'delay') {
      this.subDelayMs = clamp(this.subDelayMs + delta * 500, -60000, 60000);
      this.syncSubtitle();
    } else if (key === 'size') {
      this.subScale = clamp(Math.round((this.subScale + delta * 0.1) * 10) / 10, 0.5, 2.5);
      const s = Settings.copy(this.settings);
      s.subtitleScale = this.subScale;
      this.settings = s;
      Settings.save(s).catch((e: Error) => {
        console.warn(`[Player] save subtitleScale failed: ${e.message}`);
      });
    }
  }

  // ---------- layout ----------

  private videoBox(): VideoBox {
    return computeVideoBox(this.aspect, this.areaW, this.areaH, this.videoW, this.videoH);
  }

  @Builder
  centerHint() {
    if (this.gestureHint.length > 0) {
      Text(this.gestureHint)
        .fontSize(18)
        .fontColor(Color.White)
        .padding({ left: 20, right: 20, top: 10, bottom: 10 })
        .borderRadius(8)
        .backgroundColor('#99000000')
    }
  }

  private hasOtherFlicxLine(): boolean {
    const info = this.info;
    return this.isFlicx && info !== undefined &&
      (info.url !== this.curUrl || info.qualities.some((q: QualityOption) => q.url !== this.curUrl));
  }

  private flicxWatchPage(): string {
    return this.isFlicx && this.item !== undefined ? FlicxMapper.watchPage(this.item.id) : '';
  }

  private openFlicxPage(): void {
    const url = this.flicxWatchPage();
    if (url.length === 0) {
      return;
    }
    try {
      AppContext.get().openLink(url, { appLinkingOnly: false }).catch((e: BusinessError) => {
        console.error(`[Player] openLink: ${e.code} ${e.message}`);
        this.showHint('无法打开浏览器');
      });
    } catch (e) {
      this.showHint('无法打开浏览器');
    }
  }

  @Builder
  errorView() {
    Column({ space: 16 }) {
      Text('播放出错').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White)
      Text(this.errorMsg)
        .fontSize(14)
        .fontColor(Theme.text2)
        .textAlign(TextAlign.Center)
        .maxLines(4)
        .constraintSize({ maxWidth: 520 })
      Row({ space: 16 }) {
        Button('重试')
          .backgroundColor(Theme.accent)
          .fontColor(Color.White)
          .onClick(() => this.retry())
        if (this.hasOtherFlicxLine()) {
          Button('切换线路')
            .backgroundColor(Theme.surface2)
            .fontColor(Color.White)
            .onClick(() => this.openSheet('quality'))
        } else if (!this.isFlicx && this.info !== undefined && this.effectiveMode() !== 'transcode') {
          Button('尝试转码播放')
            .backgroundColor(Theme.surface2)
            .fontColor(Color.White)
            .onClick(() => this.retryTranscode())
        }
        if (this.flicxWatchPage().length > 0) {
          Button('网页播放')
            .backgroundColor(Theme.surface2)
            .fontColor(Color.White)
            .onClick(() => this.openFlicxPage())
        }
        Button('返回')
          .backgroundColor(Theme.surface2)
          .fontColor(Color.White)
          .onClick(() => router.back())
      }
    }
    .padding(24)
    .borderRadius(Theme.radius)
    .backgroundColor('#CC000000')
  }

  build() {
    Stack() {
      // video surface, sized from videoSizeChange + aspect mode
      Stack() {
        XComponent({ type: XComponentType.SURFACE, controller: this.xc })
          .onLoad(() => {
            const id = this.xc.getXComponentSurfaceId();
            this.ctl.setSurface(id);
            this.surfaceReady = true;
            const p = this.pendingOpen;
            this.pendingOpen = undefined;
            if (p !== undefined) {
              this.ctl.open(p);
            }
          })
          .width(this.videoBox().width > 0 ? this.videoBox().width : '100%')
          .height(this.videoBox().height > 0 ? this.videoBox().height : '100%')
          .onAreaChange((oldV: Area, newV: Area) => {
            // on-screen surface size in px for setVideoWindowSize (super resolution); follows rotation / aspect
            const ui = this.getUIContext();
            this.ctl.setDisplaySize(ui.vp2px(Number(newV.width)), ui.vp2px(Number(newV.height)));
          })
      }
      .width('100%')
      .height('100%')
      .clip(true)
      .backgroundColor(Color.Black)
      .onAreaChange((oldV: Area, newV: Area) => {
        this.areaW = Number(newV.width);
        this.areaH = Number(newV.height);
      })

      // subtitles
      if (this.subtitleText.length > 0) {
        Column() {
          Blank().layoutWeight(1)
          Text(this.subtitleText)
            .fontSize(Math.round(22 * this.subScale))
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .textShadow({ radius: 4, color: Color.Black, offsetX: 1, offsetY: 1 })
            .padding({ left: 12, right: 12, top: 2, bottom: 2 })
            .backgroundColor('#33000000')
            .borderRadius(4)
            .constraintSize({ maxWidth: '86%' })
        }
        .width('100%')
        .height('100%')
        .padding({ bottom: this.showControls && !this.locked ? 120 : 36 })
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // gesture layer: wraps controls so child buttons win over these gestures
      Stack() {
      // controls
      PlayerOverlay({
        title: this.title,
        subtitle: this.subTitle,
        playing: this.playing,
        positionMs: this.scrubMs >= 0 ? this.scrubMs : this.positionMs,
        durationMs: this.durationMs,
        bufferedMs: this.bufferedMs,
        locked: this.locked,
        showControls: this.showControls && this.errorMsg.length === 0,
        speedText: this.speed === 1 ? '倍速' : speedLabel(this.speed),
        qualityText: this.isFlicx ? '线路' : (this.req.maxBitrate > 0 ? '转码' : '画质'),
        aspectText: aspectLabel(this.aspect),
        hasEpisodes: this.item !== undefined && this.item.type === 'episode',
        hasNext: this.hasNext,
        hasPrev: this.hasPrev,
        hasAudio: this.embeddedAudio.length > 1 || (this.info !== undefined && this.info.audioTracks.length > 1),
        hasSubtitle: true,
        onBack: () => router.back(),
        onToggle: () => this.toggle(),
        onSeekRel: (d: number) => this.seekRel(d),
        onSeekTo: (ms: number) => this.seekTo(ms),
        onScrubbing: (ms: number, a: boolean) => this.onScrub(ms, a),
        onLock: () => {
          this.locked = !this.locked;
          this.showHint(this.locked ? '已锁定' : '已解锁');
          this.revealControls();
        },
        onMenu: (k: string) => this.openSheet(k),
        onNext: () => this.playNext(),
        onPrev: () => this.playPrev(),
        onInteract: () => this.scheduleHide()
      })
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)

      // loading / buffering
      if ((this.loading || this.buffering) && this.errorMsg.length === 0) {
        Column({ space: 12 }) {
          LoadingProgress().width(56).height(56).color(Color.White)
          Text(this.loading ? this.loadingText : '缓冲中…').fontSize(14).fontColor(Theme.text2)
        }
        .hitTestBehavior(HitTestMode.Transparent)
      }

      this.centerHint()

      // resume banner
      if (this.resumeBannerMs > 0 && this.errorMsg.length === 0) {
        Column() {
          Blank().layoutWeight(1)
          Row({ space: 12 }) {
            Text(`从 ${formatDuration(this.resumeBannerMs)} 继续播放`).fontSize(14).fontColor(Color.White)
            Text('从头播放')
              .fontSize(14)
              .fontColor(Theme.accent)
              .fontWeight(FontWeight.Bold)
              .onClick(() => this.restartFromBeginning())
          }
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .borderRadius(20)
          .backgroundColor('#CC000000')
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 24, bottom: 130 })
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // skip intro / next countdown (bottom-right)
      if ((this.showSkipIntro || this.countdown > 0) && this.errorMsg.length === 0 && !this.locked) {
        Column() {
          Blank().layoutWeight(1)
          if (this.showSkipIntro) {
            Text('跳过片头')
              .fontSize(15)
              .fontColor(Color.White)
              .padding({ left: 18, right: 18, top: 10, bottom: 10 })
              .borderRadius(20)
              .border({ width: 1, color: '#80FFFFFF' })
              .backgroundColor('#99000000')
              .onClick(() => this.skipIntro())
          }
          if (this.countdown > 0) {
            Row({ space: 12 }) {
              Text(`即将播放下一集 ${this.countdown}`).fontSize(14).fontColor(Color.White)
              Text('立即播放')
                .fontSize(14)
                .fontColor(Theme.accent)
                .fontWeight(FontWeight.Bold)
                .onClick(() => this.playNext())
              Text('取消')
                .fontSize(14)
                .fontColor(Theme.text2)
                .onClick(() => {
                  this.nextCancelled = true;
                  this.countdown = -1;
                })
            }
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .borderRadius(20)
            .backgroundColor('#CC000000')
          }
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.End)
        .padding({ right: 24, bottom: 130 })
        .hitTestBehavior(HitTestMode.Transparent)
      }

      }
      .width('100%')
      .height('100%')
      .gesture(
          GestureGroup(GestureMode.Exclusive,
            TapGesture({ count: 2 }).onAction(() => {
              if (!this.locked) {
                this.toggle();
                this.showHint(this.playing ? '暂停' : '播放');
              }
            }),
            TapGesture({ count: 1 }).onAction(() => this.onTap()),
            LongPressGesture({ repeat: false, duration: 500 })
              .onAction(() => this.onLongPressStart())
              .onActionEnd(() => this.onLongPressEnd())
              .onActionCancel(() => this.onLongPressEnd()),
            PanGesture({ fingers: 1, direction: PanDirection.All, distance: 8 })
              .onActionStart((ev: GestureEvent) => this.onPanStart(ev))
              .onActionUpdate((ev: GestureEvent) => this.onPanUpdate(ev))
              .onActionEnd(() => this.onPanEnd())
              .onActionCancel(() => this.onPanEnd())
          )
        )

      // system volume panel (shown during right-side swipe)
      if (this.showVolumePanel) {
        Column() {
          AVVolumePanel({ volumeLevel: this.volumeLevel })
        }
        .width(1)
        .height(1)
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // 播放信息 (top-left)
      if (this.showInfo) {
        Column() {
          PlaybackInfoPanel({
            rows: this.infoRows,
            onClose: () => this.toggleInfo()
          })
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 24, top: this.showControls && !this.locked ? 80 : 24 })
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // automatic fallback notice (top-center)
      if (this.fallbackBanner.length > 0) {
        Column() {
          Text(this.fallbackBanner)
            .fontSize(14)
            .fontColor(Color.White)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .borderRadius(18)
            .backgroundColor('#CC000000')
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 72 })
        .hitTestBehavior(HitTestMode.Transparent)
      }

      if (this.errorMsg.length > 0) {
        this.errorView()
      }

      // side sheet
      if (this.sheet.length > 0) {
        TrackSheet({
          title: this.sheetTitle(),
          items: this.sheetItems(),
          steppers: this.sheet === 'subtitle' ? this.subtitleSteppers() : [],
          loading: this.sheetLoading,
          emptyText: this.sheet === 'episodes' ? '暂无剧集' : '暂无可选项',
          panelWidth: this.sheet === 'episodes' ? 400 : 320,
          showImages: this.sheet === 'episodes',
          onPick: (k: string) => {
            this.onSheetPick(k);
          },
          onStep: (k: string, d: number) => this.onSheetStep(k, d),
          onClose: () => {
            this.sheet = '';
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
}
