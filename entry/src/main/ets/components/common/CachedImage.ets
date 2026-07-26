import { imageCacheService } from '../../services/ImageCacheService';

/**
 * 预取图片到本地缓存（供查看器相邻页预加载等场景），
 * 不等待结果、失败静默。
 */
export function prefetchCachedImage(url: string): void {
  if (!url) {
    return
  }
  imageCacheService.getLocalPath(url).then(() => {
    // 预热完成，无需处理
  }).catch((e: Object) => {
    console.error('Prefetch image failed: ' + e)
  })
}

@Component
export struct CachedImage {
  @Prop @Watch('onUrlChange') url: string
  @Prop ratio: number = 1
  @Prop fit: ImageFit = ImageFit.Cover
  @State localPath: string = ''
  @State isLoading: boolean = true

  aboutToAppear() {
    this.loadImage()
  }

  onUrlChange(): void {
    this.localPath = ''
    this.isLoading = true
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
        .aspectRatio(this.ratio)
        .backgroundColor('#F5F5F5')
        .border({ width: 1, color: '#E5E5E5' })
      if (this.localPath) {
        Image('file://' + this.localPath)
          .width('100%')
          .aspectRatio(this.ratio)
          .objectFit(this.fit)
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
        .aspectRatio(this.ratio)
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
        .aspectRatio(this.ratio)
        .justifyContent(FlexAlign.Center)
        .onClick(() => { this.loadImage() })
      }
    }
    .width('100%')
    .aspectRatio(this.ratio)
  }
}
