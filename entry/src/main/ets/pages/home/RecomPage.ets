import { router } from '@kit.ArkUI';
import { apiService } from '../../network/ApiService';
import { Illust } from '../../models/Illust';
import { userSettingStore } from '../../stores/UserSettingStore';
import { CachedImage } from '../../components/common/CachedImage';
import { ErrorView } from '../../components/common/CommonViews';

interface RecommendedResponse {
  illusts: Object[]
  next_url: string
}

@Component
export struct RecomPage {
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
      let response = await apiService.getRecommendedIllusts()
      let illusts = (response as RecommendedResponse).illusts
      if (illusts) {
        this.illustList = illusts.map((item: Object) => Illust.fromJson(item))
      }
      this.nextUrl = (response as RecommendedResponse).next_url || ''
      this.hasMore = this.nextUrl.length > 0
    } catch (e) {
      this.errorMessage = '加载失败: ' + e
      console.error('Load recommend failed: ' + e)
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
      // TODO: follow next_url for pagination
    } catch (e) {
      console.error('Load more failed: ' + e)
    } finally {
      this.isLoading = false
    }
  }

  @Builder
  IllustCard(item: Illust) {
    Column() {
      CachedImage({ url: item.imageUrls.medium })
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

