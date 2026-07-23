import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { apiService } from '../../network/ApiService';
import { downloadService } from '../../services/DownloadService';
import { imageCacheService } from '../../services/ImageCacheService';
import { getDbService } from '../../services/DatabaseService';
import { Illust, ImageUrls, Tag } from '../../models/Illust';
import { userSettingStore } from '../../stores/UserSettingStore';
import { ErrorView } from '../../components/common/CommonViews';

function pickUrlByQuality(urls: ImageUrls, quality: number): string {
  if (quality === 0) {
    return urls.medium || urls.large || urls.original
  }
  if (quality === 1) {
    return urls.large || urls.original || urls.medium
  }
  return urls.original || urls.large || urls.medium
}

function pickPreviewUrl(urls: ImageUrls, quality: number): string {
  if (quality === 0) {
    return urls.squareMedium || urls.medium || urls.large
  }
  if (quality === 1) {
    return urls.medium || urls.large || urls.original
  }
  return urls.large || urls.medium || urls.original
}

function pickDetailUrl(illust: Illust, pageIndex: number, quality: number): string {
  let urls = illust.pageCount > 1
    ? illust.metaPages[pageIndex].imageUrls
    : illust.imageUrls
  if (quality === 1) {
    if (illust.pageCount > 1) {
      return urls.original || urls.large || urls.medium
    }
    return illust.metaSinglePage.originalImageUrl || urls.large || urls.original || urls.medium
  }
  return urls.large || urls.medium
}

interface RouteParams {
  illustId: number
}

interface IllustDetailResponse {
  illust: Object
}

@Entry
@Component
struct IllustDetailPage {
  @State illust: Illust = new Illust()
  @State isLoading: boolean = false
  @State currentPageIndex: number = 0
  @State isBookmarked: boolean = false
  @State mainImagePath: string = ''
  @State userAvatarPath: string = ''
  @State errorMessage: string = ''
  @State illustId: number = 0

  aboutToAppear() {
    let params = router.getParams() as RouteParams
    if (params && params.illustId) {
      this.illustId = params.illustId
      this.loadDetail(params.illustId)
    }
  }

  async loadDetail(id: number, forceRefresh: boolean = false) {
    this.errorMessage = ''
    let db = await getDbService()
    let hasCache = false
    try {
      let cached = await db.getIllustDetailCache(id)
      if (cached && !forceRefresh) {
        let parsed = (JSON.parse(cached) as IllustDetailResponse).illust
        if (parsed) {
          let illust = Illust.fromJson(parsed)
          this.illust = illust
          this.isBookmarked = illust.isBookmarked
          this.illustId = illust.id
          this.loadImages()
          hasCache = true
        }
      }
    } catch (e) {
      console.error('Load illust detail cache failed: ' + e)
    }
    if (hasCache) {
      this.isLoading = false
    } else {
      this.isLoading = true
    }
    try {
      let response = await apiService.getIllustDetail(id)
      let illust = (response as IllustDetailResponse).illust
      if (!illust) {
        if (!hasCache) {
          this.errorMessage = '返回数据无效，请重试'
        }
        return
      }
      let parsed = Illust.fromJson(illust)
      if (!parsed.id || !parsed.title) {
        if (!hasCache) {
          this.errorMessage = '作品数据解析失败'
        }
        return
      }
      this.illust = parsed
      this.isBookmarked = this.illust.isBookmarked
      this.loadImages()
      await db.setIllustDetailCache(id, JSON.stringify(response as object))
    } catch (e) {
      if (!hasCache) {
        this.errorMessage = '加载失败: ' + e
      }
      console.error('Load detail failed: ' + e)
    } finally {
      this.isLoading = false
    }
  }

  async loadImages() {
    let settings = userSettingStore.getSettings()
    let url = pickDetailUrl(this.illust, this.currentPageIndex, settings.detailQuality)
    let avatarUrl = this.illust.user.profileImageUrls.medium
    let paths: string[] = await Promise.all([
      imageCacheService.getLocalPath(url),
      imageCacheService.getLocalPath(avatarUrl)
    ])
    this.mainImagePath = paths[0]
    this.userAvatarPath = paths[1]
  }

  openImageViewer() {
    let settings = userSettingStore.getSettings()
    let url = pickDetailUrl(this.illust, this.currentPageIndex, settings.fullScreenQuality)
    let downloadUrl = pickDetailUrl(this.illust, this.currentPageIndex, settings.downloadQuality)
    router.pushUrl({
      url: 'pages/detail/ImageViewerPage',
      params: { imageUrl: url, downloadUrl: downloadUrl, illust: this.illust, pageIndex: this.currentPageIndex }
    })
  }

