# 沉浸光感（API 26+）

> 从 AGENTS.md 拆分。改动材质/沉浸光感相关代码时阅读并同步更新本文档。

- **应用级开关**：module.json5 module 节点 metadata `{ "name": "ohos.arkui.UIMaterial.state", "value": "enable" }`（ENABLE 模式，Toast/Dialog/菜单控制/Select/Toggle 等系统组件在 API 26+ 默认材质化）；排查结论：项目未使用 Select/Chip/Slider/SegmentButton，Toggle/TextPickerDialog/AlertDialog/ContextMenu/Toast 均为标准默认材质化场景，无组件需 `Material.empty` 单独关闭
- **生效区域红线（官方约束，已踩坑）**：uiMaterial 的 `systemMaterial` 对普通容器组件**仅在两处区域生效**——Navigation/NavDestination 标题栏、横向 Tabs 且 barPosition=End 的底部 TabBar；**其余区域（详情页 FAB、顶栏 ‹/⋮ 药丸、查看器底栏）直挂容器后完全不渲染（材质透明）**，曾致收藏 FAB 圆圈隐形。绕行方案：MaterialFab 邪修（见下），详情页双 FAB 已上玻璃球；顶栏药丸/查看器底栏维持 rgba 半透明样式
- **唯一入口 `utils/MaterialUtils.ets`**：`isImmersiveSupported()` = `deviceInfo.sdkApiVersion >= 26` 版本短路 + `import lazy { uiMaterial } from '@kit.ArkUI'`（防 API 23~25 模块求值崩溃，参照 EntryAbility lazy import 模式）+ `uiMaterial.isImmersiveMaterialSupported()`，结果模块级缓存；唯一材质工厂 `tabBarMaterial()`（`new uiMaterial.ImmersiveMaterial({})` 官方默认参数，折射/高光/边缘光效/深浅色自适应全由系统接管，应用侧不调参），**uiMaterial 仅允许在 MaterialUtils 内 import，组件不得直接引用**
- **首页底栏胶囊双分支（HomePage，`useImmersiveTabs` 在 aboutToAppear 一次性定值）**：
  - API 26+ 支持端：**标准 Tabs** + `barFloatingStyle({ barBottomMargin: 12, barSideMargin: 24, maskColor: Color.Transparent, systemMaterial: tabBarMaterial() })`（ArkUI 通道，`FloatingTabBarStyle` 全系 API 26+ 属性，严禁出现在低版本分支）——模拟器上即可见磨砂模糊+边缘光晕（底部 TabBar 是生效区域，模拟器也渲染）；`barSideMargin: 24` 对齐原 HDS 胶囊宽度，`maskColor: Color.Transparent` 去默认背板蒙层
  - 低版本端：HdsTabs + `barFloatingStyle.systemMaterialEffect`（HDS 通道，API 23+ 磨砂，`materialType: ADAPTIVE` + `materialLevel` 按 `hdsMaterial.getSystemMaterialTypes()` 探测——支持 IMMERSIVE→EXQUISITE，否则 SMOOTH，官方 FAQ 路径）+ `gradientMask: { maskColor: '#01F1F3F5', maskHeight: 1 }` 去背板蒙层 + `blurStrategy(DISABLE)` 去滚动触发条带磨砂
  - 两分支共享 @Builder `TabContents()`（五个 TabContent）与 TabBuilder；控制器分类型（TabsController/HdsTabsController），`changeTab()` 统一分发；barOverlap(true)/onChange 接续登记/根底色 #F5F5F5 两分支一致
- **模拟器材质渲染差异**：API 26 模拟器上底部 TabBar 区域的 ImmersiveMaterial 正常渲染（磨砂+边缘光晕实测可见）；生效区域之外的容器材质完全不渲染（见上"生效区域红线"）；HDS 通道（hdsMaterial，API 23+）在模拟器上正常渲染磨砂模糊
- **任意组件沉浸光感邪修（`components/common/MaterialFab.ets`，详情页双 FAB 已用）**：既然材质只在 Tabs 底部 Bar 渲染，就把目标内容塞进一个**单 Tab、无内容区的迷你 Tabs**（宽=高=球直径，TabContent 放 1×1 占位），内容经 `tabBar` Builder 放进悬浮 Bar，材质按 Bar 轮廓出玻璃球。API 26+ 走标准 Tabs `barFloatingStyle.systemMaterial: tabBarMaterial()`，低版本走 HdsTabs `systemMaterialEffect`（与首页底栏同双分支）。要点：
  - `barMode(BarMode.Scrollable)`——Fixed 有最小胶囊宽 ~96vp 会露出条带；`maskColor: '#01000000'` 近全透（`Color.Transparent` 在部分版本回退默认蒙层，是"球外方块"来源之一）
  - 迷你 Tabs 必须 `.clip(true).borderRadius(直径/2)`——否则 Bar 轨道方形阴影残留在球外
  - Bar item 内容区被钳制（宽 ~30vp/高 ~48vp）且底对齐：内容**不要套固定尺寸容器**，直接放 glyph 才能与材质球同心
  - 点击统一走 `onTabBarClick`（Bar 内容上的 onClick 可能被切 Tab 手势吞掉）；长按手势挂 Bar 内容，长按抬起可能被识别为 Bar 点击→用时间戳 500ms 内抑制误触（见 IllustDetailPane `bookmarkLongPressAt`）
- **SaveButton 安全控件透底（已实测 + 官方文档证实）**：背景 alpha <0x1a 会被系统**强制调整为 0xff 不透明**（防用户在不知情下触发授权），故 `Color.Transparent`→黑盘、`'#00FFFFFF'`→白盘、省略→系统默认蓝盘；可用下限是 `'#1AFFFFFF'`（10% 白纱，基本不可见，授权链路不受影响：SUCCESS 正常、静默保存正常）。图标用 `SaveIconStyle.LINES` 线条风（`FULL_FILLED` 是实心圆盘图标）
- **quickfix 坑（已踩）**：`devecocli run --apply` 对 MaterialFab.ets 这类新组件/Bar 结构改动**静默不生效**（界面全是旧代码假象），改这些文件后必须全量 `devecocli run`
