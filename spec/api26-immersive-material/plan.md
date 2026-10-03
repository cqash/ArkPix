# Implementation Plan: API 26 升级与沉浸光感适配

**Input**: Feature specification from `spec/api26-immersive-material/spec.md`

## Summary

将项目 target/compile SDK 升级到 6.2.0(API 26)（compatible 保持 6.1.0(23)），在 module.json5 配置应用级沉浸光感开关（ENABLE），并新增一个运行时能力判定工具（MaterialUtils），对图片查看器底栏、详情页顶栏药丸按钮、详情页收藏 FAB 应用组件级沉浸式材质；所有材质调用经 `sdkApiVersion >= 26 && isImmersiveMaterialSupported()` 门控，低版本设备走既有样式分支，零回归。

## Technical Context

**Language/Version**: ArkTS（strict mode），HarmonyOS Stage 模型  
**Primary Dependencies**: `@kit.ArkUI`（`uiMaterial` 模块，API 26.0.0 起）、`@kit.BasicServicesKit`（`deviceInfo.sdkApiVersion`）  
**State Management**: 沿用项目现有 State Management V1（@State/@StorageLink/AppStorage），不迁移  
**Storage**: N/A（无持久化变更；module.json5 metadata 为声明式配置）  
**Testing**: 构建验证（build_project）+ 真机 UI 验证（start_app + verify）  
**Target Platform**: HarmonyOS，compile/target 6.2.0(26)，compatible 6.1.0(23)，phone + 2in1  
**Project Type**: 既有 HarmonyOS 单模块应用（entry）的增量适配  
**Performance Goals**: 材质仅用于 3 处局部浮动组件，不引入可感知掉帧；遵循官方性能约束（不叠模糊/阴影、不嵌套材质、不在列表项/动态内容上使用）  
**Constraints**: API 23~25 设备 0 崩溃 0 样式异常；SaveButton 安全控件不改变其既有属性用法；ArkTS 严格模式（禁 any/as/动态访问）  
**Scale/Scope**: 3 个配置文件/组件文件改动 + 1 个新增工具文件

## Project Structure

### Documentation (this feature)

```text
spec/api26-immersive-material/
├── spec.md
├── plan.md              # This file
└── tasks.md
```

### Source Code (repository root)

```text
D:\work\pixiv-\
├── build-profile.json5                              # [改] compileSdkVersion/targetSdkVersion → 6.2.0(26)
└── entry/src/main/
    ├── module.json5                                 # [改] metadata 增加 ohos.arkui.UIMaterial.state=enable
    └── ets/
        ├── utils/
        │   └── MaterialUtils.ets                    # [新增] 沉浸光感运行时判定 + 材质工厂
        ├── pages/detail/
        │   └── ImageViewerPage.ets                  # [改] 底部图标栏应用超薄材质（低版本保留 rgba(0,0,0,0.25)）
        └── components/detail/
            └── IllustDetailPane.ets                 # [改] 顶栏药丸按钮 + 收藏 FAB 应用材质（低版本保留现状）
```

**Structure Decision**: 遵循既有项目架构（pages/components/utils/stores 分层），不引入 MVVM 迁移。新增仅 1 个工具文件（MaterialUtils），符合增量适配的最小文件集原则；材质参数集中定义于工具文件，避免各页面散落硬编码。

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 下载 FAB（SaveButton 安全控件）不直接应用材质 | 安全控件属性受系统限制（AGENTS.md 既有约束：勿深度自定义/勿换普通按钮），`systemMaterial` 对安全控件生效无官方保证，强行设置有交互/授权失效风险 | 对包裹容器设置材质会造成材质嵌套与视觉重复，官方明确禁止材质层叠 |

## Research & Decisions

### R1: 运行时能力判定方式

- **Decision**: 双条件门控——`deviceInfo.sdkApiVersion >= 26`（`@kit.BasicServicesKit`）为前置短路，通过后才调 `uiMaterial.isImmersiveMaterialSupported()`；结果缓存为模块级/单例级常量，运行期不变。
- **Rationale**: `isImmersiveMaterialSupported` 本身是 API 26 接口，低版本系统上直接调用会失败，必须先用版本号短路；官方示例 5 亦推荐用支持判定做同一代码双路径适配。
- **Alternatives considered**: ① `canIUse(syscap)`——syscap 粒度是 `SystemCapability.ArkUI.ArkUI.Full`，无法区分 26 新增接口，不可用；② `deviceInfo.apiAvailable('26.0.0')`——该接口面向 7.0 点分版本号场景，对 6.2.0(26) 直接用 `sdkApiVersion >= 26` 更直观。