  prevPage() {
    if (this.currentPageIndex > 0) {
      this.currentPageIndex--
      this.loadImages()
    }
  }

  nextPage() {
    if (this.currentPageIndex < this.illust.pageCount - 1) {
      this.currentPageIndex++
      this.loadImages()
    }
  }

  goToPage(index: number) {
    if (index >= 0 && index < this.illust.pageCount && index !== this.currentPageIndex) {
      this.currentPageIndex = index
      this.loadImages()
    }
  }

  private getImageAspectRatio(): number {
    if (this.illust.width > 0 && this.illust.height > 0) {
      return this.illust.width / this.illust.height
    }
    return 0.75
  }

  @Builder
  TagChip(tag: Tag) {
    if (userSettingStore.getSettings().showTranslatedTags && tag.translatedName) {
      Column() {
        Text(tag.name)
          .fontSize(10)
          .fontColor('#0096FA')
        Text(tag.translatedName)
          .fontSize(8)
          .fontColor('#0096FA')
          .opacity(0.8)
      }
      .backgroundColor('#E6F4FF')
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(12)
      .margin({ right: 4, bottom: 4 })
      .onClick(() => {
        router.pushUrl({ url: 'pages/search/TagSearchPage', params: { keyword: tag.name } })
      })
    } else {
      Text(tag.name)
        .fontSize(10)
        .fontColor('#0096FA')
        .backgroundColor('#E6F4FF')
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(12)
        .margin({ right: 4, bottom: 4 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/search/TagSearchPage', params: { keyword: tag.name } })
        })
    }
  }

  async toggleBookmark() {
    try {
      if (this.isBookmarked) {
        await apiService.deleteBookmark(this.illust.id)
      } else {
        await apiService.addBookmark(this.illust.id, 'public')
      }
      this.isBookmarked = !this.isBookmarked
    } catch (e) {
      console.error('Bookmark failed: ' + e)
    }
  }

