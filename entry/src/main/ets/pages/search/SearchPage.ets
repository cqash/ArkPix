import { apiService } from '../../network/ApiService';
import { getDbService, SearchHistoryItem } from '../../services/DatabaseService';
import { IllustWaterfall, IllustListPage, parseIllustListPage } from '../../components/illust/IllustWaterfall';

interface TrendingTagsResponse {
  trend_tags: string[]
}

@Component
export struct SearchPage {
  @State searchKeyword: string = ''
  @State searchedKeyword: string = ''
  @State hasSearched: boolean = false
  @State reloadToken: number = 0
  @State trendingTags: string[] = []
  @State searchHistory: string[] = []

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
    try {
      let db = await getDbService()
      let items = await db.getSearchHistory(30)
      this.searchHistory = items.map((item: SearchHistoryItem) => item.keyword)
    } catch (e) {
      console.error('Load search history failed: ' + e)
    }
  }

  async clearSearchHistory() {
    try {
      let db = await getDbService()
      await db.clearSearchHistory()
      this.searchHistory = []
    } catch (e) {
      console.error('Clear search history failed: ' + e)
    }
  }

  search() {
    let keyword = this.searchKeyword.trim()
    if (!keyword) {
      return
    }
    this.searchedKeyword = keyword
    this.hasSearched = true
    this.reloadToken++
    getDbService().then((db) => {
      return db.addSearchHistory(keyword, 'illust')
    }).then(() => {
      this.loadSearchHistory()
    }).catch((e: Object) => {
      console.error('Add search history failed: ' + e)
    })
  }

  private async fetchFirst(): Promise<IllustListPage> {
    if (!this.searchedKeyword) {
      let empty: IllustListPage = { illusts: [], nextUrl: '' }
      return empty
    }
    let response = await apiService.searchIllusts(this.searchedKeyword)
    return parseIllustListPage(response)
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

      if (!this.hasSearched) {
        Column() {
          if (this.searchHistory.length > 0) {
            Row() {
              Text('搜索历史')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#333333')
                .layoutWeight(1)
              Text('清除')
                .fontSize(12)
                .fontColor('#FF4444')
                .onClick(() => { this.clearSearchHistory() })
            }
            .width('100%')
            .margin({ bottom: 12 })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.searchHistory, (keyword: string) => {
                Text(keyword)
                  .fontSize(12)
                  .fontColor('#333333')
                  .backgroundColor('#F0F0F0')
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(16)
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => {
                    this.searchKeyword = keyword
                    this.search()
                  })
              }, (keyword: string) => keyword)
            }
            .width('100%')
            .margin({ bottom: 16 })
          }
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
      } else {
        IllustWaterfall({
          fetchFirst: (): Promise<IllustListPage> => this.fetchFirst(),
          reloadToken: this.reloadToken
        })
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }
}
