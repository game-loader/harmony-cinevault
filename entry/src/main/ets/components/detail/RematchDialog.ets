import { BusinessError } from '@kit.BasicServicesKit';
import { MediaItem } from '../../common/Models';
import { Theme } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { Scraper } from '../../scraper/Scraper';

/** TMDB poster path -> absolute URL (scraper may already return absolute URLs). */
export function tmdbPoster(p: string): string {
  if (p.length === 0 || p.startsWith('http')) {
    return p;
  }
  let base = Settings.get().tmdbImageBase;
  if (base.length === 0) {
    base = 'https://image.tmdb.org/t/p/';
  }
  if (!base.endsWith('/')) {
    base = base + '/';
  }
  return base + 'w185' + (p.startsWith('/') ? p : '/' + p);
}

/** Values the dialog starts with; read when the dialog opens. */
export class RematchSeed {
  sourceId: string = '';
  itemId: string = '';
  query: string = '';
  year: number = 0;
  type: 'movie' | 'tv' = 'movie';
}

function errText(e: Object): string {
  const be = e as BusinessError;
  if (be && be.message) {
    return be.message;
  }
  return '未知错误';
}

/** 重新匹配: manual TMDB search + pick for Quark-backed items. */
@CustomDialog
export struct RematchDialog {
  controller?: CustomDialogController;
  seed: () => RematchSeed = () => new RematchSeed();
  onMatched: (item: MediaItem | undefined) => void = () => {};

  private sourceId: string = '';
  private itemId: string = '';
  @State query: string = '';
  @State yearText: string = '';
  @State type: 'movie' | 'tv' = 'movie';
  @State results: MediaItem[] = [];
  @State loading: boolean = false;
  @State applying: string = '';
  @State error: string = '';
  @State searched: boolean = false;

  aboutToAppear(): void {
    const sd = this.seed();
    this.sourceId = sd.sourceId;
    this.itemId = sd.itemId;
    this.query = sd.query;
    this.yearText = sd.year > 0 ? sd.year.toString() : '';
    this.type = sd.type;
    if (this.query.length > 0) {
      this.doSearch();
    }
  }

  async doSearch(): Promise<void> {
    const q = this.query.trim();
    if (q.length === 0) {
      this.error = '请输入片名';
      return;
    }
    this.loading = true;
    this.error = '';
    try {
      const y = parseInt(this.yearText.trim());
      this.results = await Scraper.searchTmdb(q, isNaN(y) ? 0 : y, this.type);
    } catch (e) {
      this.results = [];
      this.error = '搜索失败：' + errText(e as Object);
    } finally {
      this.loading = false;
      this.searched = true;
    }
  }

  async pick(r: MediaItem): Promise<void> {
    if (this.applying.length > 0) {
      return;
    }
    const tmdbId = r.tmdbId.length > 0 ? r.tmdbId : r.id;
    this.applying = r.id;
    this.error = '';
    try {
      const res = await Scraper.rematch(this.sourceId, this.itemId, this.type, tmdbId);
      this.applying = '';
      this.onMatched(res);
      this.controller?.close();
    } catch (e) {
      this.applying = '';
      this.error = '匹配失败：' + errText(e as Object);
    }
  }

  @Builder
  typeChip(label: string, t: 'movie' | 'tv') {
    Text(label)
      .fontSize(13)
      .fontColor(this.type === t ? Color.White : Theme.text2)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.type === t ? Theme.accent : Theme.surface2)
      .onClick(() => {
        if (this.type !== t) {
          this.type = t;
          this.doSearch();
        }
      })
  }

  @Builder
  resultRow(r: MediaItem) {
    Row({ space: 12 }) {
      Stack() {
        if (r.images.poster.length > 0) {
          Image(tmdbPoster(r.images.poster)).width('100%').height('100%').objectFit(ImageFit.Cover)
        } else {
          Text('无海报').fontSize(10).fontColor(Theme.text3)
        }
      }
      .width(54).height(81).borderRadius(6).clip(true).backgroundColor(Theme.surface2)

      Column({ space: 4 }) {
        Text(r.title).fontSize(15).fontColor(Theme.text).fontWeight(FontWeight.Medium)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text((r.year > 0 ? r.year.toString() : '年份未知') +
          (r.originalTitle.length > 0 && r.originalTitle !== r.title ? ' · ' + r.originalTitle : ''))
          .fontSize(12).fontColor(Theme.text2)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(r.overview).fontSize(12).fontColor(Theme.text3)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)

      if (this.applying === r.id) {
        LoadingProgress().width(24).height(24).color(Theme.accent)
      }
    }
    .width('100%').padding(8).borderRadius(8)
    .backgroundColor(Theme.surface)
    .onClick(() => {
      this.pick(r);
    })
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('重新匹配').fontSize(18).fontColor(Theme.text).fontWeight(FontWeight.Bold).layoutWeight(1)
        Text('关闭').fontSize(14).fontColor(Theme.text2)
          .onClick(() => this.controller?.close())
      }.width('100%')

      Row({ space: 8 }) {
        TextInput({ text: this.query, placeholder: '片名' })
          .layoutWeight(1).height(40)
          .fontColor(Theme.text).placeholderColor(Theme.text3)
          .backgroundColor(Theme.surface2)
          .enterKeyType(EnterKeyType.Search)
          .onChange((v: string) => {
            this.query = v;
          })
          .onSubmit(() => {
            this.doSearch();
          })
        TextInput({ text: this.yearText, placeholder: '年份' })
          .width(80).height(40)
          .type(InputType.Number).maxLength(4)
          .fontColor(Theme.text).placeholderColor(Theme.text3)
          .backgroundColor(Theme.surface2)
          .onChange((v: string) => {
            this.yearText = v;
          })
        Button('搜索').height(40).backgroundColor(Theme.accent)
          .onClick(() => {
            this.doSearch();
          })
      }.width('100%')

      Row({ space: 8 }) {
        this.typeChip('电影', 'movie')
        this.typeChip('剧集', 'tv')
      }.width('100%')

      if (this.error.length > 0) {
        Text(this.error).fontSize(13).fontColor(Theme.accent).width('100%')
      }

      if (this.loading) {
        Column() {
          LoadingProgress().width(36).height(36).color(Theme.accent)
          Text('正在搜索 TMDB…').fontSize(13).fontColor(Theme.text2)
        }.width('100%').height(200).justifyContent(FlexAlign.Center)
      } else if (this.searched && this.results.length === 0 && this.error.length === 0) {
        Column() {
          Text('没有找到结果，试试其他关键词或切换类型').fontSize(13).fontColor(Theme.text2)
        }.width('100%').height(200).justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.results, (r: MediaItem) => {
            ListItem() {
              this.resultRow(r)
            }
          }, (r: MediaItem) => r.id + '|' + r.tmdbId)
        }
        .width('100%').height(380)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .padding(20)
    .backgroundColor(Theme.bg)
    .borderRadius(16)
  }
}