### R2: uiMaterial 模块的导入方式

- **Decision**: MaterialUtils 内使用 `import lazy { uiMaterial } from '@kit.ArkUI'`（API 12+ 惰性加载），且首次访问发生在版本门控通过之后。
- **Rationale**: compatible=23 的应用装在 API 23~25 设备上时，系统不存在 `uiMaterial` 模块；静态 import 会在模块求值期崩溃（与 EntryAbility 不得静态 import Store 单例模块的既有教训同类）。lazy import 首次访问才加载，配合版本短路可彻底规避。
- **Alternatives considered**: try/catch 包裹静态 import——ArkTS 不支持对 import 语句本身 try/catch；运行时动态 require 不符合 ArkTS 严格模式。

### R3: 组件级材质应用方式与降级路径

- **Decision**: 双分支渲染——`if (MaterialUtils.isSupported())` 分支走「透明背景 + `.systemMaterial(material)`」，else 分支走既有 `.backgroundColor(rgba...)` 样式；两分支共享内部内容 @Builder，避免交互逻辑重复。材质属性在同组件上后于其他样式属性设置。
- **Rationale**: 官方 FAQ 明确低版本系统调用高版本 UI 属性有闪退风险，推荐版本判断分支；共享 @Builder 保证单击/长按/手势等交互行为两分支完全一致（FR-005 零回归）。
- **Alternatives considered**: ① 单分支 `.systemMaterial(isSupported ? material : undefined)`——`systemMaterial` 属性本身为 API 26 新增，低版本运行时调用该属性方法仍有风险，官方 FAQ 不推荐裸调；② AttributeModifier 统一封装——对本特性 3 处落点而言引入 Modifier 类收益低，if/else 更直观可审。

### R4: 各落点的材质参数选型

- **Decision**:
  - 查看器底栏（ImageViewerPage 底部图标栏）：`ULTRA_THIN`，`interactive: false`（栏内按钮各自有点击反馈），`applyShadow` 默认；原 `rgba(0,0,0,0.25)` 底色仅保留在降级分支。图标白色 20~22vp 与 SVG 资源方案不变；如真机验证浅色图片下可读性不足，再开 `colorInvert: true`（预留参数位，默认不开——图标为 Image fillColor/SVG，反色覆盖有限）。
  - 详情页顶栏药丸按钮（‹ / ⋮）：`ULTRA_THIN` + `interactive: true`（按压弹性反馈），替代原 `rgba(0,0,0,0.4)` 药丸底色（降级分支保留）。
  - 详情页收藏 FAB：`THIN` + `interactive: true`；材质自带阴影（applyShadow 默认 true），**移除既有自定义 shadow**（FR-006 冲突约束）；下载 FAB 为 SaveButton 安全控件，不应用材质（见 Complexity Tracking），视觉上与收藏 FAB 的蓝底圆形并存可接受。
- **Rationale**: 官方样式指引——悬浮按钮/轻量提示用 ULTRA_THIN/THIN；FAB 属于强调性悬浮控件用 THIN 保证辨识度；查看器底栏需最大通透度故 ULTRA_THIN。
- **Alternatives considered**: 全部统一 ULTRA_THIN——FAB 辨识度不足；统一 THIN——底栏通透度损失。

### R5: 应用级开关与默认材质的兜底

- **Decision**: module.json5 metadata 配置 `ohos.arkui.UIMaterial.state = "enable"`（仅 entry 模块生效，本项目单模块满足）。ENABLE 后 Dialog/Toast/菜单控制/Select/Chip/SegmentButton/Slider/Toggle 等默认材质化；验证阶段逐一排查设置族页面的 Select/Picker 类组件，若默认材质不符合预期，用 `uiMaterial.Material.empty` 单独关闭（FR-008）。
- **Rationale**: ENABLE 是官方一键接入路径，Toast/菜单/AlertDialog 是本项目高频系统组件（toast 遍布各页、bindContextMenu 遍布详情页/历史页/设置页）。
- **Alternatives considered**: DEFAULT 模式——仅 Dialog/Toast/AlphabetIndexer/文本菜单默认开启，覆盖面小于需求预期。

### R6: SDK 版本字段与构建前提

