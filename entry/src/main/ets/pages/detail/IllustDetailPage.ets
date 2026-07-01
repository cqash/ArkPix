import { router } from '@kit.ArkUI';
import { apiService } from '../../network/ApiService';
import { downloadService } from '../../services/DownloadService';
import { imageCacheService } from '../../services/ImageCacheService';
import { Illust, Tag } from '../../models/Illust';

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

  aboutToAppear() {
    let params = router.getParams() as RouteParams
    if (params && params.illustId) {
      this.loadDetail(params.illustId)
    }
  }

  async loadDetail(id: number) {
    this.isLoading = true
    try {
      let response = await apiService.getIllustDetail(id)
      let illust = (response as IllustDetailResponse).illust
      if (illust) {
        this.illust = Illust.fromJson(illust)
        this.isBookmarked = this.illust.isBookmarked
        this.loadImages()
      }
    } catch (e) {
      console.error('Load detail failed: ' + e)
    } finally {
      this.isLoading = false
    }
  }

  async loadImages() {
    let url = this.illust.pageCount > 1
      ? this.illust.metaPages[this.currentPageIndex].imageUrls.large
      : this.illust.imageUrls.large
    this.mainImagePath = await imageCacheService.getLocalPath(url)

    let avatarUrl = this.illust.user.profileImageUrls.medium
    this.userAvatarPath = await imageCacheService.getLocalPath(avatarUrl)
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

  async downloadImage() {
    let url = this.illust.pageCount > 1
      ? this.illust.metaPages[this.currentPageIndex].imageUrls.original
      : this.illust.imageUrls.original
    await downloadService.downloadImage(url, this.illust.id, this.currentPageIndex)
  }

  build() {
    Column() {
      if (this.isLoading) {
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
            }

            if (this.mainImagePath) {
              Image('file://' + this.mainImagePath)
                .width('100%')
                .objectFit(ImageFit.Contain)
            } else {
              Column() {
                LoadingProgress()
                  .width(24)
                  .height(24)
                  .color('#0096FA')
              }
              .width('100%')
              .height(200)
              .justifyContent(FlexAlign.Center)
              .backgroundColor('#F5F5F5')
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
                Text(tag.name)
                  .fontSize(10)
                  .fontColor('#0096FA')
                  .backgroundColor('#E6F4FF')
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .borderRadius(12)
                  .margin({ right: 4, bottom: 4 })
              }, (tag: Tag) => tag.name)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8 })

            Row() {
              Button(this.isBookmarked ? '已收藏' : '收藏')
                .width('30%')
                .backgroundColor(this.isBookmarked ? '#FF6B6B' : '#0096FA')
                .onClick(() => { this.toggleBookmark() })

              Button('下载')
                .width('30%')
                .backgroundColor('#0096FA')
                .onClick(() => { this.downloadImage() })
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
