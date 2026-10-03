import { router } from '@kit.ArkUI';
import { apiService } from '../../network/ApiService';
import { accountStore } from '../../stores/AccountStore';
import { Illust } from '../../models/Illust';
import { getDbService } from '../../services/DatabaseService';
import { bookmarkSnapshotFromJsonString, BookmarkSnapshot } from '../../models/RelayModels';
import {
  IllustWaterfall,
  IllustListPage,
  parseIllustListPage,
  compareArrivalReverse
} from '../../components/illust/IllustWaterfall';
import { getStr } from '../../utils/I18nUtils';

/** 收藏排序模式：bookmarkDesc 默认（接口原始序）；仅存 @State 不持久化 */
type BookmarkSortMode = 'bookmarkDesc' | 'bookmarkAsc' | 'uploadDesc' | 'totalBookmarksDesc'

/** 判删走查分页上限（防超大收藏走查失控；超出按失败处理，不插入占位卡） */
const BOOKMARK_CLASSIFY_MAX_PAGES = 20

@Entry
@Component
struct BookmarkPage {
  @State restrict: string = 'public'
  @State reloadToken: number = 0
  @State loginError: string = ''
  @State sortMode: BookmarkSortMode = 'bookmarkDesc'
  @State compareToken: number = 0
  @State sortMenuShown: boolean = false
  /** 已确认删除的占位卡（后台走查完成后前置插入列表头部；restrict 切换时清空） */
  @State confirmedPlaceholders: Illust[] = []
  /** 本 Tab 走查是否已结束（成功/失败/超上限均置位，本轮会话不再重试，防 reload 循环） */
  private classifyDone: boolean = false
  private classifyRunning: boolean = false
  /** 走查代数：restrict 切换即递增，在途走查结果作废 */
  private classifyGen: number = 0
  /** 走查进行中收到的新走查请求（如切换 Tab 后的首屏），待当前走查结束后链式补跑 */
  private classifyPending: boolean = false
  private pendingNextUrl: string = ''
  private pendingApiIds: number[] = []

  aboutToAppear() {
    if (accountStore.getCurrentUserId() === 0) {
      this.loginError = getStr($r('app.string.bookmark_login_required'))
    }
  }

  private async fetchFirst(): Promise<IllustListPage> {
    let userId = accountStore.getCurrentUserId()
    if (userId === 0) {
      throw new Error(getStr($r('app.string.bookmark_login_required')))
    }
    let response = await apiService.getUserBookmarks(userId, this.restrict)
    let page = parseIllustListPage(response)
    if (this.confirmedPlaceholders.length > 0) {
      // 已确认删除的占位卡置于列表头部（API 列表无收藏时间戳，无法真实混排）；
      // 走查已结束（classifyDone=true），本轮不再触发走查，防 reload 循环
      page.illusts = this.confirmedPlaceholders.concat(page.illusts)
    } else if (!this.classifyDone) {
      // 后台走查全收藏列表确认缺席快照（fire-and-forget，占位卡延迟数秒出现属预期）
      this.startClassify(page.nextUrl, page.illusts.map((item: Illust) => item.id))
    }
    return page
  }

  /** 触发后台判删走查；已在走查中则登记待处理请求，走查结束后链式补跑（防请求丢失） */
  private startClassify(nextUrl: string, apiIds: number[]): void {
    if (this.classifyDone) {
      return
    }
    if (this.classifyRunning) {
      this.classifyPending = true
      this.pendingNextUrl = nextUrl
      this.pendingApiIds = apiIds
      return
    }
    this.classifyDeletedSnapshots(nextUrl, apiIds)
  }

  /**
   * 后台走查全收藏列表，确认"本地快照存在但 API 全列表缺席"的已删作品（R6 判删规则）：
   * ①快照候选按 restrict 匹配过滤（restrict 空串按 public 对待）并排除首屏已有 id；
   * ②复用 fetchNext 游标逐页走查（上限 20 页）收集全部 illust id；
   * ③完整走完（nextUrl 为空且未超上限）后差集确认 → 构造占位卡存 confirmedPlaceholders
   *   并 reloadToken++ 触发瀑布流重载（fetchFirst 届时前置插入）；
   * ④走查中途失败/超上限/restrict 切换 → 静默放弃不插入（宁漏勿误）。
   */
  private async classifyDeletedSnapshots(nextUrl: string, apiIds: number[]): Promise<void> {
    let gen = this.classifyGen
    this.classifyRunning = true
    try {
      let db = await getDbService()
      let rows = await db.getAliveBookmarkSnapshots()
      let candidates: BookmarkSnapshot[] = []
      for (let i = 0; i < rows.length; i++) {
        let snapshot: BookmarkSnapshot | null = bookmarkSnapshotFromJsonString(rows[i].data)
        if (snapshot === null) {
          continue
        }
        let snapshotRestrict = snapshot.restrict.length === 0 ? 'public' : snapshot.restrict
        if (snapshotRestrict !== this.restrict) {
          continue
        }
        if (apiIds.includes(snapshot.illustId)) {
          continue
        }
        candidates.push(snapshot)
      }
      if (candidates.length === 0) {
        return
      }
      let knownIds: Set<number> = new Set<number>()
      for (let i = 0; i < apiIds.length; i++) {
        knownIds.add(apiIds[i])
      }
      let url: string = nextUrl
      let pages = 0
      let complete = false
      while (pages < BOOKMARK_CLASSIFY_MAX_PAGES) {
        if (this.classifyGen !== gen) {
          break
        }
        if (url.length === 0) {
          complete = true
          break
        }
        let response = await apiService.fetchNext(url)
        let page = parseIllustListPage(response)
        for (let i = 0; i < page.illusts.length; i++) {
          knownIds.add(page.illusts[i].id)
        }
        url = page.nextUrl
        pages++
      }
      if (complete && this.classifyGen === gen) {
        let confirmed: Illust[] = []
        for (let i = 0; i < candidates.length; i++) {
          if (!knownIds.has(candidates[i].illustId)) {
            confirmed.push(this.buildDeletedPlaceholder(candidates[i]))
          }
        }
        // rows 已按收藏时间（updated_at）倒序，candidates 保持该顺序
        if (confirmed.length > 0) {
          this.confirmedPlaceholders = confirmed
          this.reloadToken++
        }
      }
    } catch (e) {
      // 走查中途失败（网络失败等）：静默放弃，不插入任何占位卡
      console.error('Classify deleted bookmark snapshots failed: ' + e)
    } finally {
      this.classifyRunning = false
      if (this.classifyGen !== gen) {
        // 走查期间发生 restrict 切换：本轮结果整体作废，不置 classifyDone（新 Tab 需重新走查）
        if (this.classifyPending) {
          let pendingNextUrl = this.pendingNextUrl
          let pendingApiIds = this.pendingApiIds
          this.classifyPending = false
          this.classifyDeletedSnapshots(pendingNextUrl, pendingApiIds)
        }
      } else {
        // 本轮会话内该 Tab 走查结束（成功确认/失败/超上限均不再重试）
        this.classifyDone = true
        this.classifyPending = false
      }
    }
  }

