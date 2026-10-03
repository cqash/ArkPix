import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { picker, fileIo } from '@kit.CoreFileKit';
import { getDbService, HistoryItem, SearchHistoryItem } from '../../services/DatabaseService';
import { CachedImage } from '../../components/common/CachedImage';
import { EmptyView, LoadingView } from '../../components/common/CommonViews';
import { buildHistoryExportJson, buildHistoryPidText } from '../../utils/HistoryExport';
import { getStr, getStrf } from '../../utils/I18nUtils';
import { HapticUtils } from '../../utils/HapticUtils';
import { IllustListPage } from '../../components/illust/IllustWaterfall';
import { DetailListContextRegistry, DetailListContext } from '../../services/DetailListContextRegistry';

@Entry
@Component
struct HistoryPage {
  @State browseHistory: HistoryItem[] = []
  @State searchHistory: SearchHistoryItem[] = []
  @State isLoading: boolean = true
  @State currentTab: number = 0
  @State menuShown: boolean = false

  aboutToAppear() {
    this.loadData()
  }

  private async loadData(): Promise<void> {
    this.isLoading = true
    try {
      let db = await getDbService()
      this.browseHistory = await db.getHistory()
      this.searchHistory = await db.getSearchHistory(30)
    } catch (e) {
      console.error('Load history failed: ' + e)
    } finally {
      this.isLoading = false
    }
  }

