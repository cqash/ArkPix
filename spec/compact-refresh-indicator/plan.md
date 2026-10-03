# Implementation Plan: 下拉刷新指示改为顶部小条

**Input**: Feature specification from `spec/compact-refresh-indicator/spec.md`

## Summary

改造 IllustWaterfall 的 Refresh 用法：通过「自定义刷新区域内容（builder）+ 子组件 position 固定」的官方机制，使下拉过程中瀑布流内容不跟随手势位移；刷新指示改为顶部悬浮小药丸（环形进度/小菊花，≤64vp），所有使用该组件的页面零改动统一生效。

## Technical Context

**Language/Version**: ArkTS（strict mode），HarmonyOS Stage 模型（target 26.0.0，compatible 6.1.0(23)）  
**Primary Dependencies**: ArkUI `Refresh` 容器组件（API 8+，所用 builder/refreshOffset/pullDownRatio/onOffsetChange/onStateChange 均为 API 12- 既有能力；`maxPullDownDistance` 为 API 20+，兼容基线 23 满足）  
**State Management**: 沿用 State Management V1（@State）  
**Storage**: N/A  
**Testing**: 构建验证 + 模拟器 UI 验证（下拉手势截图）  
**Target Platform**: HarmonyOS phone/2in1  
**Project Type**: 既有单模块应用的增量 UI 改造  
**Performance Goals**: 下拉/刷新过程无新增渲染负担（指示为单个小组件，state 驱动显隐）  
**Constraints**: 只改 IllustWaterfall 一个文件；页面调用方零改动；触底分页/回顶/错误重试零回归  
**Scale/Scope**: 1 个文件，约 40 行改动

## Project Structure

### Documentation (this feature)

```text
spec/compact-refresh-indicator/
├── spec.md
├── plan.md              # This file
└── tasks.md
```

### Source Code (repository root)

```text
D:\work\pixiv-\entry\src\main\ets\components\illust\
└── IllustWaterfall.ets    # [改] Refresh 用法：builder 自定义小指示 + 子组件 position 固定 + 状态/偏移跟踪
```

**Structure Decision**: 遵循既有项目架构，不引入新文件/MVVM。改动收敛在 IllustWaterfall 内部（刷新容器封装层），符合 FR-004「页面调用方零修改」——所有瀑布流页面经此单点统一生效。

## Complexity Tracking

无（无违反项）。

## Research & Decisions

### R1: 内容不跟随手势下移的实现机制

- **Decision**: 采用 Refresh 的自定义刷新区域（`builder` 参数）+ 瀑布流子组件设置 `.position({ x: 0, y: 0 })`。
- **Rationale**: 官方 Refresh 文档明确——未设 builder 时子组件靠 translate 跟手下移（当前现状）；设置 builder/refreshingContent 后改为相对位置位移，且**子组件设置 position 即固定不动**。这是官方支持的「内容不动」路径，无需自研手势。
- **Alternatives considered**: ① `pullDownRatio(0)`——官方语义是「不跟手=禁用下拉刷新」，会把手势一并杀掉，违背 FR-002；② 移除 Refresh 自研 PanGesture 下拉——与 WaterFlow 滚动手势冲突处理复杂、嵌套滚动边界（不满一屏）需自行兜底，风险远高于官方机制。

### R2: 刷新指示的形态与状态驱动

- **Decision**: builder 内容为顶部居中小药丸——半透明白底圆角容器（约 48vp）内嵌 `Progress` 环形（`ProgressType.Ring`，约 32vp）：下拉中（Drag/OverDrag）显示为进度环（value=当前下拉偏移，total=refreshOffset），进入刷新中（Refresh）切换为 `ProgressStatus.LOADING` 旋转菊花；`onStateChange` 跟踪 RefreshStatus、`onOffsetChange` 跟踪偏移量，Inactive/Done 状态隐藏。模式参照官方 Refresh 文档示例 6 的 refreshBuilder。
- **Rationale**: 进度环→菊花的转换是官方示例的标准模式，下拉过程有即时反馈、刷新中有明确指示，且整体高度 ≤64vp 满足 SC-002；builder 内容带 clip + constraintSize(minHeight) 防高度塌缩（官方建议）。
- **Alternatives considered**: ① 仅用 LoadingProgress 常显——下拉过程无进度反馈；② `refreshingContent`（ComponentContent，API 12+ 推荐）——可避免 builder 销毁重建导致的动画中断，但需引入 ComponentContent/UIContext/wrapBuilder 样板；LoadingProgress 动画中断重建对用户无感知，builder 足够；③ promptText 纯文本——无法满足「小条指示」的图形化期望。

### R3: 触发阈值与下拉距离参数

- **Decision**: `refreshOffset(64)`（触发阈值与现状一致）；`maxPullDownDistance(96)`（限制最大下拉，避免顶部露出过大空白区）；`pullDownRatio` 不设置（保持系统动态阻尼手感）；废弃参数 `offset`/`friction`（API 11 起 deprecated）一并移除。`pullToRefresh(true)` 显式声明。
- **Rationale**: 触发手感维持现状（SC-003）；子组件固定后下拉露出的只有刷新区域本身，必须封顶防空白。
- **Alternatives considered**: maxPullDownDistance 不设——大力下拉会出现过大指示区空白，观感差。

### R4: 刷新数据逻辑与兼容边界

- **Decision**: `onRefreshing` 回调、`isRefreshing` 双向绑定、`refresh()` 数据流程、`enableRefresh=false` 旁路、触底 loadMore、scrollTopToken 回顶等全部保持不变；Refresh 嵌套 WaterFlow 的嵌套滚动行为不变（官方 API 12+ 支持与垂直滚动组件联动）。
- **Rationale**: FR-005 零回归要求，改动严格限定在「呈现层」。
- **Alternatives considered**: 无。

## Data Model

无新增持久化数据。组件内新增两个呈现层状态：

- **refreshState: RefreshStatus** — onStateChange 同步，驱动指示显隐与进度环/菊花形态切换。
- **refreshPullOffset: number** — onOffsetChange 同步（vp），驱动下拉中的环形进度值。

## Contracts & Interfaces

内部组件改动，无对外契约变更：

- `IllustWaterfall` 的全部对外入参（fetchFirst/reloadToken/compareFn/scrollTopToken/enableRefresh/onStarLongPress 等）签名与语义不变，页面调用方零改动（FR-004）。
- 新增私有 @Builder 刷新指示构建器与两个 @State 字段（见 Data Model），均为组件内部实现细节。