  /** 由快照构造"已删除"灰色占位伪 Illust（无图片 URL，IllustCard 走既有已删除显示） */
  private buildDeletedPlaceholder(snapshot: BookmarkSnapshot): Illust {
    return new Illust({
      id: snapshot.illustId,
      title: snapshot.title,
      pageCount: snapshot.pageCount,
      width: snapshot.width,
      height: snapshot.height,
      isBookmarked: true,
      isDeletedPlaceholder: true,
      user: { id: snapshot.userId, name: snapshot.userName }
    })
  }

  switchRestrict(restrict: string) {
    if (this.restrict === restrict) {
      return
    }
    this.restrict = restrict
    this.confirmedPlaceholders = []
    this.classifyDone = false
    this.classifyPending = false
    this.classifyGen++
    this.reloadToken++
  }

  private currentCompareFn(): ((a: Illust, b: Illust) => number) | undefined {
    if (this.sortMode === 'bookmarkAsc') {
      return compareArrivalReverse
    }
    if (this.sortMode === 'uploadDesc') {
      return (a: Illust, b: Illust): number => b.createDate.localeCompare(a.createDate)
    }
    if (this.sortMode === 'totalBookmarksDesc') {
      return (a: Illust, b: Illust): number => b.totalBookmarks - a.totalBookmarks
    }
    return undefined
  }

  private applySort(mode: BookmarkSortMode): void {
    if (this.sortMode === mode) {
      return
    }
    this.sortMode = mode
    this.compareToken++
  }

  @Builder
  SortMenuItem(label: string, action: () => void) {
    Text(label)
      .fontSize(14)
      .fontColor('#333333')
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .onClick(action)
  }

  @Builder
  SortMenuBuilder() {
    Column() {
      this.SortMenuItem(getStr($r('app.string.bookmark_sort_bookmark_desc')), () => { this.applySort('bookmarkDesc') })
      this.SortMenuItem(getStr($r('app.string.bookmark_sort_bookmark_asc')), () => { this.applySort('bookmarkAsc') })
      this.SortMenuItem(getStr($r('app.string.bookmark_sort_upload_desc')), () => { this.applySort('uploadDesc') })
      this.SortMenuItem(getStr($r('app.string.bookmark_sort_total_desc')), () => { this.applySort('totalBookmarksDesc') })
    }
    .width(180)
    .padding({ top: 4, bottom: 4 })
  }

  build() {
    Column() {
      Row() {
        Button($r('app.string.common_back'))
          .fontSize(14)
          .backgroundColor('#F5F5F5')
          .fontColor('#333333')
          .onClick(() => { router.back() })
        Text($r('app.string.bookmark_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text($r('app.string.bookmark_sort'))
          .fontSize(14)
          .fontColor('#0096FA')
          .width(60)
          .textAlign(TextAlign.End)
          .onClick(() => { this.sortMenuShown = true })
          .bindContextMenu(this.sortMenuShown, this.SortMenuBuilder, {
            onDisappear: () => { this.sortMenuShown = false }
          })
      }
      .width('100%')
      .height(48)
      .padding({ left: 8, right: 8 })
      .backgroundColor('#FFFFFF')

      Row() {
        Text($r('app.string.bookmark_public'))
          .fontSize(14)
          .fontColor(this.restrict === 'public' ? '#0096FA' : '#333333')
          .fontWeight(this.restrict === 'public' ? FontWeight.Bold : FontWeight.Normal)
          .padding({ left: 24, right: 24, top: 8, bottom: 8 })
          .onClick(() => { this.switchRestrict('public') })
        Text($r('app.string.bookmark_private'))
          .fontSize(14)
          .fontColor(this.restrict === 'private' ? '#0096FA' : '#333333')
          .fontWeight(this.restrict === 'private' ? FontWeight.Bold : FontWeight.Normal)
          .padding({ left: 24, right: 24, top: 8, bottom: 8 })
          .onClick(() => { this.switchRestrict('private') })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#FFFFFF')

      if (this.loginError) {
        Text(this.loginError)
          .fontSize(14)
          .fontColor('#999999')
          .margin({ top: 32 })
      } else {
        IllustWaterfall({
          fetchFirst: (): Promise<IllustListPage> => this.fetchFirst(),
          reloadToken: this.reloadToken,
          compareFn: this.currentCompareFn(),
          compareToken: this.compareToken
        })
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
