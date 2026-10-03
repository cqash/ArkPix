import { router } from '@kit.ArkUI';
import { IllustDetailPane } from '../../components/detail/IllustDetailPane';
import { continuationService } from '../../services/ContinuationService';
import { ContinuationPayload, CONTINUATION_PAGE_ILLUST_DETAIL } from '../../models/ContinuationPayload';
import { DetailListContextRegistry, DetailListContext } from '../../services/DetailListContextRegistry';
import { IllustListPage } from '../../components/illust/IllustWaterfall';
import { apiService } from '../../network/ApiService';
import { getDbService } from '../../services/DatabaseService';
import { userSettingStore } from '../../stores/UserSettingStore';
import { Illust } from '../../models/Illust';
import { pickDetailUrl } from '../../utils/ImageUrlUtils';
import { prefetchCachedImage } from '../../components/common/CachedImage';

interface RouteParams {
  illustId: number
  contextToken?: string
  contextIndex?: number
}

/** 详情接口响应（仅内部断言层使用，与 IllustDetailStore 同模式） */
interface IllustDetailResponse {
  illust: Object
}

/** 作品间滑动的 id 序列数据源（Swiper + LazyForEach；末尾预取追加经 onDataAdd 驱动） */
class DetailIdDataSource implements IDataSource {
  private listeners: DataChangeListener[] = []
  public items: number[] = []

  totalCount(): number {
    return this.items.length
  }