- **Decision**: 根 `build-profile.json5` products.default：`compileSdkVersion` 显式新增为 `"6.2.0(26)"`（当前未显式声明，随默认值）、`targetSdkVersion` 改为 `"6.2.0(26)"`、`compatibleSdkVersion` 保持 `"6.1.0(23)"` 不变。实现前用户须已通过 DevEco Studio 安装 6.2.0(26) SDK，否则构建失败属预期阻塞，在 tasks/验证阶段先行检查。
- **Rationale**: 应用级开关官方要求 targetAPIVersion ≥ 26；compatible 保持 23 是用户已确认的决策。
- **Alternatives considered**: 同步提升 compatible 至 26——已被用户否决（放弃旧设备）。

### R7: 明确不适配的范围

- **Decision**: 不做——① HDS 组件（hdsMaterial/TitleBarStyleOptions/HdsTabsFloatingStyle，本项目无 HDS 导航与页签）；② WebView 登录页同层渲染场景（官方 FAQ：API 23 及以前同层渲染不支持沉浸光感，且登录页非视觉重点）；③ 滚动列表项、整页背景、动图/视频上方组件（官方性能红线）；④ 选页弹窗/EXIF Picker/合并审查等自定义覆盖层（本轮保持现状，后续可单独迭代）。
- **Rationale**: 控制在「重点组件」范围内（用户已确认），避免面积过大/嵌套/动态内容采样等性能陷阱。
- **Alternatives considered**: 全面组件级（含搜索框、设置卡片、底部面板）——用户已选择「应用级 + 重点组件」。

## Data Model

无新增持久化数据。唯一状态为运行时判定结果：

- **材质支持标记**: 布尔值，来源 = `sdkApiVersion >= 26 && uiMaterial.isImmersiveMaterialSupported()`，进程生命周期内不变，缓存于 MaterialUtils；不参与 AppStorage/偏好/同步域。
- **应用级开关状态**: module.json5 静态声明（enable），运行期可通过 `uiMaterial.getMaterialInfo()` 读取（仅排查问题时使用，不进入常设代码路径）。

## Contracts & Interfaces

### MaterialUtils（新增，`entry/src/main/ets/utils/MaterialUtils.ets`）

内部工具契约（ArkTS 严格模式，纯同步接口，无网络/无 IO）：

- `isImmersiveSupported(): boolean` — 双条件门控的缓存结果；任何材质调用前必须经此判定。
- `viewerBarMaterial(): uiMaterial.Material | undefined` — 查看器底栏材质（ULTRA_THIN）；不支持时返回 undefined。
- `pillButtonMaterial(): uiMaterial.Material | undefined` — 顶栏药丸按钮材质（ULTRA_THIN + interactive）。
- `fabMaterial(): uiMaterial.Material | undefined` — 收藏 FAB 材质（THIN + interactive）。

约束：
- `uiMaterial` 仅允许经 lazy import 在本文件内访问，其他文件不得直接 import uiMaterial（保证版本短路唯一入口）。
- 材质对象可缓存复用（官方要求材质参数稳定，禁止运行期频繁变更）。
- 返回 undefined 时调用方必须走既有样式分支，不得将 undefined 传入 `systemMaterial` 之外的用途。

### 组件接入契约

- **ImageViewerPage 底栏**: `if (isImmersiveSupported())` 分支 = 既有 Row 结构 + 透明底 + `.systemMaterial(viewerBarMaterial())`；else 分支 = 现状（`rgba(0,0,0,0.25)` 底）。两个分支复用同一内部 @Builder，保证复制/页码/返回/全屏/SaveButton/分享/HD 七项交互完全一致；底部安全区 padding 与 hitTestBehavior(Transparent) 两分支均保留。
- **IllustDetailPane 顶栏药丸**: 同上分叉策略；`router.back()` 与 `bindContextMenu` 六项菜单逻辑不进分支，共享。
- **IllustDetailPane 收藏 FAB**: 分叉策略同上；材质分支移除自定义 shadow（applyShadow 默认生效）；单击 toggleBookmark / 长按 BookmarkTagPanel / 可见性门控逻辑不变。下载 FAB（SaveButton）不改动。

### 构建配置契约

- `build-profile.json5`: `compileSdkVersion: "6.2.0(26)"`、`targetSdkVersion: "6.2.0(26)"`、`compatibleSdkVersion: "6.1.0(23)"`（不变）。
- `module.json5`: module 级 `metadata` 追加 `{ "name": "ohos.arkui.UIMaterial.state", "value": "enable" }`（与既有 abilities/extensionAbilities metadata 并存，互不影响）。
