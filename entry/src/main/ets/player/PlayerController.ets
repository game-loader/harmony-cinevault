import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { wantSuperResolution, srWindowSize, VideoBox } from './PlayerLogic';

/** Track reported by AVPlayer.getTrackDescription (embedded in the container). */
export class EmbeddedTrack {
  index: number = -1;
  /** 0 audio, 1 video, 2 subtitle (media.MediaType) */
  type: number = -1;
  language: string = '';
  name: string = '';
  codec: string = '';
  channels: number = 0;
  width: number = 0;
  height: number = 0;
  /** frames per second (MD_KEY_FRAME_RATE is frames per 100 s) */
  frameRate: number = 0;
  /** raw MD_KEY_HDR_TYPE value ('' when absent) */
  hdrType: string = '';
  bitrate: number = 0;
  sampleRate: number = 0;
}

/** Snapshot of AVPlayer.getPlaybackInfo(); -1 / '' when not reported. */
export class NetStats {
  downloadRate: number = -1;     // bit/s
  avgDownloadRate: number = -1;  // bit/s
  bufferSec: number = -1;
  downloading: number = -1;      // 1 downloading, 0 done
  serverIp: string = '';
}

/** Callbacks raised by PlayerController. Assign the ones you need. */
export class PlayerCallbacks {
  onState: (state: string) => void = (s: string) => {};
  onTime: (ms: number) => void = (ms: number) => {};
  onDuration: (ms: number) => void = (ms: number) => {};
  onBuffering: (buffering: boolean) => void = (b: boolean) => {};
  onBufferPercent: (percent: number) => void = (p: number) => {};
  onCachedMs: (ms: number) => void = (ms: number) => {};
  onVideoSize: (w: number, h: number) => void = (w: number, h: number) => {};
  onSeekDone: (ms: number) => void = (ms: number) => {};
  onError: (message: string) => void = (m: string) => {};
  onTracks: (tracks: EmbeddedTrack[]) => void = (t: EmbeddedTrack[]) => {};
  onSubtitle: (text: string, startMs: number, durationMs: number) => void = (t: string, s: number, d: number) => {};
  onFirstPlay: () => void = () => {};
  onInterruptPause: () => void = () => {};
  /** First video frame rendered (startRenderFrame). */
  onFirstFrame: () => void = () => {};
  /** Super resolution status: 'off' | 'on' | 'idle' | 'unavailable' */
  onSuperRes: (status: string) => void = (s: string) => {};
  /** Non-fatal problem worth a toast (does not trigger the fallback chain). */
  onWarn: (message: string) => void = (m: string) => {};
}

export class OpenOptions {
  url: string = '';
  headers: Record<string, string> = {};
  startMs: number = 0;
  speed: number = 1;
  autoPlay: boolean = true;
  preferredAudioLang: string = '';
  preferredSubtitleLang: string = '';
  isHls: boolean = false;
  /** PlaybackStrategy.enableSuperResolution; actually switched on only for sub-1080p sources */
  superResolution: boolean = false;
  preferHdr: boolean = false;
}

function speedEnum(s: number): media.PlaybackSpeed {
  if (s <= 0.5) {
    return media.PlaybackSpeed.SPEED_FORWARD_0_50_X;
  }
  if (s <= 0.75) {
    return media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
  }
  if (s <= 1) {
    return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
  }
  if (s <= 1.25) {
    return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
  }
  if (s <= 1.5) {
    return media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
  }
  if (s <= 1.75) {
    return media.PlaybackSpeed.SPEED_FORWARD_1_75_X;
  }
  if (s <= 2) {
    return media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
  }
  return media.PlaybackSpeed.SPEED_FORWARD_3_00_X;
}

function str(v: Object | undefined): string {
  return v === undefined || v === null ? '' : String(v);
}

function num(v: Object | undefined): number {
  if (v === undefined || v === null) {
    return -1;
  }
  const n = Number(v);
  return isNaN(n) ? -1 : n;
}

