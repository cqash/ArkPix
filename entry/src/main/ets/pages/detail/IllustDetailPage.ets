import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { imageCacheService } from '../../services/ImageCacheService';
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
import { continuationService } from '../../services/ContinuationService';
import { ContinuationPayload, CONTINUATION_PAGE_ILLUST_DETAIL } from '../../models/ContinuationPayload';
import { formatCreateDate } from '../../utils/DateUtils';
import { buildPageUrls } from '../../utils/ImageUrlUtils';
import { CachedImage } from '../../components/common/CachedImage';
import { IllustCard } from '../../components/illust/IllustCard';
import { ErrorView, LoadingView } from '../../components/common/CommonViews';
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

interface RouteParams {
  illustId: number
}

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

@Entry
@Component
struct IllustDetailPage {
  private store: IllustDetailStore = new IllustDetailStore()
  @State illust: Illust = new Illust()
  @State rows: DetailRow[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State illustId: number = 0
  @State deletedSnapshot: BookmarkSnapshot | null = null
  @State recoverState: string = RECOVER_STATE_IDLE
  @State recoverProgressText: string = ''
  @State userAvatarPath: string = ''
  @State revealedR18: boolean = false
  @State bookmarkMenuShown: boolean = false
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
  @StorageLink('bookmarkStates') bookmarkStates: Map<number, number> = new Map<number, number>()
  @StorageLink('appSettings') appSettings: AppSettings = new AppSettings()

  aboutToAppear() {
    this.store.uiContext = this.getUIContext()
    let params = router.getParams() as RouteParams
    if (params && params.illustId) {
      this.illustId = params.illustId
      this.loadDetail(params.illustId)
      // 多端流转：登记当前页面状态（供 onContinue 构建接续载荷）
      continuationService.setCurrentPageState(new ContinuationPayload({
        page: CONTINUATION_PAGE_ILLUST_DETAIL,
        illustId: params.illustId
      }))
    }
  }

  aboutToDisappear() {
    // 页面退出：停止恢复轮询，不残留后台任务
    this.store.cancelRecover()
    // 多端流转：清除页面状态登记
    continuationService.setCurrentPageState(null)
  }

  async loadDetail(id: number, forceRefresh: boolean = false) {
    if (this.rows.length === 0) {
      this.isLoading = true
    }
    this.errorMessage = ''
    this.deletedSnapshot = null
    let ok = await this.store.load(id, forceRefresh)
    if (ok || this.store.illust.id > 0) {
      this.illust = this.store.illust
      this.rebuildRows()
      this.loadAvatar()
      this.store.loadRelated().then(() => {
        this.rebuildRows()
      }).catch((e: Object) => {
        console.error('Load related failed: ' + e)
      })
    } else if (this.store.deletedSnapshot !== null) {
      // 404 + 有收藏快照：快照兜底分支（不显示普通错误页）
      this.deletedSnapshot = this.store.deletedSnapshot
      this.recoverState = RECOVER_STATE_IDLE
      this.recoverProgressText = ''
    } else {
      this.errorMessage = this.store.errorMessage || '加载失败'
    }
    this.isLoading = false
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
    promptAction.showToast({ message: '合并规则已保存，请再次点击保存' })
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
  BookmarkMenuBuilder() {
    Column() {
      Text('公开收藏')
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => { this.store.starWithRestrict('public') })
      Text('私密收藏')
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => { this.store.starWithRestrict('private') })
    }
    .width(140)
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  SaveMenuBuilder() {
    Column() {
      Text('保存当前页')
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => { this.handleSavePage(this.saveMenuPageIndex) })
      if (this.illust.pageCount > 1) {
        Text('保存全部页')
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
      Text('复制标签名')
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => {
          let data = pasteboard.createPlainTextData(this.tagMenuTarget)
          pasteboard.getSystemPasteboard().setData(data)
        })
      Text('屏蔽该标签')
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => {
          userSettingStore.addMuteTag(this.tagMenuTarget)
        })
      Text('备注中屏蔽')
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => {
          userSettingStore.addExifMutedTag(this.tagMenuTarget)
          promptAction.showToast({ message: '已从EXIF备注中屏蔽: ' + this.tagMenuTarget })
        })
      Text('备注中合并')
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

  /** 保存单页：先检测合并审查，再检测 EXIF 超限 */
  private handleSavePage(pageIndex: number): void {
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

  /** 保存全部页：先检测合并审查，再检测 EXIF 超限 */
  private handleSaveAll(): void {
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

  /** TagExifPicker 确认回调：更新 exifMutedTags 和 exifTagPriority 后继续保存 */
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

  /** TagExifPicker 跳过回调：直接保存不做过滤 */
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
          Text('点击显示')
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
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })
      .onClick(() => { this.goToUserProfile() })

