import { FollowPage } from './FollowPage'
import { RankPage } from './RankPage'
import { RecomPage } from './RecomPage'
import { SearchPage } from '../search/SearchPage'
import { SettingsPage } from '../settings/SettingsPage'

@Entry
@Component
struct HomePage {
  @State currentIndex: number = 0
  private tabsController: TabsController = new TabsController()

  @Builder
  TabBuilder(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(10)
        .fontColor(this.currentIndex === index ? '#0096FA' : '#999999')
        .margin({ top: 4 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.tabsController }) {
      TabContent() {
        RecomPage()
      }
      .tabBar(this.TabBuilder('推荐', 0))

      TabContent() {
        FollowPage()
      }
      .tabBar(this.TabBuilder('动态', 1))

      TabContent() {
        RankPage()
      }
      .tabBar(this.TabBuilder('排行', 2))

      TabContent() {
        SearchPage()
      }
      .tabBar(this.TabBuilder('搜索', 3))

      TabContent() {
        SettingsPage()
      }
      .tabBar(this.TabBuilder('设置', 4))
    }
    .onChange((index: number) => {
      this.currentIndex = index
    })
    .width('100%')
    .height('100%')
  }
}
