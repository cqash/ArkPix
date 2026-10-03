import { router } from '@kit.ArkUI';
import { apiService } from '../../network/ApiService';
import { Illust } from '../../models/Illust';
import { AppSettings } from '../../models/AppSettings';
import { userSettingStore } from '../../stores/UserSettingStore';
import { bookmarkStateStore, BOOKMARK_LOADING, BOOKMARK_DONE } from '../../stores/BookmarkStateStore';
import { BookmarkTagPanel } from './BookmarkTagPanel';
import { MuteFilter } from '../../utils/MuteFilter';
import { IllustCard } from './IllustCard';
import { ErrorView, LoadingView } from '../common/CommonViews';
import { getStrf } from '../../utils/I18nUtils';
import { DetailListContextRegistry, DetailListContext } from '../../services/DetailListContextRegistry';

/** 分页数据包：各列表页 fetchFirst 回调的返回类型 */
export interface IllustListPage {
  illusts: Illust[]
  nextUrl: string
}

interface RawIllustListResponse {
  illusts?: Object[]
  next_url?: string
}

/** 解析 Pixiv 列表接口统一结构（illusts + next_url） */
export function parseIllustListPage(response: Object): IllustListPage {
  let raw = response as RawIllustListResponse
  let illusts = (raw.illusts ?? []).map((item: Object) => Illust.fromJson(item))
  let page: IllustListPage = { illusts: illusts, nextUrl: raw.next_url ?? '' }
  return page
}

export type FooterState = 'idle' | 'loading' | 'noMore' | 'error'

/** 插画入库到达顺序（接口原始顺序）：用于"收藏时间 旧→新"等到达序排序 */
const arrivalSeqMap: WeakMap<Illust, number> = new WeakMap<Illust, number>()

/** 到达顺序反转比较器：收藏页"收藏时间 旧→新"排序（到达顺序即接口的收藏新→旧） */
export function compareArrivalReverse(a: Illust, b: Illust): number {
  let sa = arrivalSeqMap.get(a) ?? 0
  let sb = arrivalSeqMap.get(b) ?? 0
  return sb - sa
}

class IllustDataSource implements IDataSource {
  private listeners: DataChangeListener[] = []
  public items: Illust[] = []

  totalCount(): number {
    return this.items.length
  }

  getData(index: number): Illust {
    return this.items[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    let pos = this.listeners.indexOf(listener)
    if (pos >= 0) {
      this.listeners.splice(pos, 1)
    }
  }

  setItems(items: Illust[]): void {
    this.items = items
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded()
    })
  }

  appendItems(items: Illust[]): void {
    if (items.length === 0) {
      return
    }
    let start = this.items.length
    this.items = this.items.concat(items)
    for (let i = 0; i < items.length; i++) {
      let index = start + i
      this.listeners.forEach((listener: DataChangeListener) => {
        listener.onDataAdd(index)
      })
    }
  }
}

/**
 * 可复用瀑布流容器：WaterFlow + LazyForEach + 预计算卡片高度（内容驱动）。
 * 内聚分页状态机（idle/loading/noMore/error，防重入，按 id 去重）、
 * 触底前预加载、Refresh 下拉刷新、MuteFilter 过滤、收藏注册表播种。
 */
