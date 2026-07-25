import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Illust } from '../../models/Illust';
import { CachedImage } from '../common/CachedImage';
import { bookmarkStateStore, BOOKMARK_LOADING, BOOKMARK_DONE } from '../../stores/BookmarkStateStore';
import { userSettingStore } from '../../stores/UserSettingStore';
import { downloadService } from '../../services/DownloadService';
import { pickPreviewUrl, pickDetailUrl } from '../../utils/ImageUrlUtils';

/**
 * 公共插画卡片（@Reusable）：
 * 按真实宽高比展示（高/宽>3 降级方图）、标题、作者、多 P 角标、红心角标，
 * 长按弹出快捷菜单（保存 / 收藏 / 屏蔽作者）。
 */
@Reusable
@Component
export struct IllustCard {
  @State illust: Illust = new Illust()
  @State menuShown: boolean = false
  @StorageLink('bookmarkStates') bookmarkStates: Map<number, number> = new Map<number, number>()
  onCardClick: (illust: Illust) => void = (illust: Illust) => {}
  onMuteChange: () => void = () => {}

  aboutToReuse(params: Record<string, Object>) {
    this.illust = params.illust as Illust
    this.menuShown = false
    if (params.onCardClick !== undefined) {
      this.onCardClick = params.onCardClick as (illust: Illust) => void
    }
    if (params.onMuteChange !== undefined) {
      this.onMuteChange = params.onMuteChange as () => void
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
        title: '提示',
        message: '该图片已下载过',
        autoCancel: true,
        primaryButton: {
          value: '取消',
          action: () => {}
        },
        secondaryButton: {
          value: '仍要下载',
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
    let localPath = await downloadService.downloadToCache(url, this.illust, 0)
    if (!localPath) {
      this.showToast('下载失败')
      return
    }
    let ctx = AppStorage.get<common.Context>('context')
    if (!ctx) {
      this.showToast('保存失败')
      return
    }
    let saved = await downloadService.applyToGallery(localPath, ctx)
    if (saved) {
      this.showToast('已保存到图库')
      if (userSettingStore.getSettings().autoBookmarkOnDownload && this.heartState() !== BOOKMARK_DONE) {
        await bookmarkStateStore.star(this.illust)
      }
    } else {
      this.showToast('保存失败')
    }
  }

  private async toggleBookmark(): Promise<void> {
    let state = bookmarkStateStore.stateOf(this.illust.id, this.illust.isBookmarked)
    if (state === BOOKMARK_LOADING) {
      return
    }
    if (state === BOOKMARK_DONE) {
      await bookmarkStateStore.unstar(this.illust)
    } else {
      await bookmarkStateStore.star(this.illust)
    }
  }

  private muteAuthor(): void {
    userSettingStore.addMuteUser(this.illust.user.id)
    this.showToast('已屏蔽作者: ' + this.illust.user.name)
    this.onMuteChange()
  }

  @Builder
  MenuItem(label: string, action: () => void) {
    Text(label)
      .fontSize(14)
      .fontColor('#333333')
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .onClick(action)
  }

  @Builder
  MenuBuilder() {
    Column() {
      this.MenuItem('保存图片', () => { this.saveImage() })
      this.MenuItem(this.heartState() === BOOKMARK_DONE ? '取消收藏' : '收藏', () => { this.toggleBookmark() })
      this.MenuItem('屏蔽该作者', () => { this.muteAuthor() })
    }
    .width(160)
    .padding({ top: 4, bottom: 4 })
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        CachedImage({ url: this.previewUrl(), ratio: this.imageRatio(), fit: ImageFit.Cover })
        if (this.illust.pageCount > 1) {
          Text(this.illust.pageCount + 'P')
            .fontSize(10)
            .fontColor('#FFFFFF')
            .backgroundColor('rgba(0, 0, 0, 0.6)')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(8)
            .margin(6)
        }
        if (this.heartState() === BOOKMARK_DONE) {
          Text('♥')
            .fontSize(14)
            .fontColor('#FF4060')
            .backgroundColor('rgba(255, 255, 255, 0.85)')
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .borderRadius(10)
            .margin({ top: this.illust.pageCount > 1 ? 30 : 6, right: 6 })
        }
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
    .onClick(() => { this.onCardClick(this.illust) })
    .gesture(
      // 显式长按手势驱动 isShown 态菜单（瀑布流/LazyForEach 场景下
      // bindContextMenu 的内置 LongPress 触发不稳定，改为程序化触发）
      LongPressGesture({ fingers: 1, duration: 500 })
        .onAction(() => { this.menuShown = true })
    )
    .bindContextMenu(this.menuShown, this.MenuBuilder, {
      onDisappear: () => { this.menuShown = false }
    })
  }
}
