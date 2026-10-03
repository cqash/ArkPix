import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { CaptionSegment, parseCaptionHtml, captionToPlainText } from '../../utils/CaptionParser';
import { PixivLinkParser } from '../../utils/PixivLinkParser';
import { imageCacheService } from '../../services/ImageCacheService';
import { getDbService, DatabaseService } from '../../services/DatabaseService';
import { apiService } from '../../network/ApiService';
import { buildLocalSuggestions } from '../../utils/MergeSuggest';
import { Illust, Tag } from '../../models/Illust';
import { AppSettings } from '../../models/AppSettings';
import { userSettingStore } from '../../stores/UserSettingStore';
import { BOOKMARK_LOADING, BOOKMARK_DONE } from '../../stores/BookmarkStateStore';
import { IllustDetailStore, DetailRow, RECOVER_STATE_IDLE, RECOVER_STATE_POLLING, RECOVER_STATE_READY }
  from '../../stores/IllustDetailStore';
import { BookmarkSnapshot } from '../../models/RelayModels';
import { Constants } from '../../utils/Constants';
import { copyText } from '../../utils/ClipboardUtils';
import { formatCreateDate } from '../../utils/DateUtils';
import { buildPageUrls } from '../../utils/ImageUrlUtils';
import { CachedImage } from '../common/CachedImage';
import { UgoiraPlayer } from '../illust/UgoiraPlayer';
import { IllustCard } from '../illust/IllustCard';
import { ErrorView, LoadingView } from '../common/CommonViews';
import { MuteFilter } from '../../utils/MuteFilter';
import {
  ExifTag,
  ExifInfo,
  filterTagsForExif,
  isCommentOverLimit,
  renderCommentWithTags,
  renderCommentBytes,
  utf8ByteLength,
  EXIF_FIELD_MAX_BYTES,
  findUnresolvedMergeGroups,
  MergeGroup
} from '../../services/ImageExifService';
import { getStr, getStrf } from '../../utils/I18nUtils';
import { HapticUtils } from '../../utils/HapticUtils';
import { BookmarkTagPanel } from '../illust/BookmarkTagPanel';
import { FollowButton } from '../common/FollowButton';
import { IllustListPage, parseIllustListPage } from '../illust/IllustWaterfall';
import { DetailListContextRegistry, DetailListContext } from '../../services/DetailListContextRegistry';
import { MaterialFab } from '../common/MaterialFab';

interface ExifPickerItem {
  name: string
  translatedName: string
  checked: boolean
  withinBudget: boolean
}

/** /v2/search/autocomplete 响应 tags[] 元素 */
interface RawAutoCompleteTag {
  name?: string
  translated_name?: string
}

interface RawAutoCompleteResponse {
  tags?: Object[]
}

/**
 * 详情内容面板（自 IllustDetailPage 抽取，供单页与 Swiper 作品间滑动两种模式复用）：
 * 承载图片行/信息行/相关作品/双 FAB/EXIF Picker/合并审查/选页弹窗/画师行菜单/带标签收藏面板全套。
 * 每实例独立 new IllustDetailStore()；isActive=true 才加载数据（Swiper 懒加载）；
 * 接续登记由宿主壳（IllustDetailPage）统一管理。
 * US6：命中屏蔽规则的作品整页替换为占位视图（临时查看仅组件内存态，会话级）。
 */
