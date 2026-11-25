import { BusinessError } from '@kit.BasicServicesKit';
import { MediaItem, Person } from '../common/Models';
import { MediaProvider } from '../common/MediaProvider';
import { DetailParams, Nav } from '../common/Nav';
import { Theme } from '../common/Theme';
import { ProviderRegistry } from '../providers/ProviderRegistry';
import { LibraryDb, LocalFile } from '../library/LibraryDb';
import { DetailPosterCard, PersonAvatar, EpisodeRow } from '../components/detail/DetailCards';
import { RematchDialog, RematchSeed } from '../components/detail/RematchDialog';
import {
  formatClock, formatRating, formatSize, mediaBadges, metaParts, progressFraction, hasResume, pickNextEpisode,
  pickSeasonIndex, seasonLabel, episodeCode, tmdbTypeFor, guessQuery, withPlayed, genreLabel } from '../components/detail/DetailLogic';
import { AppLog } from '../common/AppLog';

function errMsg(e: Object): string {
  const be = e as BusinessError;
  if (be && be.message && be.message.length > 0) {
    return be.message;
  }
  return '未知错误';
}

@Entry
@Component
struct DetailPage {
  private sourceId: string = '';
  private itemId: string = '';
  private provider: MediaProvider | undefined = undefined;
  private loadedOnce: boolean = false;
  private loadToken: number = 0;
  private epToken: number = 0;

  @State item: MediaItem = new MediaItem();
  @State loading: boolean = true;
  @State error: string = '';
  @State played: boolean = false;
  @State favorite: boolean = false;
  @State busyPlayed: boolean = false;
  @State busyFav: boolean = false;

  /** Series id that owns the seasons shown ('' when item is a movie). */
  @State seriesId: string = '';
  @State seasons: MediaItem[] = [];
  @State seasonIdx: number = -1;
  @State episodes: MediaItem[] = [];
  @State epLoading: boolean = false;
  @State epError: string = '';

  @State similar: MediaItem[] = [];
  @State files: LocalFile[] = [];
  @State expanded: boolean = false;
  @State winWidth: number = 360;

  private rematchCtl: CustomDialogController = new CustomDialogController({
    builder: RematchDialog({
      seed: (): RematchSeed => this.rematchSeed(),
      onMatched: (res: MediaItem | undefined) => this.onRematched(res)
    }),
    autoCancel: true,
    customStyle: true,
    alignment: DialogAlignment.Center,
    width: '92%'
  });

  aboutToAppear(): void {
    const p = this.getUIContext().getRouter().getParams() as DetailParams;
    if (p) {
      this.sourceId = p.sourceId ?? '';
      this.itemId = p.itemId ?? '';
    }
  }

  onPageShow(): void {
    // First show loads with spinner; later shows (e.g. back from player) refresh silently.
    this.load(this.loadedOnce);
  }

  wide(): boolean {
    return this.winWidth >= Theme.bpMd;
  }

  large(): boolean {
    return this.winWidth >= Theme.bpLg;
  }

  isFlicx(): boolean {
    return this.provider !== undefined && this.provider.config.kind === 'flicx';
  }

  isQuark(): boolean {
    return this.provider !== undefined && this.provider.config.kind === 'quark';
  }

  hasSeasons(): boolean {
    return this.seriesId.length > 0;
  }

