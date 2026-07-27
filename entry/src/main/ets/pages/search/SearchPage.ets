import { router } from '@kit.ArkUI';
import { apiService } from '../../network/ApiService';
import { getDbService, SearchHistoryItem } from '../../services/DatabaseService';
import { IllustWaterfall, IllustListPage, parseIllustListPage } from '../../components/illust/IllustWaterfall';
import { UserPreview } from '../../models/Illust';
import { CachedImage } from '../../components/common/CachedImage';
import { EmptyView, ErrorView, LoadingView } from '../../components/common/CommonViews';

interface TrendingTagsResponse {
  trend_tags: string[]
}

interface RawUserSearchResponse {
  user_previews?: Object[]
  next_url?: string
}

/** /v1/search/user 的 user_previews[] 元素是包装对象，需先取 .user 再解析 */
interface RawUserPreviewWrapper {
  user?: Object
}

/** 历史记录页回放路由参数：keyword 预填并自动提交；tab='user' 初始定位画师 Tab */
interface SearchPageRouteParams {
  keyword?: string
  tab?: string
}

@Component
export struct SearchPage {
  @State searchKeyword: string = ''
  @State searchedKeyword: string = ''
  @State hasSearched: boolean = false
  @State reloadToken: number = 0
  @State trendingTags: string[] = []
  @State searchHistory: string[] = []
  @State userResults: UserPreview[] = []
  @State userNextUrl: string = ''
  @State userLoading: boolean = false
  @State userError: string = ''
  @State userLoadedOnce: boolean = false
  /** 结果区当前 Tab（0=插画，1=画师），决定搜索历史记录的 search_type */
  @State currentTabIndex: number = 0

  aboutToAppear() {
    this.loadTrendingTags()
    this.loadSearchHistory()
    let params = router.getParams() as SearchPageRouteParams | undefined
    if (params) {
      if (params.tab === 'user') {
        this.currentTabIndex = 1
      }
      if (params.keyword !== undefined && params.keyword.length > 0) {
        this.searchKeyword = params.keyword
        this.search()
      }
    }
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
    this.loadUserSearch()
    // 按当前结果 Tab 记录历史类型（插画 Tab=illust、画师 Tab=user）
    let searchType = this.currentTabIndex === 1 ? 'user' : 'illust'
    this.recordSearchHistory(keyword, searchType)
  }

  /** 写入搜索历史并刷新本地历史区 */
  private recordSearchHistory(keyword: string, searchType: string) {
    getDbService().then((db) => {
      return db.addSearchHistory(keyword, searchType)
    }).then(() => {
      this.loadSearchHistory()
    }).catch((e: Object) => {
      console.error('Add search history failed: ' + e)
    })
  }

  /** 输入是否为纯数字（非空且全为数字字符），用于 PID/UID 直达建议 */
  private isNumericInput(): boolean {
    let kw = this.searchKeyword.trim()
    if (kw.length === 0) {
      return false
    }
    for (let i = 0; i < kw.length; i++) {
      let code = kw.charCodeAt(i)
      if (code < 48 || code > 57) {
        return false
      }
    }
    return true
  }

  private numericInputValue(): number {
    return Number(this.searchKeyword.trim())
  }

  private parseUserPreviews(response: Object): UserPreview[] {
    let raw = response as RawUserSearchResponse
    let items = raw.user_previews ?? []
    let results: UserPreview[] = []
    for (let i = 0; i < items.length; i++) {
      let wrapper = items[i] as RawUserPreviewWrapper
      if (wrapper.user) {
        results.push(new UserPreview(UserPreview.fromJson(wrapper.user)))
      }
    }
    return results
  }

  private userSearchNextUrl(response: Object): string {
    let raw = response as RawUserSearchResponse
    return raw.next_url ?? ''
  }

  async loadUserSearch() {
    if (!this.searchedKeyword) {
      return
    }
    this.userLoading = true
    this.userError = ''
    try {
      let response = await apiService.searchUsers(this.searchedKeyword)
      this.userResults = this.parseUserPreviews(response)
      this.userNextUrl = this.userSearchNextUrl(response)
      this.userLoadedOnce = true
    } catch (e) {
      this.userError = '加载失败: ' + e
      console.error('Search users failed: ' + e)
    } finally {
      this.userLoading = false
    }
  }