export function errorText(e: BusinessError): string {
  const code = e.code;
  let hint = '';
  if (code === 5400103 || code === 5411001 || code === 5411002 || code === 5411003 || code === 5411006) {
    hint = '网络连接失败';
  } else if (code === 5411011 || code === 5411004 || code === 5411005) {
    hint = '服务器拒绝了请求';
  } else if (code === 5400106 || code === 5410003 || code === 5410004 || code === 5410005) {
    hint = '不支持的视频格式或编码';
  } else if (code === 5411007 || code === 5411008 || code === 5411009 || code === 5411010) {
    hint = '网络超时或连接中断';
  } else if (code === 5400105) {
    hint = '播放服务异常';
  }
  const msg = e.message ?? '';
  return (hint.length > 0 ? hint : '播放失败') + (code !== undefined ? ` (${code})` : '') +
    (msg.length > 0 && hint.length === 0 ? ': ' + msg : '');
}

/**
 * Wraps one media.AVPlayer instance at a time. open() creates a fresh player (the previous one is released),
 * so switching quality / episode is simply another open().
 */
export class PlayerController {
  cb: PlayerCallbacks = new PlayerCallbacks();
  state: string = 'idle';
  durationMs: number = 0;
  positionMs: number = 0;
  speed: number = 1;
  private player: media.AVPlayer | undefined = undefined;
  private surfaceId: string = '';
  private gen: number = 0;
  private pendingStart: number = 0;
  private autoPlay: boolean = true;
  private firstPlayDone: boolean = false;
  private released: boolean = false;
  /** Incremented per open() call; lets an open() that awaited releasePlayer detect it was superseded. */
  private openSeq: number = 0;
  /** Super resolution: requested in the strategy of the current player, current status, last applied window */
  private srRequested: boolean = false;
  srStatus: string = 'off';
  private srActive: boolean = false;
  private videoW: number = 0;
  private videoH: number = 0;
  private displayW: number = 0;
  private displayH: number = 0;
  private srAppliedW: number = 0;
  private srAppliedH: number = 0;
  /** 5410003 (not supported) seen once: skip super resolution for the rest of the app session */
  private static srUnsupported: boolean = false;

  setSurface(id: string): void {
    this.surfaceId = id;
  }

  hasSurface(): boolean {
    return this.surfaceId.length > 0;
  }

  isPlaying(): boolean {
    return this.state === 'playing';
  }

  canControl(): boolean {
    return this.state === 'prepared' || this.state === 'playing' || this.state === 'paused' ||
      this.state === 'completed';
  }

