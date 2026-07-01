import { router } from '@kit.ArkUI';
import { apiService } from '../../network/ApiService';
import { Illust, ImageUrls } from '../../models/Illust';
import { userSettingStore } from '../../stores/UserSettingStore';
import { CachedImage } from '../../components/common/CachedImage';
import { ErrorView } from '../../components/common/CommonViews';

function pickPreviewUrl(urls: ImageUrls, quality: number): string {
  if (quality === 0) {
    return urls.squareMedium || urls.medium || urls.large
  }
  if (quality === 1) {
    return urls.medium || urls.large || urls.original
  }
  return urls.large || urls.medium || urls.original
}

interface TrendingTagsResponse {
  trend_tags: string[]
}

interface SearchResponse {
  illusts: Object[]
}

@Component
export struct SearchPage {
  @State searchKeyword: string = ''
  @State illustList: Illust[] = []
  @State isLoading: boolean = false
  @State trendingTags: string[] = []
  @State searchHistory: string[] = []
  @State searchError: string = ''

  aboutToAppear() {
    this.loadTrendingTags()
    this.loadSearchHistory()
  }

  async loadTrendingTags() {
    try {
      let response = await apiService.getTrendingTags()
      let tags = (response as TrendingTagsResponse).trend_tags
      if (tags) {
        this.trendingTags = tags
      }
    } catch (e) {
      console.error('Load trending tags failed: ' + e)
    }
  }

  async loadSearchHistory() {
    // TODO: load from database
    this.searchHistory = []
  }

  async search() {
    if (!this.searchKeyword.trim()) { return }
    this.isLoading = true
    this.searchError = ''
    try {
      let response = await apiService.searchIllusts(this.searchKeyword)
      let illusts = (response as SearchResponse).illusts
      if (illusts) {
        this.illustList = illusts.map((item: Object) => Illust.fromJson(item))
      }
    } catch (e) {
      this.searchError = '搜索失败: ' + e
      console.error('Search failed: ' + e)
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
    Column() {
      Row() {
        TextInput({ placeholder: '搜索插画', text: $$this.searchKeyword })
          .width('80%')
          .height(40)
          .backgroundColor('#F5F5F5')
          .borderRadius(20)
          .padding({ left: 16, right: 16 })
          .onSubmit(() => { this.search() })
        Button('搜索')
          .width('18%')
          .height(40)
          .backgroundColor('#0096FA')
          .onClick(() => { this.search() })
      }
      .width('100%')
      .padding(16)
      .justifyContent(FlexAlign.SpaceBetween)

      if (this.searchError && this.illustList.length === 0) {
        Column() {
          ErrorView({ message: this.searchError, onRetry: () => { this.search() } })
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.illustList.length === 0 && !this.isLoading) {
        Column() {
          Text('热门标签')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .margin({ bottom: 12 })
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.trendingTags, (tag: string) => {
              Text(tag)
                .fontSize(12)
                .fontColor('#0096FA')
                .backgroundColor('#E6F4FF')
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(16)
                .margin({ right: 8, bottom: 8 })
                .onClick(() => {
                  this.searchKeyword = tag
                  this.search()
                })
            }, (tag: string) => tag)
          }
          .width('100%')
        }
        .width('100%')
        .padding(16)
        .layoutWeight(1)
      } else if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#0096FA')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
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
  }
}
