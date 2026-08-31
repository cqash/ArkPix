import { router } from '@kit.ArkUI';
import { FollowPage } from './FollowPage'
import { RankPage } from './RankPage'
import { RecomPage } from './RecomPage'
import { SearchPage } from '../search/SearchPage'
import { SettingsPage } from '../settings/SettingsPage'
import { continuationService } from '../../services/ContinuationService'
import { ContinuationPayload, CONTINUATION_PAGE_HOME } from '../../models/ContinuationPayload'

interface HomeRouteParams {
  tabIndex?: number
}

@Entry
@Component
struct HomePage {
  @State currentIndex: number = 0
  private tabsController: TabsController = new TabsController()

  aboutToAppear() {
    // 接续恢复：SplashPage 跳转携带 tabIndex 时定位到对应 Tab（Tabs 构造 index 仅创建时生效，须 changeIndex）
    let params = router.getParams() as HomeRouteParams
    if (params && params.tabIndex !== undefined && params.tabIndex >= 0 && params.tabIndex <= 4) {
      this.currentIndex = params.tabIndex
      this.tabsController.changeIndex(params.tabIndex)
    }
    // 多端流转：登记当前页面状态（主页 = Tab 索引）
    this.registerContinuationState()
  }

  aboutToDisappear() {
    continuationService.setCurrentPageState(null)
  }

  private registerContinuationState() {
    continuationService.setCurrentPageState(new ContinuationPayload({
      page: CONTINUATION_PAGE_HOME,
      tabIndex: this.currentIndex
    }))
  }

  @Builder
  TabBuilder(title: Resource, index: number) {
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
      .tabBar(this.TabBuilder($r('app.string.home_tab_recom'), 0))

      TabContent() {
        FollowPage()
      }
      .tabBar(this.TabBuilder($r('app.string.home_tab_follow'), 1))

      TabContent() {
        RankPage()
      }
      .tabBar(this.TabBuilder($r('app.string.home_tab_rank'), 2))

      TabContent() {
        SearchPage()
      }
      .tabBar(this.TabBuilder($r('app.string.home_tab_search'), 3))

      TabContent() {
        SettingsPage()
      }
      .tabBar(this.TabBuilder($r('app.string.home_tab_settings'), 4))
    }
    .onChange((index: number) => {
      this.currentIndex = index
      // 切 Tab 同步更新接续登记
      this.registerContinuationState()
    })
    .width('100%')
    .height('100%')
  }
}
