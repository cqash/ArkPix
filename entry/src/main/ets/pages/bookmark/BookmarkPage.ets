import { router, promptAction } from '@kit.ArkUI';
import { apiService } from '../../network/ApiService';
import { Illust, ImageUrls } from '../../models/Illust';
import { userSettingStore } from '../../stores/UserSettingStore';
import { accountStore } from '../../stores/AccountStore';
import { CachedImage } from '../../components/common/CachedImage';
import { ErrorView } from '../../components/common/CommonViews';

interface BookmarkResponse {
  illusts: Object[]
  next_url: string
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

@Entry
@Component
struct BookmarkPage {
  @State illustList: Illust[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''

  aboutToAppear() {
    this.loadBookmarks()
  }

  async loadBookmarks() {
    this.isLoading = true
    this.errorMessage = ''
    try {
      let userId = accountStore.getCurrentUserId()
      if (userId === 0) {
        this.errorMessage = '未登录，无法查看收藏'
        return
      }
      let response = await apiService.getUserBookmarks(userId, 'public')
      let illusts = (response as BookmarkResponse).illusts
      if (illusts) {
        this.illustList = illusts.map((item: Object) => Illust.fromJson(item))
      }
    } catch (e) {
      this.errorMessage = '加载收藏失败: ' + e
      console.error('Load bookmarks failed: ' + e)
    } finally {
      this.isLoading = false
    }
  }

  async removeBookmark(illustId: number) {
    try {
      await apiService.deleteBookmark(illustId)
      this.illustList = this.illustList.filter((item: Illust) => item.id !== illustId)
      promptAction.showToast({ message: '已取消收藏' })
    } catch (e) {
      console.error('Remove bookmark failed: ' + e)
    }
  }

  @Builder
  IllustCard(item: Illust) {
    Column() {
      CachedImage({ url: pickPreviewUrl(item.imageUrls, userSettingStore.getSettings().previewQuality) })
      Text(item.title)
        .fontSize(12)
        .fontColor('#333333')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })
      Row() {
        Text(item.user.name)
          .fontSize(10)
          .fontColor('#999999')
          .maxLines(1)
          .layoutWeight(1)
        Text('取消收藏')
          .fontSize(10)
          .fontColor('#FF4444')
          .onClick(() => { this.removeBookmark(item.id) })
      }
      .width('100%')
      .margin({ top: 2 })
    }
    .width('100%')
    .padding(4)
    .onClick(() => {
      router.pushUrl({ url: 'pages/detail/IllustDetailPage', params: { illustId: item.id } })
    })
  }

  build() {
    Column() {
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor('#F5F5F5')
          .fontColor('#333333')
          .onClick(() => { router.back() })
        Text('我的收藏')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank()
          .width(60)
      }
      .width('100%')
      .height(48)
      .padding({ left: 8, right: 8 })
      .backgroundColor('#FFFFFF')

      if (this.errorMessage && this.illustList.length === 0) {
        ErrorView({ message: this.errorMessage, onRetry: () => { this.loadBookmarks() } })
      } else if (this.isLoading) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color('#0096FA')
          .margin({ top: 32 })
      } else if (this.illustList.length === 0) {
        Text('暂无收藏')
          .fontSize(14)
          .fontColor('#999999')
          .margin({ top: 32 })
      } else {
        List({ space: 8 }) {
          ForEach(this.illustList, (item: Illust) => {
            ListItem() {
              this.IllustCard(item)
            }
          }, (item: Illust) => item.id.toString())
        }
        .lanes(userSettingStore.getSettings().crossCount)
        .padding(8)
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