@Component
export struct IllustWaterfall {
  fetchFirst: () => Promise<IllustListPage> = async (): Promise<IllustListPage> => {
    let empty: IllustListPage = { illusts: [], nextUrl: '' }
    return empty
  }
  enableRefresh: boolean = true
  onCardClick: (illust: Illust) => void = (illust: Illust) => {
    // 列表进入详情：先注册作品间滑动上下文（当前已加载 id 序列 + 续页游标 + 续页闭包），
    // 再 pushUrl 传轻量标量（illustId/contextToken/contextIndex），详情页据此启用 Swiper 滑动切换
    let ids: number[] = []
    for (let i = 0; i < this.dataSource.totalCount(); i++) {
      ids.push(this.dataSource.getData(i).id)
    }
    let index = ids.indexOf(illust.id)
    let ctx: DetailListContext = {
      ids: ids,
      nextUrl: this.nextUrl,
      fetchNext: (nextUrl: string): Promise<IllustListPage> => this.fetchNextForContext(nextUrl)
    }
    let token = DetailListContextRegistry.register(ctx)
    router.pushUrl({
      url: 'pages/detail/IllustDetailPage',
      params: { illustId: illust.id, contextToken: token, contextIndex: index }
    })
  }
  /** 可选排序比较器：提供时入库数据按之排序；compareToken 变更触发已加载数据全量重排 */
  compareFn: ((a: Illust, b: Illust) => number) | undefined = undefined
  /** 卡片星标长按上抛（可选；缺省时容器内自建 BookmarkTagPanel 宿主） */
  onStarLongPress: ((illust: Illust) => void) | undefined = undefined
  /**
   * 可选冷启动缓存源（如 RecomPage 的 recommend_cache）：命中时先渲染缓存内容，
   * 再自动后台刷新（顶部药丸旋转），避免慢网下全屏 LoadingView；返回 null 表示无缓存
   */
  fetchCached: (() => Promise<IllustListPage | null>) | undefined = undefined
  /** 底部额外留白 vp（如首页悬浮胶囊底栏遮挡区，让末行内容可滚动到胶囊上方）；默认 0；由 footer 高度承载，勿改用 WaterFlow padding（会在底部裁出永久空白带挡住胶囊沉浸背景） */
  bottomInset: number = 0
  @Prop @Watch('onCompareTokenChange') compareToken: number = 0
  @Prop @Watch('onReloadTokenChange') reloadToken: number = 0
  /** 回顶令牌（底栏 Tab 再点广播）：值变更即 scrollEdge(Top) */
  @Prop @Watch('onScrollTopTokenChange') scrollTopToken: number = 0
  @StorageLink('appSettings') @Watch('onSettingsChange') appSettings: AppSettings = new AppSettings()
  @State dataSource: IllustDataSource = new IllustDataSource()
  @State isRefreshing: boolean = false
  /** 刷新状态机（onStateChange 同步）：驱动顶部小药丸显隐与进度环/菊花形态切换 */
  @State refreshState: RefreshStatus = RefreshStatus.Inactive
  /** 下拉偏移 vp（onOffsetChange 同步）：驱动下拉中的环形进度值 */
  @State refreshPullOffset: number = 0
  @State isInitialLoading: boolean = false
  @State errorMessage: string = ''
  @State footerState: FooterState = 'idle'
  private nextUrl: string = ''
  private loadingMore: boolean = false
  private seenIds: Set<number> = new Set<number>()
  private hasLoadedOnce: boolean = false
  private arrivalCounter: number = 0
  private scroller: Scroller = new Scroller()
  /** 带标签收藏面板宿主态（星标长按缺省入口） */
  @State tagPanelShown: boolean = false
  @State tagPanelIllust: Illust = new Illust()

  aboutToAppear() {
    this.loadInitialWithCache()
  }

  /**
   * 冷启动入口：fetchCached 命中缓存 → 先渲染缓存（走 acceptPage 的屏蔽过滤/收藏播种），
   * 再 refresh() 后台刷新（保留缓存内容+顶部药丸指示）；未提供/未命中 → 原全量加载路径
   */
  private async loadInitialWithCache(): Promise<void> {
    if (this.fetchCached !== undefined) {
      try {
        let cached = await this.fetchCached()
        if (cached !== null && cached.illusts.length > 0) {
          this.acceptPage(cached, true)
          this.hasLoadedOnce = true
          this.refresh()
          return
        }
      } catch (e) {
        console.error('Waterfall cache load failed, fallback to network: ' + e)
      }
    }
    this.loadInitial()
  }

  onReloadTokenChange() {
    if (this.hasLoadedOnce) {
      this.refresh()
    }
  }

  onSettingsChange() {
    this.refilter()
  }

  onScrollTopTokenChange() {
    this.scroller.scrollEdge(Edge.Top)
  }

  onCompareTokenChange() {
    if (this.compareFn !== undefined && this.dataSource.totalCount() > 0) {
      this.dataSource.setItems(this.sortItems(this.dataSource.items))
    }
  }

  private sortItems(items: Illust[]): Illust[] {
    let cmp = this.compareFn
    if (cmp === undefined) {
      return items
    }
    let fn: (a: Illust, b: Illust) => number = cmp
    let copy = items.slice()
    copy.sort((a: Illust, b: Illust) => fn(a, b))
    return copy
  }

  private async loadInitial(): Promise<void> {
    if (this.isInitialLoading) {
      return
    }
    this.isInitialLoading = true
    this.errorMessage = ''
    try {
      let page = await this.fetchFirst()
      this.acceptPage(page, true)
    } catch (e) {
      if (this.dataSource.totalCount() === 0) {
        this.errorMessage = getStrf($r('app.string.common_load_failed_detail'), String(e))
      }
      console.error('Waterfall first page failed: ' + e)
    } finally {
      this.isInitialLoading = false
    }
    this.hasLoadedOnce = true
  }

