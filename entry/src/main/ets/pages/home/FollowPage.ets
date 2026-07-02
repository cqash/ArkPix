import { router } from '@kit.ArkUI';
import { apiService } from '../../network/ApiService';
import { Illust, ImageUrls } from '../../models/Illust';
import { userSettingStore } from '../../stores/UserSettingStore';
import { CachedImage } from '../../components/common/CachedImage';
import { ErrorView } from '../../components/common/CommonViews';

interface FollowResponse {
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

@Component
export struct FollowPage {
  @State illustList: Illust[] = []
  @State isLoading: boolean = false
  @State isRefreshing: boolean = false
  @State hasMore: boolean = true
  @State errorMessage: string = ''
  private nextUrl: string = ''

  aboutToAppear() {
    this.loadData()
  }

  async loadData() {
    if (this.isLoading) { return }
    this.isLoading = true
    this.errorMessage = ''
    try {
      let response = await apiService.getFollowIllusts('public')
      let illusts = (response as FollowResponse).illusts
      if (illusts) {
        this.illustList = illusts.map((item: Object) => Illust.fromJson(item))
      }
      this.nextUrl = (response as FollowResponse).next_url || ''
      this.hasMore = this.nextUrl.length > 0
    } catch (e) {
      this.errorMessage = '加载失败: ' + e
      console.error('Load follow illusts failed: ' + e)
    } finally {
      this.isLoading = false
    }
  }

  async onRefresh() {
    this.isRefreshing = true
    await this.loadData()
    this.isRefreshing = false
  }

  async onLoadMore() {
    if (!this.hasMore || this.isLoading) { return }
    this.isLoading = true
    try {
      let response = await apiService.getFollowIllusts('public')
      let illusts = (response as FollowResponse).illusts
      if (illusts) {
        let newItems = illusts.map((item: Object) => Illust.fromJson(item))
        this.illustList = this.illustList.concat(newItems)
      }
      this.nextUrl = (response as FollowResponse).next_url || ''
      this.hasMore = this.nextUrl.length > 0
    } catch (e) {
      console.error('Load more follow illusts failed: ' + e)
    } finally {
      this.isLoading = false
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
      Text(item.user.name)
        .fontSize(10)
        .fontColor('#999999')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(4)
    .onClick(() => {
      router.pushUrl({ url: 'pages/detail/IllustDetailPage', params: { illustId: item.id } })
    })
  }

  build() {
    if (this.errorMessage && this.illustList.length === 0) {
      ErrorView({ message: this.errorMessage, onRetry: () => { this.loadData() } })
    } else {
      Refresh({ refreshing: $$this.isRefreshing, offset: 64, friction: 100 }) {
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
        .onReachEnd(() => {
          this.onLoadMore()
        })
      }
      .onRefreshing(() => {
        this.onRefresh()
      })
      .width('100%')
      .height('100%')
    }
  }
}
