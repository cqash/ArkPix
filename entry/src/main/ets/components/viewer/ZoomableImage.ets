import { display } from '@kit.ArkUI';
import { imageCacheService } from '../../services/ImageCacheService';

/**
 * 可缩放图片（官方手势竞争方案，禁止回退条件手势组）：
 * - GestureGroup(Parallel, Pinch + Pan + Tap) 静态常驻挂载，不按 scale 条件切换手势组；
 * - PanGesture distance 动态化：scale=1 时 50vp（让位 Swiper 翻页），scale>1 时 3vp（跟手平移）；
 * - 放大后拖到 X 向边界继续外拖时通过 onZoomChange(false) 释放回 Swiper 翻页，松手后恢复；
 * - 双击 1↔2.5 倍切换；缩放限幅 1~maxScale，平移边界钳制。
 */
@Component
export struct ZoomableImage {
  @Prop url: string = ''
  maxScale: number = 5
  onZoomChange: (isZoomed: boolean) => void = (isZoomed: boolean) => {}
  @State localPath: string = ''
  @State isLoading: boolean = true
  @State loadFailed: boolean = false
  @State scaleValue: number = 1
  @State offsetX: number = 0
  @State offsetY: number = 0
  private baseScale: number = 1
  private panStartX: number = 0
  private panStartY: number = 0
  private releasedAtEdge: boolean = false

  aboutToAppear() {
    this.load()
  }

  async load() {
    if (!this.url) {
      this.isLoading = false
      this.loadFailed = true
      return
    }
    this.isLoading = true
    this.loadFailed = false
    try {
      let path = await imageCacheService.getLocalPath(this.url)
      this.localPath = path
      this.loadFailed = path.length === 0
    } catch (e) {
      console.error('ZoomableImage load failed: ' + e)
      this.loadFailed = true
    } finally {
      this.isLoading = false
    }
  }

  private clampScale(value: number): number {
    if (value < 1) {
      return 1
    }
    if (value > this.maxScale) {
      return this.maxScale
    }
    return value
  }

  private maxOffsetX(): number {
    let disp = display.getDefaultDisplaySync()
    return (this.scaleValue - 1) * (disp.width / disp.densityPixels / 2)
  }

  private clampOffsets(): void {
    let disp = display.getDefaultDisplaySync()
    let halfW = disp.width / disp.densityPixels / 2
    let halfH = disp.height / disp.densityPixels / 2
    let maxX = (this.scaleValue - 1) * halfW
    let maxY = (this.scaleValue - 1) * halfH
    if (this.offsetX > maxX) {
      this.offsetX = maxX
    }
    if (this.offsetX < -maxX) {
      this.offsetX = -maxX
    }
    if (this.offsetY > maxY) {
      this.offsetY = maxY
    }
    if (this.offsetY < -maxY) {
      this.offsetY = -maxY
    }
  }

  private applyScale(value: number): void {
    this.scaleValue = this.clampScale(value)
    if (this.scaleValue === 1) {
      this.offsetX = 0
      this.offsetY = 0
    } else {
      this.clampOffsets()
    }
    this.onZoomChange(this.scaleValue > 1)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.localPath) {
        Image('file://' + this.localPath)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .scale({ x: this.scaleValue, y: this.scaleValue })
          .translate({ x: this.offsetX, y: this.offsetY })
      } else if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color('#FFFFFF')
          Text('大图加载中...')
            .fontSize(12)
            .fontColor('#CCCCCC')
            .margin({ top: 8 })
        }
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Text('图片加载失败')
            .fontSize(16)
            .fontColor('#FFFFFF')
          Text('点击重试')
            .fontSize(12)
            .fontColor('#0096FA')
            .margin({ top: 8 })
        }
        .justifyContent(FlexAlign.Center)
        .onClick(() => { this.load() })
      }
    }
    .width('100%')
    .height('100%')
    .gesture(
      // 静态常驻手势组：Pinch/Pan/Tap 始终挂载，仅靠 Pan distance 动态值仲裁竞争
      GestureGroup(GestureMode.Parallel,
        PinchGesture({ fingers: 2, distance: 1 })
          .onActionStart(() => {
            this.baseScale = this.scaleValue
          })
          .onActionUpdate((event: GestureEvent) => {
            this.applyScale(this.baseScale * event.scale)
          })
          .onActionEnd(() => {
            if (this.scaleValue < 1.05) {
              this.applyScale(1)
            }
          }),
        // distance 动态：scale=1 → 50vp 内不触发（Swiper 赢得竞争翻页）；scale>1 → 3vp 即触即发
        PanGesture({ fingers: 1, distance: this.scaleValue > 1 ? 3 : 50 })
          .onActionStart(() => {
            this.panStartX = this.offsetX
            this.panStartY = this.offsetY
            this.releasedAtEdge = false
          })
          .onActionUpdate((event: GestureEvent) => {
            let rawX = this.panStartX + event.offsetX
            this.offsetX = rawX
            this.offsetY = this.panStartY + event.offsetY
            this.clampOffsets()
            // 到达 X 向边界后继续外拖：释放回 Swiper 接管翻页
            let maxX = this.maxOffsetX()
            if (!this.releasedAtEdge && (rawX > maxX + 1 || rawX < -maxX - 1)) {
              this.releasedAtEdge = true
              this.onZoomChange(false)
            }
          })
          .onActionEnd(() => {
            if (this.releasedAtEdge) {
              this.releasedAtEdge = false
              this.onZoomChange(this.scaleValue > 1)
            }
          }),
        TapGesture({ count: 2 })
          .onAction(() => {
            if (this.scaleValue > 1) {
              this.applyScale(1)
            } else {
              this.applyScale(2.5)
            }
          })
      )
    )
  }
}
