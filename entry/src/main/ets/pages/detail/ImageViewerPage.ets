import { router } from '@kit.ArkUI';
import { imageCacheService } from '../../services/ImageCacheService';

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

  aboutToAppear() {
    let params = router.getParams() as ViewerParams
    if (params && params.imageUrl) {
      this.loadImage(params.imageUrl)
    }
  }

  async loadImage(url: string) {
    this.isLoading = true
    this.imagePath = await imageCacheService.getLocalPath(url)
    this.isLoading = false
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

      Row() {
        Button('返回')
          .fontSize(12)
          .backgroundColor('rgba(0, 0, 0, 0.5)')
          .onClick(() => { router.back() })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16 })
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