  async open(opt: OpenOptions): Promise<void> {
    // Reset before awaiting so a release() issued during the await stays in effect.
    this.released = false;
    const ticket = ++this.openSeq;
    await this.releasePlayer();
    if (this.released || ticket !== this.openSeq) {
      // Page closed (release()) or a newer open() superseded this one while the old player was releasing.
      return;
    }
    const myGen = ++this.gen;
    this.state = 'idle';
    this.durationMs = 0;
    this.positionMs = opt.startMs;
    this.pendingStart = opt.startMs;
    this.autoPlay = opt.autoPlay;
    this.speed = opt.speed;
    this.firstPlayDone = false;
    this.srRequested = opt.superResolution && !PlayerController.srUnsupported;
    this.srActive = false;
    this.videoW = 0;
    this.videoH = 0;
    this.srAppliedW = 0;
    this.srAppliedH = 0;
    this.setSrStatus(opt.superResolution ? (PlayerController.srUnsupported ? 'unavailable' : 'idle') : 'off');
    let p: media.AVPlayer;
    try {
      p = await media.createAVPlayer();
    } catch (e) {
      this.cb.onError(errorText(e as BusinessError));
      return;
    }
    if (myGen !== this.gen || this.released) {
      p.release();
      return;
    }
    this.player = p;
    this.bind(p, myGen);
    try {
      // setMediaSource for every network URL so the PlaybackStrategy (super resolution, HDR, first frame) applies
      if (/^https?:\/\//i.test(opt.url) || Object.keys(opt.headers).length > 0 || opt.isHls) {
        const src = media.createMediaSourceWithUrl(opt.url, opt.headers);
        if (opt.isHls) {
          src.setMimeType(media.AVMimeTypes.APPLICATION_M3U8);
        }
        const strategy: media.PlaybackStrategy = {
          preferredBufferDuration: 20,
          preferredBufferDurationForPlaying: 2,
          showFirstFrameOnPrepare: true,
          preferredHdr: opt.preferHdr
        };
        if (this.srRequested) {
          strategy.enableSuperResolution = true;
        }
        if (opt.preferredAudioLang.length > 0) {
          strategy.preferredAudioLanguage = opt.preferredAudioLang;
        }
        if (opt.preferredSubtitleLang.length > 0) {
          strategy.preferredSubtitleLanguage = opt.preferredSubtitleLang;
        }
        await p.setMediaSource(src, strategy);
      } else {
        p.url = opt.url;
      }
    } catch (e) {
      if (myGen === this.gen) {
        this.cb.onError(errorText(e as BusinessError));
      }
    }
  }

  private bind(p: media.AVPlayer, myGen: number): void {
    p.on('stateChange', async (state: media.AVPlayerState, reason: media.StateChangeReason) => {
      if (myGen !== this.gen) {
        return;
      }
      this.state = state;
      this.cb.onState(state);
      try {
        if (state === 'initialized') {
          if (this.surfaceId.length > 0) {
            p.surfaceId = this.surfaceId;
          }
          p.audioInterruptMode = audio.InterruptMode.SHARE_MODE;
          await p.prepare();
        } else if (state === 'prepared') {
          this.durationMs = p.duration > 0 ? p.duration : this.durationMs;
          this.cb.onDuration(this.durationMs);
          this.loadTracks();
          if (this.pendingStart > 0 && (this.durationMs <= 0 || this.pendingStart < this.durationMs)) {
            p.seek(this.pendingStart, media.SeekMode.SEEK_PREV_SYNC);
          }
          this.pendingStart = 0;
          if (this.speed !== 1) {
            p.setSpeed(speedEnum(this.speed));
          }
          this.applySuperResolution(p, myGen);
          if (this.autoPlay) {
            await p.play();
          }
        } else if (state === 'playing') {
          if (!this.firstPlayDone) {
            this.firstPlayDone = true;
            this.cb.onFirstPlay();
          }
        }
      } catch (e) {
        this.cb.onError(errorText(e as BusinessError));
      }
    });
    p.on('error', (err: BusinessError) => {
      if (myGen !== this.gen) {
        return;
      }
      this.cb.onError(errorText(err));
    });
    p.on('timeUpdate', (ms: number) => {
      if (myGen !== this.gen) {
        return;
      }
      this.positionMs = ms;
      this.cb.onTime(ms);
    });
    p.on('durationUpdate', (ms: number) => {
      if (myGen !== this.gen || ms <= 0) {
        return;
      }
      this.durationMs = ms;
      this.cb.onDuration(ms);
    });
    p.on('bufferingUpdate', (infoType: media.BufferingInfoType, value: number) => {
      if (myGen !== this.gen) {
        return;
      }
      if (infoType === media.BufferingInfoType.BUFFERING_START) {
        this.cb.onBuffering(true);
      } else if (infoType === media.BufferingInfoType.BUFFERING_END) {
        this.cb.onBuffering(false);
      } else if (infoType === media.BufferingInfoType.BUFFERING_PERCENT) {
        this.cb.onBufferPercent(value);
      } else if (infoType === media.BufferingInfoType.CACHED_DURATION) {
        this.cb.onCachedMs(value);
      }
    });
    p.on('videoSizeChange', (w: number, h: number) => {
      if (myGen === this.gen) {
        if (w > 0 && h > 0) {
          this.videoW = w;
          this.videoH = h;
          if (this.canControl()) {
            this.applySuperResolution(p, myGen);
          }
        }
        this.cb.onVideoSize(w, h);
      }
    });
    p.on('startRenderFrame', () => {
      if (myGen === this.gen) {
        this.cb.onFirstFrame();
      }
    });
    if (this.srRequested) {
      p.on('superResolutionChanged', (enabled: boolean) => {
        if (myGen === this.gen) {
          this.srActive = enabled;
          if (this.srStatus !== 'unavailable') {
            this.setSrStatus(enabled ? 'on' : 'idle');
          }
        }
      });
    }
    p.on('seekDone', (ms: number) => {
      if (myGen === this.gen) {
        this.cb.onSeekDone(ms);
      }
    });
    p.on('trackInfoUpdate', (list: Array<media.MediaDescription>) => {
      if (myGen === this.gen) {
        this.cb.onTracks(PlayerController.mapTracks(list));
      }
    });
    p.on('subtitleUpdate', (info: media.SubtitleInfo) => {
      if (myGen === this.gen) {
        this.cb.onSubtitle(info.text ?? '', info.startTime ?? 0, info.duration ?? 0);
      }
    });
    p.on('audioInterrupt', (ev: audio.InterruptEvent) => {
      if (myGen !== this.gen) {
        return;
      }
      if (ev.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE ||
        ev.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
        this.cb.onInterruptPause();
      }
    });
  }

