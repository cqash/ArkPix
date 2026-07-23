import { router } from '@kit.ArkUI';
import { apiService } from '../../network/ApiService';
import { Illust, ImageUrls } from '../../models/Illust';
import { userSettingStore } from '../../stores/UserSettingStore';
import { CachedImage } from '../../components/common/CachedImage';
import { ErrorView } from '../../components/common/CommonViews';
import { getDbService } from '../../services/DatabaseService';

function pickPreviewUrl(urls: ImageUrls, quality: number): string {
  if (quality === 0) {
    return urls.squareMedium || urls.medium || urls.large
  }
  if (quality === 1) {
    return urls.medium || urls.large || urls.original
  }
  return urls.large || urls.medium || urls.original
}

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

  async loadData(forceRefresh: boolean = false) {
    if (this.isLoading && !forceRefresh) { return }
    if (!forceRefresh) {
      this.isLoading = true
    }
    this.errorMessage = ''
    let db = await getDbService()
    let hasCache = false
    try {
      let cached = await db.getRecommendCache()
      if (cached && !forceRefresh) {
        let parsed = JSON.parse(cached) as RecommendedResponse
        this.illustList = parsed.illusts.map((item: Object) => Illust.fromJson(item))
        this.nextUrl = parsed.next_url || ''
        this.hasMore = this.nextUrl.length > 0
        hasCache = true
      }
    } catch (e) {
      console.error('Load recommend cache failed: ' + e)
    }
    try {
      let response = await apiService.getRecommendedIllusts()
      let parsed = response as RecommendedResponse
      if (parsed.illusts) {
        this.illustList = parsed.illusts.map((item: Object) => Illust.fromJson(item))
      }
      this.nextUrl = parsed.next_url || ''
      this.hasMore = this.nextUrl.length > 0
      await db.setRecommendCache(JSON.stringify(response as object))
    } catch (e) {
      if (!hasCache) {
        this.errorMessage = '加载失败: ' + e
      }
      console.error('Load recommend failed: ' + e)
    } finally {
      if (!forceRefresh) {
        this.isLoading = false
      }
    }
  }

  async onRefresh() {
    this.isRefreshing = true
    await this.loadData(true)
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

