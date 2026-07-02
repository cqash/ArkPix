import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { imageCacheService } from '../../services/ImageCacheService';
import { downloadService } from '../../services/DownloadService';

interface ViewerParams {
  imageUrl: string
  downloadUrl: string
  illustId?: number
  pageIndex?: number
}

@Entry
@Component
struct ImageViewerPage {
  @State imagePath: string = ''
  @State isLoading: boolean = false
  @State illustId: number = 0
  @State pageIndex: number = 0

  aboutToAppear() {
    let params = router.getParams() as ViewerParams
    if (params && params.imageUrl) {
      this.illustId = params.illustId ?? 0
      this.pageIndex = params.pageIndex ?? 0
      this.loadImage(params.imageUrl)
    }
  }

  async loadImage(url: string) {
    this.isLoading = true
    this.imagePath = await imageCacheService.getLocalPath(url)
    this.isLoading = false
  }

  async handleSave(): Promise<void> {
    let params = router.getParams() as ViewerParams
    if (!params || !params.downloadUrl) { return }
    let localPath = await downloadService.downloadToCache(params.downloadUrl, this.illustId, this.pageIndex)
    if (!localPath) {
      promptAction.showToast({ message: '下载失败' })
      return
    }
    let ctx = AppStorage.get<common.Context>('context')
    if (!ctx) {
      promptAction.showToast({ message: '保存失败' })
      return
    }
    let saved = await downloadService.applyToGallery(localPath, ctx)
    if (saved) {
      promptAction.showToast({ message: '已保存到图库' })
    } else {
      promptAction.showToast({ message: '保存失败' })
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.imagePath) {
        Image('file://' + this.imagePath)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .backgroundColor('#000000')
          .onClick(() => {
            router.back()
          })
      } else if (this.isLoading) {
        LoadingProgress()
          .width(48)
          .height(48)
          .color('#FFFFFF')
      } else {
        Text('图片加载失败')
          .fontSize(16)
          .fontColor('#FFFFFF')
      }

      Column() {
        Row() {
          Button('返回')
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