  private static mapTracks(list: Array<media.MediaDescription>): EmbeddedTrack[] {
    const out: EmbeddedTrack[] = [];
    for (let i = 0; i < list.length; i++) {
      const d = list[i];
      const t = new EmbeddedTrack();
      t.index = num(d[media.MediaDescriptionKey.MD_KEY_TRACK_INDEX]);
      t.type = num(d[media.MediaDescriptionKey.MD_KEY_TRACK_TYPE]);
      t.language = str(d[media.MediaDescriptionKey.MD_KEY_LANGUAGE]);
      t.name = str(d[media.MediaDescriptionKey.MD_KEY_TRACK_NAME]);
      t.codec = str(d[media.MediaDescriptionKey.MD_KEY_CODEC_MIME]);
      t.channels = num(d[media.MediaDescriptionKey.MD_KEY_AUD_CHANNEL_COUNT]);
      t.width = Math.max(0, num(d[media.MediaDescriptionKey.MD_KEY_WIDTH]));
      t.height = Math.max(0, num(d[media.MediaDescriptionKey.MD_KEY_HEIGHT]));
      const fr = num(d[media.MediaDescriptionKey.MD_KEY_FRAME_RATE]);
      t.frameRate = fr > 0 ? fr / 100 : 0;
      t.hdrType = str(d[media.MediaDescriptionKey.MD_KEY_HDR_TYPE]);
      t.bitrate = Math.max(0, num(d[media.MediaDescriptionKey.MD_KEY_BITRATE]));
      t.sampleRate = Math.max(0, num(d[media.MediaDescriptionKey.MD_KEY_AUD_SAMPLE_RATE]));
      if (t.index >= 0) {
        out.push(t);
      }
    }
    return out;
  }

  private setSrStatus(s: string): void {
    if (this.srStatus !== s) {
      this.srStatus = s;
      this.cb.onSuperRes(s);
    }
  }

  private srFailed(e: BusinessError): void {
    console.warn(`[Player] super resolution failed: ${e.code} ${e.message}`);
    if (e.code === 5410003) {
      PlayerController.srUnsupported = true;
    }
    this.srActive = false;
    this.setSrStatus('unavailable');
  }

