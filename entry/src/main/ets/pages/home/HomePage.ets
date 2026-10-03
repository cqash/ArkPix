import { router } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, BlurStrategy, hdsMaterial } from '@kit.UIDesignKit';
import { FollowPage } from './FollowPage'
import { RankPage } from './RankPage'
import { RecomPage } from './RecomPage'
import { SearchPage } from '../search/SearchPage'
import { SettingsPage } from '../settings/SettingsPage'
import { continuationService } from '../../services/ContinuationService'
import { ContinuationPayload, CONTINUATION_PAGE_HOME } from '../../models/ContinuationPayload'
import { HapticUtils } from '../../utils/HapticUtils'
import { isImmersiveSupported, tabBarMaterial } from '../../utils/MaterialUtils'

interface HomeRouteParams {
  tabIndex?: number
}

@Entry
@Component
struct HomePage {
  @State currentIndex: number = 0
  /** 底栏胶囊沉浸光感材质等级（HDS 分支用）：按设备能力探测（支持 IMMERSIVE→EXQUISITE，否则降级 SMOOTH，官方 FAQ 路径） */
  @State barMaterialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE
  /** API 26+ 且支持沉浸光感时走标准 Tabs + ImmersiveMaterial（ArkUI 通道，折射/边缘光效/随深浅色自适应）；
   *  低版本走 HdsTabs + HDS 材质通道（API 23+ 磨砂）。判定结果进程内不变，aboutToAppear 内一次性定值 */
  private useImmersiveTabs: boolean = false
  private tabsController: TabsController = new TabsController()
  private hdsTabsController: HdsTabsController = new HdsTabsController()

  aboutToAppear() {
    this.useImmersiveTabs = isImmersiveSupported()
    // HDS 分支材质能力探测：getSystemMaterialTypes 为 API 23+，低版本/异常保持 ADAPTIVE 兜原样
    try {
      let types = hdsMaterial.getSystemMaterialTypes()
      console.info(`[HomePage] systemMaterialTypes=${JSON.stringify(types)}`)
      if (types.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0) {
        this.barMaterialLevel = hdsMaterial.MaterialLevel.EXQUISITE
      } else {
        this.barMaterialLevel = hdsMaterial.MaterialLevel.SMOOTH
      }
    } catch (e) {
      console.error('[HomePage] getSystemMaterialTypes failed: ' + e)
    }
    // 接续恢复：SplashPage 跳转携带 tabIndex 时定位到对应 Tab（Tabs 构造 index 仅创建时生效，须 changeIndex）
    let params = router.getParams() as HomeRouteParams
    if (params && params.tabIndex !== undefined && params.tabIndex >= 0 && params.tabIndex <= 4) {
      this.currentIndex = params.tabIndex
      this.changeTab(params.tabIndex)
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

  /** 按当前底栏分支分发 changeIndex（两分支控制器类型不同） */
  private changeTab(index: number): void {
    if (this.useImmersiveTabs) {
      this.tabsController.changeIndex(index)
    } else {
      this.hdsTabsController.changeIndex(index)
    }
  }

  @Builder
  TabBuilder(title: Resource, index: number) {
    Column() {
      Text(title)
        .fontSize(12)
        .fontColor(this.currentIndex === index ? '#0096FA' : '#666666')
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (this.currentIndex === index) {
        // 再点当前 Tab：广播回顶令牌（"<tabIndex>:<epochMs>"，各列表页仅响应自身索引）
        AppStorage.setOrCreate('tabRetapToken', index.toString() + ':' + Date.now().toString())
      } else {
        this.changeTab(index)
      }
    })
  }

  /** 五个 Tab 内容（两个底栏分支共享） */
  @Builder
  TabContents() {
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

  build() {
    if (this.useImmersiveTabs) {
      // API 26+ 沉浸光感底栏：标准 Tabs 悬浮样式 + ImmersiveMaterial（官方典型场景方案）。
      // 注意：barFloatingStyle 为 API 26+ 属性，只允许出现在本分支（useImmersiveTabs 已含版本门控）
      Tabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.tabsController }) {
        this.TabContents()
      }
      .barOverlap(true)
      .vertical(false)
      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(BlurStyle.NONE)
      .barFloatingStyle({
        barBottomMargin: 12,
        // 侧边距对齐原 HDS 胶囊视觉（默认太宽近乎贴边）
        barSideMargin: 24,
        // 悬浮样式默认背板蒙层（浅色奶白带子根因，同 HDS 分支处理）：置透明
        maskColor: Color.Transparent,
        systemMaterial: tabBarMaterial()
      })
      .onChange((index: number) => {
        HapticUtils.selectionClick()
        this.currentIndex = index
        // 切 Tab 同步更新接续登记
        this.registerContinuationState()
      })
      .width('100%')
      .height('100%')
      // 底部安全区带透出根节点底色：对齐页面 #F5F5F5
      .backgroundColor('#F5F5F5')
    } else {
      // HDS 底部页签：悬浮胶囊栏 + 系统自适应沉浸光感材质（图库底栏方案，API 23+ HDS 通道渲染）
      HdsTabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.hdsTabsController }) {
        this.TabContents()
      }
      .barOverlap(true)
      .vertical(false)
      // 滚动触发的条带磨砂背景（像素实证）：默认 BlurStrategy.ADAPTIVE 下，列表内容一旦滚过底栏，
      // HDS 即在条带区（胶囊左右各~40px+全带纵向 y2496-2730）渲染一层持久的磨砂+染色池——
      // 平坦区只显 ~-4 lum 柔影（245→240→245 山谷），彩色内容则被模糊抹平成中性 (241,241,241)；
      // 重启后未滚动时条带完全透明（内容透出 sd 与清晰区一致），一滚即触发且静置 40s+ 不消退。
      // DISABLE 彻底关闭该自适应模糊策略。
      .blurStrategy(BlurStrategy.DISABLE)
      // TabBar 节点默认带模糊底并扩展进底部安全区（胶囊下的奶白带子）：显式去背景去模糊，只留胶囊材质
      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(BlurStyle.NONE)
      .barFloatingStyle({
        barBottomMargin: 12,
        // 背板蒙层：Color.Transparent 会回退默认（浅#CCF1F3F5/暗#99000000，80%/60% 实心蒙层=奶白带子根因）；
        // 字符串 '#01xxxxxx' 的 alpha=01（0.4%）实测被正常解析、蒙层近乎不可见（maskColor 改红色条带不变红可证）。
        // maskHeight 压至 1vp（文档明示不可为 0）双保险。
        // 残余：胶囊自带软投影（~2% 亮度山谷，横跨胶囊左右各~40px、纵深 y2496-2730，像素实测 245→240→245）与
        // 安全区底带的投影延续（x 对齐胶囊 84-1232），均极淡，属 HDS 悬浮样式固有渲染，无法经配置移除。
        gradientMask: { maskColor: '#01F1F3F5', maskHeight: 1 },
        // 沉浸光感材质（官方推荐 ADAPTIVE 类型 + 按设备能力选档，见 aboutToAppear 探测）
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: this.barMaterialLevel
        }
      })
      .onChange((index: number) => {
        HapticUtils.selectionClick()
        this.currentIndex = index
        // 切 Tab 同步更新接续登记
        this.registerContinuationState()
      })
      .width('100%')
      .height('100%')
      // 底部安全区带（TabContent 子页只铺到安全区顶 y2734，2734-2832 露根节点底色=窗口白）：
      // 根底色对齐页面 #F5F5F5，消除胶囊下方全宽白带（像素实测 253 纯白 → 245 页面灰）
      .backgroundColor('#F5F5F5')
    }
  }
}
