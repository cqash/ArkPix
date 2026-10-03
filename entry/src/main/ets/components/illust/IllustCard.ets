import { promptAction } from '@kit.ArkUI';
import { Illust } from '../../models/Illust';
import { AppSettings } from '../../models/AppSettings';
import { CachedImage } from '../common/CachedImage';
import { bookmarkStateStore, BOOKMARK_LOADING, BOOKMARK_DONE } from '../../stores/BookmarkStateStore';
import { userSettingStore } from '../../stores/UserSettingStore';
import { downloadService } from '../../services/DownloadService';
import { pickPreviewUrl, pickDetailUrl } from '../../utils/ImageUrlUtils';
import { getStr, getStrf } from '../../utils/I18nUtils';
import { HapticUtils } from '../../utils/HapticUtils';

/**
 * 公共插画卡片（@Reusable）：
 * 按真实宽高比展示（高/宽>3 降级方图）、标题、作者、多 P 角标、红心角标。
 * 长按直接保存（对齐 pixez：单页存 p0、多页存全部页；longPressSaveConfirm 开启时先弹确认框）；
 * 「屏蔽作者」已迁至详情页画师行长按菜单。
 * 防社死模式下 R18/R18G 图片显示遮罩。
 */
@Reusable
@Component
export struct IllustCard {
  @State illust: Illust = new Illust()
  @StorageLink('bookmarkStates') bookmarkStates: Map<number, number> = new Map<number, number>()
  @StorageLink('appSettings') appSettings: AppSettings = new AppSettings()
  onCardClick: (illust: Illust) => void = (illust: Illust) => {}
  onMuteChange: () => void = () => {}
  /** 星标长按上抛（宿主打开带标签收藏面板） */
  onStarLongPress: (illust: Illust) => void = (illust: Illust) => {}

  aboutToReuse(params: Record<string, Object>) {
    this.illust = params.illust as Illust
    if (params.onCardClick !== undefined) {
      this.onCardClick = params.onCardClick as (illust: Illust) => void
    }
    if (params.onMuteChange !== undefined) {
      this.onMuteChange = params.onMuteChange as () => void
    }
    if (params.onStarLongPress !== undefined) {
      this.onStarLongPress = params.onStarLongPress as (illust: Illust) => void
    }
  }

  private imageRatio(): number {
    let w = this.illust.width
    let h = this.illust.height
    if (w > 0 && h > 0) {
      if (h / w > 3) {
        return 1
      }
      return w / h
    }
    return 1
  }

  private heartState(): number {
    let state = this.bookmarkStates.get(this.illust.id)
    if (state !== undefined) {
      return state
    }
    return this.illust.isBookmarked ? BOOKMARK_DONE : 0
  }

  private previewUrl(): string {
    return pickPreviewUrl(this.illust.imageUrls, userSettingStore.getSettings().previewQuality)
  }

  private isR18(): boolean {
    return this.illust.xRestrict === 1 || this.illust.xRestrict === 2
  }

  /** 星标单击：快速收藏/取消（pixez 卡片星标语义） */
  private toggleBookmark(): void {
    let state = bookmarkStateStore.stateOf(this.illust.id, this.illust.isBookmarked)
    if (state === BOOKMARK_LOADING) {
      return
    }
    HapticUtils.selectionClick()
    if (state === BOOKMARK_DONE) {
      bookmarkStateStore.unstar(this.illust)
    } else {
      bookmarkStateStore.star(this.illust)
    }
  }

  /** 星标长按：上抛宿主打开带标签收藏面板（已收藏时不响应） */
  private handleStarLongPress(): void {
    let state = bookmarkStateStore.stateOf(this.illust.id, this.illust.isBookmarked)
    if (state !== BOOKMARK_DONE && state !== BOOKMARK_LOADING) {
      HapticUtils.heavy()
      this.onStarLongPress(this.illust)
    }
  }

  private showToast(message: string): void {
    try {
      promptAction.showToast({ message: message })
    } catch (e) {
      console.error('Toast failed: ' + e)
    }
  }

  private async saveImage(): Promise<void> {
    let downloaded = await downloadService.isDownloaded(this.illust.id, 0)
    if (downloaded) {
      this.getUIContext().showAlertDialog({
        title: $r('app.string.common_tip'),
        message: $r('app.string.common_img_downloaded'),
        autoCancel: true,
        primaryButton: {
          value: $r('app.string.common_cancel'),
          action: () => {}
        },
        secondaryButton: {
          value: $r('app.string.common_download_anyway'),
          action: () => { this.doSaveImage() }
        }
      })
      return
    }
    await this.doSaveImage()
  }