  private acceptPage(page: IllustListPage, reset: boolean): void {
    bookmarkStateStore.seedFromList(page.illusts)
    let settings = userSettingStore.getSettings()
    let fresh: Illust[] = []
    for (let i = 0; i < page.illusts.length; i++) {
      let illust = page.illusts[i]
      if (MuteFilter.isMuted(illust, settings)) {
        continue
      }
      if (this.seenIds.has(illust.id)) {
        continue
      }
      this.seenIds.add(illust.id)
      arrivalSeqMap.set(illust, this.arrivalCounter++)
      fresh.push(illust)
    }
    this.nextUrl = page.nextUrl
    this.footerState = this.nextUrl.length > 0 ? 'idle' : 'noMore'
    if (reset) {
      this.dataSource.setItems(this.sortItems(fresh))
    } else if (this.compareFn === undefined) {
      this.dataSource.appendItems(fresh)
    } else {
      // 本地排序语义：分页追加后对已加载数据全量重排，保证全局有序
      this.dataSource.setItems(this.sortItems(this.dataSource.items.concat(fresh)))
    }
  }

  private async refresh(): Promise<void> {
    this.isRefreshing = true
    this.seenIds.clear()
    this.nextUrl = ''
    this.footerState = 'idle'
    // 刷新期间保留旧列表内容（不清空），避免触发 isInitialLoading+空数据 的全屏 LoadingView；
    // 新数据到达后由 acceptPage(reset=true) 整体替换；失败时保留旧内容不打扰用户
    await this.loadInitial()
    this.isRefreshing = false
  }

  /** 详情页末尾预取用的续页闭包：拉取下一页并套用与列表一致的 MuteFilter 过滤 */
  private async fetchNextForContext(nextUrl: string): Promise<IllustListPage> {
    let response = await apiService.fetchNext(nextUrl)
    let page = parseIllustListPage(response)
    let settings = userSettingStore.getSettings()
    let fresh: Illust[] = []
    for (let i = 0; i < page.illusts.length; i++) {
      let illust = page.illusts[i]
      if (MuteFilter.isMuted(illust, settings)) {
        continue
      }
      if (this.seenIds.has(illust.id)) {
        continue
      }
      this.seenIds.add(illust.id)
      fresh.push(illust)
    }
    let filtered: IllustListPage = { illusts: fresh, nextUrl: page.nextUrl }
    return filtered
  }

  private async loadMore(): Promise<void> {
    if (this.loadingMore || this.isInitialLoading) {
      return
    }
    if (this.nextUrl.length === 0) {
      if (this.dataSource.totalCount() > 0) {
        this.footerState = 'noMore'
      }
      return
    }
    this.loadingMore = true
    this.footerState = 'loading'
    try {
      let response = await apiService.fetchNext(this.nextUrl)
      let page = parseIllustListPage(response)
      this.acceptPage(page, false)
    } catch (e) {
      this.footerState = 'error'
      console.error('Waterfall load more failed: ' + e)
    } finally {
      this.loadingMore = false
    }
  }

  /** 星标长按：已收藏/请求中不响应；外部回调优先，否则开容器内建面板 */
  private handleStarLongPress(illust: Illust): void {
    let state = bookmarkStateStore.stateOf(illust.id, illust.isBookmarked)
    if (state === BOOKMARK_DONE || state === BOOKMARK_LOADING) {
      return
    }
    let external = this.onStarLongPress
    if (external !== undefined) {
      external(illust)
      return
    }
    this.tagPanelIllust = illust
    this.tagPanelShown = true
  }

  private refilter(): void {
    let settings = userSettingStore.getSettings()
    let kept = this.dataSource.items.filter((illust: Illust) => !MuteFilter.isMuted(illust, settings))
    if (kept.length !== this.dataSource.items.length) {
      this.dataSource.setItems(kept)
    }
  }