  async handleSave(): Promise<void> {
    let quality = userSettingStore.getSettings().downloadQuality
    let url = pickDetailUrl(this.illust, this.currentPageIndex, quality)
    let localPath = await downloadService.downloadToCache(url, this.illust, this.currentPageIndex)
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
      if (userSettingStore.getSettings().autoBookmarkOnDownload && !this.isBookmarked) {
        try {
          await apiService.addBookmark(this.illust.id, 'public')
          this.isBookmarked = true
          promptAction.showToast({ message: '已自动收藏' })
        } catch (e) {
          console.error('Auto bookmark failed: ' + e)
        }
      }
    } else {
      promptAction.showToast({ message: '保存失败' })
    }
  }

  async handleSaveAll(): Promise<void> {
    if (this.illust.pageCount <= 1) { return }
    let quality = userSettingStore.getSettings().downloadQuality
    let ctx = AppStorage.get<common.Context>('context')
    if (!ctx) {
      promptAction.showToast({ message: '保存失败' })
      return
    }
    let successCount = 0
    let failCount = 0
    for (let i = 0; i < this.illust.pageCount; i++) {
      let url = pickDetailUrl(this.illust, i, quality)
      promptAction.showToast({ message: '开始下载 第' + (i + 1) + '/' + this.illust.pageCount + '页...' })
      let localPath = await downloadService.downloadToCache(url, this.illust, i)
      if (!localPath) {
        failCount++
        continue
      }
      let saved = await downloadService.applyToGallery(localPath, ctx)
      if (saved) {
        successCount++
      } else {
        failCount++
      }
    }
    promptAction.showToast({ message: '完成: 成功' + successCount + ', 失败' + failCount })
    if (userSettingStore.getSettings().autoBookmarkOnDownload && !this.isBookmarked) {
      try {
        await apiService.addBookmark(this.illust.id, 'public')
        this.isBookmarked = true
        promptAction.showToast({ message: '已自动收藏' })
      } catch (e) {
        console.error('Auto bookmark failed: ' + e)
      }
    }
  }

  build() {
    Column() {
      if (this.errorMessage) {
        ErrorView({ message: this.errorMessage, onRetry: () => { this.loadDetail(this.illustId) } })
      } else if (this.isLoading) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color('#0096FA')
      } else {
        Scroll() {
          Column() {
            if (this.illust.pageCount > 1) {
              Row() {
                Text('第 ' + (this.currentPageIndex + 1) + ' / ' + this.illust.pageCount + ' 页')
                  .fontSize(14)
                  .fontColor('#999999')
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 8, bottom: 8 })

              Row() {
                Button('上一页')
                  .fontSize(12)
                  .width('40%')
                  .backgroundColor('#0096FA')
                  .enabled(this.currentPageIndex > 0)
                  .onClick(() => { this.prevPage() })
                Button('下一页')
                  .fontSize(12)
                  .width('40%')
                  .backgroundColor('#0096FA')
                  .enabled(this.currentPageIndex < this.illust.pageCount - 1)
                  .onClick(() => { this.nextPage() })
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceEvenly)
              .padding({ bottom: 8 })
            }

            Column() {
              if (this.mainImagePath) {
                Image('file://' + this.mainImagePath)
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Contain)
                  .gesture(
                    SwipeGesture({ direction: SwipeDirection.Horizontal })
                      .onAction((event: GestureEvent) => {
                        if (event.offsetX > 0) {
                          this.prevPage()
                        } else {
                          this.nextPage()
                        }
                      })
                  )
                  .onClick(() => {
                    this.openImageViewer()
                  })
              } else {
                Column() {
                  LoadingProgress()
                    .width(40)
                    .height(40)
                    .color('#0096FA')
                  Text('图片加载中...')
                    .fontSize(12)
                    .fontColor('#999999')
                    .margin({ top: 8 })
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
              }
            }
            .width('100%')
            .aspectRatio(this.getImageAspectRatio())
            .backgroundColor('#F5F5F5')
            .border({ width: 1, color: '#E5E5E5' })

            if (this.illust.pageCount > 1) {
              Row() {
                ForEach(new Array<number>(this.illust.pageCount).fill(0), (_: number, index: number) => {
                  Column()
                    .width(8)
                    .height(8)
                    .borderRadius(4)
                    .backgroundColor(index === this.currentPageIndex ? '#0096FA' : '#DDDDDD')
                    .margin({ left: 4, right: 4 })
                    .onClick(() => { this.goToPage(index) })
                }, (index: number) => index.toString())
              }
              .width('100%')
              .height(24)
              .justifyContent(FlexAlign.Center)
              .padding({ top: 8, bottom: 8 })
            }

            Row() {
              Text(this.illust.title)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#333333')
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8 })

            Row() {
              if (this.userAvatarPath) {
                Image('file://' + this.userAvatarPath)
                  .width(32)
                  .height(32)
                  .borderRadius(16)
              } else {
                Column()
                  .width(32)
                  .height(32)
                  .borderRadius(16)
                  .backgroundColor('#F5F5F5')
              }
              Text(this.illust.user.name)
                .fontSize(14)
                .fontColor('#333333')
                .margin({ left: 8 })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8 })

            Row() {
              Text('收藏 ' + this.illust.totalBookmarks)
                .fontSize(12)
                .fontColor('#999999')
              Text('浏览 ' + this.illust.totalView)
                .fontSize(12)
                .fontColor('#999999')
                .margin({ left: 16 })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8 })

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.illust.tags, (tag: Tag) => {
                this.TagChip(tag)
              }, (tag: Tag) => tag.name)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8 })

              Row() {
                Button(this.isBookmarked ? '已收藏' : '收藏')
                  .width(this.illust.pageCount > 1 ? '25%' : '30%')
                  .backgroundColor(this.isBookmarked ? '#FF6B6B' : '#0096FA')
                  .onClick(() => { this.toggleBookmark() })

                SaveButton({ icon: SaveIconStyle.FULL_FILLED, text: SaveDescription.SAVE })
                  .width(this.illust.pageCount > 1 ? '25%' : '30%')
                  .onClick(async (_event: ClickEvent, result: SaveButtonOnClickResult) => {
                    if (result === SaveButtonOnClickResult.SUCCESS) {
                      await this.handleSave()
                    }
                  })

                if (this.illust.pageCount > 1) {
                  Button('下载全部')
                    .width('25%')
                    .backgroundColor('#FF8800')
                    .fontSize(12)
                    .onClick(() => { this.handleSaveAll() })
                }
              }
            .width('100%')
            .justifyContent(FlexAlign.SpaceEvenly)
            .padding({ top: 16, bottom: 16 })
          }
          .width('100%')
        }
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }
}
