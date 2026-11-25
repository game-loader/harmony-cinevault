import { Theme } from '../common/Theme';
import { formatDuration } from './SubtitleParser';

/** Control layer on top of the video: top bar, center controls, progress + action buttons, lock. */
@Component
export struct PlayerOverlay {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop playing: boolean = false;
  @Prop positionMs: number = 0;
  @Prop durationMs: number = 0;
  @Prop bufferedMs: number = 0;
  @Prop locked: boolean = false;
  @Prop showControls: boolean = true;
  @Prop speedText: string = '倍速';
  @Prop qualityText: string = '画质';
  /** Current resolution label ('自动', '1080p', ...); '' hides the button (single-variant streams). */
  @Prop resolutionText: string = '';
  @Prop aspectText: string = '画面';
  @Prop hasEpisodes: boolean = false;
  @Prop hasNext: boolean = false;
  @Prop hasPrev: boolean = false;
  @Prop hasAudio: boolean = false;
  @Prop hasSubtitle: boolean = true;
  onBack: () => void = () => {};
  onToggle: () => void = () => {};
  onSeekRel: (deltaMs: number) => void = (d: number) => {};
  onSeekTo: (ms: number) => void = (ms: number) => {};
  onScrubbing: (ms: number, active: boolean) => void = (ms: number, a: boolean) => {};
  onLock: () => void = () => {};
  onMenu: (key: string) => void = (k: string) => {};
  onNext: () => void = () => {};
  onPrev: () => void = () => {};
  onInteract: () => void = () => {};

