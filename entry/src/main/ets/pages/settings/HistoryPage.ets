import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { picker, fileIo } from '@kit.CoreFileKit';
import { getDbService, HistoryItem, SearchHistoryItem } from '../../services/DatabaseService';
import { CachedImage } from '../../components/common/CachedImage';
import { EmptyView, LoadingView } from '../../components/common/CommonViews';
import { buildHistoryExportJson, buildHistoryPidText } from '../../utils/HistoryExport';

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
      title: '清空浏览历史',
      message: '确定要清空全部浏览历史吗？该操作不可恢复。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '清空',
        action: () => {
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
      this.showToast('暂无历史记录')
      return
    }
    let content = asJson ? buildHistoryExportJson(this.browseHistory) : buildHistoryPidText(this.browseHistory)
    let fileName = asJson ? 'arkpix-history.json' : 'arkpix-history-pids.txt'
    try {
      let ctx = AppStorage.get<common.Context>('context')
      if (!ctx) {
        this.showToast('导出失败：无法获取上下文')
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
      this.showToast('导出成功')
    } catch (e) {
      this.showToast('导出失败: ' + e)
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
      Text('导出 JSON')
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => { this.runAfterMenuClosed(() => { this.exportHistory(true) }) })
      Text('导出 PID 列表')
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => { this.runAfterMenuClosed(() => { this.exportHistory(false) }) })
      Text('清空浏览历史')
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
      title: '清空搜索历史',
      message: '确定要清空全部搜索历史吗？',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '清空',
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
      EmptyView({ message: '暂无浏览历史' })
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
            router.pushUrl({ url: 'pages/detail/IllustDetailPage', params: { illustId: item.illust_id } })
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
      return '插画'
    }
    if (searchType === 'user') {
      return '画师'
    }
    if (searchType === 'pid') {
      return 'PID'
    }
    if (searchType === 'uid') {
      return 'UID'
    }
    return searchType
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
      EmptyView({ message: '暂无搜索历史' })
    } else {
      Column() {
        Row() {
          Text('共 ' + this.searchHistory.length + ' 条')
            .fontSize(12)
            .fontColor('#999999')
            .layoutWeight(1)
          Text('清空')
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
        Text('< 返回')
          .fontSize(16)
          .fontColor('#0096FA')
          .onClick(() => {
            router.back()
          })
        Text('历史记录')
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
          .tabBar('浏览历史')
          TabContent() {
            this.SearchHistoryTab()
          }
          .tabBar('搜索历史')
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