  /** On-screen size of the video surface in px; forwarded to setVideoWindowSize while super resolution is on. */
  setDisplaySize(pxW: number, pxH: number): void {
    this.displayW = Math.round(pxW);
    this.displayH = Math.round(pxH);
    const p = this.player;
    if (p !== undefined && this.srActive && this.canControl()) {
      this.applyWindowSize(p, this.gen);
    }
  }

  private async applyWindowSize(p: media.AVPlayer, myGen: number): Promise<void> {
    const box: VideoBox = srWindowSize(this.displayW, this.displayH);
    if (box.width <= 0 || (box.width === this.srAppliedW && box.height === this.srAppliedH)) {
      return;
    }
    this.srAppliedW = box.width;
    this.srAppliedH = box.height;
    try {
      await p.setVideoWindowSize(box.width, box.height);
    } catch (e) {
      if (myGen === this.gen) {
        this.srFailed(e as BusinessError);
      }
    }
  }

  /** Turn super resolution on for sub-1080p sources, off otherwise. Errors mark it unavailable, never fail playback. */
  private async applySuperResolution(p: media.AVPlayer, myGen: number): Promise<void> {
    if (!this.srRequested || this.srStatus === 'unavailable' || this.videoH <= 0) {
      return;
    }
    const want = wantSuperResolution(this.videoW, this.videoH);
    if (want === this.srActive) {
      if (want) {
        await this.applyWindowSize(p, myGen);
      }
      return;
    }
    try {
      if (want) {
        this.srAppliedW = 0;
        this.srAppliedH = 0;
        await this.applyWindowSize(p, myGen);
        if (myGen !== this.gen || this.srStatus === 'unavailable') {
          return;
        }
      }
      await p.setSuperResolution(want);
      if (myGen === this.gen) {
        this.srActive = want;
        this.setSrStatus(want ? 'on' : 'idle');
      }
    } catch (e) {
      if (myGen === this.gen) {
        this.srFailed(e as BusinessError);
      }
    }
  }

  /** Network statistics; empty snapshot when the player is not prepared / playing / paused. */
  async netStats(): Promise<NetStats> {
    const out = new NetStats();
    const p = this.player;
    if (p === undefined || !(this.state === 'prepared' || this.state === 'playing' || this.state === 'paused')) {
      return out;
    }
    try {
      const info: media.PlaybackInfo = await p.getPlaybackInfo();
      out.downloadRate = num(info[media.PlaybackInfoKey.DOWNLOAD_RATE]);
      out.avgDownloadRate = num(info[media.PlaybackInfoKey.AVG_DOWNLOAD_RATE]);
      out.bufferSec = num(info[media.PlaybackInfoKey.BUFFER_DURATION]);
      out.downloading = num(info[media.PlaybackInfoKey.IS_DOWNLOADING]);
      out.serverIp = str(info[media.PlaybackInfoKey.SERVER_IP_ADDRESS]);
    } catch (e) {
      console.warn(`[Player] getPlaybackInfo failed: ${(e as BusinessError).message}`);
    }
    return out;
  }

  /** Fresh getTrackDescription() (all tracks, including video). */
  async trackList(): Promise<EmbeddedTrack[]> {
    const p = this.player;
    if (p === undefined || !this.canControl()) {
      return [];
    }
    try {
      return PlayerController.mapTracks(await p.getTrackDescription());
    } catch (e) {
      return [];
    }
  }

  private async loadTracks(): Promise<void> {
    const p = this.player;
    const myGen = this.gen;
    if (p === undefined) {
      return;
    }
    try {
      const list = await p.getTrackDescription();
      if (myGen === this.gen) {
        this.cb.onTracks(PlayerController.mapTracks(list));
      }
    } catch (e) {
      console.warn(`[Player] getTrackDescription failed: ${(e as BusinessError).message}`);
    }
  }

  async selectedTracks(): Promise<number[]> {
    if (this.player === undefined || !this.canControl()) {
      return [];
    }
    try {
      return await this.player.getSelectedTracks();
    } catch (e) {
      return [];
    }
  }

