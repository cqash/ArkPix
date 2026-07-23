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

interface RankingResponse {
  illusts: Object[]
  next_url: string
}

@Component
export struct RankPage {
  @State illustList: Illust[] = []
  @State isLoading: boolean = false
  @State isRefreshing: boolean = false
  @State selectedMode: string = 'day'
  @State selectedDate: string = ''
  @State errorMessage: string = ''

  aboutToAppear() {
    let yesterday = new Date()
    yesterday.setDate(yesterday.getDate() - 1)
    this.selectedDate = yesterday.toISOString().split('T')[0]
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
      let cached = await db.getRankingCache(this.selectedMode, this.selectedDate)
      if (cached && !forceRefresh) {
        let parsed = JSON.parse(cached) as RankingResponse
        this.illustList = parsed.illusts.map((item: Object) => Illust.fromJson(item))
        hasCache = true
      }
    } catch (e) {
      console.error('Load ranking cache failed: ' + e)
    }
    try {
      let response = await apiService.getRankingIllusts(this.selectedMode, this.selectedDate)
      let parsed = response as RankingResponse
      if (parsed.illusts) {
        this.illustList = parsed.illusts.map((item: Object) => Illust.fromJson(item))
      }
      await db.setRankingCache(this.selectedMode, this.selectedDate, JSON.stringify(response as object))
    } catch (e) {
      if (!hasCache) {
        this.errorMessage = '加载失败: ' + e
      }
      console.error('Load ranking failed: ' + e)
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

  selectMode(mode: string) {
    this.selectedMode = mode
    this.loadData()
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
      Column() {
        Row() {
          Text('日榜')
            .fontSize(14)
            .fontColor(this.selectedMode === 'day' ? '#0096FA' : '#333333')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .onClick(() => { this.selectMode('day') })
          Text('周榜')
            .fontSize(14)
            .fontColor(this.selectedMode === 'week' ? '#0096FA' : '#333333')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .onClick(() => { this.selectMode('week') })
          Text('月榜')
            .fontSize(14)
            .fontColor(this.selectedMode === 'month' ? '#0096FA' : '#333333')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .onClick(() => { this.selectMode('month') })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 8, bottom: 8 })

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
        }
        .onRefreshing(() => { this.onRefresh() })
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
  }
}
