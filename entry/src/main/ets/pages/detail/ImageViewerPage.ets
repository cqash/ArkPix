import { router, promptAction, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { downloadService } from '../../services/DownloadService';
import { imageCacheService } from '../../services/ImageCacheService';
import { Illust } from '../../models/Illust';
import { AppSettings } from '../../models/AppSettings';
import { userSettingStore } from '../../stores/UserSettingStore';
import { bookmarkStateStore, BOOKMARK_DONE } from '../../stores/BookmarkStateStore';
import { ZoomableImage } from '../../components/viewer/ZoomableImage';
import { UgoiraPlayer } from '../../components/illust/UgoiraPlayer';
import { prefetchCachedImage } from '../../components/common/CachedImage';
import { HapticUtils } from '../../utils/HapticUtils';
import { copyText, copyImage } from '../../utils/ClipboardUtils';

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
  /** R4：HD 切换（false=大图档 urls，true=原图档 downloadUrls） */
  @State showOriginal: boolean = false
  /** R4：全屏开关（隐藏状态栏；页面销毁时强制恢复） */
  @State fullScreen: boolean = false
  /** R5：分享按钮可用态（当前页图片已缓存为 true；未缓存半透明+点击 toast） */
  @State shareEnabled: boolean = false
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
    this.refreshShareEnabled()
  }

  private isR18(): boolean {
    return this.illust.xRestrict === 1 || this.illust.xRestrict === 2
  }

  private isUgoira(): boolean {
    return this.illust.type === 'ugoira'
  }

  /** ugoira 封面/播放器宽高比 */
  private ugoiraRatio(): number {
    if (this.illust.width > 0 && this.illust.height > 0) {
      return this.illust.width / this.illust.height
    }
    return 1
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

  /** 当前展示 URL：HD 开启时取原图档 downloadUrls，否则大图档 urls */
  private displayUrl(index: number): string {
    if (index < 0 || index >= this.urls.length) {
      return ''
    }
    if (this.showOriginal && index < this.downloadUrls.length && this.downloadUrls[index].length > 0) {
      return this.downloadUrls[index]
    }
    return this.urls[index]
  }

  /** R4 底栏-HD 切换：ZoomableImage @Watch('onUrlPropChange') 感知 URL 变化自动重载 */
  private toggleHd(): void {
    HapticUtils.selectionClick()
    this.showOriginal = !this.showOriginal
    this.refreshShareEnabled()
  }

  /** R5：解析当前页可分享的本地缓存文件路径；当前档位未命中时回退另一档，均无缓存返回 ''
   *  ugoira 分流：取已下载 GIF 本地路径（未下载返回 ''） */
  private async resolveSharePath(): Promise<string> {
    if (this.isUgoira()) {
      try {
        let ugoiraPath = await downloadService.getUgoiraLocalPath(this.illust.id)
        if (ugoiraPath.length > 0 && fileIo.accessSync(ugoiraPath)) {
          return ugoiraPath
        }
      } catch (e) {
        console.error('Resolve ugoira share path failed: ' + e)
      }
      return ''
    }
    if (this.currentIndex < 0 || this.currentIndex >= this.urls.length) {
      return ''
    }
    let candidates: string[] = []
    let current = this.displayUrl(this.currentIndex)
    if (current.length > 0) {
      candidates.push(current)
    }
    // 档位间回退：当前档未缓存时尝试另一档
    let alternate = ''
    if (this.showOriginal) {
      alternate = this.urls[this.currentIndex]
    } else if (this.currentIndex < this.downloadUrls.length) {
      alternate = this.downloadUrls[this.currentIndex]
    }
    if (alternate.length > 0 && alternate !== current) {
      candidates.push(alternate)
    }
    for (let url of candidates) {
      try {
        let path = await imageCacheService.getLocalPath(url)
        if (path.length > 0 && fileIo.accessSync(path)) {
          return path
        }
      } catch (e) {
        console.error('Resolve share cache path failed: ' + e)
      }
    }
    return ''
  }

  /** R5：静默刷新分享按钮可用态（进页/切页/切档后调用） */
  private refreshShareEnabled(): void {
    this.resolveSharePath().then((path: string) => {
      this.shareEnabled = path.length > 0
    }).catch((e: Object) => {
      console.error('Refresh share enabled failed: ' + e)
      this.shareEnabled = false
    })
  }

  /** R5 底栏-分享：ShareKit 分享当前页图片文件（image utd + fileUri）；未缓存/异常时置灰+toast
   *  ugoira 分支：分享已下载 GIF；未下载 toast "动图下载后可分享" */
  private async shareCurrentImage(): Promise<void> {
    HapticUtils.selectionClick()
    let path = await this.resolveSharePath()
    if (path.length === 0) {
      this.shareEnabled = false
      promptAction.showToast({
        message: this.isUgoira() ? $r('app.string.ugoira_share_download_first') : $r('app.string.viewer_share_not_ready')
      })
      return
    }
    this.shareEnabled = true
    try {
      let ext = '.jpg'
      let dot = path.lastIndexOf('.')
      if (dot >= 0 && dot < path.length - 1) {
        ext = path.substring(dot).toLowerCase()
      }
      let utdTypeId = utd.getUniformDataTypeByFilenameExtension(ext, utd.UniformDataType.IMAGE)
      let record: systemShare.SharedRecord = {
        utd: utdTypeId,
        uri: fileUri.getUriFromPath(path),
        title: this.illust.title.length > 0 ? this.illust.title : 'ArkPix',
        description: 'PID:' + this.illust.id.toString()
      }
      let shareData = new systemShare.SharedData(record)
      let controller = new systemShare.ShareController(shareData)
      let context = this.getUIContext().getHostContext() as common.UIAbilityContext
      controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      }).then(() => {}).catch((err: Object) => {
        console.error('Share panel show failed: ' + err)
      })
    } catch (e) {
      console.error('Share image failed: ' + e)
      promptAction.showToast({ message: $r('app.string.viewer_share_not_ready') })
    }
  }

  /** R4 底栏-复制图片：缓存文件 → PixelMap 剪贴板；任一失败回退复制当前 URL */
  private async copyCurrentImage(): Promise<void> {
    HapticUtils.selectionClick()
    let url = this.displayUrl(this.currentIndex)
    if (url.length === 0) {
      return
    }
    let copied = false
    try {
      let path = await imageCacheService.getLocalPath(url)
      if (path.length > 0) {
        copied = await copyImage(path)
      }
    } catch (e) {
      console.error('Copy image failed: ' + e)
    }
    if (copied) {
      promptAction.showToast({ message: $r('app.string.viewer_image_copied') })
      return
    }
    let ok = await copyText(url)
    promptAction.showToast({
      message: ok ? $r('app.string.viewer_image_link_copied') : $r('app.string.common_copy_failed')
    })
  }

  /** R4 底栏-全屏开关：隐藏/恢复状态栏 */
  private async toggleFullScreen(): Promise<void> {
    HapticUtils.selectionClick()
    let target = !this.fullScreen
    try {
      let win = await window.getLastWindow(getContext(this))
      await win.setSpecificSystemBarEnabled('status', !target)
      this.fullScreen = target
    } catch (e) {
      console.error('Toggle fullscreen failed: ' + e)
    }
  }

  /** 页面销毁时若处于全屏则强制恢复状态栏 */
  private restoreStatusBar(): void {
    if (!this.fullScreen) {
      return
    }
    this.fullScreen = false
    try {
      window.getLastWindow(getContext(this)).then((win: window.Window) => {
        win.setSpecificSystemBarEnabled('status', true).then(() => {}).catch((e: Object) => {
          console.error('Restore status bar failed: ' + e)
        })
      }).catch((e: Object) => {
        console.error('Restore status bar failed: ' + e)
      })
    } catch (e) {
      console.error('Restore status bar failed: ' + e)
    }
  }

  aboutToDisappear() {
    this.restoreStatusBar()
  }

  onIndexChange(index: number): void {
    this.currentIndex = index
    this.prefetchNeighbors(index)
    this.refreshShareEnabled()
  }

  async handleSave(): Promise<void> {
    HapticUtils.selectionClick()
    if (this.isUgoira()) {
      let ugoiraDownloaded = await downloadService.isUgoiraDownloaded(this.illust.id)
      if (ugoiraDownloaded) {
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
      return
    }
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
    if (this.isUgoira()) {
      let ugoiraResult = downloadService.enqueueUgoira(this.illust)
      promptAction.showToast({
        message: ugoiraResult === 'inflight' ? $r('app.string.dl_already_in_queue') : $r('app.string.common_added_download')
      })
    } else {
      let result = downloadService.enqueue(this.downloadUrls[this.currentIndex], this.illust, this.currentIndex)
      promptAction.showToast({
        message: result === 'inflight' ? $r('app.string.dl_already_in_queue') : $r('app.string.common_added_download')
      })
    }
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
          ForEach(this.urls, (url: string, index: number) => {
            if (this.isUgoira()) {
              // ugoira：单页动图播放器（封面兜底），无缩放交互
              UgoiraPlayer({
                illustId: this.illust.id,
                ratio: this.ugoiraRatio(),
                fit: ImageFit.Contain,
                coverUrl: this.urls.length > 0 ? this.urls[0] : ''
              })
            } else {
              ZoomableImage({
                url: this.displayUrl(index),
                onZoomChange: (zoomed: boolean) => { this.isZoomed = zoomed }
              })
            }
          }, (url: string) => url)
        }
        .index(this.currentIndex)
        .indicator(false)
        .disableSwipe(this.isZoomed || this.isUgoira())
        .onChange((index: number) => { this.onIndexChange(index) })
        .width('100%')
        .height('100%')
      }

      // R5 底部单行图标栏（对齐 pixez，替代原顶部工具栏）：复制图片/页码/返回/全屏/保存/分享/HD
      // 白色图标悬浮于黑底（rgba 0.25 淡底保证浅色图上的可读性）；遮罩态下底栏保持可用。
      // 勿加 systemMaterial 沉浸光感：uiMaterial 在此区域不生效（渲染为透明），已踩坑回退
      Column() {
        Row() {
          this.BottomBarButtons()
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceEvenly)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 8, right: 8, top: 6, bottom: 28 })
        .backgroundColor('rgba(0, 0, 0, 0.25)')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }

  /** 底栏按钮内容（七项，两分支共享，交互逻辑不进版本分支） */
  @Builder
  BottomBarButtons() {
    // ① 复制图片（SVG 资源图标；padding/onClick 挂外层容器）
    Column() {
      Image($r('app.media.ic_viewer_copy'))
        .width(22)
        .height(22)
    }
    .padding(8)
    .onClick(() => { this.copyCurrentImage() })
    // ② 页码指示（仅多页显示）
    if (this.urls.length > 1) {
      Text((this.currentIndex + 1) + '/' + this.urls.length)
        .fontSize(13)
        .fontColor('#FFFFFF')
        .padding(8)
    }
    // ③ 返回
    Text('‹')
      .fontSize(28)
      .fontColor('#FFFFFF')
      .padding({ left: 12, right: 12 })
      .onClick(() => {
        HapticUtils.selectionClick()
        router.back()
      })
    // ④ 全屏开关（SVG 四角图标；padding/opacity/onClick 挂外层容器）
    Column() {
      Image($r('app.media.ic_viewer_fullscreen'))
        .width(22)
        .height(22)
    }
    .padding(8)
    .opacity(this.fullScreen ? 0.6 : 1)
    .onClick(() => { this.toggleFullScreen() })
    // ⑤ 保存（SaveButton 安全控件 icon-only；授权逻辑不变）
    SaveButton({ icon: SaveIconStyle.FULL_FILLED })
      .onClick(async (_event: ClickEvent, result: SaveButtonOnClickResult) => {
        if (result === SaveButtonOnClickResult.SUCCESS) {
          await this.handleSave()
        }
      })
    // ⑥ 分享当前页图片（SVG 出盒箭头图标；未缓存置灰；padding/opacity/onClick 挂外层容器）
    Column() {
      Image($r('app.media.ic_viewer_share'))
        .width(22)
        .height(22)
    }
    .padding(8)
    .opacity(this.shareEnabled ? 1 : 0.4)
    .onClick(() => { this.shareCurrentImage() })
    // ⑦ HD 切换（描边文本；原图档反色高亮；ugoira 无原图档概念，隐藏）
    if (!this.isUgoira()) {
      Text('HD')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.showOriginal ? '#000000' : '#FFFFFF')
        .backgroundColor(this.showOriginal ? '#FFFFFF' : Color.Transparent)
        .border({ width: 1, color: '#FFFFFF', radius: 4 })
        .padding({ left: 5, right: 5, top: 2, bottom: 2 })
        .margin({ left: 8, right: 8 })
        .onClick(() => { this.toggleHd() })
    }
  }
}