  getData(index: number): number {
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

  setItems(items: number[]): void {
    this.items = items
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded()
    })
  }

  appendItems(items: number[]): void {
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
 * 详情页壳：详情内容已抽取至 IllustDetailPane。
 * 无 contextToken（历史/深链/PID 直达等非列表入口）→ 单 Pane，行为与现状一致；
 * 有 contextToken（列表页进入）→ Swiper + LazyForEach 作品间左右滑动（cachedCount 1），
 * 滑至倒数第 2 项且有续页游标时自动预取，无更多数据时尾部追加 No More/加载/重试占位页。
 * 多端流转接续登记（当前作品 illustId）由本壳统一管理。
 */
@Entry
@Component
struct IllustDetailPage {
  @State illustId: number = 0
  @State currentIndex: number = 0
  @State hasMoreContext: boolean = false
  /** 末尾预取失败态（尾部占位页显示"加载失败，点击重试"） */
  @State prefetchError: boolean = false
  private dataSource: DetailIdDataSource = new DetailIdDataSource()
  private contextToken: string = ''
  private prefetching: boolean = false
  /** R7：已预取（含在途）的作品 id，会话级去重防重复请求；失败时移除允许下次触发重试 */
  private neighborPrefetchedIds: Set<number> = new Set<number>()
  /** R7：相邻预取代数，每次触发递增；在途预取检测到代数变化即中止（快速连滑防请求堆积） */
  private prefetchGen: number = 0

  aboutToAppear() {
    let params = router.getParams() as RouteParams
    if (!params || !params.illustId) {
      return
    }
    this.illustId = params.illustId
    if (params.contextToken !== undefined && params.contextToken.length > 0) {
      let ctx = DetailListContextRegistry.get(params.contextToken)
      if (ctx !== null && ctx.ids.length > 0) {
        this.contextToken = params.contextToken
        this.dataSource.setItems(ctx.ids.slice())
        this.hasMoreContext = ctx.nextUrl.length > 0
        let idx = params.contextIndex !== undefined ? params.contextIndex : ctx.ids.indexOf(params.illustId)
        if (idx < 0 || idx >= ctx.ids.length) {
          idx = 0
        }
        this.currentIndex = idx
      }
    }
    // 多端流转：登记当前页面状态（供 onContinue 构建接续载荷）
    this.registerContinuation(this.currentIllustId())
  }

  aboutToDisappear() {
    continuationService.setCurrentPageState(null)
  }

  private currentIllustId(): number {
    if (this.dataSource.totalCount() > 0 && this.currentIndex < this.dataSource.totalCount()) {
      return this.dataSource.getData(this.currentIndex)
    }
    return this.illustId
  }

  private registerContinuation(illustId: number): void {
    continuationService.setCurrentPageState(new ContinuationPayload({
      page: CONTINUATION_PAGE_ILLUST_DETAIL,
      illustId: illustId
    }))
  }

  private onSwiperChange(index: number): void {
    this.currentIndex = index
    if (index < this.dataSource.totalCount()) {
      this.registerContinuation(this.dataSource.getData(index))
    }
    // 末尾预取：滑至倒数第 2 项且仍有续页游标
    if (this.hasMoreContext && index >= this.dataSource.totalCount() - 2) {
      this.prefetchNext()
    }
  }

  /** 末尾预取下一批：经上下文 fetchNext 闭包拉取，追加 ids 到 Registry 与本页数据源 */
  private async prefetchNext(): Promise<void> {
    if (this.prefetching || this.contextToken.length === 0 || !this.hasMoreContext) {
      return
    }
    let ctx = DetailListContextRegistry.get(this.contextToken)
    if (ctx === null || ctx.nextUrl.length === 0) {
      return
    }
    this.prefetching = true
    this.prefetchError = false
    try {
      let page: IllustListPage = await ctx.fetchNext(ctx.nextUrl)
      DetailListContextRegistry.append(this.contextToken, page)
      let newIds: number[] = []
      for (let i = 0; i < page.illusts.length; i++) {
        newIds.push(page.illusts[i].id)
      }
      this.dataSource.appendItems(newIds)
      this.hasMoreContext = page.nextUrl.length > 0
    } catch (e) {
      console.error('Detail list prefetch failed: ' + e)
      this.prefetchError = true
    } finally {
      this.prefetching = false
    }
  }

  private showTailSlide(): boolean {
    // 尾部占位：预取中（转圈）/ 预取失败（重试）/ 无更多（No More），对齐 pixez PictureListNextPage 三态
    return this.dataSource.totalCount() > 0 && (this.prefetching || this.prefetchError || !this.hasMoreContext)
  }

  /**
   * R7：当前作品详情加载完成后，对相邻 ±1 作品（与 cachedCount 深度对齐）静默预取：
   * DB 详情缓存 + 当前 detailQuality 档位首图，滑动激活时直接命中秒出。
   * 仅 contextToken（列表入口）模式启用；单作品模式直接返回。
   * 红线：预取绝不走 IllustDetailStore.load()（会写浏览历史污染未看过的作品），
   * 也不播种收藏注册表、不产生任何用户可见副作用（toast/状态变更）。
   */
  private prefetchNeighbors(index: number): void {
    if (this.contextToken.length === 0 || this.dataSource.totalCount() === 0) {
      return
    }
    this.prefetchGen++
    let gen = this.prefetchGen
    if (index - 1 >= 0) {
      this.prefetchOne(this.dataSource.getData(index - 1), gen)
    }
    if (index + 1 < this.dataSource.totalCount()) {
      this.prefetchOne(this.dataSource.getData(index + 1), gen)
    }
  }

  /**
   * 单个相邻作品预取（fire-and-forget）：
   * DB 缓存命中 → 仅补首图预取；未命中 → getIllustDetail → 解析校验 → 落 DB 缓存 → 首图预取。
   * 每个 await 后校验代数，快速连滑时旧预取中止；异常/无效数据静默放弃并移出去重集允许重试。
   */
  private async prefetchOne(id: number, gen: number): Promise<void> {
    if (id <= 0 || this.neighborPrefetchedIds.has(id)) {
      return
    }
    this.neighborPrefetchedIds.add(id)
    try {
      let db = await getDbService()
      if (gen !== this.prefetchGen) {
        console.info('Prefetch neighbor aborted: ' + id + ' gen=' + gen)
        return
      }
      let cached = await db.getIllustDetailCache(id)
      if (gen !== this.prefetchGen) {
        console.info('Prefetch neighbor aborted: ' + id + ' gen=' + gen)
        return
      }
      let illust: Illust = new Illust()
      let ready = false
      if (cached) {
        let rawCached = (JSON.parse(cached) as IllustDetailResponse).illust
        if (rawCached) {
          let parsed = Illust.fromJson(rawCached)
          if (parsed.id && parsed.title) {
            illust = parsed
            ready = true
          }
        }
      }
      if (!ready) {
        let response = await apiService.getIllustDetail(id)
        if (gen !== this.prefetchGen) {
          console.info('Prefetch neighbor aborted: ' + id + ' gen=' + gen)
          return
        }
        let raw = (response as IllustDetailResponse).illust
        let parsed = raw ? Illust.fromJson(raw) : new Illust()
        if (!raw || !parsed.id || !parsed.title) {
          // 解析失败/无效数据：静默放弃，移出去重集允许下次触发重试
          this.neighborPrefetchedIds.delete(id)
          return
        }
        illust = parsed
        await db.setIllustDetailCache(id, JSON.stringify(response as object))
        if (gen !== this.prefetchGen) {
          console.info('Prefetch neighbor aborted: ' + id + ' gen=' + gen)
          return
        }
      }
      // 首图预取：档位必须取当前 detailQuality 设置（与详情图行一致），否则激活时不命中
      console.info('Prefetch neighbor ok: ' + id + (ready ? ' (cache)' : ' (api)'))
      prefetchCachedImage(pickDetailUrl(illust, 0, userSettingStore.getSettings().detailQuality))
    } catch (e) {
      console.error('Prefetch neighbor detail failed: ' + e)
      this.neighborPrefetchedIds.delete(id)
    }
  }

  @Builder
  TailSlide() {
    Column() {
      if (this.prefetching) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color('#0096FA')
        Text($r('app.string.common_loading'))
          .fontSize(13)
          .fontColor('#999999')
          .margin({ top: 12 })
      } else if (this.prefetchError) {
        Text($r('app.string.waterfall_load_failed_retry'))
          .fontSize(14)
          .fontColor('#0096FA')
          .padding({ left: 24, right: 24, top: 10, bottom: 10 })
          .onClick(() => {
            this.hasMoreContext = true
            this.prefetchNext()
          })
      } else {
        Text($r('app.string.waterfall_no_more'))
          .fontSize(14)
          .fontColor('#999999')
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F5F5F5')
  }

  build() {
    if (this.dataSource.totalCount() === 0) {
      // 非列表入口：单 Pane，行为与现状一致（prefetchNeighbors 内部按 contextToken 短路，不预取）
      IllustDetailPane({
        illustId: this.illustId,
        isActive: true,
        onDetailLoaded: () => {
          this.prefetchNeighbors(this.currentIndex)
        }
      })
    } else {
      Swiper() {
        LazyForEach(this.dataSource, (id: number, index: number) => {
          IllustDetailPane({
            illustId: id,
            isActive: index === this.currentIndex,
            onDetailLoaded: () => {
              this.prefetchNeighbors(this.currentIndex)
            }
          })
        }, (id: number) => id.toString())
        if (this.showTailSlide()) {
          this.TailSlide()
        }
      }
      .index(this.currentIndex)
      .cachedCount(1)
      .loop(false)
      .indicator(false)
      .onChange((index: number) => { this.onSwiperChange(index) })
      .width('100%')
      .height('100%')
    }
  }
}