  private async doSaveImage(): Promise<void> {
    let quality = userSettingStore.getSettings().downloadQuality
    let url = pickDetailUrl(this.illust, 0, quality)
    let result = downloadService.enqueue(url, this.illust, 0)
    this.showToast(getStr(result === 'inflight' ? $r('app.string.dl_already_in_queue') : $r('app.string.common_added_download')))
    if (userSettingStore.getSettings().autoBookmarkOnDownload && this.heartState() !== BOOKMARK_DONE) {
      await bookmarkStateStore.star(this.illust)
    }
  }

  /** 长按直存入口：longPressSaveConfirm 开启时先弹确认对话框（对齐 pixez） */
  private handleLongPress(): void {
    if (userSettingStore.getSettings().longPressSaveConfirm) {
      this.getUIContext().showAlertDialog({
        title: $r('app.string.common_tip'),
        message: this.illust.pageCount > 1 ?
          getStrf($r('app.string.card_save_confirm_multi'), this.illust.pageCount) :
          getStr($r('app.string.card_save_confirm_single')),
        autoCancel: true,
        primaryButton: {
          value: $r('app.string.common_cancel'),
          action: () => {}
        },
        secondaryButton: {
          value: $r('app.string.common_confirm'),
          action: () => { this.directSave() }
        }
      })
      return
    }
    this.directSave()
  }

  /** 直存：ugoira 走帧包入队分流；单页走既有单页流程；多页逐页重复检测，命中弹"跳过已下载页/全部重新下载"对话框 */
  private async directSave(): Promise<void> {
    if (this.illust.type === 'ugoira') {
      await this.saveUgoira()
      return
    }
    if (this.illust.pageCount <= 1) {
      await this.saveImage()
      return
    }
    let allPages: number[] = []
    let downloadedPages: number[] = []
    for (let i = 0; i < this.illust.pageCount; i++) {
      allPages.push(i)
      if (await downloadService.isDownloaded(this.illust.id, i)) {
        downloadedPages.push(i)
      }
    }
    if (downloadedPages.length > 0) {
      let freshPages: number[] = []
      for (let i = 0; i < allPages.length; i++) {
        if (downloadedPages.indexOf(allPages[i]) < 0) {
          freshPages.push(allPages[i])
        }
      }
      this.getUIContext().showAlertDialog({
        title: $r('app.string.store_dup_confirm_title'),
        message: getStrf($r('app.string.store_pages_downloaded'), downloadedPages.length),
        autoCancel: true,
        primaryButton: {
          value: $r('app.string.store_skip_downloaded'),
          action: () => { this.doSavePages(freshPages) }
        },
        secondaryButton: {
          value: $r('app.string.store_redownload_all'),
          action: () => { this.doSavePages(allPages) }
        }
      })
      return
    }
    await this.doSavePages(allPages)
  }

  /** 循环入队全部指定页（fire-and-forget）+ autoBookmarkOnDownload 联动；全部在途→"已在下载队列中" */
  private async doSavePages(pageIndexes: number[]): Promise<void> {
    if (pageIndexes.length === 0) {
      this.showToast(getStr($r('app.string.store_no_pages_to_download')))
      return
    }
    let quality = userSettingStore.getSettings().downloadQuality
    let enqueuedCount = 0
    let inflightCount = 0
    for (let i = 0; i < pageIndexes.length; i++) {
      let url = pickDetailUrl(this.illust, pageIndexes[i], quality)
      let result = downloadService.enqueue(url, this.illust, pageIndexes[i])
      if (result === 'inflight') {
        inflightCount++
      } else {
        enqueuedCount++
      }
    }
    if (enqueuedCount === 0 && inflightCount > 0) {
      this.showToast(getStr($r('app.string.dl_already_in_queue')))
    } else if (inflightCount > 0) {
      this.showToast(getStr($r('app.string.common_added_download')))
    } else {
      this.showToast(getStrf($r('app.string.store_added_downloads'), pageIndexes.length))
    }
    if (userSettingStore.getSettings().autoBookmarkOnDownload && this.heartState() !== BOOKMARK_DONE) {
      await bookmarkStateStore.star(this.illust)
    }
  }