@Component
export struct IllustDetailPane {
  @Prop illustId: number = 0
  @Prop @Watch('onActiveChange') isActive: boolean = true
  private store: IllustDetailStore = new IllustDetailStore()
  @State illust: Illust = new Illust()
  @State rows: DetailRow[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  /** US6：屏蔽占位"临时查看"（组件内存态，仅本次会话） */
  @State tempRevealed: boolean = false
  private loadStarted: boolean = false
  /** R7：详情加载成功（store.load 返回 true）后通知宿主壳，用于触发相邻作品预取；未传入时不调用 */
  onDetailLoaded: (() => void) | undefined = undefined
  @State deletedSnapshot: BookmarkSnapshot | null = null
  @State recoverState: string = RECOVER_STATE_IDLE
  @State recoverProgressText: string = ''
  @State userAvatarPath: string = ''
  @State revealedR18: boolean = false
  /** 画师行三态关注按钮态（详情接口 user.is_followed 初始化） */
  @State authorFollowed: boolean = false
  @State bookmarkTagPanelShown: boolean = false
  @State authorMenuShown: boolean = false
  /** R4：简介富文本分段（loadDetail 后由 caption 解析，空数组不渲染简介行） */
  @State captionSegments: CaptionSegment[] = []
  /** R4：顶栏 ⋮ 溢出菜单可见性 */
  @State topMenuShown: boolean = false
  /** R4：相关作品是否还有续页（触底自动加载 + 手动按钮兜底门控） */
  @State hasMoreRelated: boolean = false
  @State tagMenuShown: boolean = false
  @State tagMenuTarget: string = ''
  @State saveMenuShown: boolean = false
  @State saveMenuPageIndex: number = 0
  @State mergeDialogShown: boolean = false
  @State mergeFromTag: string = ''
  @State mergeInputText: string = ''
  /** 合并对话框补全建议（名称 + 对齐的翻译副标题），输入为空时不显示 */
  @State mergeSuggestions: string[] = []
  @State mergeSuggestionSubs: string[] = []
  private mergeSuggestTimer: number = -1
  @State exifPickerShown: boolean = false
  /** EXIF Picker 确认/跳过后续走的页集合（单页=[index]，全部=全集，选页=子集） */
  @State exifPickerPendingPages: number[] = []
  @State exifPickerWritableItems: ExifPickerItem[] = []
  @State exifPickerMutedItems: ExifPickerItem[] = []
  @State exifPickerPreviewText: string = ''
  @State exifPickerPreviewBytes: number = 0
  @State exifPickerMuteConfirmTarget: string = ''
  @State mergeReviewShown: boolean = false
  @State mergeReviewGroups: MergeGroup[] = []
  @State mergeReviewSelected: string[] = []  // 每组选中的主 tag 名
  // 选页弹窗状态
  @State pageSelectShown: boolean = false
  @State pageSelectChecked: boolean[] = []
  private pageSelectThumbUrls: string[] = []
  /** 拖选：PanGestureOptions 动态 distance（普通 10000vp 让位 Grid 滚动，长按激活后 1vp 跟手拖选） */
  private pageSelectPanOptions: PanGestureOptions = new PanGestureOptions({ fingers: 1, distance: 10000 })
  private pageSelectDragging: boolean = false
  private pageSelectStartIndex: number = -1
  private pageSelectTargetState: boolean = false
  private pageSelectPreDrag: boolean[] = []
  private pageSelectGridWidth: number = 0
  private pageSelectScrollOffset: number = 0
  private pageSelectSuppressClick: boolean = false
  /** 收藏 FAB 长按时间戳：长按抬起被迷你 Tabs 识别为 Bar 点击时用于抑制误触收藏切换 */
  private bookmarkLongPressAt: number = 0
  @StorageLink('bookmarkStates') bookmarkStates: Map<number, number> = new Map<number, number>()
  @StorageLink('appSettings') appSettings: AppSettings = new AppSettings()

  aboutToAppear() {
    this.store.uiContext = this.getUIContext()
    if (this.isActive) {
      this.ensureLoaded()
    }
  }

  onActiveChange() {
    // Swiper 懒加载：滑入激活时才首次加载详情数据
    if (this.isActive) {
      this.ensureLoaded()
    }
  }

  private ensureLoaded(): void {
    if (this.loadStarted || this.illustId <= 0) {
      return
    }
    this.loadStarted = true
    this.loadDetail(this.illustId)
  }

  aboutToDisappear() {
    // 页面退出：停止恢复轮询，不残留后台任务（接续登记由宿主壳统一管理）
    this.store.cancelRecover()
  }

  async loadDetail(id: number, forceRefresh: boolean = false) {
    if (this.rows.length === 0) {
      this.isLoading = true
    }
    this.errorMessage = ''
    this.deletedSnapshot = null
    if (!forceRefresh) {
      // R8 缓存优先渲染：DB 缓存命中立即出内容（不等网络，FR-046），后台再静默刷新
      let cachedOk = await this.store.loadFromCache(id)
      if (cachedOk) {
        this.applyDetailToState()
        // 用户已实际查看：写浏览历史（loadFromCache 不写；先删后插幂等，网络刷新成功再写无害）
        this.writeHistoryQuietly()
        this.isLoading = false
        // 相邻预取不等网络：缓存渲染后立即触发（FR-046）
        if (this.onDetailLoaded !== undefined) {
          this.onDetailLoaded()
        }
        this.store.refreshFromNetwork(id).then((ok: boolean) => {
          if (ok) {
            this.illust = this.store.illust
            this.captionSegments = parseCaptionHtml(this.illust.caption)
            this.authorFollowed = this.illust.user.isFollowed
            this.rebuildRows()
          }
        }).catch((e: Object) => {
          // FR-048：后台刷新失败静默保留缓存内容，不弹错误页/toast
          console.error('Background refresh failed: ' + e)
        })
        return
      }
    }
    // 缓存未命中或强刷：原全量路径（store.load 内部含缓存段；404 快照兜底/错误页语义不变）
    let ok = await this.store.load(id, forceRefresh)
    if (ok || this.store.illust.id > 0) {
      this.applyDetailToState()
      // R7：详情数据加载成功，通知宿主壳触发相邻作品预取（壳内自行判定是否启用）
      if (ok && this.onDetailLoaded !== undefined) {
        this.onDetailLoaded()
      }
    } else if (this.store.deletedSnapshot !== null) {
      // 404 + 有收藏快照：快照兜底分支（不显示普通错误页）
      this.deletedSnapshot = this.store.deletedSnapshot
      this.recoverState = RECOVER_STATE_IDLE
      this.recoverProgressText = ''
    } else {
      this.errorMessage = this.store.errorMessage || getStr($r('app.string.common_load_failed'))
    }
    this.isLoading = false
  }

  /** 详情渲染链：镜像 store 内容到 @State，触发头像与相关作品加载 */
  private applyDetailToState(): void {
    this.illust = this.store.illust
    this.captionSegments = parseCaptionHtml(this.illust.caption)
    this.authorFollowed = this.illust.user.isFollowed
    this.rebuildRows()
    this.loadAvatar()
    this.store.loadRelated().then(() => {
      this.rebuildRows()
    }).catch((e: Object) => {
      console.error('Load related failed: ' + e)
    })
  }

  /** R8：缓存命中渲染即写浏览历史（FR-047 补偿：loadFromCache 无副作用，历史在渲染点写入） */
  private writeHistoryQuietly(): void {
    let illust = this.illust
    if (illust.id <= 0) {
      return
    }
    getDbService().then((db: DatabaseService) => {
      db.addHistory(illust.id, illust.title, illust.imageUrls.medium, illust.user.name).catch((e: Object) => {
        console.error('Add history failed: ' + e)
      })
    }).catch((e: Object) => {
      console.error('Get db service for history failed: ' + e)
    })
  }

  /** 点击"尝试从第三方恢复"：轮询编排交 store，状态镜像回页面 */
  private startRecover(): void {
    this.recoverState = RECOVER_STATE_POLLING
    this.store.startRecover((text: string) => {
      this.recoverProgressText = text
    }).then(() => {
      this.recoverState = this.store.recoverState
      if (this.store.recoverState === RECOVER_STATE_READY && this.store.recoveredImageUrls.length > 0) {
        this.openRecoveredViewer(this.store.recoveredImageUrls)
      }
    }).catch((e: Object) => {
      console.error('Recover failed: ' + e)
      this.recoverState = this.store.recoverState
    })
  }

  private cancelRecover(): void {
    this.store.cancelRecover()
    this.recoverState = RECOVER_STATE_IDLE
    this.recoverProgressText = ''
  }

  /** 恢复成功：用快照元数据构造 Illust 跳查看器（图片 URL 直接可用） */
  private openRecoveredViewer(urls: string[]): void {
    let snapshot = this.deletedSnapshot
    let recovered: Illust = new Illust()
    if (snapshot !== null) {
      recovered = new Illust({
        id: snapshot.illustId,
        title: snapshot.title,
        pageCount: snapshot.pageCount,
        width: snapshot.width,
        height: snapshot.height,
        createDate: snapshot.createDate,
        user: { id: snapshot.userId, name: snapshot.userName }
      })
    }
    router.pushUrl({
      url: 'pages/detail/ImageViewerPage',
      params: { urls: urls, downloadUrls: urls, illust: recovered, pageIndex: 0 }
    })
  }

  private rebuildRows(): void {
    this.rows = this.store.buildRows(userSettingStore.getSettings().detailQuality)
    this.hasMoreRelated = this.store.relatedNextUrl.length > 0
  }

  /** R4：相关作品续页（触底自动加载与手动按钮共用入口；门控：有续页且非加载中） */
  private loadMoreRelated(): void {
    if (!this.hasMoreRelated || this.store.relatedLoading) {
      return
    }
    this.store.loadMoreRelated().then(() => {
      this.rebuildRows()
    }).catch((e: Object) => {
      console.error('Load more related failed: ' + e)
    })
  }

  private async loadAvatar(): Promise<void> {
    let url = this.illust.user.profileImageUrls.medium
    if (url) {
      this.userAvatarPath = await imageCacheService.getLocalPath(url)
    }
  }

  private bookmarkState(): number {
    let state = this.bookmarkStates.get(this.illust.id)
    if (state !== undefined) {
      return state
    }
    return this.illust.isBookmarked ? BOOKMARK_DONE : 0
  }

  private isR18(): boolean {
    return this.illust.xRestrict === 1 || this.illust.xRestrict === 2
  }

  /** US6：命中屏蔽规则（屏蔽词/屏蔽作者，复用 MuteFilter 纯函数，不新增规则类型） */
  private isMutedIllust(): boolean {
    if (this.illust.id <= 0) {
      return false
    }
    return MuteFilter.isMuted(this.illust, userSettingStore.getSettings())
  }

  private hasUnresolvedMergeGroups(): boolean {
    let settings = userSettingStore.getSettings()
    let exifTags: ExifTag[] = this.illust.tags.map((t: Tag): ExifTag => {
      return { name: t.name, translatedName: t.translatedName }
    })
    let groups = findUnresolvedMergeGroups(exifTags, settings)
    return groups.length > 0
  }

  private checkMergeReview(): void {
    let settings = userSettingStore.getSettings()
    let exifTags: ExifTag[] = this.illust.tags.map((t: Tag): ExifTag => {
      return { name: t.name, translatedName: t.translatedName }
    })
    let groups = findUnresolvedMergeGroups(exifTags, settings)
    if (groups.length === 0) {
      return
    }
    this.mergeReviewGroups = groups
    // Default: select the first tag in each group as main
    this.mergeReviewSelected = []
    for (let i = 0; i < groups.length; i++) {
      if (groups[i].tags.length > 0) {
        this.mergeReviewSelected.push(groups[i].tags[0].name)
      }
    }
    this.mergeReviewShown = true
  }

  private confirmMergeReview(): void {
    for (let i = 0; i < this.mergeReviewGroups.length; i++) {
      let group = this.mergeReviewGroups[i]
      let mainTag = this.mergeReviewSelected[i]
      if (!mainTag || mainTag.length === 0) {
        continue
      }
      let fromTags: string[] = []
      for (let j = 0; j < group.tags.length; j++) {
        if (group.tags[j].name !== mainTag) {
          fromTags.push(group.tags[j].name)
        }
      }
      if (fromTags.length > 0) {
        userSettingStore.addExifMergeRule(mainTag, fromTags)
      }
    }
    this.mergeReviewShown = false
    this.mergeReviewGroups = []
    this.mergeReviewSelected = []
    promptAction.showToast({ message: $r('app.string.detail_merge_rule_saved') })
  }

  private needMask(): boolean {
    return this.appSettings.antiSocialDeath && this.isR18() && !this.revealedR18
  }

  private clearMergeSuggestState(): void {
    if (this.mergeSuggestTimer >= 0) {
      clearTimeout(this.mergeSuggestTimer)
      this.mergeSuggestTimer = -1
    }
    this.mergeSuggestions = []
    this.mergeSuggestionSubs = []
  }

  private closeMergeDialog(): void {
    this.clearMergeSuggestState()
    this.mergeDialogShown = false
  }

  /** 合并输入变化：本地来源（合并规则+本作品 tag）即时匹配；本地零匹配且停顿 ≥300ms 才调 API */
  private onMergeInputChange(value: string): void {
    this.mergeInputText = value
    if (this.mergeSuggestTimer >= 0) {
      clearTimeout(this.mergeSuggestTimer)
      this.mergeSuggestTimer = -1
    }
    let prefix = value.trim()
    if (prefix.length === 0) {
      this.mergeSuggestions = []
      this.mergeSuggestionSubs = []
      return
    }
    let settings = userSettingStore.getSettings()
    let illustTagNames: string[] = this.illust.tags.map((t: Tag) => t.name)
    let local = buildLocalSuggestions(prefix, settings.exifMergedTags, illustTagNames)
    if (local.length > 0) {
      // 本地有匹配 → 不发起 API 请求
      this.mergeSuggestions = local
      this.mergeSuggestionSubs = local.map((): string => '')
      return
    }
    this.mergeSuggestions = []
    this.mergeSuggestionSubs = []
    this.mergeSuggestTimer = setTimeout(() => {
      this.mergeSuggestTimer = -1
      this.fetchApiSuggestions(prefix)
    }, 300)
  }

  /** API 联想词兜底：仅在本地零匹配时触发；失败静默降级不影响本地建议 */
  private async fetchApiSuggestions(prefix: string): Promise<void> {
    try {
      let response = await apiService.getAutoComplete(prefix)
      // 输入已变化则丢弃过期结果
      if (!this.mergeDialogShown || this.mergeInputText.trim() !== prefix) {
        return
      }
      let raw = response as RawAutoCompleteResponse
      let tags = raw.tags ?? []
      let names: string[] = []
      let subs: string[] = []
      for (let i = 0; i < tags.length; i++) {
        let item = tags[i] as RawAutoCompleteTag
        let name = item.name ?? ''
        if (name.length === 0 || names.includes(name)) {
          continue
        }
        names.push(name)
        subs.push(Constants.filterTranslatedName(name, item.translated_name ?? ''))
      }
      this.mergeSuggestions = names
      this.mergeSuggestionSubs = subs
    } catch (e) {
      console.error('Autocomplete failed: ' + e)
    }
  }

  /** 点选建议：回填输入框并收起建议区 */
  private pickMergeSuggestion(name: string): void {
    this.mergeInputText = name
    this.clearMergeSuggestState()
  }

  openViewer(pageIndex: number) {
    let settings = userSettingStore.getSettings()
    let urls = buildPageUrls(this.illust, settings.fullScreenQuality)
    let downloadUrls = buildPageUrls(this.illust, settings.downloadQuality)
    router.pushUrl({
      url: 'pages/detail/ImageViewerPage',
      params: { urls: urls, downloadUrls: downloadUrls, illust: this.illust, pageIndex: pageIndex }
    })
  }

  @Builder
  SaveMenuBuilder() {
    Column() {
      Text($r('app.string.detail_save_current_page'))
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => { this.handleSavePage(this.saveMenuPageIndex) })
      if (this.illust.pageCount > 1) {
        Text($r('app.string.detail_save_all_pages'))
          .fontSize(14)
          .fontColor('#333333')
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .onClick(() => { this.handleSaveAll() })
      }
    }
    .width(140)
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  TagMenuBuilder() {
    Column() {
      Text($r('app.string.detail_copy_tag'))
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => {
          let data = pasteboard.createPlainTextData(this.tagMenuTarget)
          pasteboard.getSystemPasteboard().setData(data)
        })
      Text($r('app.string.detail_mute_tag'))
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => {
          userSettingStore.addMuteTag(this.tagMenuTarget)
        })
      Text($r('app.string.detail_exif_mute'))
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => {
          userSettingStore.addExifMutedTag(this.tagMenuTarget)
          promptAction.showToast({ message: getStrf($r('app.string.detail_exif_muted_toast'), this.tagMenuTarget) })
        })
      Text($r('app.string.detail_exif_merge'))
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => {
          this.mergeFromTag = this.tagMenuTarget
          this.mergeInputText = ''
          this.clearMergeSuggestState()
          this.mergeDialogShown = true
        })
    }
    .width(140)
    .padding({ top: 4, bottom: 4 })
  }

  goToUserProfile() {
    if (this.illust.user.id > 0) {
      router.pushUrl({ url: 'pages/user/UserProfilePage', params: { userId: this.illust.user.id } })
    }
  }

  /** 保存单页：先检测合并审查，再检测 EXIF 超限；ugoira 为 zip 帧包下载，跳过预检链直走 store 单页路径 */
  private handleSavePage(pageIndex: number): void {
    if (this.illust.type === 'ugoira') {
      this.store.savePage(0)
      return
    }
    if (this.hasUnresolvedMergeGroups()) {
      this.checkMergeReview()
      return
    }
    if (this.store.isExifOverLimit()) {
      this.exifPickerPendingPages = [pageIndex]
      this.initExifPickerItems()
      this.exifPickerShown = true
    } else {
      this.store.savePage(pageIndex)
    }
  }

  /** 保存全部页：先检测合并审查，再检测 EXIF 超限；ugoira pageCount 恒为 1，直走 store 单页路径 */
  private handleSaveAll(): void {
    if (this.illust.type === 'ugoira') {
      this.store.savePage(0)
      return
    }
    if (this.hasUnresolvedMergeGroups()) {
      this.checkMergeReview()
      return
    }
    if (this.store.isExifOverLimit()) {
      let pages: number[] = []
      for (let i = 0; i < this.illust.pageCount; i++) {
        pages.push(i)
      }
      this.exifPickerPendingPages = pages
      this.initExifPickerItems()
      this.exifPickerShown = true
    } else {
      this.store.saveAll()
    }
  }

  /** 保存指定页集合（选页弹窗确认入口）：空集合不发起；先检测合并审查，再检测 EXIF 超限 */
  private handleSavePages(pageIndexes: number[]): void {
    if (pageIndexes.length === 0) {
      return
    }
    if (this.hasUnresolvedMergeGroups()) {
      this.checkMergeReview()
      return
    }
    if (this.store.isExifOverLimit()) {
      this.exifPickerPendingPages = pageIndexes.slice()
      this.initExifPickerItems()
      this.exifPickerShown = true
    } else {
      this.store.savePages(pageIndexes)
    }
  }

  /** EXIF Picker 确认/跳过后的续走：单页→savePage，全集→saveAll，子集→savePages */
  private resumeSaveAfterPicker(): void {
    let pages = this.exifPickerPendingPages
    if (pages.length === 1) {
      this.store.savePage(pages[0])
    } else if (pages.length === this.illust.pageCount && pages.length > 1) {
      this.store.saveAll()
    } else if (pages.length > 0) {
      this.store.savePages(pages)
    }
  }

  /** 选页弹窗：缩略图 URL（方图缩略档优先） */
  private pageThumbUrl(pageIndex: number): string {
    let hasMetaPage = this.illust.pageCount > 1 && pageIndex >= 0 && pageIndex < this.illust.metaPages.length
    let urls = hasMetaPage ? this.illust.metaPages[pageIndex].imageUrls : this.illust.imageUrls
    return urls.squareMedium || urls.medium || urls.large
  }

  /** 打开选页弹窗（仅多页）：默认全选，重置拖选/滚动状态 */
  private openPageSelect(): void {
    let count = this.illust.pageCount
    if (count <= 1) {
      return
    }
    let checked: boolean[] = []
    let thumbs: string[] = []
    for (let i = 0; i < count; i++) {
      checked.push(true)
      thumbs.push(this.pageThumbUrl(i))
    }
    this.pageSelectChecked = checked
    this.pageSelectThumbUrls = thumbs
    this.pageSelectScrollOffset = 0
    this.pageSelectDragging = false
    this.pageSelectSuppressClick = false
    this.pageSelectPanOptions.setDistance(10000)
    this.pageSelectShown = true
  }

  private closePageSelect(): void {
    this.pageSelectShown = false
    this.endPageSelectDrag()
  }

  private pageSelectCount(): number {
    let n = 0
    for (let i = 0; i < this.pageSelectChecked.length; i++) {
      if (this.pageSelectChecked[i]) {
        n++
      }
    }
    return n
  }

  /** 确认下载：空选择不发起 */
  private confirmPageSelect(): void {
    let selected: number[] = []
    for (let i = 0; i < this.pageSelectChecked.length; i++) {
      if (this.pageSelectChecked[i]) {
        selected.push(i)
      }
    }
    if (selected.length === 0) {
      return
    }
    this.closePageSelect()
    this.handleSavePages(selected)
  }

  private setAllPageSelect(value: boolean): void {
    let next: boolean[] = []
    for (let i = 0; i < this.pageSelectChecked.length; i++) {
      next.push(value)
    }
    this.pageSelectChecked = next
  }

  /** 单击单格切换（长按后的抬起 click 被吞掉，避免撤销拖选起始格的置位） */
  private togglePageSelect(index: number): void {
    if (this.pageSelectSuppressClick) {
      this.pageSelectSuppressClick = false
      return
    }
    if (index < 0 || index >= this.pageSelectChecked.length) {
      return
    }
    let next = this.pageSelectChecked.slice()
    next[index] = !next[index]
    this.pageSelectChecked = next
  }

  /** 长按（≥300ms）激活拖选：起始格定方向（选中↔未选），记录拖前快照供区间重算 */
  private startPageSelectDrag(index: number): void {
    if (index < 0 || index >= this.pageSelectChecked.length) {
      return
    }
    this.pageSelectDragging = true
    this.pageSelectSuppressClick = true
    this.pageSelectStartIndex = index
    this.pageSelectTargetState = !this.pageSelectChecked[index]
    this.pageSelectPreDrag = this.pageSelectChecked.slice()
    this.pageSelectPanOptions.setDistance(1)
    this.applyPageSelectRange(index)
  }

  /** 拖选区间置位：起始格与当前格之间的连续区间（行优先序）统一置为目标状态 */
  private applyPageSelectRange(currentIndex: number): void {
    if (this.pageSelectStartIndex < 0) {
      return
    }
    let start = Math.min(this.pageSelectStartIndex, currentIndex)
    let end = Math.max(this.pageSelectStartIndex, currentIndex)
    let next = this.pageSelectPreDrag.slice()
    for (let i = start; i <= end && i < next.length; i++) {
      next[i] = this.pageSelectTargetState
    }
    this.pageSelectChecked = next
  }

  private endPageSelectDrag(): void {
    if (!this.pageSelectDragging) {
      return
    }
    this.pageSelectDragging = false
    this.pageSelectStartIndex = -1
    this.pageSelectPanOptions.setDistance(10000)
  }

  /** 单格边长（4 列，gap 8vp） */
  private pageSelectCellSize(): number {
    if (this.pageSelectGridWidth <= 0) {
      return 0
    }
    return (this.pageSelectGridWidth - 24) / 4
  }

  /** 触点坐标（相对 Grid，vp）→ 格子索引；含滚动偏移换算，越界钳制 */
  private pageSelectIndexAt(x: number, y: number): number {
    let cell = this.pageSelectCellSize()
    if (cell <= 0 || this.pageSelectChecked.length === 0) {
      return -1
    }
    let col = Math.floor(x / (cell + 8))
    if (col < 0) {
      col = 0
    }
    if (col > 3) {
      col = 3
    }
    let row = Math.floor((y + this.pageSelectScrollOffset) / (cell + 8))
    let index = row * 4 + col
    if (index < 0) {
      index = 0
    }
    if (index >= this.pageSelectChecked.length) {
      index = this.pageSelectChecked.length - 1
    }
    return index
  }

  /** 拖选滑动更新：按经过格区间批量置目标状态 */
  private onPageSelectPanUpdate(event: GestureEvent): void {
    if (!this.pageSelectDragging || event.fingerList.length === 0) {
      return
    }
    let finger = event.fingerList[0]
    let index = this.pageSelectIndexAt(finger.localX, finger.localY)
    if (index >= 0) {
      this.applyPageSelectRange(index)
    }
  }

  /** 初始化 EXIF 标签选择器的数据 */
  private initExifPickerItems(): void {
    let settings = userSettingStore.getSettings()
    let filteredTags = filterTagsForExif(this.illust.tags.map((t: Tag): ExifTag => {
      return { name: t.name, translatedName: t.translatedName }
    }), settings)

    let writable: ExifPickerItem[] = []
    let muted: ExifPickerItem[] = []

    for (let i = 0; i < filteredTags.length; i++) {
      let tag = filteredTags[i]
      let isMuted = settings.exifMutedTags.includes(tag.name)
      let item: ExifPickerItem = {
        name: tag.name,
        translatedName: tag.translatedName,
        checked: !isMuted,
        withinBudget: true
      }
      if (isMuted) {
        muted.push(item)
      } else {
        writable.push(item)
      }
    }

    // Also add muted tags not in filteredTags
    let filteredNames: string[] = []
    for (let i = 0; i < filteredTags.length; i++) {
      filteredNames.push(filteredTags[i].name)
    }
    for (let i = 0; i < this.illust.tags.length; i++) {
      let tag = this.illust.tags[i]
      if (settings.exifMutedTags.includes(tag.name) && !filteredNames.includes(tag.name)) {
        let item: ExifPickerItem = {
          name: tag.name,
          translatedName: tag.translatedName,
          checked: false,
          withinBudget: false
        }
        let alreadyInMuted = false
        for (let m = 0; m < muted.length; m++) {
          if (muted[m].name === tag.name) {
            alreadyInMuted = true
            break
          }
        }
        if (!alreadyInMuted) {
          muted.push(item)
        }
      }
    }

    this.exifPickerWritableItems = writable
    this.exifPickerMutedItems = muted
    this.recalculateExifPickerPreview()
  }

  /** 重新计算 EXIF 选择器预览 */
  private recalculateExifPickerPreview(): void {
    let info = this.store.buildExifInfo()
    let checkedTags: ExifTag[] = []
    for (let i = 0; i < this.exifPickerWritableItems.length; i++) {
      if (this.exifPickerWritableItems[i].checked) {
        let t: ExifTag = {
          name: this.exifPickerWritableItems[i].name,
          translatedName: this.exifPickerWritableItems[i].translatedName
        }
        checkedTags.push(t)
      }
    }

    let rendered = renderCommentWithTags(info, checkedTags)
    let totalBytes = utf8ByteLength(rendered)
    this.exifPickerPreviewText = rendered
    this.exifPickerPreviewBytes = totalBytes

    // Calculate withinBudget for each writable item
    let budgetTags: ExifTag[] = []
    for (let i = 0; i < this.exifPickerWritableItems.length; i++) {
      if (this.exifPickerWritableItems[i].checked) {
        let t: ExifTag = {
          name: this.exifPickerWritableItems[i].name,
          translatedName: this.exifPickerWritableItems[i].translatedName
        }
        budgetTags.push(t)
        let partialBytes = renderCommentBytes(info, budgetTags)
        this.exifPickerWritableItems[i].withinBudget = partialBytes <= EXIF_FIELD_MAX_BYTES
      } else {
        this.exifPickerWritableItems[i].withinBudget = false
      }
    }
  }

  /** EXIF Picker 确认回调：更新 exifMutedTags 和 exifTagPriority 后继续保存 */
  private onExifPickerConfirm(): void {
    let selectedTags: string[] = []
    let allTagsOrdered: string[] = []
    for (let i = 0; i < this.exifPickerWritableItems.length; i++) {
      allTagsOrdered.push(this.exifPickerWritableItems[i].name)
      if (this.exifPickerWritableItems[i].checked) {
        selectedTags.push(this.exifPickerWritableItems[i].name)
      }
    }

    // 只有在屏蔽区中的标签才持久化屏蔽（取消勾选只是跳过本次）
    let settings = userSettingStore.getSettings()
    let currentMuted: string[] = settings.exifMutedTags.slice()
    for (let i = 0; i < this.exifPickerMutedItems.length; i++) {
      if (!currentMuted.includes(this.exifPickerMutedItems[i].name)) {
        currentMuted.push(this.exifPickerMutedItems[i].name)
      }
    }
    userSettingStore.setExifMutedTags(currentMuted)

    // 更新优先级排序（拖拽后的顺序持久化）
    userSettingStore.updateExifTagPriority(allTagsOrdered)

    this.exifPickerShown = false

    // 继续保存流程
    this.resumeSaveAfterPicker()
  }

  /** EXIF Picker 跳过回调：直接保存不做过滤 */
  private onExifPickerSkip(): void {
    this.exifPickerShown = false
    this.resumeSaveAfterPicker()
   }

  /** 长按可写入标签 → 移入屏蔽区（永久屏蔽） */
  private muteExifPickerTag(tagName: string): void {
    let targetIdx = -1
    for (let i = 0; i < this.exifPickerWritableItems.length; i++) {
      if (this.exifPickerWritableItems[i].name === tagName) {
        targetIdx = i
        break
      }
    }
    if (targetIdx < 0) {
      this.exifPickerMuteConfirmTarget = ''
      return
    }
    let movedItem = this.exifPickerWritableItems[targetIdx]
    let newWritable: ExifPickerItem[] = []
    for (let i = 0; i < this.exifPickerWritableItems.length; i++) {
      if (i !== targetIdx) {
        newWritable.push(this.exifPickerWritableItems[i])
      }
    }
    this.exifPickerWritableItems = newWritable
    let mutedItem: ExifPickerItem = {
      name: movedItem.name,
      translatedName: movedItem.translatedName,
      checked: false,
      withinBudget: false
    }
    let newMuted: ExifPickerItem[] = []
    for (let i = 0; i < this.exifPickerMutedItems.length; i++) {
      newMuted.push(this.exifPickerMutedItems[i])
    }
    newMuted.push(mutedItem)
    this.exifPickerMutedItems = newMuted
    this.exifPickerMuteConfirmTarget = ''
    this.recalculateExifPickerPreview()
  }

  /** 从屏蔽区恢复标签到可写入区 */
  private restoreExifPickerMutedTag(index: number): void {
    if (index < 0 || index >= this.exifPickerMutedItems.length) {
      return
    }
    let item = this.exifPickerMutedItems[index]
    let newMuted: ExifPickerItem[] = []
    for (let i = 0; i < this.exifPickerMutedItems.length; i++) {
      if (i !== index) {
        newMuted.push(this.exifPickerMutedItems[i])
      }
    }
    this.exifPickerMutedItems = newMuted
    let restoredItem: ExifPickerItem = {
      name: item.name,
      translatedName: item.translatedName,
      checked: true,
      withinBudget: false
    }
    let newWritable: ExifPickerItem[] = []
    for (let i = 0; i < this.exifPickerWritableItems.length; i++) {
      newWritable.push(this.exifPickerWritableItems[i])
    }
    newWritable.push(restoredItem)
    this.exifPickerWritableItems = newWritable
    this.recalculateExifPickerPreview()
  }

   private getDisplayTranslation(tagName: string, translatedName: string): string {
     return Constants.filterTranslatedName(tagName, translatedName)
  }

  @Builder
  TagChip(tag: Tag) {
    if (userSettingStore.getSettings().showTranslatedTags && tag.translatedName &&
      this.getDisplayTranslation(tag.name, tag.translatedName).length > 0) {
      Column() {
        Text(tag.name)
          .fontSize(10)
          .fontColor('#0096FA')
        Text(this.getDisplayTranslation(tag.name, tag.translatedName))
          .fontSize(8)
          .fontColor('#0096FA')
          .opacity(0.8)
      }
      .backgroundColor('#E6F4FF')
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(12)
      .margin({ right: 4, bottom: 4 })
      .onClick(() => {
        router.pushUrl({ url: 'pages/search/TagSearchPage', params: { keyword: tag.name } })
      })
      .gesture(
        LongPressGesture({ duration: 500 })
          .onAction(() => {
            HapticUtils.heavy()
            this.tagMenuTarget = tag.name
            this.tagMenuShown = true
          })
      )
      .bindContextMenu(this.tagMenuShown && this.tagMenuTarget === tag.name, this.TagMenuBuilder, {
        onDisappear: () => { this.tagMenuShown = false }
      })
    } else {
      Text(tag.name)
        .fontSize(10)
        .fontColor('#0096FA')
        .backgroundColor('#E6F4FF')
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(12)
        .margin({ right: 4, bottom: 4 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/search/TagSearchPage', params: { keyword: tag.name } })
        })
        .gesture(
          LongPressGesture({ duration: 500 })
            .onAction(() => {
              HapticUtils.heavy()
              this.tagMenuTarget = tag.name
              this.tagMenuShown = true
            })
        )
        .bindContextMenu(this.tagMenuShown && this.tagMenuTarget === tag.name, this.TagMenuBuilder, {
          onDisappear: () => { this.tagMenuShown = false }
        })
    }
  }

  @Builder
  ImageRow(row: DetailRow) {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.needMask()) {
        Column() {
          Text('🔒')
            .fontSize(28)
            .opacity(0.4)
          Text($r('app.string.detail_tap_to_show'))
            .fontSize(12)
            .fontColor('rgba(255, 255, 255, 0.35)')
            .margin({ top: 8 })
        }
        .width('100%')
        .aspectRatio(row.ratio)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#E0E0E0')
        .borderRadius(8)
        .onClick(() => { this.revealedR18 = true })
      } else if (this.illust.type === 'ugoira') {
        UgoiraPlayer({ illustId: this.illust.id, ratio: row.ratio, fit: ImageFit.Contain, coverUrl: row.imageUrl })
      } else {
        CachedImage({ url: row.imageUrl, ratio: row.ratio, fit: ImageFit.Contain })
      }
      if (this.illust.pageCount > 1 && !this.needMask()) {
        Text((row.pageIndex + 1) + '/' + this.illust.pageCount)
          .fontSize(10)
          .fontColor('#FFFFFF')
          .backgroundColor('rgba(0, 0, 0, 0.6)')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(8)
          .margin(6)
      }
      if (this.illust.type === 'ugoira' && !this.needMask()) {
        Text($r('app.string.ugoira_badge'))
          .fontSize(10)
          .fontColor('#FFFFFF')
          .backgroundColor('rgba(0, 0, 0, 0.6)')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(8)
          .margin(6)
      }
    }
    .width('100%')
    .onClick(() => {
      if (this.needMask()) {
        this.revealedR18 = true
        return
      }
      this.openViewer(row.pageIndex)
    })
    .gesture(
      LongPressGesture({ duration: 500 })
        .onAction(() => {
          if (!this.needMask()) {
            HapticUtils.heavy()
            if (this.illust.pageCount > 1) {
              this.saveMenuPageIndex = row.pageIndex
              this.saveMenuShown = true
            } else {
              this.handleSavePage(row.pageIndex)
            }
          }
        })
    )
    .bindContextMenu(this.saveMenuShown && this.saveMenuPageIndex === row.pageIndex, this.SaveMenuBuilder, {
      onDisappear: () => { this.saveMenuShown = false }
    })
  }

  private muteAuthor(): void {
    userSettingStore.addMuteUser(this.illust.user.id)
    promptAction.showToast({ message: getStrf($r('app.string.card_muted_author'), this.illust.user.name) })
  }

  private illustWebUrl(): string {
    return 'https://www.pixiv.net/artworks/' + this.illust.id
  }

  /** 简介链接点击：pixiv 链接应用内跳详情/画师页；外链走系统浏览器（失败静默） */
  private openCaptionLink(href: string): void {
    let target = PixivLinkParser.parse(href)
    if (target !== null) {
      if (target.kind === 'illust') {
        router.pushUrl({ url: 'pages/detail/IllustDetailPage', params: { illustId: target.id } })
      } else {
        router.pushUrl({ url: 'pages/user/UserProfilePage', params: { userId: target.id } })
      }
      return
    }
    try {
      let context = this.getUIContext().getHostContext() as common.UIAbilityContext
      context.openLink(href, { appLinkingOnly: false }).then(() => {}).catch((err: Object) => {
        console.error('Open caption link failed: ' + err)
      })
    } catch (e) {
      console.error('Open caption link failed: ' + e)
    }
  }

  /** 顶栏菜单-分享：系统分享面板，文本记录 = 作品 web URL */
  private shareIllust(): void {
    try {
      let record: systemShare.SharedRecord = {
        utd: utd.UniformDataType.TEXT,
        content: this.illustWebUrl(),
        title: this.illust.title,
        description: this.illust.user.name
      }
      let shareData = new systemShare.SharedData(record)
      let controller = new systemShare.ShareController(shareData)
      let context = this.getUIContext().getHostContext() as common.UIAbilityContext
      controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      }).then(() => {}).catch((err: Object) => {
        console.error('Share panel show failed: ' + err)
      })
    } catch (e) {
      console.error('Share failed: ' + e)
    }
  }

  /** 顶栏菜单-复制链接 */
  private copyIllustLink(): void {
    copyText(this.illustWebUrl()).then((ok: boolean) => {
      promptAction.showToast({ message: ok ? $r('app.string.detail_link_copied') : $r('app.string.common_copy_failed') })
    })
  }

  /** 顶栏菜单-复制文案：标题 + 简介纯文本 */
  private copyCaption(): void {
    let text = this.illust.title
    let plain = captionToPlainText(this.illust.caption)
    if (plain.length > 0) {
      text = text + '\n' + plain
    }
    copyText(text).then((ok: boolean) => {
      promptAction.showToast({ message: ok ? $r('app.string.detail_caption_copied') : $r('app.string.common_copy_failed') })
    })
  }

  /** R4 顶栏 ⋮ 溢出菜单（菜单内 toast/弹窗约定：先收菜单再 setTimeout(300) 执行） */
  @Builder
  TopMenuBuilder() {
    Column() {
      Text($r('app.string.detail_menu_share'))
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => {
          this.topMenuShown = false
          setTimeout(() => { this.shareIllust() }, 300)
        })
      Text($r('app.string.detail_copy_link'))
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => {
          this.topMenuShown = false
          setTimeout(() => { this.copyIllustLink() }, 300)
        })
      Text($r('app.string.detail_copy_caption'))
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => {
          this.topMenuShown = false
          setTimeout(() => { this.copyCaption() }, 300)
        })
      Text($r('app.string.detail_author_info'))
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => {
          this.topMenuShown = false
          setTimeout(() => { this.goToUserProfile() }, 300)
        })
      if (this.illust.pageCount > 1) {
        Text($r('app.string.detail_save_multi'))
          .fontSize(14)
          .fontColor('#333333')
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .onClick(() => {
            this.topMenuShown = false
            setTimeout(() => { this.openPageSelect() }, 300)
          })
      }
      Text($r('app.string.card_mute_author'))
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => {
          this.topMenuShown = false
          setTimeout(() => { this.muteAuthor() }, 300)
        })
    }
    .width(160)
    .padding({ top: 4, bottom: 4 })
  }

  private copyUid(): void {
    copyText(this.illust.user.id.toString()).then((ok: boolean) => {
      promptAction.showToast({ message: ok ? $r('app.string.detail_uid_copied') : $r('app.string.common_copy_failed') })
    })
  }

  /** 画师行长按菜单（承接卡片长按菜单迁移项）：屏蔽作者 / 复制 UID */
  @Builder
  AuthorMenuBuilder() {
    Column() {
      Text($r('app.string.card_mute_author'))
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => {
          this.authorMenuShown = false
          setTimeout(() => { this.muteAuthor() }, 300)
        })
      Text($r('app.string.detail_copy_uid'))
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => {
          this.authorMenuShown = false
          setTimeout(() => { this.copyUid() }, 300)
        })
    }
    .width(160)
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  InfoRow() {
    Column() {
      Row() {
        Text(this.illust.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })

      Row() {
        if (this.userAvatarPath) {
          Image('file://' + this.userAvatarPath)
            .width(32)
            .height(32)
            .borderRadius(16)
        } else {
          Column()
            .width(32)
            .height(32)
            .borderRadius(16)
            .backgroundColor('#F5F5F5')
        }
        Text(this.illust.user.name)
          .fontSize(14)
          .fontColor('#0096FA')
          .margin({ left: 8 })
        Blank()
        // 三态关注按钮（对齐 pixez：单击快关，长按精细关注菜单）
        FollowButton({
          userId: this.illust.user.id,
          isFollowed: this.authorFollowed,
          onChanged: (newState: boolean) => { this.authorFollowed = newState }
        })
          .width(80)
          .height(28)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })
      .onClick(() => { this.goToUserProfile() })
      .gesture(
        LongPressGesture({ fingers: 1, duration: 500 })
          .onAction(() => {
            HapticUtils.heavy()
            this.authorMenuShown = true
          })
      )
      .bindContextMenu(this.authorMenuShown, this.AuthorMenuBuilder, {
        onDisappear: () => { this.authorMenuShown = false }
      })

      Row() {
        Text(getStrf($r('app.string.detail_stat_bookmarks'), this.illust.totalBookmarks))
          .fontSize(12)
          .fontColor('#999999')
        Text(getStrf($r('app.string.detail_stat_views'), this.illust.totalView))
          .fontSize(12)
          .fontColor('#999999')
          .margin({ left: 16 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })

      // 发布日期（本地时区 yyyy-MM-dd HH:mm；解析失败返回 '' 不渲染该行）
      if (formatCreateDate(this.illust.createDate).length > 0) {
        Row() {
          Text(getStrf($r('app.string.detail_published_at'), formatCreateDate(this.illust.createDate)))
            .fontSize(12)
            .fontColor('#999999')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
      }

      Row() {
        Text('PID: ' + this.illust.id)
          .fontSize(12)
          .fontColor('#999999')
          .gesture(
            LongPressGesture({ duration: 500 })
              .onAction(() => {
                copyText(this.illust.id.toString()).then((ok: boolean) => {
                  promptAction.showToast({ message: ok ? $r('app.string.detail_pid_copied') : $r('app.string.common_copy_failed') })
                })
              })
          )
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })

      // 分辨率（R4）：宽×高，任一维度为 0 不渲染该行
      if (this.illust.width > 0 && this.illust.height > 0) {
        Row() {
          Text(this.illust.width + '×' + this.illust.height)
            .fontSize(12)
            .fontColor('#999999')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
      }

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.illust.tags, (tag: Tag) => {
          this.TagChip(tag)
        }, (tag: Tag) => tag.name)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })

      // 简介富文本（R4）：HTML 分段渲染，链接段高亮可点（pixiv 链接应用内跳转，外链开浏览器）
      if (this.captionSegments.length > 0) {
        Text() {
          ForEach(this.captionSegments, (seg: CaptionSegment, segIndex: number) => {
            if (seg.href.length > 0) {
              Span(seg.text)
                .fontColor('#0096FA')
                .onClick(() => { this.openCaptionLink(seg.href) })
            } else {
              Span(seg.text)
            }
          }, (seg: CaptionSegment, segIndex: number) => segIndex.toString() + '_' + seg.href)
        }
        .fontSize(13)
        .fontColor('#666666')
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
      }

      // 查看评论：tag 云之后、相关作品之前的居中小号文字按钮（原按钮区已迁移至右下角双 FAB）
      Text($r('app.string.detail_view_comments'))
        .fontSize(12)
        .fontColor('#999999')
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 12, bottom: 16 })
        .onClick(() => {
          router.pushUrl({
            url: 'pages/detail/CommentPage',
            params: { illustId: this.illust.id, illustTitle: this.illust.title }
          })
        })
    }
    .width('100%')
  }

  @Builder
  RelatedHeaderRow() {
    Row() {
      Text($r('app.string.detail_related'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  /**
   * 相关作品点击：先向 DetailListContextRegistry 注册滑动上下文（快照本 Pane store 的
   * relatedIllusts id 序列——加载时已 MuteFilter 过滤——+ relatedNextUrl 快照 +
   * 自持局部游标的续页闭包，不引用原 store，原 Pane 销毁后仍可续页），
   * 再 pushUrl 传轻量标量 { illustId, contextToken, contextIndex }，详情页据此启用作品间滑动
   */
  private openRelatedDetail(target: Illust): void {
    let snapshot: Illust[] = this.store.relatedIllusts.slice()
    let ids: number[] = []
    let seenIds: Set<number> = new Set<number>()
    for (let i = 0; i < snapshot.length; i++) {
      ids.push(snapshot[i].id)
      seenIds.add(snapshot[i].id)
    }
    let index = ids.indexOf(target.id)
    if (index < 0) {
      index = 0
    }
    let cursor: string = this.store.relatedNextUrl
    let ctx: DetailListContext = {
      ids: ids,
      nextUrl: cursor,
      fetchNext: async (nextUrl: string): Promise<IllustListPage> => {
        let effective = nextUrl.length > 0 ? nextUrl : cursor
        let response = await apiService.fetchNext(effective)
        let page = parseIllustListPage(response)
        cursor = page.nextUrl
        let settings = userSettingStore.getSettings()
        let fresh: Illust[] = []
        for (let i = 0; i < page.illusts.length; i++) {
          let illust = page.illusts[i]
          if (MuteFilter.isMuted(illust, settings)) {
            continue
          }
          if (seenIds.has(illust.id)) {
            continue
          }
          seenIds.add(illust.id)
          fresh.push(illust)
        }
        let filtered: IllustListPage = { illusts: fresh, nextUrl: page.nextUrl }
        return filtered
      }
    }
    let token = DetailListContextRegistry.register(ctx)
    router.pushUrl({
      url: 'pages/detail/IllustDetailPage',
      params: { illustId: target.id, contextToken: token, contextIndex: index }
    })
  }

  @Builder
  RelatedRow(row: DetailRow) {
    Row() {
      ForEach(row.related, (item: Illust) => {
        Column() {
          IllustCard({
            illust: item,
            onCardClick: (target: Illust) => {
              this.openRelatedDetail(target)
            }
          })
        }
        .width('33.3%')
      }, (item: Illust) => item.id.toString())
    }
    .width('100%')
  }

  /** 收藏 FAB 内 glyph：未收藏=浅灰♡，已收藏=红❤，请求中=灰色（两分支共享） */
  @Builder
  BookmarkFabGlyph() {
    Text(this.bookmarkState() === BOOKMARK_DONE ? '❤' : '♡')
      .fontSize(22)
      .fontColor(this.bookmarkState() === BOOKMARK_DONE ? '#FF4081' :
        this.bookmarkState() === BOOKMARK_LOADING ? '#CCCCCC' : '#999999')
  }

  /** 收藏 FAB 长按手势动作：仅未收藏时打开带标签收藏面板（两分支共享） */
  private onBookmarkFabLongPress(): void {
    if (this.bookmarkState() === 0) {
      // 长按=带标签收藏面板（可见性并入面板）；已收藏时长按不响应
      HapticUtils.heavy()
      this.bookmarkTagPanelShown = true
    }
  }

  /** 右下角双 FAB：收藏（点按收藏/取消，长按带标签收藏面板；未收藏=浅灰♡，已收藏=红❤）+
   *  下载（SaveButton 安全控件，透明白底透出玻璃球；单击=保存全部页/单页保存，长按仅多页=选页弹窗）。
   *  沉浸光感走 MaterialFab（迷你 Tabs 悬浮 Bar 承载内容，材质按 Bar 轮廓渲染，API 23+ 均可用）；
   *  uiMaterial 直挂 Stack 的方案已踩坑回退（材质在非 Bar 区域不渲染），勿再尝试 */
  @Builder
  FabOverlay() {
    Column({ space: 40 }) {
      // 收藏 FAB：点击走 onTabBarClick（onFabClick），长按手势挂内容（长按后 500ms 内抑制一次点击，
      // 防止长按抬起被 Tabs 识别为 Bar 点击误触收藏切换）；内容不固定尺寸，让 bar item 包裹内容并与材质球同心
      MaterialFab({
        onFabClick: () => {
          if (Date.now() - this.bookmarkLongPressAt > 500) {
            this.store.toggleBookmark()
          }
        }
      }) {
        Column() {
          this.BookmarkFabGlyph()
        }
        .gesture(
          LongPressGesture({ duration: 500 })
            .onAction(() => {
              this.bookmarkLongPressAt = Date.now()
              this.onBookmarkFabLongPress()
            })
        )
      }

      // 下载 FAB：SaveButton 安全控件（点击获 1 分钟临时图库写权限，实现静默保存不弹窗；
      // 首次使用弹一次系统授权，之后每次点击静默授权）。长按仅多页=选页弹窗
      // 底色只能压到 '#1AFFFFFF'（10% 白）：官方机制——安全控件背景 alpha <0x1a 会被强制调整为
      // 0xff 不透明（防用户在不知情下触发授权），故 Color.Transparent→黑盘、'#00FFFFFF'→白盘；
      // 0x1a 是放行下限，10% 白纱基本不可见
      MaterialFab({
        onFabClick: () => {}
      }) {
        Column() {
          SaveButton({ icon: SaveIconStyle.LINES })
            .width(30)
            .height(30)
            .backgroundColor('#1AFFFFFF')
            .iconColor('#333333')
            .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
              if (result === SaveButtonOnClickResult.SUCCESS) {
                if (this.illust.pageCount > 1) {
                  this.handleSaveAll()
                } else {
                  this.handleSavePage(0)
                }
              } else {
                this.getUIContext().getPromptAction().showToast({ message: $r('app.string.detail_save_auth_cancelled') })
              }
            })
        }
        .gesture(
          LongPressGesture({ duration: 500 })
            .onAction(() => {
              if (this.illust.pageCount > 1) {
                this.openPageSelect()
              }
            })
        )
      }
    }
    .margin({ right: 16, bottom: 32 })
  }

  /** 选页弹窗单格：缩略图 + 勾选角标 + 页码；防社死模式下 R18 页纯色遮罩（弹层内不揭示） */
  @Builder
  PageSelectCell(url: string, index: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.appSettings.antiSocialDeath && this.isR18()) {
        Column() {
          Text('🔒')
            .fontSize(16)
            .opacity(0.4)
        }
        .width('100%')
        .aspectRatio(1)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#E0E0E0')
        .borderRadius(6)
      } else {
        CachedImage({ url: url, ratio: 1, fit: ImageFit.Cover })
      }
      // 勾选角标（右上）
      if (index < this.pageSelectChecked.length && this.pageSelectChecked[index]) {
        Text('✓')
          .fontSize(12)
          .fontColor('#FFFFFF')
          .width(20)
          .height(20)
          .borderRadius(10)
          .backgroundColor('#0096FA')
          .textAlign(TextAlign.Center)
          .margin(4)
      } else {
        Column()
          .width(20)
          .height(20)
          .borderRadius(10)
          .backgroundColor('rgba(0, 0, 0, 0.3)')
          .border({ width: 1, color: '#FFFFFF' })
          .margin(4)
      }
      // 页码（左下）
      Text('P' + (index + 1))
        .fontSize(10)
        .fontColor('#FFFFFF')
        .backgroundColor('rgba(0, 0, 0, 0.6)')
        .padding({ left: 4, right: 4, top: 1, bottom: 1 })
        .borderRadius(4)
        .margin(4)
        .align(Alignment.BottomStart)
    }
    .width('100%')
    .aspectRatio(1)
    .clip(true)
    .borderRadius(6)
    .border({
      width: 2,
      color: index < this.pageSelectChecked.length && this.pageSelectChecked[index] ? '#0096FA' : '#00000000'
    })
    .onClick(() => { this.togglePageSelect(index) })
    .gesture(
      LongPressGesture({ duration: 300 })
        .onAction(() => { this.startPageSelectDrag(index) })
    )
  }

  /** 选页弹窗：半透明遮罩 + 底部弹层（4 列缩略图网格；单击切换，长按≥300ms 激活拖选后滑动连选） */
  @Builder
  PageSelectOverlay() {
    Column() {
      Column() {
        // 头部：计数 + 全选/清空
        Row() {
          Text(getStrf($r('app.string.detail_page_select_title'), this.pageSelectCount(), this.pageSelectChecked.length))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .layoutWeight(1)
          Text($r('app.string.detail_select_all'))
            .fontSize(13)
            .fontColor('#0096FA')
            .onClick(() => { this.setAllPageSelect(true) })
          Text($r('app.string.common_clear'))
            .fontSize(13)
            .fontColor('#999999')
            .margin({ left: 16 })
            .onClick(() => { this.setAllPageSelect(false) })
        }
        .width('100%')
        .margin({ bottom: 12 })

        // 缩略图网格：priorityGesture 动态 distance——普通状态 10000vp 让位 Grid 滚动，
        // 长按激活拖选后 1vp 即触，滑动按经过格区间批量置目标状态
        Grid() {
          ForEach(this.pageSelectThumbUrls, (url: string, index: number) => {
            GridItem() {
              this.PageSelectCell(url, index)
            }
          }, (url: string, index: number) => index.toString() + '_' +
            (index < this.pageSelectChecked.length && this.pageSelectChecked[index] ? '1' : '0'))
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .columnsGap(8)
        .rowsGap(8)
        .width('100%')
        .layoutWeight(1)
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.pageSelectGridWidth = newArea.width as number
        })
        .onDidScroll((scrollOffset: number, _scrollState: ScrollState) => {
          this.pageSelectScrollOffset += scrollOffset
        })
        .priorityGesture(
          PanGesture(this.pageSelectPanOptions)
            .onActionUpdate((event: GestureEvent) => { this.onPageSelectPanUpdate(event) })
            .onActionEnd(() => { this.endPageSelectDrag() })
            .onActionCancel(() => { this.endPageSelectDrag() })
        )

        // 底部按钮：取消 / 确定下载(N)，空选择不发起
        Row({ space: 12 }) {
          Button($r('app.string.common_cancel'))
            .fontSize(14)
            .backgroundColor('#EEEEEE')
            .fontColor('#333333')
            .layoutWeight(1)
            .onClick(() => { this.closePageSelect() })
          Button(this.pageSelectCount() > 0 ?
            getStrf($r('app.string.detail_download_confirm_count'), this.pageSelectCount()) :
            getStr($r('app.string.detail_download_confirm')))
            .fontSize(14)
            .backgroundColor(this.pageSelectCount() > 0 ? '#0096FA' : '#CCCCCC')
            .fontColor('#FFFFFF')
            .layoutWeight(1)
            .onClick(() => { this.confirmPageSelect() })
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('100%')
      .height('75%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius({ topLeft: 16, topRight: 16 })
      // 内层消费点击防冒泡到遮罩关闭
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0, 0, 0, 0.4)')
    .justifyContent(FlexAlign.End)
    .onClick(() => { this.closePageSelect() })
  }

  @Builder
  MergeDialogOverlay() {
    Column() {
      Column() {
        Text($r('app.string.detail_merge_dialog_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .margin({ bottom: 12 })
        Text(getStrf($r('app.string.detail_merge_prompt'), this.mergeFromTag))
          .fontSize(14)
          .fontColor('#666666')
          .margin({ bottom: 16 })
        TextInput({ placeholder: $r('app.string.detail_merge_input_placeholder'), text: this.mergeInputText })
          .onChange((value: string) => {
            this.onMergeInputChange(value)
          })
          .width('100%')
          .margin({ bottom: 8 })
        // 输入补全建议区：本地来源即时、API 防抖兜底；点选回填
        if (this.mergeSuggestions.length > 0) {
          Column() {
            ForEach(this.mergeSuggestions, (name: string, index: number) => {
              Row() {
                Text(name)
                  .fontSize(14)
                  .fontColor('#333333')
                  .layoutWeight(1)
                if (index < this.mergeSuggestionSubs.length && this.mergeSuggestionSubs[index].length > 0) {
                  Text(this.mergeSuggestionSubs[index])
                    .fontSize(11)
                    .fontColor('#999999')
                    .margin({ left: 8 })
                }
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .onClick(() => {
                this.pickMergeSuggestion(name)
              })
            }, (name: string, index: number) => name + '_' + index)
          }
          .width('100%')
          .backgroundColor('#F8F8F8')
          .borderRadius(8)
          .margin({ bottom: 16 })
        }
        Row({ space: 12 }) {
          Button($r('app.string.common_cancel'))
            .fontSize(14)
            .backgroundColor('#EEEEEE')
            .fontColor('#333333')
            .layoutWeight(1)
            .onClick(() => {
              this.closeMergeDialog()
            })
          Button($r('app.string.detail_merge_confirm_btn'))
            .fontSize(14)
            .backgroundColor('#0096FA')
            .fontColor('#FFFFFF')
            .layoutWeight(1)
            .onClick(() => {
              if (this.mergeInputText.length > 0) {
                userSettingStore.addExifMergeRule(this.mergeInputText, [this.mergeFromTag])
                promptAction.showToast({ message: getStrf($r('app.string.detail_merge_done'), this.mergeFromTag, this.mergeInputText) })
                this.closeMergeDialog()
              }
            })
        }
        .width('100%')
      }
      .padding(20)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .width('85%')
      // 内层消费点击防冒泡到遮罩关闭（hitTestBehavior(Block) 会挡住输入框/按钮交互，已禁用）
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0, 0, 0, 0.4)')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.closeMergeDialog()
    })
  }

  /** 404 快照兜底卡片：快照元数据（标题/作者/页数/标签）+ 恢复入口 + 轮询进度/取消 */
  @Builder
  DeletedSnapshotCard(snapshot: BookmarkSnapshot) {
    Column() {
      Text($r('app.string.detail_deleted_notice'))
        .fontSize(14)
        .fontColor('#999999')
        .margin({ bottom: 12 })
      Column() {
        Text(snapshot.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .width('100%')
          .margin({ bottom: 8 })
        Text(getStrf($r('app.string.detail_deleted_author'), snapshot.userName, snapshot.userId))
          .fontSize(13)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })
        Text(getStrf($r('app.string.detail_deleted_meta'), snapshot.pageCount, snapshot.illustId))
          .fontSize(13)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })
        if (snapshot.tags.length > 0) {
          Text(snapshot.tags.join(' / '))
            .fontSize(12)
            .fontColor('#0096FA')
            .width('100%')
            .margin({ bottom: 4 })
        }
        if (snapshot.createDate.length > 0) {
          Text(getStrf($r('app.string.detail_published_at'), formatCreateDate(snapshot.createDate)))
            .fontSize(12)
            .fontColor('#999999')
            .width('100%')
        }
      }
      .width('85%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .margin({ bottom: 16 })

      if (this.recoverState === RECOVER_STATE_POLLING) {
        Text(this.recoverProgressText.length > 0 ? this.recoverProgressText : getStr($r('app.string.detail_recover_querying')))
          .fontSize(13)
          .fontColor('#666666')
          .margin({ bottom: 8 })
        Text($r('app.string.common_cancel'))
          .fontSize(14)
          .fontColor('#0096FA')
          .padding({ left: 24, right: 24, top: 8, bottom: 8 })
          .onClick(() => {
            this.cancelRecover()
          })
      } else if (this.store.canRecover()) {
        Text($r('app.string.detail_recover_try'))
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#0096FA')
          .borderRadius(8)
          .padding({ left: 24, right: 24, top: 8, bottom: 8 })
          .onClick(() => {
            this.startRecover()
          })
      } else {
        Text($r('app.string.detail_recover_need_relay'))
          .fontSize(12)
          .fontColor('#999999')
      }
      Text($r('app.string.detail_retry_load'))
        .fontSize(13)
        .fontColor('#999999')
        .margin({ top: 16 })
        .onClick(() => {
          this.loadDetail(this.illustId, true)
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F5F5F5')
  }

  /** US6 屏蔽占位视图（对齐 pixez BanPage）：屏蔽提示 + 查看屏蔽设置 + 临时查看（会话级） */
  @Builder
  MutedPlaceholder() {
    Column() {
      Text('🚫')
        .fontSize(32)
        .opacity(0.4)
      Text($r('app.string.detail_muted_placeholder'))
        .fontSize(14)
        .fontColor('#999999')
        .margin({ top: 12 })
      Text($r('app.string.detail_muted_temp_view'))
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor('#0096FA')
        .borderRadius(18)
        .padding({ left: 24, right: 24, top: 8, bottom: 8 })
        .margin({ top: 24 })
        .onClick(() => {
          this.tempRevealed = true
        })
      Text($r('app.string.detail_muted_view_settings'))
        .fontSize(13)
        .fontColor('#0096FA')
        .padding({ left: 24, right: 24, top: 8, bottom: 8 })
        .margin({ top: 8 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/settings/MutePage' })
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F5F5F5')
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        if (this.deletedSnapshot !== null && this.rows.length === 0) {
          this.DeletedSnapshotCard(this.deletedSnapshot)
        } else if (this.errorMessage && this.rows.length === 0) {
          ErrorView({ message: this.errorMessage, onRetry: () => { this.loadDetail(this.illustId) } })
        } else if (this.isLoading && this.rows.length === 0) {
          LoadingView()
        } else if (this.isMutedIllust() && !this.tempRevealed) {
          // US6：命中屏蔽规则 → 整页占位（防社死遮罩不受影响，占位优先级高于内容展示）
          this.MutedPlaceholder()
        } else {
          List() {
            ForEach(this.rows, (row: DetailRow) => {
              ListItem() {
                if (row.kind === 'image') {
                  this.ImageRow(row)
                } else if (row.kind === 'info') {
                  this.InfoRow()
                } else if (row.kind === 'related_header') {
                  this.RelatedHeaderRow()
                } else {
                  this.RelatedRow(row)
                }
              }
            }, (row: DetailRow) => row.kind + '_' + row.pageIndex + '_' +
              (row.related.length > 0 ? row.related[0].id : 0))
            // R4：相关作品手动"加载更多"兜底（触底自动加载失败时可手动重试）
            if (this.hasMoreRelated) {
              ListItem() {
                Text($r('app.string.detail_load_more'))
                  .fontSize(13)
                  .fontColor('#0096FA')
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 12, bottom: 24 })
                  .onClick(() => { this.loadMoreRelated() })
              }
            }
          }
          .width('100%')
          .layoutWeight(1)
          .onReachEnd(() => {
            // R4：相关作品触底自动加载（hasMoreRelated/relatedLoading 双门控）
            this.loadMoreRelated()
          })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: 44 })

      // R4 顶栏叠加：左返回 + 右 ⋮ 溢出菜单（半透明药丸按钮；Transparent 透传不遮挡内容滚动）。
      // 勿加 systemMaterial 沉浸光感：uiMaterial 在此区域不生效（渲染为透明），已踩坑回退
      Column() {
        Row() {
          Text('‹')
            .fontSize(24)
            .fontColor('#FFFFFF')
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor('rgba(0, 0, 0, 0.4)')
            .textAlign(TextAlign.Center)
            .onClick(() => { router.back() })
          Blank()
            .layoutWeight(1)
          Text('⋮')
            .fontSize(20)
            .fontColor('#FFFFFF')
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor('rgba(0, 0, 0, 0.4)')
            .textAlign(TextAlign.Center)
            .onClick(() => { this.topMenuShown = true })
            .bindContextMenu(this.topMenuShown, this.TopMenuBuilder, {
              onDisappear: () => { this.topMenuShown = false }
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .hitTestBehavior(HitTestMode.Transparent)

      // 双 FAB：主 Column 之后、各弹层之前；任一弹层打开时隐藏（屏蔽占位态亦不显示）
      if (this.illust.id > 0 && !this.exifPickerShown && !this.mergeReviewShown && !this.mergeDialogShown &&
        !this.pageSelectShown && !this.bookmarkTagPanelShown && (!this.isMutedIllust() || this.tempRevealed)) {
        this.FabOverlay()
      }

      // 带标签收藏面板（FAB 长按打开；内联底部弹层，作用于当前作品）
      BookmarkTagPanel({
        visible: this.$bookmarkTagPanelShown,
        onConfirm: (tags: string[], restrict: string) => {
          this.store.starWithTags(restrict, tags)
        },
        onCancel: () => {}
      })

      if (this.mergeDialogShown) {
        this.MergeDialogOverlay()
      }

      if (this.pageSelectShown) {
        this.PageSelectOverlay()
      }

      if (this.mergeReviewShown) {
        Column() {
          Column() {
            Text($r('app.string.detail_merge_review_title'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 12 })
            Text($r('app.string.detail_merge_review_desc'))
              .fontSize(12)
              .fontColor('#666666')
              .width('100%')
              .margin({ bottom: 12 })

            ForEach(this.mergeReviewGroups, (group: MergeGroup, groupIndex: number) => {
              Column() {
                Text(getStrf($r('app.string.detail_merge_translated'), group.translatedName))
                  .fontSize(12)
                  .fontColor('#999999')
                  .width('100%')
                  .margin({ bottom: 4 })
                ForEach(group.tags, (tag: ExifTag, tagIndex: number) => {
                  Row() {
                    Radio({ value: tag.name, group: 'merge_group_' + groupIndex })
                      .checked(this.mergeReviewSelected[groupIndex] === tag.name)
                      .hitTestBehavior(HitTestMode.Transparent)
                    Text(tag.name)
                      .fontSize(14)
                      .fontColor(this.mergeReviewSelected[groupIndex] === tag.name ? '#0096FA' : '#333333')
                      .margin({ left: 8 })
                    if (tag.translatedName.length > 0) {
                      Text(tag.translatedName)
                        .fontSize(11)
                        .fontColor('#999999')
                        .margin({ left: 4 })
                    }
                  }
                  .width('100%')
                  .height(40)
                  .padding({ left: 8, right: 8 })
                  .onClick(() => {
                    let newSelected = this.mergeReviewSelected.slice()
                    newSelected[groupIndex] = tag.name
                    this.mergeReviewSelected = newSelected
                  })
                }, (tag: ExifTag) => tag.name)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor('#FFFFFF')
              .borderRadius(8)
              .margin({ bottom: 8 })
            }, (group: MergeGroup, groupIndex: number) => group.translatedName + '_' + groupIndex)

            Row() {
              Button($r('app.string.detail_skip'))
                .fontSize(14)
                .backgroundColor('#F0F0F0')
                .fontColor('#666666')
                .layoutWeight(1)
                .onClick(() => {
                  this.mergeReviewShown = false
                  this.mergeReviewGroups = []
                  this.mergeReviewSelected = []
                })
              Button($r('app.string.detail_merge_confirm_btn'))
                .fontSize(14)
                .backgroundColor('#0096FA')
                .fontColor('#FFFFFF')
                .layoutWeight(1)
                .margin({ left: 12 })
                .onClick(() => { this.confirmMergeReview() })
            }
            .width('100%')
            .margin({ top: 12 })
          }
          .width('90%')
          .padding(16)
          .backgroundColor('#F5F5F5')
          .borderRadius(12)
          .onClick(() => {})
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.5)')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.mergeReviewShown = false
          this.mergeReviewGroups = []
          this.mergeReviewSelected = []
        })
      }

      if (this.exifPickerShown) {
        Column() {
          Column() {
            Text($r('app.string.detail_exif_picker_title'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 12 })

            // Preview area
            Column() {
              Text($r('app.string.common_preview'))
                .fontSize(12)
                .fontColor('#999999')
                .margin({ bottom: 4 })
              Text(this.exifPickerPreviewText)
                .fontSize(12)
                .fontColor('#333333')
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(getStrf($r('app.string.detail_exif_bytes'), this.exifPickerPreviewBytes, EXIF_FIELD_MAX_BYTES))
                .fontSize(12)
                .fontColor(this.exifPickerPreviewBytes > EXIF_FIELD_MAX_BYTES ? '#CC3333' : '#0096FA')
                .margin({ top: 4 })
            }
            .width('100%')
            .padding(8)
            .backgroundColor('#F8F8F8')
            .borderRadius(8)
            .margin({ bottom: 12 })

            // Writable tags section
            Row() {
              Text($r('app.string.detail_exif_writable'))
                .fontSize(14)
                .fontColor('#333333')
                .fontWeight(FontWeight.Medium)
              Text($r('app.string.detail_exif_writable_hint'))
                .fontSize(10)
                .fontColor('#999999')
                .margin({ left: 8 })
            }
            .width('100%')
            .margin({ bottom: 6 })

            List() {
              ForEach(this.exifPickerWritableItems, (item: ExifPickerItem, index: number) => {
                ListItem() {
                  Row() {
                    Row() {
                      Checkbox()
                        .select(item.checked)
                        .onChange((checked: boolean) => {
                          if (index >= 0 && index < this.exifPickerWritableItems.length) {
                            // 取消勾选 = 跳过本次写入（不持久化屏蔽）
                            this.exifPickerWritableItems[index].checked = checked
                            this.recalculateExifPickerPreview()
                          }
                        })
                      Column() {
                        Text(item.name)
                          .fontSize(13)
                          .fontColor('#333333')
                        if (this.getDisplayTranslation(item.name, item.translatedName).length > 0) {
                          Text(this.getDisplayTranslation(item.name, item.translatedName))
                            .fontSize(11)
                            .fontColor('#666666')
                            .margin({ top: 2 })
                        }
                      }
                      .layoutWeight(1)
                      .margin({ left: 8 })
                    }
                    .layoutWeight(1)
                    .gesture(
                      LongPressGesture({ duration: 300 })
                        .onAction(() => {
                          this.exifPickerMuteConfirmTarget = item.name
                        })
                    )
                    Text('≡')
                      .fontSize(18)
                      .fontColor('#999999')
                      .padding({ left: 8, right: 4, top: 4, bottom: 4 })
                  }
                  .width('100%')
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor(item.withinBudget && item.checked ? '#E6F4FF' : '#F0F0F0')
                  .borderRadius(6)
                  .margin({ bottom: 4 })
                }
              }, (item: ExifPickerItem, index: number) => item.name + '_' + index)
              .onMove((from: number, to: number) => {
                let items = this.exifPickerWritableItems.slice()
                let moved = items[from]
                items.splice(from, 1)
                items.splice(to, 0, moved)
                this.exifPickerWritableItems = items
                this.recalculateExifPickerPreview()
              })
            }
            .width('100%')
            .layoutWeight(1)
            .divider({ strokeWidth: 0 })

            // Muted tags section
            if (this.exifPickerMutedItems.length > 0) {
              Text($r('app.string.detail_exif_muted_section'))
                .fontSize(14)
                .fontColor('#CC3333')
                .fontWeight(FontWeight.Medium)
                .margin({ top: 8, bottom: 6 })

              List() {
                ForEach(this.exifPickerMutedItems, (item: ExifPickerItem, index: number) => {
                  ListItem() {
                    Row() {
                      Text(item.name)
                        .fontSize(13)
                        .fontColor('#CC3333')
                        .layoutWeight(1)
                      if (this.getDisplayTranslation(item.name, item.translatedName).length > 0) {
                        Text(this.getDisplayTranslation(item.name, item.translatedName))
                          .fontSize(11)
                          .fontColor('#999999')
                          .margin({ left: 4 })
                      }
                      Text($r('app.string.detail_exif_restore'))
                        .fontSize(12)
                        .fontColor('#0096FA')
                        .margin({ left: 8 })
                        .onClick(() => {
                          this.restoreExifPickerMutedTag(index)
                        })
                    }
                    .width('100%')
                    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                    .backgroundColor('#FFEAEA')
                    .borderRadius(6)
                    .margin({ bottom: 4 })
                  }
                }, (item: ExifPickerItem, index: number) => 'muted_' + item.name + '_' + index)
              }
              .width('100%')
              .height(Math.min(this.exifPickerMutedItems.length * 50, 150))
              .divider({ strokeWidth: 0 })
            }

            // Action buttons
            Row({ space: 12 }) {
              Button($r('app.string.detail_skip'))
                .fontSize(14)
                .backgroundColor('#EEEEEE')
                .fontColor('#333333')
                .layoutWeight(1)
                .onClick(() => {
                  this.onExifPickerSkip()
                })
              Button($r('app.string.common_confirm_action'))
                .fontSize(14)
                .backgroundColor('#0096FA')
                .fontColor('#FFFFFF')
                .layoutWeight(1)
                .onClick(() => {
                  this.onExifPickerConfirm()
                })
            }
            .width('100%')
            .margin({ top: 12 })

            // 长按屏蔽二次确认弹窗
            if (this.exifPickerMuteConfirmTarget.length > 0) {
              Column() {
                Text(getStrf($r('app.string.detail_mute_confirm_title'), this.exifPickerMuteConfirmTarget))
                  .fontSize(14)
                  .fontColor('#333333')
                  .margin({ bottom: 12 })
                Text($r('app.string.detail_mute_confirm_desc'))
                  .fontSize(12)
                  .fontColor('#666666')
                  .margin({ bottom: 16 })
                Row({ space: 12 }) {
                  Button($r('app.string.common_cancel'))
                    .fontSize(13)
                    .backgroundColor('#EEEEEE')
                    .fontColor('#333333')
                    .layoutWeight(1)
                    .onClick(() => {
                      this.exifPickerMuteConfirmTarget = ''
                    })
                  Button($r('app.string.detail_mute_confirm_btn'))
                    .fontSize(13)
                    .backgroundColor('#CC3333')
                    .fontColor('#FFFFFF')
                    .layoutWeight(1)
                    .onClick(() => {
                      this.muteExifPickerTag(this.exifPickerMuteConfirmTarget)
                    })
                }
                .width('100%')
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#FFF5F5')
              .borderRadius(8)
              .margin({ top: 8 })
            }
          }
          .padding(16)
          .width('100%')
          .height('80%')
          .backgroundColor('#FFFFFF')
          .borderRadius({ topLeft: 16, topRight: 16 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.4)')
        .justifyContent(FlexAlign.End)
        .onClick(() => {
          // 点击遮罩层不关闭，需要用户明确选择
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