  async loadMoreUsers() {
    if (this.userLoading || this.userNextUrl.length === 0) {
      return
    }
    this.userLoading = true
    try {
      let response = await apiService.fetchNext(this.userNextUrl)
      let fresh = this.parseUserPreviews(response)
      let append: UserPreview[] = []
      for (let i = 0; i < fresh.length; i++) {
        let exists = false
        for (let j = 0; j < this.userResults.length; j++) {
          if (this.userResults[j].id === fresh[i].id) {
            exists = true
            break
          }
        }
        if (!exists) {
          append.push(fresh[i])
        }
      }
      this.userResults = this.userResults.concat(append)
      this.userNextUrl = this.userSearchNextUrl(response)
    } catch (e) {
      console.error('Load more users failed: ' + e)
    } finally {
      this.userLoading = false
    }
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

      // 数字直达入口：移出 hasSearched 门控（SearchPage 为常驻组件，提交过搜索后建议区不再渲染，
      // 直达入口需在两分支共用位置常驻可用）
      if (this.isNumericInput()) {
        this.NumericDirectEntries()
      }

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
        // Tabs 构造参数 index 仅在创建时生效：hasSearched 变 true 时按 currentTabIndex 初始定位
        Tabs({ barPosition: BarPosition.Start, index: this.currentTabIndex }) {
          TabContent() {
            IllustWaterfall({
              fetchFirst: (): Promise<IllustListPage> => this.fetchFirst(),
              reloadToken: this.reloadToken
            })
          }
          .tabBar('插画')
          TabContent() {
            this.UserResultTab()
          }
          .tabBar('画师')
        }
        .layoutWeight(1)
        .barHeight(40)
        .onChange((index: number) => {
          this.currentTabIndex = index
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 数字直达入口（插画 ID / 画师 ID），输入框之下、建议区与结果区共用 */
  @Builder
  NumericDirectEntries() {
    Column() {
      Row() {
        Text('插画 ID 直达：' + this.searchKeyword.trim())
          .fontSize(14)
          .fontColor('#0096FA')
          .layoutWeight(1)
        Text('>')
          .fontSize(14)
          .fontColor('#999999')
      }
      .width('100%')
      .height(44)
      .padding({ left: 12, right: 12 })
      .backgroundColor('#E6F4FF')
      .borderRadius(8)
      .margin({ bottom: 8 })
      .onClick(() => {
        this.recordSearchHistory(this.searchKeyword.trim(), 'pid')
        router.pushUrl({
          url: 'pages/detail/IllustDetailPage',
          params: { illustId: this.numericInputValue() }
        })
      })
      Row() {
        Text('画师 ID 直达：' + this.searchKeyword.trim())
          .fontSize(14)
          .fontColor('#0096FA')
          .layoutWeight(1)
        Text('>')
          .fontSize(14)
          .fontColor('#999999')
      }
      .width('100%')
      .height(44)
      .padding({ left: 12, right: 12 })
      .backgroundColor('#E6F4FF')
      .borderRadius(8)
      .onClick(() => {
        this.recordSearchHistory(this.searchKeyword.trim(), 'uid')
        router.pushUrl({
          url: 'pages/user/UserProfilePage',
          params: { userId: this.numericInputValue() }
        })
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 8 })
  }

  @Builder
  UserResultTab() {
    if (this.userError && this.userResults.length === 0) {
      ErrorView({ message: this.userError, onRetry: () => { this.loadUserSearch() } })
    } else if (this.userLoading && !this.userLoadedOnce) {
      LoadingView()
    } else if (this.userLoadedOnce && this.userResults.length === 0) {
      EmptyView({ message: '未找到匹配的画师' })
    } else {
      List() {
        ForEach(this.userResults, (user: UserPreview) => {
          ListItem() {
            Row() {
              if (user.profileImageUrls.medium.length > 0) {
                Stack() {
                  CachedImage({ url: user.profileImageUrls.medium, ratio: 1, fit: ImageFit.Cover })
                }
                .width(48)
                .height(48)
                .clip(true)
                .borderRadius(24)
              } else {
                Column()
                  .width(48)
                  .height(48)
                  .borderRadius(24)
                  .backgroundColor('#F0F0F0')
              }
              Column() {
                Text(user.name)
                  .fontSize(14)
                  .fontColor('#333333')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text('@' + user.account)
                  .fontSize(12)
                  .fontColor('#999999')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ left: 12 })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor('#FFFFFF')
          }
          .onClick(() => {
            router.pushUrl({ url: 'pages/user/UserProfilePage', params: { userId: user.id } })
          })
        }, (user: UserPreview) => user.id.toString())
      }
      .width('100%')
      .height('100%')
      .onReachEnd(() => { this.loadMoreUsers() })
    }
  }
}
