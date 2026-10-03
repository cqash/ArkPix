import { router } from '@kit.ArkUI';
import { apiService } from '../../network/ApiService';
import { getDbService, SearchHistoryItem } from '../../services/DatabaseService';
import { IllustWaterfall, IllustListPage, parseIllustListPage } from '../../components/illust/IllustWaterfall';
import { UserPreview } from '../../models/Illust';
import { CachedImage } from '../../components/common/CachedImage';
import { EmptyView, ErrorView, LoadingView } from '../../components/common/CommonViews';
import { getStr, getStrf } from '../../utils/I18nUtils';
import { PixivLinkParser, PixivLinkTarget } from '../../utils/PixivLinkParser';

/** /v2/search/autocomplete 响应 tags[] 元素 */
interface RawAutoCompleteTag {
  name?: string
}

interface RawAutoCompleteResponse {
  tags?: Object[]
}

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
  /** 底栏 Tab 再点回顶：仅响应 tabIndex=3 的令牌（作用于插画结果瀑布流） */
  @StorageLink('tabRetapToken') @Watch('onTabRetap') tabRetapToken: string = ''
  @State scrollTopToken: number = 0
  /** 链接直达目标（输入为可解析的 pixiv 链接时非 null）；不识别静默不显示入口 */
  @State linkTarget: PixivLinkTarget | null = null
  /** 自动补全建议（最多 10 条）；提交/失焦/清空时收起 */
  @State suggestNames: string[] = []
  private suggestTimer: number = -1

  onTabRetap() {
    let idx = this.tabRetapToken.indexOf(':')
    if (idx <= 0) {
      return
    }
    if (Number(this.tabRetapToken.substring(0, idx)) === 3) {
      this.scrollTopToken += 1
    }
  }

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
        this.linkTarget = PixivLinkParser.parse(params.keyword.trim())
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
    // 提交时收起补全下拉
    this.clearSuggestState()
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

  /** 输入变化：链接直达判定（即时）+ 补全防抖调度（300ms，非数字非 URL 时才调 API） */
  private onKeywordChange(value: string): void {
    let kw = value.trim()
    this.linkTarget = PixivLinkParser.parse(kw)
    if (this.suggestTimer >= 0) {
      clearTimeout(this.suggestTimer)
      this.suggestTimer = -1
    }
    if (kw.length === 0 || this.isNumericString(kw) || kw.startsWith('https://') || kw.startsWith('pixiv://')) {
      this.suggestNames = []
      return
    }
    this.suggestTimer = setTimeout(() => {
      this.suggestTimer = -1
      this.fetchSuggestions(kw)
    }, 300)
  }

  private isNumericString(kw: string): boolean {
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

  private clearSuggestState(): void {
    if (this.suggestTimer >= 0) {
      clearTimeout(this.suggestTimer)
      this.suggestTimer = -1
    }
    this.suggestNames = []
  }

  /** 自动补全：/v2/search/autocomplete，去重截断 10 条；输入已变化则丢弃过期结果 */
  private async fetchSuggestions(prefix: string): Promise<void> {
    try {
      let response = await apiService.getAutoComplete(prefix)
      if (this.searchKeyword.trim() !== prefix) {
        return
      }
      let raw = response as RawAutoCompleteResponse
      let tags = raw.tags ?? []
      let names: string[] = []
      for (let i = 0; i < tags.length && names.length < 10; i++) {
        let item = tags[i] as RawAutoCompleteTag
        let name = item.name ?? ''
        if (name.length === 0 || names.includes(name)) {
          continue
        }
        names.push(name)
      }
      this.suggestNames = names
    } catch (e) {
      console.error('Search autocomplete failed: ' + e)
    }
  }

  /** 点选补全：多词（空格分词≥2，含全角空格）仅替换最后一个词、光标置末尾、不提交；单词回填并直接提交 */
  private pickSuggestion(name: string): void {
    let kw = this.searchKeyword.trim()
    let words = kw.split(new RegExp('[\\s　]+'))
    if (words.length >= 2) {
      let m = new RegExp('^(.*[\\s　])[^\\s　]+$').exec(kw)
      if (m !== null && m.length >= 2) {
        this.searchKeyword = m[1] + name
      } else {
        this.searchKeyword = name
      }
      this.clearSuggestState()
      return
    }
    this.searchKeyword = name
    this.clearSuggestState()
    this.search()
  }

  /** 链接直达点击：跳详情/画师页并写搜索历史（复用 pid/uid 类型） */
  private goLinkTarget(): void {
    let target = this.linkTarget
    if (target === null) {
      return
    }
    if (target.kind === 'illust') {
      this.recordSearchHistory(target.id.toString(), 'pid')
      router.pushUrl({ url: 'pages/detail/IllustDetailPage', params: { illustId: target.id } })
    } else {
      this.recordSearchHistory(target.id.toString(), 'uid')
      router.pushUrl({ url: 'pages/user/UserProfilePage', params: { userId: target.id } })
    }
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
      this.userError = getStrf($r('app.string.common_load_failed_detail'), String(e))
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
        TextInput({ placeholder: $r('app.string.search_placeholder'), text: $$this.searchKeyword })
          .width('80%')
          .height(40)
          .backgroundColor('#F5F5F5')
          .borderRadius(20)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => { this.onKeywordChange(value) })
          .onBlur(() => { this.clearSuggestState() })
          .onSubmit(() => { this.search() })
        Button($r('app.string.search_button'))
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

      // 链接直达入口（pixiv 作品/用户链接；无法解析静默不显示）
      if (this.linkTarget !== null) {
        this.LinkDirectEntry()
      }

      // 自动补全下拉（最多 10 条；多词点选仅替换末词，单词点选回填并提交）
      if (this.suggestNames.length > 0) {
        Column() {
          ForEach(this.suggestNames, (name: string, index: number) => {
            Text(name)
              .fontSize(14)
              .fontColor('#333333')
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .onClick(() => { this.pickSuggestion(name) })
          }, (name: string, index: number) => name + '_' + index)
        }
        .width('100%')
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .margin({ left: 16, right: 16, bottom: 8 })
      }

      if (!this.hasSearched) {
        Column() {
          if (this.searchHistory.length > 0) {
            Row() {
              Text($r('app.string.search_history_title'))
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#333333')
                .layoutWeight(1)
              Text($r('app.string.search_clear'))
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
          Text($r('app.string.search_trending'))
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
              reloadToken: this.reloadToken,
              scrollTopToken: this.scrollTopToken,
              bottomInset: 72
            })
          }
          .tabBar($r('app.string.search_tab_illust'))
          TabContent() {
            this.UserResultTab()
          }
          .tabBar($r('app.string.search_tab_user'))
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

  private linkDirectLabel(): string {
    let target = this.linkTarget
    if (target === null) {
      return ''
    }
    if (target.kind === 'illust') {
      return getStrf($r('app.string.search_link_direct_illust'), target.id.toString())
    }
    return getStrf($r('app.string.search_link_direct_user'), target.id.toString())
  }

  /** 链接直达入口（与 NumericDirectEntries 并列）：输入为可解析 pixiv 链接时显示 */
  @Builder
  LinkDirectEntry() {
    Row() {
      Text(this.linkDirectLabel())
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
    .margin({ left: 16, right: 16, bottom: 8 })
    .onClick(() => { this.goLinkTarget() })
  }

  /** 数字直达入口（插画 ID / 画师 ID），输入框之下、建议区与结果区共用 */
  @Builder
  NumericDirectEntries() {
    Column() {
      Row() {
        Text(getStrf($r('app.string.search_pid_direct'), this.searchKeyword.trim()))
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
        Text(getStrf($r('app.string.search_uid_direct'), this.searchKeyword.trim()))
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
      EmptyView({ message: getStr($r('app.string.search_no_users')) })
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
        // 底部留白用占位 ListItem 承载，勿用 List padding（padding 会在底部裁出永久空白带，
        // 透出页面底色挡住首页悬浮胶囊底栏的沉浸背景）
        ListItem() {
        }
        .width('100%')
        .height(72)
      }
      .width('100%')
      .height('100%')
      .onReachEnd(() => { this.loadMoreUsers() })
    }
  }
}
