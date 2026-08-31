import { router, promptAction } from '@kit.ArkUI';
import { downloadService } from '../../services/DownloadService';
import { Illust } from '../../models/Illust';
import { AppSettings } from '../../models/AppSettings';
import { userSettingStore } from '../../stores/UserSettingStore';
import { bookmarkStateStore, BOOKMARK_DONE } from '../../stores/BookmarkStateStore';
import { ZoomableImage } from '../../components/viewer/ZoomableImage';
import { prefetchCachedImage } from '../../components/common/CachedImage';

interface ViewerParams {
  imageUrl?: string
  downloadUrl?: string
  urls?: string[]
  downloadUrls?: string[]
  illust?: Illust
  pageIndex?: number
}

@Entry
@Component
struct ImageViewerPage {
  @State urls: string[] = []
  @State downloadUrls: string[] = []
  @State illust: Illust = new Illust()
  @State currentIndex: number = 0
  @State isZoomed: boolean = false
  @State revealedR18: boolean = false
  @StorageLink('appSettings') appSettings: AppSettings = new AppSettings()

  aboutToAppear() {
    let params = router.getParams() as ViewerParams
    if (!params) {
      return
    }
    this.illust = params.illust ?? new Illust()
    if (params.urls !== undefined && params.urls.length > 0) {
      this.urls = params.urls
      this.downloadUrls = params.downloadUrls ?? params.urls
      let index = params.pageIndex ?? 0
      if (index < 0 || index >= this.urls.length) {
        index = 0
      }
      this.currentIndex = index
    } else if (params.imageUrl !== undefined) {
      // 兼容旧单页入口
      this.urls = [params.imageUrl]
      this.downloadUrls = [params.downloadUrl ?? params.imageUrl]
      this.currentIndex = 0
    }
    this.prefetchNeighbors(this.currentIndex)
  }

  private isR18(): boolean {
    return this.illust.xRestrict === 1 || this.illust.xRestrict === 2
  }

  private needMask(): boolean {
    return this.appSettings.antiSocialDeath && this.isR18() && !this.revealedR18
  }

  private prefetchNeighbors(index: number): void {
    if (index - 1 >= 0 && index - 1 < this.urls.length) {
      prefetchCachedImage(this.urls[index - 1])
    }
    if (index + 1 >= 0 && index + 1 < this.urls.length) {
      prefetchCachedImage(this.urls[index + 1])
    }
  }

  onIndexChange(index: number): void {
    this.currentIndex = index
    this.prefetchNeighbors(index)
  }

  async handleSave(): Promise<void> {
    if (this.downloadUrls.length === 0 || this.currentIndex >= this.downloadUrls.length) {
      return
    }
    let downloaded = await downloadService.isDownloaded(this.illust.id, this.currentIndex)
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
          action: () => { this.doSave() }
        }
      })
      return
    }
    await this.doSave()
  }

  private async doSave(): Promise<void> {
    downloadService.enqueue(this.downloadUrls[this.currentIndex], this.illust, this.currentIndex)
    promptAction.showToast({ message: $r('app.string.common_added_download') })
    // 下载时自动收藏联动，走 BookmarkStateStore 保证跨页同步
    if (userSettingStore.getSettings().autoBookmarkOnDownload && this.illust.id > 0 &&
      bookmarkStateStore.stateOf(this.illust.id, this.illust.isBookmarked) !== BOOKMARK_DONE) {
      await bookmarkStateStore.star(this.illust, 'public')
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.needMask()) {
        Column() {
          Text('🔒')
            .fontSize(32)
            .opacity(0.25)
          Text($r('app.string.detail_tap_to_show'))
            .fontSize(13)
            .fontColor('rgba(255, 255, 255, 0.3)')
            .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#2C2C2C')
        .onClick(() => {
          this.revealedR18 = true
          this.prefetchNeighbors(this.currentIndex)
        })
      } else {
        Swiper() {
          ForEach(this.urls, (url: string) => {
            ZoomableImage({
              url: url,
              onZoomChange: (zoomed: boolean) => { this.isZoomed = zoomed }
            })
          }, (url: string) => url)
        }
        .index(this.currentIndex)
        .indicator(false)
        .disableSwipe(this.isZoomed)
        .onChange((index: number) => { this.onIndexChange(index) })
        .width('100%')
        .height('100%')
      }

      Column() {
        Row() {
          Button($r('app.string.common_back'))
            .fontSize(12)
            .backgroundColor('rgba(0, 0, 0, 0.5)')
            .onClick(() => { router.back() })
          Blank()
            .layoutWeight(1)
          SaveButton({ icon: SaveIconStyle.FULL_FILLED, text: SaveDescription.SAVE })
            .onClick(async (_event: ClickEvent, result: SaveButtonOnClickResult) => {
              if (result === SaveButtonOnClickResult.SUCCESS) {
                await this.handleSave()
              }
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16 })
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .hitTestBehavior(HitTestMode.Transparent)

      if (this.urls.length > 1) {
        Column() {
          Text((this.currentIndex + 1) + '/' + this.urls.length)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('rgba(0, 0, 0, 0.5)')
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .borderRadius(12)
            .margin({ bottom: 32 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
