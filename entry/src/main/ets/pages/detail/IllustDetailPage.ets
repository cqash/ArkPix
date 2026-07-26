import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { imageCacheService } from '../../services/ImageCacheService';
import { Illust, Tag } from '../../models/Illust';
import { AppSettings } from '../../models/AppSettings';
import { userSettingStore } from '../../stores/UserSettingStore';
import { BOOKMARK_LOADING, BOOKMARK_DONE } from '../../stores/BookmarkStateStore';
import { IllustDetailStore, DetailRow } from '../../stores/IllustDetailStore';
import { Constants } from '../../utils/Constants';
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

@Entry
@Component
struct IllustDetailPage {
  private store: IllustDetailStore = new IllustDetailStore()
  @State illust: Illust = new Illust()
  @State rows: DetailRow[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State illustId: number = 0
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
  @State exifPickerShown: boolean = false
  @State exifPickerPageIndex: number = 0
  @State exifPickerIsSaveAll: boolean = false
  @State exifPickerWritableItems: ExifPickerItem[] = []
  @State exifPickerMutedItems: ExifPickerItem[] = []
  @State exifPickerPreviewText: string = ''
  @State exifPickerPreviewBytes: number = 0
  @State exifPickerDragFromIndex: number = -1
  @State exifPickerMuteConfirmTarget: string = ''
  @State mergeReviewShown: boolean = false
  @State mergeReviewGroups: MergeGroup[] = []
  @State mergeReviewSelected: string[] = []  // 每组选中的主 tag 名
  @StorageLink('bookmarkStates') bookmarkStates: Map<number, number> = new Map<number, number>()
  @StorageLink('appSettings') appSettings: AppSettings = new AppSettings()

  aboutToAppear() {
    this.store.uiContext = this.getUIContext()
    let params = router.getParams() as RouteParams
    if (params && params.illustId) {
      this.illustId = params.illustId
      this.loadDetail(params.illustId)
    }
  }

  async loadDetail(id: number, forceRefresh: boolean = false) {
    if (this.rows.length === 0) {
      this.isLoading = true
    }
    this.errorMessage = ''
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
    } else {
      this.errorMessage = this.store.errorMessage || '加载失败'
    }
    this.isLoading = false
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
      this.exifPickerPageIndex = pageIndex
      this.exifPickerIsSaveAll = false
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
      this.exifPickerPageIndex = 0
      this.exifPickerIsSaveAll = true
      this.initExifPickerItems()
      this.exifPickerShown = true
    } else {
      this.store.saveAll()
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
    if (this.exifPickerIsSaveAll) {
      this.store.saveAll()
    } else {
      this.store.savePage(this.exifPickerPageIndex)
    }
  }

  /** TagExifPicker 跳过回调：直接保存不做过滤 */
  private onExifPickerSkip(): void {
    this.exifPickerShown = false
    if (this.exifPickerIsSaveAll) {
      this.store.saveAll()
    } else {
      this.store.savePage(this.exifPickerPageIndex)
     }
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

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.illust.tags, (tag: Tag) => {
          this.TagChip(tag)
        }, (tag: Tag) => tag.name)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })

      Row() {
        Button(this.bookmarkState() === BOOKMARK_LOADING ? '收藏中...' :
          this.bookmarkState() === BOOKMARK_DONE ? '已收藏' : '收藏')
          .width('28%')
          .fontSize(13)
          .backgroundColor(this.bookmarkState() === BOOKMARK_DONE ? '#FF6B6B' :
            this.bookmarkState() === BOOKMARK_LOADING ? '#999999' : '#0096FA')
          .enabled(this.bookmarkState() !== BOOKMARK_LOADING)
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

        Button('保存图片')
          .width('28%')
          .fontSize(13)
          .backgroundColor('#0096FA')
          .onClick(() => {
            if (this.illust.pageCount > 1) {
              this.saveMenuPageIndex = 0
              this.saveMenuShown = true
            } else {
              this.handleSavePage(0)
            }
          })
          .bindContextMenu(this.saveMenuShown && this.saveMenuPageIndex === 0, this.SaveMenuBuilder, {
            onDisappear: () => { this.saveMenuShown = false }
          })

        if (this.illust.pageCount > 1) {
          Button('下载全部')
            .width('28%')
            .fontSize(13)
            .backgroundColor('#FF8800')
            .onClick(() => { this.handleSaveAll() })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .padding({ top: 16, bottom: 16 })
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
            this.mergeInputText = value
          })
          .width('100%')
          .margin({ bottom: 24 })
        Row({ space: 12 }) {
          Button('取消')
            .fontSize(14)
            .backgroundColor('#EEEEEE')
            .fontColor('#333333')
            .layoutWeight(1)
            .onClick(() => {
              this.mergeDialogShown = false
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
                this.mergeDialogShown = false
              }
            })
        }
        .width('100%')
      }
      .padding(20)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .width('85%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0, 0, 0, 0.4)')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.mergeDialogShown = false
    })
  }

  build() {
    Stack() {
      Column() {
        if (this.errorMessage && this.rows.length === 0) {
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

      if (this.mergeDialogShown) {
        this.MergeDialogOverlay()
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
                      .onChange((isChecked: boolean) => {
                        if (isChecked) {
                          let newSelected = this.mergeReviewSelected.slice()
                          newSelected[groupIndex] = tag.name
                          this.mergeReviewSelected = newSelected
                        }
                      })
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
                    Text('≡')
                      .fontSize(18)
                      .fontColor('#999999')
                  }
                  .width('100%')
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor(item.withinBudget && item.checked ? '#E6F4FF' : '#F0F0F0')
                  .borderRadius(6)
                  .margin({ bottom: 4 })
                }
                .gesture(
                  LongPressGesture({ duration: 300 })
                    .onAction(() => {
                      this.exifPickerMuteConfirmTarget = item.name
                    })
                )
              }, (item: ExifPickerItem, index: number) => item.name + '_' + index)
            }
            .width('100%')
            .layoutWeight(1)
            .divider({ strokeWidth: 0 })
            .onItemDragStart((event: ItemDragInfo, itemIndex: number) => {
              this.exifPickerDragFromIndex = itemIndex
              return null
            })
            .onItemDrop((event: ItemDragInfo, itemIndex: number, insertIndex: number) => {
              if (itemIndex >= 0 && insertIndex >= 0 && itemIndex !== insertIndex &&
                itemIndex < this.exifPickerWritableItems.length && insertIndex < this.exifPickerWritableItems.length) {
                let items = this.exifPickerWritableItems.slice()
                let moved = items[itemIndex]
                items.splice(itemIndex, 1)
                items.splice(insertIndex, 0, moved)
                this.exifPickerWritableItems = items
                this.recalculateExifPickerPreview()
              }
              this.exifPickerDragFromIndex = -1
            })

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
