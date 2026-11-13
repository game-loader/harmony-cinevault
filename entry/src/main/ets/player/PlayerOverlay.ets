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

  @Builder
  barButton(label: string, key: string) {
    Text(label)
      .fontSize(14)
      .fontColor(Theme.text)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .borderRadius(16)
      .onClick(() => {
        this.onInteract();
        this.onMenu(key);
      })
  }

  @Builder
  roundButton(label: string, size: number, fontSize: number, action: () => void) {
    Text(label)
      .fontSize(fontSize)
      .fontColor(Color.White)
      .textAlign(TextAlign.Center)
      .width(size)
      .height(size)
      .borderRadius(size / 2)
      .backgroundColor('#55000000')
      .onClick(() => {
        this.onInteract();
        action();
      })
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
            this.roundButton('‹', 40, 26, () => this.onBack())
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
          .padding({ left: 24, right: 24, top: 16, bottom: 28 })
          .linearGradient({ angle: 180, colors: [['#B0000000', 0], ['#00000000', 1]] })

          Blank().layoutWeight(1)

          // center controls
          Row({ space: 40 }) {
            if (this.hasPrev) {
              this.roundButton('⏮', 48, 20, () => this.onPrev())
            }
            this.roundButton('-10', 56, 16, () => this.onSeekRel(-10000))
            this.roundButton(this.playing ? '❚❚' : '▶', 72, 26, () => this.onToggle())
            this.roundButton('+10', 56, 16, () => this.onSeekRel(10000))
            if (this.hasNext) {
              this.roundButton('⏭', 48, 20, () => this.onNext())
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

            Row() {
              this.barButton(this.playing ? '暂停' : '播放', 'toggle')
              if (this.hasNext) {
                this.barButton('下一集', 'next')
              }
              Blank().layoutWeight(1)
              this.barButton(this.speedText, 'speed')
              this.barButton(this.qualityText, 'quality')
              if (this.hasAudio) {
                this.barButton('音轨', 'audio')
              }
              if (this.hasSubtitle) {
                this.barButton('字幕', 'subtitle')
              }
              this.barButton(this.aspectText, 'aspect')
              if (this.hasEpisodes) {
                this.barButton('选集', 'episodes')
              }
            }
            .width('100%')
            .margin({ top: 4 })
          }
          .width('100%')
          .padding({ left: 24, right: 24, top: 28, bottom: 16 })
          .linearGradient({ angle: 0, colors: [['#C0000000', 0], ['#00000000', 1]] })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // lock button, always reachable when controls are visible
      if (this.showControls) {
        Row() {
          this.roundButton(this.locked ? '🔒' : '🔓', 48, 20, () => this.onLock())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 24 })
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
