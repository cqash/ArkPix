import { router, promptAction } from '@kit.ArkUI';
import { imageCacheService } from '../../services/ImageCacheService';
import { downloadService } from '../../services/DownloadService';

interface ViewerParams {
  imageUrl: string
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

  async saveImage() {
    let params = router.getParams() as ViewerParams
    if (!params || !params.imageUrl) { return }
    let success = await downloadService.downloadImage(params.imageUrl, this.illustId, this.pageIndex)
    if (success) {
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
          Button('保存到图库')
            .fontSize(12)
            .backgroundColor('rgba(0, 150, 250, 0.8)')
            .onClick(() => { this.saveImage() })
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