      Row() {
        Text('收藏 ' + this.illust.totalBookmarks)
          .fontSize(12)
          .fontColor('#999999')
        Text('浏览 ' + this.illust.totalView)
          .fontSize(12)
          .fontColor('#999999')
          .margin({ left: 16 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })

      // 发布日期（本地时区 yyyy-MM-dd HH:mm；解析失败返回 '' 不渲染该行）
      if (formatCreateDate(this.illust.createDate).length > 0) {
        Row() {
          Text('发布于 ' + formatCreateDate(this.illust.createDate))
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
                  promptAction.showToast({ message: ok ? '已复制 PID' : '复制失败' })
                })
              })
          )
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.illust.tags, (tag: Tag) => {
          this.TagChip(tag)
        }, (tag: Tag) => tag.name)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })

      // 查看评论：tag 云之后、相关作品之前的居中小号文字按钮（原按钮区已迁移至右下角双 FAB）
      Text('查看评论')
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
      Text('相关作品')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  RelatedRow(row: DetailRow) {
    Row() {
      ForEach(row.related, (item: Illust) => {
        Column() {
          IllustCard({
            illust: item,
            onCardClick: (target: Illust) => {
              router.pushUrl({ url: 'pages/detail/IllustDetailPage', params: { illustId: target.id } })
            }
          })
        }
        .width('33.3%')
      }, (item: Illust) => item.id.toString())
    }
    .width('100%')
  }

  /** 右下角双 FAB：收藏（点按收藏/取消，长按公开/私密菜单；未收藏=浅灰♡，已收藏=红❤）+
   *  下载（蓝底白↓；单击=保存全部页/单页保存，长按仅多页=选页弹窗） */
  @Builder
  FabOverlay() {
    Column({ space: 12 }) {
      // 收藏 FAB
      Stack({ alignContent: Alignment.Center }) {
        Text(this.bookmarkState() === BOOKMARK_DONE ? '❤' : '♡')
          .fontSize(22)
          .fontColor(this.bookmarkState() === BOOKMARK_DONE ? '#FF4081' :
            this.bookmarkState() === BOOKMARK_LOADING ? '#CCCCCC' : '#999999')
      }
      .width(52)
      .height(52)
      .borderRadius(26)
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 8, color: 'rgba(0, 0, 0, 0.2)', offsetY: 2 })
      .onClick(() => { this.store.toggleBookmark() })
      .gesture(
        LongPressGesture({ duration: 500 })
          .onAction(() => {
            if (this.bookmarkState() === 0) {
              this.bookmarkMenuShown = true
            }
          })
      )
      .bindContextMenu(this.bookmarkMenuShown, this.BookmarkMenuBuilder, {
        onDisappear: () => { this.bookmarkMenuShown = false }
      })

      // 下载 FAB：SaveButton 安全控件（点击获 1 分钟临时图库写权限，实现静默保存；
      // 首次点击系统弹一次授权，之后不再弹）；长按仅多页=选页弹窗
      Stack({ alignContent: Alignment.Center }) {
        SaveButton({ icon: SaveIconStyle.FULL_FILLED, buttonType: ButtonType.Circle })
          .width(52)
          .height(52)
          .backgroundColor('#0096FA')
          .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
            if (result === SaveButtonOnClickResult.SUCCESS) {
              if (this.illust.pageCount > 1) {
                this.handleSaveAll()
              } else {
                this.handleSavePage(0)
              }
            } else {
              this.getUIContext().getPromptAction().showToast({ message: '保存授权被取消' })
            }
          })
      }
      .width(52)
      .height(52)
      .borderRadius(26)
      .backgroundColor('#0096FA')
      .shadow({ radius: 8, color: 'rgba(0, 0, 0, 0.2)', offsetY: 2 })
      .gesture(
        LongPressGesture({ duration: 500 })
          .onAction(() => {
            if (this.illust.pageCount > 1) {
              this.openPageSelect()
            }
          })
      )
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
          Text('选择下载页（' + this.pageSelectCount() + '/' + this.pageSelectChecked.length + '）')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .layoutWeight(1)
          Text('全选')
            .fontSize(13)
            .fontColor('#0096FA')
            .onClick(() => { this.setAllPageSelect(true) })
          Text('清空')
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
          Button('取消')
            .fontSize(14)
            .backgroundColor('#EEEEEE')
            .fontColor('#333333')
            .layoutWeight(1)
            .onClick(() => { this.closePageSelect() })
          Button(this.pageSelectCount() > 0 ? '确定下载(' + this.pageSelectCount() + ')' : '确定下载')
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
        Text('合并标签到…')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .margin({ bottom: 12 })
        Text('将 [' + this.mergeFromTag + '] 合并到以下主标签：')
          .fontSize(14)
          .fontColor('#666666')
          .margin({ bottom: 16 })
        TextInput({ placeholder: '输入主标签名', text: this.mergeInputText })
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
          Button('取消')
            .fontSize(14)
            .backgroundColor('#EEEEEE')
            .fontColor('#333333')
            .layoutWeight(1)
            .onClick(() => {
              this.closeMergeDialog()
            })
          Button('确认合并')
            .fontSize(14)
            .backgroundColor('#0096FA')
            .fontColor('#FFFFFF')
            .layoutWeight(1)
            .onClick(() => {
              if (this.mergeInputText.length > 0) {
                userSettingStore.addExifMergeRule(this.mergeInputText, [this.mergeFromTag])
                promptAction.showToast({ message: '已将 [' + this.mergeFromTag + '] 合并到 [' + this.mergeInputText + ']' })
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
      Text('该作品已被删除或不可访问')
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
        Text('作者：' + snapshot.userName + '（UID:' + snapshot.userId + '）')
          .fontSize(13)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })
        Text('共 ' + snapshot.pageCount + ' 页 · PID: ' + snapshot.illustId)
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
          Text('发布于 ' + formatCreateDate(snapshot.createDate))
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
        Text(this.recoverProgressText.length > 0 ? this.recoverProgressText : '正在查询第三方源…')
          .fontSize(13)
          .fontColor('#666666')
          .margin({ bottom: 8 })
        Text('取消')
          .fontSize(14)
          .fontColor('#0096FA')
          .padding({ left: 24, right: 24, top: 8, bottom: 8 })
          .onClick(() => {
            this.cancelRecover()
          })
      } else if (this.store.canRecover()) {
        Text('尝试从第三方恢复')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#0096FA')
          .borderRadius(8)
          .padding({ left: 24, right: 24, top: 8, bottom: 8 })
          .onClick(() => {
            this.startRecover()
          })
      } else {
        Text('在设置页配置并注册中继服务器后，可尝试从第三方恢复')
          .fontSize(12)
          .fontColor('#999999')
      }
      Text('重试加载')
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

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        if (this.deletedSnapshot !== null && this.rows.length === 0) {
          this.DeletedSnapshotCard(this.deletedSnapshot)
        } else if (this.errorMessage && this.rows.length === 0) {
          ErrorView({ message: this.errorMessage, onRetry: () => { this.loadDetail(this.illustId) } })
        } else if (this.isLoading && this.rows.length === 0) {
          LoadingView()
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
          }
          .width('100%')
          .layoutWeight(1)
          .onReachEnd(() => {
            this.store.loadMoreRelated().then(() => {
              this.rebuildRows()
            }).catch((e: Object) => {
              console.error('Load more related failed: ' + e)
            })
          })
        }
      }
      .width('100%')
      .height('100%')

      // 双 FAB：主 Column 之后、各弹层之前；任一弹层打开时隐藏
      if (this.illust.id > 0 && !this.exifPickerShown && !this.mergeReviewShown && !this.mergeDialogShown &&
        !this.pageSelectShown) {
        this.FabOverlay()
      }

      if (this.mergeDialogShown) {
        this.MergeDialogOverlay()
      }

      if (this.pageSelectShown) {
        this.PageSelectOverlay()
      }

      if (this.mergeReviewShown) {
        Column() {
          Column() {
            Text('同义标签审查')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 12 })
            Text('检测到以下标签拥有相同翻译，请选择作为备注主标签的标签名：')
              .fontSize(12)
              .fontColor('#666666')
              .width('100%')
              .margin({ bottom: 12 })

            ForEach(this.mergeReviewGroups, (group: MergeGroup, groupIndex: number) => {
              Column() {
                Text('翻译: ' + group.translatedName)
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
              Button('跳过')
                .fontSize(14)
                .backgroundColor('#F0F0F0')
                .fontColor('#666666')
                .layoutWeight(1)
                .onClick(() => {
                  this.mergeReviewShown = false
                  this.mergeReviewGroups = []
                  this.mergeReviewSelected = []
                })
              Button('确认合并')
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
            Text('EXIF 备注标签选择')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 12 })

            // Preview area
            Column() {
              Text('预览')
                .fontSize(12)
                .fontColor('#999999')
                .margin({ bottom: 4 })
              Text(this.exifPickerPreviewText)
                .fontSize(12)
                .fontColor('#333333')
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(this.exifPickerPreviewBytes + ' / ' + EXIF_FIELD_MAX_BYTES + ' 字节')
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
              Text('可写入标签')
                .fontSize(14)
                .fontColor('#333333')
                .fontWeight(FontWeight.Medium)
              Text('取消勾选=跳过本次 | 长按=永久屏蔽')
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
              Text('已屏蔽标签')
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
                      Text('恢复')
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
              Button('跳过')
                .fontSize(14)
                .backgroundColor('#EEEEEE')
                .fontColor('#333333')
                .layoutWeight(1)
                .onClick(() => {
                  this.onExifPickerSkip()
                })
              Button('确认')
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
                Text('确认屏蔽标签「' + this.exifPickerMuteConfirmTarget + '」？')
                  .fontSize(14)
                  .fontColor('#333333')
                  .margin({ bottom: 12 })
                Text('屏蔽后该标签在所有作品的 EXIF 中都不会写入，可在设置中恢复。')
                  .fontSize(12)
                  .fontColor('#666666')
                  .margin({ bottom: 16 })
                Row({ space: 12 }) {
                  Button('取消')
                    .fontSize(13)
                    .backgroundColor('#EEEEEE')
                    .fontColor('#333333')
                    .layoutWeight(1)
                    .onClick(() => {
                      this.exifPickerMuteConfirmTarget = ''
                    })
                  Button('确认屏蔽')
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