  private confirmClearBrowseHistory(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.history_clear_browse_title'),
      message: $r('app.string.history_clear_browse_msg'),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: $r('app.string.common_clear'),
        action: () => {
          HapticUtils.heavy()
          this.clearBrowseHistory()
        }
      }
    })
  }

  private async clearBrowseHistory(): Promise<void> {
    try {
      let db = await getDbService()
      await db.clearHistory()
      this.browseHistory = []
    } catch (e) {
      console.error('Clear browse history failed: ' + e)
    }
  }

  private showToast(message: string): void {
    // 走 UIContext promptAction：菜单弹层未完全关闭时模块级 promptAction 的 toast 会被吞
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  /** 导出浏览历史：asJson=true 导出完整字段 JSON，false 导出纯文本 PID 列表 */
  private async exportHistory(asJson: boolean): Promise<void> {
    if (this.browseHistory.length === 0) {
      this.showToast(getStr($r('app.string.history_empty_toast')))
      return
    }
    let content = asJson ? buildHistoryExportJson(this.browseHistory) : buildHistoryPidText(this.browseHistory)
    let fileName = asJson ? 'arkpix-history.json' : 'arkpix-history-pids.txt'
    try {
      let ctx = AppStorage.get<common.Context>('context')
      if (!ctx) {
        this.showToast(getStr($r('app.string.common_export_no_context')))
        return
      }
      let options = new picker.DocumentSaveOptions()
      options.newFileNames = [fileName]
      let docPicker = new picker.DocumentViewPicker(ctx)
      let uris: Array<string> = await docPicker.save(options)
      if (uris.length === 0) {
        return
      }
      let file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
      fileIo.writeSync(file.fd, content)
      fileIo.closeSync(file)
      this.showToast(getStr($r('app.string.common_export_success')))
    } catch (e) {
      this.showToast(getStrf($r('app.string.common_export_failed'), String(e)))
    }
  }

  /** 菜单项点击：先关菜单，延迟 300ms（菜单关闭动画后）再执行，避免 toast/弹窗被菜单层吞掉 */
  private runAfterMenuClosed(action: () => void): void {
    this.menuShown = false
    setTimeout(() => {
      action()
    }, 300)
  }

  @Builder
  MenuBuilder() {
    Column() {
      Text($r('app.string.history_export_json'))
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => { this.runAfterMenuClosed(() => { this.exportHistory(true) }) })
      Text($r('app.string.history_export_pid'))
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => { this.runAfterMenuClosed(() => { this.exportHistory(false) }) })
      Text($r('app.string.history_clear_browse_title'))
        .fontSize(14)
        .fontColor('#FF4444')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => { this.runAfterMenuClosed(() => { this.confirmClearBrowseHistory() }) })
    }
    .width(150)
    .padding({ top: 4, bottom: 4 })
  }

  private confirmClearSearchHistory(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.history_clear_search_title'),
      message: $r('app.string.history_clear_search_msg'),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: $r('app.string.common_clear'),
        action: () => {
          this.clearSearchHistory()
        }
      }
    })
  }

  private async clearSearchHistory(): Promise<void> {
    try {
      let db = await getDbService()
      await db.clearSearchHistory()
      this.searchHistory = []
    } catch (e) {
      console.error('Clear search history failed: ' + e)
    }
  }

  @Builder
  BrowseHistoryTab() {
    if (this.browseHistory.length === 0) {
      EmptyView({ message: getStr($r('app.string.history_empty_browse')) })
    } else {
      Grid() {
        ForEach(this.browseHistory, (item: HistoryItem) => {
          GridItem() {
            Column() {
              CachedImage({ url: item.image_url, ratio: 1, fit: ImageFit.Cover })
              Text(item.title)
                .fontSize(12)
                .fontColor('#333333')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .margin({ top: 4 })
              Text(item.user_name)
                .fontSize(11)
                .fontColor('#999999')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .margin({ top: 2 })
            }
            .width('100%')
            .padding(4)
          }
          .onClick(() => {
            this.openBrowseHistoryDetail(item.illust_id)
          })
        }, (item: HistoryItem) => item.id.toString())
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(8)
      .rowsGap(8)
      .padding(8)
      .width('100%')
      .height('100%')
    }
  }

  /** 搜索历史类型标识（illust/user/pid/uid → 插画/画师/PID/UID） */
  private searchTypeLabel(searchType: string): string {
    if (searchType === 'illust') {
      return getStr($r('app.string.search_tab_illust'))
    }
    if (searchType === 'user') {
      return getStr($r('app.string.search_tab_user'))
    }
    if (searchType === 'pid') {
      return 'PID'
    }
    if (searchType === 'uid') {
      return 'UID'
    }
    return searchType
  }

  /**
   * 浏览历史点击：注册滑动上下文（ids=当前展示序列 illust_id，时间倒序已按 illust_id 去重；
   * 历史一次性取回无续页游标，nextUrl='' 且 fetchNext 返回空页，滑到末尾自然 No More），
   * 再 pushUrl 传 { illustId, contextToken, contextIndex }
   */
  private openBrowseHistoryDetail(illustId: number): void {
    let ids: number[] = this.browseHistory.map((item: HistoryItem) => item.illust_id)
    let index = ids.indexOf(illustId)
    if (index < 0) {
      index = 0
    }
    let ctx: DetailListContext = {
      ids: ids,
      nextUrl: '',
      fetchNext: async (nextUrl: string): Promise<IllustListPage> => {
        let empty: IllustListPage = { illusts: [], nextUrl: '' }
        return empty
      }
    }
    let token = DetailListContextRegistry.register(ctx)
    router.pushUrl({
      url: 'pages/detail/IllustDetailPage',
      params: { illustId: illustId, contextToken: token, contextIndex: index }
    })
  }

  /** 按类型回放：illust→插画搜索、user→画师 Tab、pid→作品详情、uid→用户主页 */
  private replaySearchHistory(item: SearchHistoryItem): void {
    if (item.search_type === 'user') {
      router.pushUrl({ url: 'pages/search/SearchPage', params: { keyword: item.keyword, tab: 'user' } })
    } else if (item.search_type === 'pid') {
      router.pushUrl({ url: 'pages/detail/IllustDetailPage', params: { illustId: Number(item.keyword) } })
    } else if (item.search_type === 'uid') {
      router.pushUrl({ url: 'pages/user/UserProfilePage', params: { userId: Number(item.keyword) } })
    } else {
      router.pushUrl({ url: 'pages/search/TagSearchPage', params: { keyword: item.keyword } })
    }
  }

  @Builder
  SearchHistoryTab() {
    if (this.searchHistory.length === 0) {
      EmptyView({ message: getStr($r('app.string.history_empty_search')) })
    } else {
      Column() {
        Row() {
          Text(getStrf($r('app.string.history_total_count'), this.searchHistory.length))
            .fontSize(12)
            .fontColor('#999999')
            .layoutWeight(1)
          Text($r('app.string.common_clear'))
            .fontSize(13)
            .fontColor('#FF4444')
            .onClick(() => { this.confirmClearSearchHistory() })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })

        List() {
          ForEach(this.searchHistory, (item: SearchHistoryItem) => {
            ListItem() {
              Row() {
                Text(item.keyword)
                  .fontSize(14)
                  .fontColor('#333333')
                  .layoutWeight(1)
                Text(this.searchTypeLabel(item.search_type))
                  .fontSize(11)
                  .fontColor('#999999')
              }
              .width('100%')
              .height(48)
              .padding({ left: 16, right: 16 })
              .backgroundColor('#FFFFFF')
            }
            .onClick(() => {
              this.replaySearchHistory(item)
            })
          }, (item: SearchHistoryItem) => item.id.toString())
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text($r('app.string.common_back_arrow'))
          .fontSize(16)
          .fontColor('#0096FA')
          .onClick(() => {
            router.back()
          })
        Text($r('app.string.settings_history'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('⋮')
          .fontSize(18)
          .fontColor('#333333')
          .width(48)
          .textAlign(TextAlign.End)
          .onClick(() => { this.menuShown = true })
          .bindContextMenu(this.menuShown, this.MenuBuilder, {
            onDisappear: () => { this.menuShown = false }
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor('#FFFFFF')

      if (this.isLoading) {
        LoadingView()
      } else {
        Tabs({ barPosition: BarPosition.Start }) {
          TabContent() {
            this.BrowseHistoryTab()
          }
          .tabBar($r('app.string.history_tab_browse'))
          TabContent() {
            this.SearchHistoryTab()
          }
          .tabBar($r('app.string.search_history_title'))
        }
        .width('100%')
        .layoutWeight(1)
        .onChange((index: number) => {
          this.currentTab = index
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
