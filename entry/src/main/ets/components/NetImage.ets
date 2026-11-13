import { Theme } from '../common/Theme';

/** Network image with placeholder colour, fallback initial and fade-in on load. */
@Component
export struct NetImage {
  @Prop @Watch('onSrcChange') src: string = '';
  @Prop placeholderText: string = '';
  @Prop fit: ImageFit = ImageFit.Cover;
  @Prop placeholderColor: string = Theme.surface2;
  @Prop radius: number = 0;
  @Prop fadeMs: number = 260;
  @State private loaded: boolean = false;
  @State private failed: boolean = false;

  onSrcChange(): void {
    this.loaded = false;
    this.failed = false;
  }

  build() {
    Stack() {
      if (this.src.length === 0 || this.failed || !this.loaded) {
        Column() {
          if (this.placeholderText.length > 0 && (this.src.length === 0 || this.failed)) {
            Text(this.placeholderText.substring(0, 1))
              .fontSize(28).fontWeight(FontWeight.Bold).fontColor(Theme.text3)
          }
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.placeholderColor)
      }
      if (this.src.length > 0 && !this.failed) {
        Image(this.src)
          .width('100%').height('100%')
          .objectFit(this.fit)
          .draggable(false)
          .opacity(this.loaded ? 1 : 0)
          .animation({ duration: this.fadeMs, curve: Curve.EaseOut })
          .onComplete(() => { this.loaded = true; })
          .onError(() => { this.failed = true; })
      }
    }
    .width('100%').height('100%')
    .borderRadius(this.radius)
    .clip(true)
  }
}
