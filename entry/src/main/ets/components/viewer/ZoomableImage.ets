import { display } from '@kit.ArkUI';
import { imageCacheService } from '../../services/ImageCacheService';

/**
 * 可缩放图片（官方手势竞争方案，禁止回退条件手势组）：
 * - GestureGroup(Parallel, Pinch + Pan + Tap) 静态常驻挂载，不按 scale 条件切换手势组；
 * - PanGestureOptions.setDistance() 动态更新 distance：scale=1 时 50vp（让位 Swiper 翻页），scale>1 时 3vp（跟手平移）；
 * - .priorityGesture() 绑定手势组，优先于 Swiper 内置手势；
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
  private panOptions: PanGestureOptions = new PanGestureOptions({ fingers: 1, distance: 50 })
  private baseScale: number = 1
  private uiContext: UIContext | undefined = undefined
  private panStartX: number = 0
  private panStartY: number = 0
  private releasedAtEdge: boolean = false
  private componentWidth: number = 0
  private componentHeight: number = 0

  aboutToAppear() {
    this.uiContext = this.getUIContext()
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
    this.panOptions.setDistance(this.scaleValue > 1 ? 3 : 50)
  }

  /**
   * 以 (focusX, focusY) 为焦点缩放到 targetScale（均为相对于组件左上角的 vp 坐标）
   * .scale() 默认以组件中心 (halfW, halfH) 为缩放原点，
   * 缩放时：先以中心缩放，再通过 translate 补偿偏移使焦点处的像素保持不动。
   * 公式：newOffset = (focus - center) * (1 - ratio) + oldOffset * ratio
   *   其中 ratio = newScale / oldScale
   */
  private applyScaleWithFocus(targetScale: number, focusX: number, focusY: number): void {
    let oldScale = this.scaleValue
    this.scaleValue = this.clampScale(targetScale)
    if (this.scaleValue === 1) {
      this.offsetX = 0
      this.offsetY = 0
    } else {
      let ratio = this.scaleValue / oldScale
      let halfW = this.componentWidth / 2
      let halfH = this.componentHeight / 2
      // 焦点相对于缩放中心的偏移
      let fx = focusX - halfW
      let fy = focusY - halfH
      this.offsetX = fx * (1 - ratio) + this.offsetX * ratio
      this.offsetY = fy * (1 - ratio) + this.offsetY * ratio
      this.clampOffsets()
    }
    this.onZoomChange(this.scaleValue > 1)
    this.panOptions.setDistance(this.scaleValue > 1 ? 3 : 50)
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
          Text($r('app.string.viewer_loading'))
            .fontSize(12)
            .fontColor('#CCCCCC')
            .margin({ top: 8 })
        }
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Text($r('app.string.viewer_load_failed'))
            .fontSize(16)
            .fontColor('#FFFFFF')
          Text($r('app.string.common_tap_retry'))
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
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.componentWidth = newArea.width as number
      this.componentHeight = newArea.height as number
    })
    .priorityGesture(
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
        PanGesture(this.panOptions)
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
          .onAction((event: GestureEvent) => {
            // 取双击第二次手指的位置作为焦点
            let focusX = this.componentWidth / 2
            let focusY = this.componentHeight / 2
            if (event.fingerList.length > 0) {
              let finger = event.fingerList[0]
              if (finger.localX > 0 && finger.localY > 0) {
                focusX = finger.localX
                focusY = finger.localY
              }
            }
            if (this.uiContext) {
              this.uiContext.animateTo({ duration: 250, curve: Curve.FastOutSlowIn }, () => {
                if (this.scaleValue > 1) {
                  this.applyScaleWithFocus(1, focusX, focusY)
                } else {
                  this.applyScaleWithFocus(2.5, focusX, focusY)
                }
              })
            } else {
              if (this.scaleValue > 1) {
                this.applyScaleWithFocus(1, focusX, focusY)
              } else {
                this.applyScaleWithFocus(2.5, focusX, focusY)
              }
            }
          })
      )
    )
  }
}