  async play(): Promise<void> {
    const p = this.player;
    if (p === undefined) {
      return;
    }
    try {
      if (this.state === 'completed') {
        p.seek(0, media.SeekMode.SEEK_PREV_SYNC);
      }
      if (this.state === 'prepared' || this.state === 'paused' || this.state === 'completed') {
        await p.play();
      }
    } catch (e) {
      this.cb.onError(errorText(e as BusinessError));
    }
  }

  async pause(): Promise<void> {
    const p = this.player;
    if (p === undefined || this.state !== 'playing') {
      return;
    }
    try {
      await p.pause();
    } catch (e) {
      console.warn(`[Player] pause failed: ${(e as BusinessError).message}`);
    }
  }

  async toggle(): Promise<void> {
    if (this.state === 'playing') {
      await this.pause();
    } else {
      await this.play();
    }
  }

  seek(ms: number): void {
    const p = this.player;
    if (p === undefined || !this.canControl()) {
      this.pendingStart = ms;
      return;
    }
    const max = this.durationMs > 0 ? this.durationMs - 500 : ms;
    const target = Math.max(0, Math.min(ms, max));
    this.positionMs = target;
    try {
      p.seek(target, media.SeekMode.SEEK_CLOSEST);
    } catch (e) {
      try {
        p.seek(target, media.SeekMode.SEEK_PREV_SYNC);
      } catch (e2) {
        console.warn(`[Player] seek failed: ${(e2 as BusinessError).message}`);
      }
    }
  }

  setSpeed(s: number): void {
    this.speed = s;
    const p = this.player;
    if (p === undefined || !this.canControl()) {
      return;
    }
    try {
      p.setSpeed(speedEnum(s));
    } catch (e) {
      console.warn(`[Player] setSpeed failed: ${(e as BusinessError).message}`);
    }
  }

  async selectTrack(index: number): Promise<void> {
    const p = this.player;
    if (p === undefined || !this.canControl()) {
      return;
    }
    try {
      await p.selectTrack(index, media.SwitchMode.SMOOTH);
    } catch (e) {
      this.cb.onWarn('切换轨道失败: ' + ((e as BusinessError).message ?? ''));
    }
  }

  async deselectTrack(index: number): Promise<void> {
    const p = this.player;
    if (p === undefined || !this.canControl()) {
      return;
    }
    try {
      await p.deselectTrack(index);
    } catch (e) {
      console.warn(`[Player] deselectTrack failed: ${(e as BusinessError).message}`);
    }
  }

  /** External subtitle without auth headers: let AVPlayer fetch it; text arrives via onSubtitle. */
  async addSubtitleUrl(url: string): Promise<boolean> {
    const p = this.player;
    if (p === undefined) {
      return false;
    }
    try {
      await p.addSubtitleFromUrl(url);
      return true;
    } catch (e) {
      console.warn(`[Player] addSubtitleFromUrl failed: ${(e as BusinessError).message}`);
      return false;
    }
  }

  private async releasePlayer(): Promise<void> {
    const p = this.player;
    this.player = undefined;
    this.gen++;
    if (p === undefined) {
      return;
    }
    try {
      p.off('stateChange');
      p.off('error');
      p.off('timeUpdate');
      p.off('durationUpdate');
      p.off('bufferingUpdate');
      p.off('videoSizeChange');
      p.off('seekDone');
      p.off('trackInfoUpdate');
      p.off('subtitleUpdate');
      p.off('audioInterrupt');
      p.off('startRenderFrame');
      p.off('superResolutionChanged');
      await p.release();
    } catch (e) {
      console.warn(`[Player] release failed: ${(e as BusinessError).message}`);
    }
  }

  async release(): Promise<void> {
    this.released = true;
    this.state = 'released';
    await this.releasePlayer();
  }
}
