import { imageCacheService } from '../../services/ImageCacheService';

@Component
export struct CachedImage {
  @Prop url: string
  @State localPath: string = ''
  @State isLoading: boolean = true

  aboutToAppear() {
    this.loadImage()
  }

  async loadImage() {
    if (!this.url) {
      this.isLoading = false
      return
    }
    try {
      let path = await imageCacheService.getLocalPath(this.url)
      this.localPath = path
    } catch (e) {
      console.error('CachedImage load failed: ' + e)
    } finally {
      this.isLoading = false
    }
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .aspectRatio(1)
        .backgroundColor('#F5F5F5')
        .border({ width: 1, color: '#E5E5E5' })
      if (this.localPath) {
        Image('file://' + this.localPath)
          .width('100%')
          .aspectRatio(1)
          .objectFit(ImageFit.Cover)
          .borderRadius(8)
      } else if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(24)
            .height(24)
            .color('#0096FA')
          Text('加载中...')
            .fontSize(10)
            .fontColor('#999999')
            .margin({ top: 4 })
        }
        .width('100%')
        .aspectRatio(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Text('加载失败')
            .fontSize(12)
            .fontColor('#999999')
          Text('点击重试')
            .fontSize(10)
            .fontColor('#0096FA')
            .margin({ top: 4 })
        }
        .width('100%')
        .aspectRatio(1)
        .justifyContent(FlexAlign.Center)
        .onClick(() => { this.loadImage() })
      }
    }
    .width('100%')
    .aspectRatio(1)
  }
}