  /** Bottom-right function area: icon over a short label; collapses to icon-only on narrow screens. */
  @Builder
  barButton(icon: Resource, label: string, key: string) {
    Column({ space: 2 }) {
      SymbolGlyph(icon).fontSize(20).fontColor([Color.White])
      if (!this.compact()) {
        Text(label)
          .fontSize(10).fontColor('#D9FFFFFF')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 64 })
      }
    }
    .constraintSize({ minWidth: 44 })
    .height(44)
    .padding({ left: 6, right: 6 })
    .justifyContent(FlexAlign.Center)
    .borderRadius(10)
    .onClick(() => {
      this.onInteract();
      this.onMenu(key);
    })
  }

  @Builder
  iconButton(icon: Resource, key: string) {
    Row() {
      SymbolGlyph(icon).fontSize(24).fontColor([Color.White])
    }
    .width(44).height(44).justifyContent(FlexAlign.Center)
    .borderRadius(22)
    .onClick(() => {
      this.onInteract();
      this.onMenu(key);
    })
  }

  /** Round glass button for the centre row and the top bar. */
  @Builder
  glassButton(icon: Resource, size: number, iconSize: number, action: () => void) {
    Row() {
      SymbolGlyph(icon).fontSize(iconSize).fontColor([Color.White])
    }
    .width(size).height(size).borderRadius(size / 2)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#40000000')
    .backdropBlur(16)
    .onClick(() => {
      this.onInteract();
      action();
    })
  }

  /** Width of the overlay in vp; Pura X Max inner screen is ~795 vp landscape, cover ~569 vp landscape. */
  @State private areaW: number = 0;
  @State private areaH: number = 0;

  private compact(): boolean {
    return this.areaW > 0 && this.areaW < 680;
  }

  /** Short screens (foldable landscape ~560 vp tall): smaller centre buttons and tighter bars. */
  private short(): boolean {
    return this.areaH > 0 && this.areaH < 600;
  }

  private pad(): number {
    return this.areaW >= 840 ? 32 : (this.areaW >= 600 ? 24 : 16);
  }

  private bufferedRatio(): number {
    if (this.durationMs <= 0) {
      return 0;
    }
    return Math.min(1, Math.max(0, this.bufferedMs / this.durationMs));
  }

  build() {
    Stack() {
      if (this.showControls && !this.locked) {
        Column() {
          // top bar
          Row() {
            this.glassButton($r('sys.symbol.chevron_left'), 40, 20, () => this.onBack())
            Column() {
              Text(this.title)
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.subtitle.length > 0) {
                Text(this.subtitle)
                  .fontSize(13)
                  .fontColor(Theme.text2)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 2 })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 12 })
          }
          .width('100%')
          .padding({ left: this.pad(), right: this.pad(), top: this.short() ? 12 : 16, bottom: 28 })
          .linearGradient({ angle: 180, colors: [['#B0000000', 0], ['#00000000', 1]] })

          Blank().layoutWeight(1)

          // center controls
          Row({ space: this.short() ? 28 : 40 }) {
            if (this.hasPrev) {
              this.glassButton($r('sys.symbol.backward_end_fill'), this.short() ? 44 : 48, 20, () => this.onPrev())
            }
            this.glassButton($r('sys.symbol.gobackward_10'), this.short() ? 52 : 56, this.short() ? 26 : 28,
              () => this.onSeekRel(-10000))
            this.glassButton(this.playing ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'),
              this.short() ? 64 : 72, this.short() ? 30 : 34, () => this.onToggle())
            this.glassButton($r('sys.symbol.goforward_10'), this.short() ? 52 : 56, this.short() ? 26 : 28,
              () => this.onSeekRel(10000))
            if (this.hasNext) {
              this.glassButton($r('sys.symbol.forward_end_fill'), this.short() ? 44 : 48, 20, () => this.onNext())
            }
          }
          .justifyContent(FlexAlign.Center)

          Blank().layoutWeight(1)

          // bottom: progress + actions
          Column() {
            Row() {
              Text(formatDuration(this.positionMs))
                .fontSize(13)
                .fontColor(Color.White)
                .width(64)
                .textAlign(TextAlign.Start)
              Stack() {
                Row()
                  .width('100%')
                  .height(4)
                  .borderRadius(2)
                  .backgroundColor('#40FFFFFF')
                Row()
                  .width(`${Math.round(this.bufferedRatio() * 1000) / 10}%`)
                  .height(4)
                  .borderRadius(2)
                  .backgroundColor('#80FFFFFF')
                Slider({
                  value: this.durationMs > 0 ? Math.min(this.positionMs, this.durationMs) : 0,
                  min: 0,
                  max: this.durationMs > 0 ? this.durationMs : 1,
                  step: 1000,
                  style: SliderStyle.OutSet
                })
                  .width('100%')
                  .trackColor(Color.Transparent)
                  .selectedColor(Theme.accent)
                  .blockColor(Color.White)
                  .trackThickness(4)
                  .onChange((value: number, mode: SliderChangeMode) => {
                    this.onInteract();
                    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                      this.onScrubbing(value, false);
                      this.onSeekTo(value);
                    } else {
                      this.onScrubbing(value, true);
                    }
                  })
              }
              .alignContent(Alignment.Start)
              .layoutWeight(1)
              Text(formatDuration(this.durationMs))
                .fontSize(13)
                .fontColor(Color.White)
                .width(64)
                .textAlign(TextAlign.End)
            }
            .width('100%')

            Row({ space: 2 }) {
              this.iconButton(this.playing ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'), 'toggle')
              if (this.hasNext) {
                this.iconButton($r('sys.symbol.forward_end_fill'), 'next')
              }
              Blank().layoutWeight(1)
              this.barButton($r('sys.symbol.double_speed'), this.speedText, 'speed')
              this.barButton($r('sys.symbol.dot_radiowaves'), this.qualityText, 'quality')
              if (this.resolutionText.length > 0) {
                this.barButton($r('sys.symbol.display'), this.resolutionText === '自动' ? '分辨率' : this.resolutionText,
                  'resolution')
              }
              if (this.hasAudio) {
                this.barButton($r('sys.symbol.speaker_wave_2'), '音轨', 'audio')
              }
              if (this.hasSubtitle) {
                this.barButton($r('sys.symbol.AI_subtitles'), '字幕', 'subtitle')
              }
              this.barButton($r('sys.symbol.aspect_ratio'), this.aspectText, 'aspect')
              if (this.hasEpisodes) {
                this.barButton($r('sys.symbol.list_badge_play'), '选集', 'episodes')
              }
              this.barButton($r('sys.symbol.ellipsis_circle'), '更多', 'more')
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: this.short() ? 0 : 4 })
          }
          .width('100%')
          .padding({ left: this.pad(), right: this.pad(), top: 28, bottom: this.short() ? 8 : 16 })
          .linearGradient({ angle: 0, colors: [['#C0000000', 0], ['#00000000', 1]] })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // lock button: always reachable when controls are visible, and the only control while locked
      if (this.showControls) {
        Row() {
          this.glassButton(this.locked ? $r('sys.symbol.lock_fill') : $r('sys.symbol.lock_open_fill'), 44, 20,
            () => this.onLock())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)
        .padding({ left: this.pad() })
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .onAreaChange((o: Area, n: Area) => {
      this.areaW = Number(n.width);
      this.areaH = Number(n.height);
    })
  }
}
