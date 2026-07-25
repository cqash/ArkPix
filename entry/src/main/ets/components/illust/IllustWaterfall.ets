import { router } from '@kit.ArkUI';
import { apiService } from '../../network/ApiService';
import { Illust } from '../../models/Illust';
import { AppSettings } from '../../models/AppSettings';
import { userSettingStore } from '../../stores/UserSettingStore';
import { bookmarkStateStore } from '../../stores/BookmarkStateStore';
import { MuteFilter } from '../../utils/MuteFilter';
import { IllustCard } from './IllustCard';
import { ErrorView, LoadingView } from '../common/CommonViews';

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
    router.pushUrl({ url: 'pages/detail/IllustDetailPage', params: { illustId: illust.id } })
  }
  /** 可选排序比较器：提供时入库数据按之排序；compareToken 变更触发已加载数据全量重排 */
  compareFn: ((a: Illust, b: Illust) => number) | undefined = undefined
  @Prop @Watch('onCompareTokenChange') compareToken: number = 0
  @Prop @Watch('onReloadTokenChange') reloadToken: number = 0
  @StorageLink('appSettings') @Watch('onSettingsChange') appSettings: AppSettings = new AppSettings()
  @State dataSource: IllustDataSource = new IllustDataSource()
  @State isRefreshing: boolean = false
  @State isInitialLoading: boolean = false
  @State errorMessage: string = ''
  @State footerState: FooterState = 'idle'
  private nextUrl: string = ''
  private loadingMore: boolean = false
  private seenIds: Set<number> = new Set<number>()
  private hasLoadedOnce: boolean = false
  private arrivalCounter: number = 0

  aboutToAppear() {
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
        this.errorMessage = '加载失败: ' + e
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
    this.dataSource.setItems([])
    await this.loadInitial()
    this.isRefreshing = false
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

  private refilter(): void {
    let settings = userSettingStore.getSettings()
    let kept = this.dataSource.items.filter((illust: Illust) => !MuteFilter.isMuted(illust, settings))
    if (kept.length !== this.dataSource.items.length) {
      this.dataSource.setItems(kept)
    }
  }

  @Builder
  FooterBuilder() {
    if (this.footerState === 'loading') {
      Row() {
        LoadingProgress()
          .width(20)
          .height(20)
          .color('#0096FA')
        Text('加载中...')
          .fontSize(12)
          .fontColor('#999999')
          .margin({ left: 8 })
      }
      .width('100%')
      .height(56)
      .justifyContent(FlexAlign.Center)
    } else if (this.footerState === 'noMore') {
      Row() {
        Text('没有更多了')
          .fontSize(12)
          .fontColor('#999999')
      }
      .width('100%')
      .height(56)
      .justifyContent(FlexAlign.Center)
    } else if (this.footerState === 'error') {
      Row() {
        Text('加载失败，点击重试')
          .fontSize(12)
          .fontColor('#0096FA')
      }
      .width('100%')
      .height(56)
      .justifyContent(FlexAlign.Center)
      .onClick(() => { this.loadMore() })
    } else {
      Row() {}
      .width('100%')
      .height(8)
    }
  }

  @Builder
  WaterfallContent() {
    WaterFlow({ footer: this.FooterBuilder() }) {
      LazyForEach(this.dataSource, (item: Illust) => {
        FlowItem() {
          IllustCard({
            illust: item,
            onCardClick: this.onCardClick,
            onMuteChange: () => { this.refilter() }
          })
        }
        .width('100%')
      }, (item: Illust) => item.id.toString())
    }
    .columnsTemplate('1fr '.repeat(this.appSettings.crossCount).trim())
    .columnsGap(4)
    .rowsGap(4)
    .padding(8)
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
    if (this.errorMessage && this.dataSource.totalCount() === 0) {
      ErrorView({ message: this.errorMessage, onRetry: () => { this.loadInitial() } })
    } else if (this.isInitialLoading && this.dataSource.totalCount() === 0) {
      LoadingView()
    } else if (this.enableRefresh) {
      Refresh({ refreshing: $$this.isRefreshing, offset: 64, friction: 100 }) {
        this.WaterfallContent()
      }
      .onRefreshing(() => { this.refresh() })
      .width('100%')
      .height('100%')
    } else {
      this.WaterfallContent()
    }
  }
}