  @Builder
  FooterBuilder() {
    // bottomInset 加在 footer 高度里而非 WaterFlow padding：padding 会把内容裁剪在 padding 盒内，
    // 底部留下一条永久空白带（透出页面底色）挡住悬浮胶囊底栏的沉浸背景；footer 属于滚动内容，
    // 滚动中卡片可一直流到胶囊后方，仅在列表到底时留出空白避让区
    if (this.footerState === 'loading') {
      Row() {
        LoadingProgress()
          .width(20)
          .height(20)
          .color('#0096FA')
        Text($r('app.string.common_loading'))
          .fontSize(12)
          .fontColor('#999999')
          .margin({ left: 8 })
      }
      .width('100%')
      .height(56 + this.bottomInset)
      .justifyContent(FlexAlign.Center)
    } else if (this.footerState === 'noMore') {
      Row() {
        Text($r('app.string.waterfall_no_more'))
          .fontSize(12)
          .fontColor('#999999')
      }
      .width('100%')
      .height(56 + this.bottomInset)
      .justifyContent(FlexAlign.Center)
    } else if (this.footerState === 'error') {
      Row() {
        Text($r('app.string.waterfall_load_failed_retry'))
          .fontSize(12)
          .fontColor('#0096FA')
      }
      .width('100%')
      .height(56 + this.bottomInset)
      .justifyContent(FlexAlign.Center)
      .onClick(() => { this.loadMore() })
    } else {
      Row() {}
      .width('100%')
      .height(8 + this.bottomInset)
    }
  }

  @Builder
  FlowItems() {
    LazyForEach(this.dataSource, (item: Illust) => {
      FlowItem() {
        IllustCard({
          illust: item,
          onCardClick: this.onCardClick,
          onMuteChange: () => { this.refilter() },
          onStarLongPress: (target: Illust) => { this.handleStarLongPress(target) }
        })
      }
      .width('100%')
    }, (item: Illust) => item.id.toString())
  }

  /**
   * 顶部刷新指示（小药丸：下拉中环形进度 / 刷新中旋转菊花）。
   * 作为 Refresh 自定义 builder 渲染在列表上方腾出的刷新区域内，随下拉距离展开/收回。
   * clip + constraintSize 防高度塌缩（官方 Refresh 文档示例 6 模式）。
   */
  @Builder
  RefreshIndicator() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.refreshState !== RefreshStatus.Inactive && this.refreshState !== RefreshStatus.Done) {
        Row() {
          Progress({ value: this.refreshPullOffset, total: 64, type: ProgressType.Ring })
            .width(32)
            .height(32)
            .style({ status: this.refreshState === RefreshStatus.Refresh ? ProgressStatus.LOADING : ProgressStatus.PROGRESSING })
            .color('#0096FA')
        }
        .width(48)
        .height(48)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#CCFFFFFF')
        .borderRadius(24)
      }
    }
    .clip(true)
    .constraintSize({ minHeight: 48 })
    .width('100%')
  }

  /** 瀑布流内容（Refresh 分支与旁路分支共用）。 */
  @Builder
  WaterfallContent() {
    WaterFlow({ footer: this.FooterBuilder(), scroller: this.scroller }) {
      this.FlowItems()
    }
    .columnsTemplate('1fr '.repeat(this.appSettings.crossCount).trim())
    .columnsGap(4)
    .rowsGap(4)
    .padding({ left: 8, right: 8, top: 8 })
    .width('100%')
    .height('100%')
    .onReachEnd(() => { this.loadMore() })
    .onScrollIndex((first: number, last: number) => {
      if (last + 6 >= this.dataSource.totalCount()) {
        this.loadMore()
      }
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.errorMessage && this.dataSource.totalCount() === 0) {
        ErrorView({ message: this.errorMessage, onRetry: () => { this.loadInitial() } })
      } else if (this.isInitialLoading && this.dataSource.totalCount() === 0) {
        LoadingView()
      } else if (this.enableRefresh) {
        // 经典下拉布局：列表随下拉整体下移腾出顶部刷新区，小药丸渲染在刷新区内（不再悬浮/垫底）；
        // 刷新中上滑浏览时 pullUpToCancelRefresh（默认 true）自动取消收回
        Refresh({ refreshing: $$this.isRefreshing, builder: this.RefreshIndicator() }) {
          this.WaterfallContent()
        }
        .refreshOffset(64)
        .maxPullDownDistance(96)
        .pullToRefresh(true)
        .pullUpToCancelRefresh(true)
        .onStateChange((state: RefreshStatus) => { this.refreshState = state })
        .onOffsetChange((offset: number) => { this.refreshPullOffset = offset })
        .onRefreshing(() => { this.refresh() })
        .width('100%')
        .height('100%')
      } else {
        this.WaterfallContent()
      }

      // 带标签收藏面板（卡片星标长按缺省宿主；内联底部弹层）
      BookmarkTagPanel({
        visible: this.$tagPanelShown,
        onConfirm: (tags: string[], restrict: string) => {
          bookmarkStateStore.star(this.tagPanelIllust, restrict, tags)
        },
        onCancel: () => {}
      })
    }
    .width('100%')
    .height('100%')
  }
}
