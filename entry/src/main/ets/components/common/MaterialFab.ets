import { HdsTabs, hdsMaterial, BlurStrategy } from '@kit.UIDesignKit';
import { isImmersiveSupported, tabBarMaterial } from '../../utils/MaterialUtils';

/**
 * 沉浸光感 FAB 容器（邪修方案，同源 @tangs/components ImmersionButton 原理）：
 * uiMaterial/HDS 材质只在 Tabs 底部 Bar 区域对容器渲染，因此把 FAB 内容塞进一个
 * 单 Tab、无内容区的迷你 Tabs 的悬浮 Bar（tabBar Builder），让材质按 Bar 轮廓出光。
 *
 * 双分支（与 HomePage 底栏一致）：
 * - API 26+ 且支持沉浸光感：标准 Tabs.barFloatingStyle.systemMaterial（ArkUI 通道）
 * - 其余：HdsTabs.barFloatingStyle.systemMaterialEffect（HDS 通道，API 23+）
 *
 * 交互约定：点击统一走 onFabClick（接 Tabs.onTabBarClick，Bar 内容上的 onClick 可能被
 * Bar 的切 Tab 手势吞掉）；长按手势挂在 Bar 内容上（@BuilderParam 由调用方自带）。
 */
@Component
export struct MaterialFab {
  /** FAB 内容（圆形按钮内的 glyph/按钮本体），由调用方 @Builder 提供 */
  @BuilderParam fabContent: () => void = this.defaultFabContent
  /** 点击回调（接 Tabs.onTabBarClick；单 Tab 切换为 no-op，仅作点击事件用） */
  onFabClick: () => void = () => {}
  /** FAB 直径（Bar 高度=直径，悬浮圆角=半高即正圆） */
  diameter: number = 52
  /** HDS 分支材质等级（EXQUISITE/SMOOTH/ADAPTIVE，由调用方探测后传入） */
  materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE
  private useImmersive: boolean = false

  aboutToAppear() {
    this.useImmersive = isImmersiveSupported()
  }

  @Builder
  defaultFabContent() {
  }

  @Builder
  BarContent() {
    // 不套固定尺寸容器：让 bar item 自然包裹内容并与材质球同心
    // （固定 52vp 容器会被 item 约束（宽~30vp/高~48vp）压到底对齐，内容偏移球心）
    this.fabContent()
  }

  build() {
    if (this.useImmersive) {
      // API 26+ 通道：barFloatingStyle 为 API 26+ 属性，只允许出现在本分支
      Tabs({ barPosition: BarPosition.End }) {
        TabContent() {
          Column()
            .width(1)
            .height(1)
        }
        .tabBar(this.BarContent())
        .backgroundColor(Color.Transparent)
      }
      .barOverlap(true)
      .vertical(false)
      // Scrollable 模式 Bar 条带收缩包裹内容（Fixed 有最小胶囊宽 ~96vp，会露出条带）
      .barMode(BarMode.Scrollable)
      .barHeight(this.diameter)
      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(BlurStyle.NONE)
      .barFloatingStyle({
        barBottomMargin: 0,
        barSideMargin: 0,
        // alpha=01 近全透（Color.Transparent 在部分版本回退默认蒙层=球外方块的来源之一）
        maskColor: '#01000000',
        systemMaterial: tabBarMaterial()
      })
      .onTabBarClick(() => {
        this.onFabClick()
      })
      .width(this.diameter)
      .height(this.diameter)
      .backgroundColor(Color.Transparent)
      // 实验：圆形裁剪，验证球外方形残影是否为 Tabs 节点自身渲染（阴影在裁剪外则无效）
      .clip(true)
      .borderRadius(this.diameter / 2)
    } else {
      HdsTabs({ barPosition: BarPosition.End }) {
        TabContent() {
          Column()
            .width(1)
            .height(1)
        }
        .tabBar(this.BarContent())
      }
      .barOverlap(true)
      .vertical(false)
      .barHeight(this.diameter)
      // 同 HomePage：关掉 HDS 自适应模糊策略与 Bar 背板，只留悬浮材质
      .blurStrategy(BlurStrategy.DISABLE)
      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(BlurStyle.NONE)
      .barFloatingStyle({
        barBottomMargin: 0,
        barSideMargin: 0,
        gradientMask: { maskColor: '#01F1F3F5', maskHeight: 1 },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: this.materialLevel
        }
      })
      .onTabBarClick(() => {
        this.onFabClick()
      })
      .width(this.diameter)
      .height(this.diameter)
    }
  }
}