  /** ugoira 直存：isUgoiraDownloaded 检测（命中走同款"取消/重新下载"确认）→ enqueueUgoira 入队 */
  private async saveUgoira(): Promise<void> {
    let downloaded = await downloadService.isUgoiraDownloaded(this.illust.id)
    if (downloaded) {
      this.getUIContext().showAlertDialog({
        title: $r('app.string.common_tip'),
        message: $r('app.string.common_img_downloaded'),
        autoCancel: true,
        primaryButton: {
          value: $r('app.string.common_cancel'),
          action: () => {}
        },
        secondaryButton: {
          value: $r('app.string.common_download_anyway'),
          action: () => { this.doSaveUgoira() }
        }
      })
      return
    }
    await this.doSaveUgoira()
  }

  private async doSaveUgoira(): Promise<void> {
    let result = downloadService.enqueueUgoira(this.illust)
    this.showToast(getStr(result === 'inflight' ? $r('app.string.dl_already_in_queue') : $r('app.string.common_added_download')))
    if (userSettingStore.getSettings().autoBookmarkOnDownload && this.heartState() !== BOOKMARK_DONE) {
      await bookmarkStateStore.star(this.illust)
    }
  }

  @Builder
  R18Mask() {
    Column() {
      Text('🔒')
        .fontSize(20)
        .opacity(0.4)
    }
    .width('100%')
    .aspectRatio(this.imageRatio())
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#E0E0E0')
    .borderRadius(8)
  }

  /** 已删除作品灰色占位卡片（收藏快照构造）：标题 + "已删除"角标，点击进详情走 404 兜底流程 */
  @Builder
  DeletedPlaceholderCard() {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column() {
          Text($r('app.string.card_deleted'))
            .fontSize(13)
            .fontColor('#999999')
        }
        .width('100%')
        .aspectRatio(this.imageRatio())
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#E0E0E0')
        .borderRadius(8)
        Text($r('app.string.card_deleted'))
          .fontSize(10)
          .fontColor('#FFFFFF')
          .backgroundColor('rgba(0, 0, 0, 0.45)')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(8)
          .margin(6)
      }
      .width('100%')

      Text(this.illust.title)
        .fontSize(12)
        .fontColor('#999999')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })
      Text(this.illust.user.name)
        .fontSize(10)
        .fontColor('#BBBBBB')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(4)
    .onClick(() => { this.onCardClick(this.illust) })
  }

  build() {
    if (this.illust.isDeletedPlaceholder) {
      this.DeletedPlaceholderCard()
    } else {
      this.NormalCard()
    }
  }

  @Builder
  NormalCard() {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (this.appSettings.antiSocialDeath && this.isR18()) {
          this.R18Mask()
        } else {
          CachedImage({ url: this.previewUrl(), ratio: this.imageRatio(), fit: ImageFit.Cover })
        }
        if (this.illust.pageCount > 1) {
          Text(this.illust.pageCount + 'P')
            .fontSize(10)
            .fontColor('#FFFFFF')
            .backgroundColor('rgba(0, 0, 0, 0.6)')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(8)
            .margin(6)
        }
        // ugoira 动图标记（与多页角标同款样式；ugoira pageCount 恒 1，两角标不叠加）
        if (this.illust.type === 'ugoira') {
          Text($r('app.string.ugoira_badge'))
            .fontSize(10)
            .fontColor('#FFFFFF')
            .backgroundColor('rgba(0, 0, 0, 0.6)')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(8)
            .margin(6)
        }
        // 星标角标（可交互）：未收藏=♡浅灰、已收藏=❤红、请求中=♥灰；单击快速收藏/取消，长按开带标签收藏面板
        Text(this.heartState() === BOOKMARK_DONE ? '❤' : '♡')
          .fontSize(14)
          .fontColor(this.heartState() === BOOKMARK_DONE ? '#FF4060' :
            this.heartState() === BOOKMARK_LOADING ? '#CCCCCC' : '#999999')
          .backgroundColor('rgba(255, 255, 255, 0.85)')
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .borderRadius(10)
          .margin({ top: this.illust.pageCount > 1 || this.illust.type === 'ugoira' ? 30 : 6, right: 6 })
          .onClick(() => { this.toggleBookmark() })
          .gesture(
            LongPressGesture({ fingers: 1, duration: 500 })
              .onAction(() => { this.handleStarLongPress() })
          )
      }
      .width('100%')

      Text(this.illust.title)
        .fontSize(12)
        .fontColor('#333333')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })
      Text(this.illust.user.name)
        .fontSize(10)
        .fontColor('#999999')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(4)
    .onClick(() => {
      HapticUtils.selectionClick()
      this.onCardClick(this.illust)
    })
    .gesture(
      LongPressGesture({ fingers: 1, duration: 500 })
        .onAction(() => {
          HapticUtils.heavy()
          this.handleLongPress()
        })
    )
  }
}