  toast(msg: string): void {
    AppLog.info(`[Detail] toast: ${msg}`);
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
    } catch (e) {
      AppLog.error('toast failed ' + errMsg(e as Object));
    }
  }

  img(it: MediaItem, kind: 'poster' | 'backdrop' | 'logo' | 'thumb', w: number): string {
    if (!this.provider) {
      return '';
    }
    try {
      return this.provider.imageUrl(it, kind, w);
    } catch (e) {
      return '';
    }
  }

  async load(silent: boolean): Promise<void> {
    const token = ++this.loadToken;
    if (!silent) {
      this.loading = true;
      this.error = '';
    }
    try {
      if (this.sourceId.length === 0 || this.itemId.length === 0) {
        throw new Error('参数缺失');
      }
      const prov = ProviderRegistry.get(this.sourceId);
      if (!prov) {
        throw new Error('媒体来源不存在或已被删除');
      }
      this.provider = prov;
      const it = await prov.getItem(this.itemId);
      if (token !== this.loadToken) {
        return;
      }
      this.item = it;
      AppLog.info(`[Detail] loaded ${this.sourceId} ${it.id} type=${it.type} "${it.title}"`);
      this.played = it.state.played;
      this.favorite = it.state.favorite;
      this.loading = false;
      this.error = '';
      this.loadedOnce = true;
      let sid = '';
      if (it.type === 'series') {
        sid = it.id;
      } else if ((it.type === 'season' || it.type === 'episode') && it.seriesId.length > 0) {
        sid = it.seriesId;
      }
      this.seriesId = sid;
      this.loadExtras(token, prov, it);
      if (sid.length > 0) {
        await this.loadSeasons(token, prov, it, silent);
      }
    } catch (e) {
      if (token !== this.loadToken) {
        return;
      }
      if (silent && this.loadedOnce) {
        AppLog.warn('detail refresh failed ' + errMsg(e as Object));
        return;
      }
      this.loading = false;
      this.error = errMsg(e as Object);
      AppLog.error(`[Detail] load ${this.sourceId} ${this.itemId} failed: ${this.error}`);
    }
  }

  async loadExtras(token: number, prov: MediaProvider, it: MediaItem): Promise<void> {
    const simId = it.type === 'episode' || it.type === 'season' ? (it.seriesId.length > 0 ? it.seriesId : it.id) : it.id;
    prov.getSimilar(simId, 20).then((list: MediaItem[]) => {
      if (token === this.loadToken) {
        this.similar = list.filter((m: MediaItem) => m.id !== simId);
      }
    }).catch((e: Object) => {
      AppLog.warn('similar failed ' + errMsg(e));
    });
    if (prov.config.kind === 'quark' && it.type !== 'series' && it.type !== 'season') {
      try {
        const fs = await LibraryDb.filesForItem(this.sourceId, it.id);
        if (token === this.loadToken) {
          this.files = fs;
        }
      } catch (e) {
        AppLog.warn('files failed ' + errMsg(e as Object));
      }
    } else {
      this.files = [];
    }
  }

  async loadSeasons(token: number, prov: MediaProvider, it: MediaItem, silent: boolean): Promise<void> {
    let ss: MediaItem[] = [];
    try {
      ss = await prov.getSeasons(this.seriesId);
    } catch (e) {
      if (token === this.loadToken) {
        this.epError = '加载季列表失败：' + errMsg(e as Object);
      }
      return;
    }
    if (token !== this.loadToken) {
      return;
    }
    // Keep the user's selected season on refresh; otherwise pick from item / next-up.
    let wantId = '';
    let wantNum = -1;
    if (silent && this.seasonIdx >= 0 && this.seasonIdx < this.seasons.length) {
      wantId = this.seasons[this.seasonIdx].id;
    } else if (it.type === 'season') {
      wantId = it.id;
      wantNum = it.seasonNumber;
    } else if (it.type === 'episode') {
      wantId = it.seasonId;
      wantNum = it.seasonNumber;
    } else {
      try {
        const nu = await prov.getNextUp(50);
        const hit = nu.find((m: MediaItem) => m.seriesId === this.seriesId);
        if (hit) {
          wantId = hit.seasonId;
          wantNum = hit.seasonNumber;
        }
      } catch (e) {
        AppLog.warn('nextUp failed ' + errMsg(e as Object));
      }
      if (token !== this.loadToken) {
        return;
      }
    }
    this.seasons = ss;
    const idx = pickSeasonIndex(ss, wantId, wantNum);
    this.seasonIdx = idx;
    if (idx >= 0) {
      await this.loadEpisodes(idx, silent);
    } else {
      // Flat series without season entries: load all episodes.
      await this.loadEpisodesFor('', silent);
    }
  }

  async selectSeason(idx: number): Promise<void> {
    if (idx === this.seasonIdx) {
      return;
    }
    this.seasonIdx = idx;
    await this.loadEpisodes(idx, false);
  }

  async loadEpisodes(idx: number, silent: boolean): Promise<void> {
    if (idx < 0 || idx >= this.seasons.length) {
      return;
    }
    await this.loadEpisodesFor(this.seasons[idx].id, silent);
  }

  async loadEpisodesFor(seasonId: string, silent: boolean): Promise<void> {
    const prov = this.provider;
    if (!prov) {
      return;
    }
    const token = ++this.epToken;
    if (!silent) {
      this.epLoading = true;
      this.episodes = [];
    }
    this.epError = '';
    try {
      const eps = await prov.getEpisodes(this.seriesId, seasonId);
      if (token === this.epToken) {
        this.episodes = eps;
      }
    } catch (e) {
      if (token === this.epToken) {
        this.epError = '加载剧集失败：' + errMsg(e as Object);
      }
    } finally {
      if (token === this.epToken) {
        this.epLoading = false;
      }
    }
  }

  /** Container-like items play an episode; movies/episodes play themselves. */
  isContainer(): boolean {
    return this.item.type === 'series' || this.item.type === 'season';
  }

  playable(): boolean {
    if (this.isContainer()) {
      return this.episodes.length > 0;
    }
    return this.item.type !== 'folder' && this.item.type !== 'collection';
  }

  /** Episode index the main button targets (-1 when not a container). */
  targetEpIdx(): number {
    return this.isContainer() ? pickNextEpisode(this.episodes) : -1;
  }

  target(): MediaItem | undefined {
    if (!this.isContainer()) {
      return this.item;
    }
    const i = this.targetEpIdx();
    return i >= 0 ? this.episodes[i] : undefined;
  }

  canResume(): boolean {
    const t = this.target();
    return t !== undefined && hasResume(t);
  }

  resumeFraction(): number {
    const t = this.target();
    return t !== undefined && hasResume(t) ? progressFraction(t) : 0;
  }

  playLabel(): string {
    const t = this.target();
    if (!t) {
      return '播放';
    }
    const prefix = this.isContainer() ? episodeCode(t.seasonNumber, t.episodeNumber) + ' ' : '';
    if (hasResume(t)) {
      return '继续播放 ' + prefix + formatClock(t.state.positionMs);
    }
    return '播放' + (prefix.length > 1 ? ' ' + prefix.trim() : '');
  }

  /** Play queue for an episode: the full loaded season list, so the Player can find the
   *  current id and offer both next and previous. Empty if the episode isn't in the list. */
  queueFor(epId: string): string[] {
    const idx = this.episodes.findIndex((m: MediaItem) => m.id === epId);
    return idx >= 0 ? this.episodes.map((m: MediaItem) => m.id) : [];
  }

  play(fromStart: boolean): void {
    let t: MediaItem | undefined = undefined;
    try {
      t = this.target();
    } catch (e) {
      AppLog.error(`[Detail] play target failed: ${errMsg(e as Object)}`);
    }
    AppLog.info(`[Detail] play ${this.sourceId} item=${this.item.id || this.itemId} type=${this.item.type} ` +
      `target=${t ? t.id : '-'} episodes=${this.episodes.length}`);
    if (!t) {
      if (!this.isContainer() && this.itemId.length > 0) {
        Nav.play(this.sourceId, this.itemId, fromStart ? 0 : -1, []);
        return;
      }
      this.toast(this.isContainer() ? '没有可播放的剧集' : '无法播放');
      return;
    }
    const queue = t.type === 'episode' ? this.queueFor(t.id) : [];
    Nav.play(this.sourceId, t.id || this.itemId, fromStart ? 0 : -1, queue);
  }

  playEpisode(idx: number): void {
    const ep = this.episodes[idx];
    Nav.play(this.sourceId, ep.id, -1, this.queueFor(ep.id));
  }

  async togglePlayed(): Promise<void> {
    const prov = this.provider;
    if (!prov || this.busyPlayed) {
      return;
    }
    const v = !this.played;
    const prevEps = this.episodes;
    this.played = v;
    this.busyPlayed = true;
    if (this.isContainer()) {
      this.episodes = prevEps.map((m: MediaItem) => withPlayed(m, v));
    }
    try {
      await prov.setPlayed(this.item, v);
      this.item.state.played = v;
      if (v) {
        this.item.state.positionMs = 0;
      }
      this.toast(v ? '已标记为已看' : '已标记为未看');
    } catch (e) {
      this.played = !v;
      this.episodes = prevEps;
      this.toast('操作失败：' + errMsg(e as Object));
    } finally {
      this.busyPlayed = false;
    }
  }

  async toggleEpisodePlayed(idx: number): Promise<void> {
    const prov = this.provider;
    if (!prov || idx < 0 || idx >= this.episodes.length) {
      return;
    }
    const ep = this.episodes[idx];
    const v = !ep.state.played;
    this.episodes.splice(idx, 1, withPlayed(ep, v));
    try {
      await prov.setPlayed(ep, v);
      this.toast((v ? '已标记为已看：' : '已标记为未看：') + ep.title);
    } catch (e) {
      const cur = this.episodes.findIndex((m: MediaItem) => m.id === ep.id);
      if (cur >= 0) {
        this.episodes.splice(cur, 1, ep);
      }
      this.toast('操作失败：' + errMsg(e as Object));
    }
  }

  async toggleFavorite(): Promise<void> {
    const prov = this.provider;
    if (!prov || this.busyFav) {
      return;
    }
    const v = !this.favorite;
    this.favorite = v;
    this.busyFav = true;
    try {
      await prov.setFavorite(this.item, v);
      this.item.state.favorite = v;
      this.toast(v ? '已加入收藏' : '已取消收藏');
    } catch (e) {
      this.favorite = !v;
      this.toast('操作失败：' + errMsg(e as Object));
    } finally {
      this.busyFav = false;
    }
  }

  rematchSeed(): RematchSeed {
    const s = new RematchSeed();
    s.sourceId = this.sourceId;
    // Episodes are matched at series level; season items too.
    s.itemId = this.item.id;
    s.query = guessQuery(this.item);
    s.year = this.item.type === 'episode' ? 0 : this.item.year;
    s.type = tmdbTypeFor(this.item);
    return s;
  }

  onRematched(res: MediaItem | undefined): void {
    this.toast('匹配成功，正在刷新');
    if (res && res.id.length > 0 && res.id !== this.itemId) {
      // Item ids are TMDB-derived for Quark sources, so the id may change after a re-match.
      this.itemId = res.id;
    }
    this.seasons = [];
    this.seasonIdx = -1;
    this.episodes = [];
    this.similar = [];
    this.load(false);
  }

  openSeries(): void {
    if (this.item.seriesId.length > 0) {
      Nav.detail(this.sourceId, this.item.seriesId);
    }
  }

  @Builder
  backButton() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([Color.White])
    }
    .width(44).height(44).borderRadius(22)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#4D000000')
    .backdropBlur(20)
    .margin({ left: 16, top: 16 })
    .onClick(() => Nav.back())
  }

  @Builder
  stateView() {
    Column({ space: 16 }) {
      if (this.loading) {
        LoadingProgress().width(48).height(48).color(Theme.accent)
        Text('正在加载…').fontSize(14).fontColor(Theme.text2)
      } else {
        Text('加载失败').fontSize(18).fontColor(Theme.text).fontWeight(FontWeight.Bold)
        Text(this.error).fontSize(13).fontColor(Theme.text2).textAlign(TextAlign.Center)
          .padding({ left: 32, right: 32 })
        Row({ space: 12 }) {
          Button('重试').backgroundColor(Theme.accent).onClick(() => {
            this.load(false);
          })
          Button('返回').backgroundColor(Theme.surface2).fontColor(Theme.text).onClick(() => Nav.back())
        }
      }
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
  }

  @Builder
  chip(label: string, filled: boolean) {
    Text(label)
      .fontSize(13)
      .fontColor(filled ? '#E6FFFFFF' : Theme.text2)
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .borderRadius(14)
      .backgroundColor(filled ? '#26FFFFFF' : Color.Transparent)
      .border({ width: filled ? 0 : 1, color: '#40FFFFFF', radius: 14 })
  }

  @Builder
  actionButton(icon: Resource, label: string, active: boolean, onTap: () => void) {
    Column({ space: 6 }) {
      Row() {
        SymbolGlyph(icon).fontSize(22).fontColor([active ? Theme.accent : Color.White])
      }
      .width(48).height(48).borderRadius(24)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(active ? '#33E53935' : '#26FFFFFF')
      .border({ width: 1, color: active ? '#66E53935' : '#33FFFFFF', radius: 24 })
      Text(label).fontSize(11).fontColor(active ? Theme.accent : Theme.text2)
    }
    .width(64)
    .onClick(onTap)
  }

  @Builder
  titleBlock() {
    Column({ space: 8 }) {
      if (this.item.type === 'episode' && this.item.seriesTitle.length > 0) {
        Text(this.item.seriesTitle + '  ›')
          .fontSize(15).fontColor(Theme.text2)
          .onClick(() => this.openSeries())
      }
      if (this.item.type === 'season' && this.item.seriesTitle.length > 0) {
        Text(this.item.seriesTitle + '  ›')
          .fontSize(15).fontColor(Theme.text2)
          .onClick(() => this.openSeries())
      }
      if (this.img(this.item, 'logo', 600).length > 0 && this.item.type !== 'episode') {
        Image(this.img(this.item, 'logo', 600))
          .height(this.large() ? 110 : 72)
          .width(this.large() ? 360 : '70%')
          .objectFit(ImageFit.Contain)
          .objectRepeat(ImageRepeat.NoRepeat)
      } else {
        Text(this.item.type === 'episode'
          ? episodeCode(this.item.seasonNumber, this.item.episodeNumber) + '  ' + this.item.title : this.item.title)
          .fontSize(this.large() ? 34 : 26).fontColor(Theme.text).fontWeight(FontWeight.Bold)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.item.originalTitle.length > 0 && this.item.originalTitle !== this.item.title) {
        Text(this.item.originalTitle).fontSize(14).fontColor(Theme.text2)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      Row({ space: 8 }) {
        if (this.item.rating > 0) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.star_fill')).fontSize(14).fontColor(['#FFC107'])
            Text(formatRating(this.item.rating)).fontSize(15).fontColor('#FFC107').fontWeight(FontWeight.Bold)
          }
        }
        Text(metaParts(this.item).join(' · ')).fontSize(14).fontColor(Theme.text2)
      }
      if (mediaBadges(this.item).length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(mediaBadges(this.item), (b: string) => {
            Text(b).fontSize(11).fontColor(Theme.text).fontWeight(FontWeight.Bold)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .border({ width: 1, color: Theme.text2, radius: 4 })
              .margin({ right: 6, bottom: 6 })
          }, (b: string) => b)
        }
      }
      if (this.item.genres.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.item.genres, (g: string) => {
            Column() {
              this.chip(genreLabel(g), true)
            }.margin({ right: 8, bottom: 8 })
          }, (g: string) => g)
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  buttons() {
    Column({ space: 10 }) {
      if (this.resumeFraction() > 0) {
        Progress({ value: this.resumeFraction() * 100, total: 100, type: ProgressType.Linear })
          .color(Theme.accent).backgroundColor('#33FFFFFF')
          .width(this.wide() ? 320 : '100%').height(4)
      }
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        Button() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.play_fill')).fontSize(20).fontColor([Color.Black])
            Text(this.playLabel()).fontSize(16).fontColor(Color.Black).fontWeight(FontWeight.Bold)
          }
          .justifyContent(FlexAlign.Center)
        }
        .type(ButtonType.Capsule)
        .height(50)
        .constraintSize({ minWidth: this.wide() ? 168 : 140 })
        .padding({ left: 28, right: 32 })
        .backgroundColor(Color.White)
        .shadow({ radius: 16, color: '#40000000', offsetY: 4 })
        .enabled(this.playable())
        .opacity(this.playable() ? 1 : 0.5)
        .margin({ right: 12, bottom: 12 })
        .onClick(() => this.play(false))

        if (this.canResume()) {
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(18).fontColor([Color.White])
              Text('从头播放').fontSize(15).fontColor(Color.White).fontWeight(FontWeight.Medium)
            }
          }
          .type(ButtonType.Capsule)
          .height(50).padding({ left: 20, right: 22 })
          .backgroundColor('#33FFFFFF')
          .border({ width: 1, color: '#33FFFFFF', radius: 25 })
          .margin({ right: 16, bottom: 12 })
          .onClick(() => this.play(true))
        }
        if (true) {
          // Flicx keeps these on this device (FlicxLibrary); servers store them in the user's account
          Column() {
            this.actionButton(this.played ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.checkmark'),
              this.played ? '已看' : '标记已看', this.played, () => {
                this.togglePlayed();
              })
          }.margin({ right: 8, bottom: 12 })
          Column() {
            this.actionButton(this.favorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
              this.favorite ? '已收藏' : '收藏', this.favorite, () => {
                this.toggleFavorite();
              })
          }.margin({ right: 8, bottom: 12 })
        }
        if (this.isQuark()) {
          Column() {
            this.actionButton($r('sys.symbol.arrow_clockwise'), '重新匹配', false, () => {
              this.rematchCtl.open();
            })
          }.margin({ right: 8, bottom: 12 })
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  overviewBlock() {
    Column({ space: 6 }) {
      if (this.item.overview.length > 0) {
        Text(this.item.overview)
          .fontSize(14).fontColor(Theme.text2).lineHeight(22)
          .maxLines(this.expanded ? 1000 : 3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => {
            this.expanded = !this.expanded;
          })
        if (this.item.overview.length > (this.wide() ? 160 : 70)) {
          Text(this.expanded ? '收起' : '更多')
            .fontSize(13).fontColor(Theme.accent)
            .onClick(() => {
              this.expanded = !this.expanded;
            })
        }
      } else {
        Text('暂无简介').fontSize(14).fontColor(Theme.text3)
      }
      if (this.item.studios.length > 0) {
        Text('出品：' + this.item.studios.join(' / '))
          .fontSize(12).fontColor(Theme.text3)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.item.premiereDate.length >= 10) {
        Text('首映：' + this.item.premiereDate.substring(0, 10)).fontSize(12).fontColor(Theme.text3)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  sectionTitle(t: string) {
    Text(t).fontSize(18).fontColor(Theme.text).fontWeight(FontWeight.Bold)
      .margin({ top: 8, bottom: 10 })
  }

  @Builder
  seasonsBlock() {
    Column() {
      this.sectionTitle(this.seasons.length > 0 ? '剧集' : '全部剧集')
      if (this.seasons.length > 1 || (this.seasons.length === 1 && this.item.type === 'series')) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.seasons, (s: MediaItem, i: number) => {
              Text(seasonLabel(s))
                .fontSize(14)
                .fontColor(i === this.seasonIdx ? Color.White : Theme.text2)
                .fontWeight(i === this.seasonIdx ? FontWeight.Bold : FontWeight.Normal)
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .borderRadius(18)
                .backgroundColor(i === this.seasonIdx ? Theme.accent : Theme.surface2)
                .onClick(() => {
                  this.selectSeason(i);
                })
            }, (s: MediaItem) => s.id)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .margin({ bottom: 12 })
      }
      if (this.epLoading) {
        Row() {
          LoadingProgress().width(32).height(32).color(Theme.accent)
        }.width('100%').height(120).justifyContent(FlexAlign.Center)
      } else if (this.epError.length > 0) {
        Column({ space: 8 }) {
          Text(this.epError).fontSize(13).fontColor(Theme.text2)
          Button('重试').height(36).backgroundColor(Theme.surface2).fontColor(Theme.text)
            .onClick(() => {
              if (this.seasons.length === 0 && this.provider) {
                this.loadSeasons(this.loadToken, this.provider, this.item, false);
              } else if (this.seasonIdx >= 0) {
                this.loadEpisodes(this.seasonIdx, false);
              } else {
                this.loadEpisodesFor('', false);
              }
            })
        }.width('100%').padding(16)
      } else if (this.episodes.length === 0) {
        Text('该季暂无剧集').fontSize(13).fontColor(Theme.text3).padding(16)
      } else {
        Column({ space: 4 }) {
          ForEach(this.episodes, (ep: MediaItem, i: number) => {
            EpisodeRow({
              ep: ep,
              thumbUrl: this.img(ep, 'thumb', 400),
              wide: this.wide(),
              current: i === this.targetEpIdx() || ep.id === this.itemId,
              onTap: () => this.playEpisode(i),
              onLong: () => {
                this.toggleEpisodePlayed(i);
              }
            })
          }, (ep: MediaItem) => ep.id + (ep.state.played ? '1' : '0') + ep.state.positionMs.toString())
        }
        .width('100%')
        if (this.wide()) {
          Text('长按剧集可切换已看状态').fontSize(11).fontColor(Theme.text3).margin({ top: 6 })
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  castBlock() {
    Column() {
      this.sectionTitle('演职人员')
      List({ space: 14 }) {
        ForEach(this.item.people, (p: Person) => {
          ListItem() {
            PersonAvatar({ person: p, avatarSize: this.wide() ? 84 : 68 })
          }
        }, (p: Person, i: number) => i.toString() + p.name)
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(this.wide() ? 140 : 122)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  similarBlock() {
    Column() {
      this.sectionTitle('相似推荐')
      List({ space: 12 }) {
        ForEach(this.similar, (m: MediaItem) => {
          ListItem() {
            DetailPosterCard({
              item: m,
              imageUrl: this.img(m, 'poster', 300),
              cardWidth: this.large() ? 150 : (this.wide() ? 130 : 110),
              onTap: () => Nav.detail(m.sourceId.length > 0 ? m.sourceId : this.sourceId, m.id)
            })
          }
        }, (m: MediaItem) => m.id)
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height((this.large() ? 150 : (this.wide() ? 130 : 110)) * 1.5 + 48)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  filesBlock() {
    Column({ space: 6 }) {
      this.sectionTitle('文件信息')
      ForEach(this.files, (f: LocalFile) => {
        Column({ space: 2 }) {
          Text(f.name.length > 0 ? f.name : f.path).fontSize(13).fontColor(Theme.text)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(f.path + '  ·  ' + formatSize(f.size)).fontSize(12).fontColor(Theme.text3)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%').padding(10).borderRadius(8)
        .backgroundColor(Theme.surface)
      }, (f: LocalFile) => f.fid)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  posterImage(w: number) {
    Stack() {
      if (this.img(this.item, this.item.type === 'episode' ? 'thumb' : 'poster', 500).length > 0) {
        Image(this.img(this.item, this.item.type === 'episode' ? 'thumb' : 'poster', 500))
          .width('100%').height('100%').objectFit(ImageFit.Cover)
      } else {
        Text(this.item.title.substring(0, 1)).fontSize(48).fontColor(Theme.text3)
      }
    }
    .width(w).height(this.item.type === 'episode' ? w * 9 / 16 : w * 1.5)
    .borderRadius(Theme.radius).clip(true)
    .backgroundColor(Theme.surface2)
    .shadow({ radius: 24, color: '#99000000', offsetY: 8 })
  }

  @Builder
  header() {
    if (this.wide()) {
      Row({ space: this.large() ? 36 : 24 }) {
        this.posterImage(this.large() ? 260 : 190)
        Column({ space: 16 }) {
          this.titleBlock()
          this.buttons()
          this.overviewBlock()
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .padding({ top: this.large() ? 160 : 120 })
    } else {
      Column({ space: 14 }) {
        this.titleBlock()
        this.buttons()
        this.overviewBlock()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: this.winWidth * 9 / 16 - 60 })
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.loading || this.error.length > 0) {
        this.stateView()
      } else {
        // Backdrop with scrim, fixed behind scrolling content.
        Stack() {
          if (this.img(this.item, 'backdrop', 1920).length > 0) {
            Image(this.img(this.item, 'backdrop', 1920))
              .width('100%').height('100%').objectFit(ImageFit.Cover)
          }
          Column()
            .width('100%').height('100%')
            .linearGradient({
              angle: 180,
              colors: [['#330B0D12', 0.0], ['#990B0D12', 0.5], [Theme.bg, 1.0]]
            })
        }
        .width('100%')
        .height(this.wide() ? '75%' : this.winWidth * 9 / 16 + 40)

        Scroll() {
          Column({ space: 24 }) {
            this.header()
            if (this.hasSeasons()) {
              this.seasonsBlock()
            }
            if (this.item.people.length > 0) {
              this.castBlock()
            }
            if (this.similar.length > 0) {
              this.similarBlock()
            }
            if (this.files.length > 0) {
              this.filesBlock()
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({
            left: this.large() ? 48 : Theme.pagePad,
            right: this.large() ? 48 : Theme.pagePad,
            bottom: 48
          })
        }
        .width('100%').height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)
      }
      this.backButton()
    }
    .width('100%').height('100%')
    .backgroundColor(Theme.bg)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .onAreaChange((oldV: Area, newV: Area) => {
      const w = Number(newV.width);
      if (w > 0 && w !== this.winWidth) {
        this.winWidth = w;
      }
    })
  }
}
