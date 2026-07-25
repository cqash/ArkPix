# Implementation Plan: ZoomableImage 手势修复

**Input**: Feature specification from `spec/zoomable-image-gesture-fix/spec.md`

## Summary

修复 ZoomableImage 组件手势失效问题：PanGesture distance 参数不响应 @State 变化（需改用 PanGestureOptions.setDistance()），以及 .gesture() 优先级低于 Swiper 内置手势导致被吞噬（需改用 .priorityGesture()）。改动仅涉及 2 个文件。

## Technical Context

**Language/Version**: ArkTS (API 12+ / SDK 6.1.0(23))  
**Primary Dependencies**: @kit.ArkUI (PanGestureOptions, GestureGroup, Swiper)  
**State Management**: V1（@State/@Prop/@StorageLink，延续现有模式）  
**Storage**: N/A  
**Testing**: @ohos/hypium，真机手势验证  
**Target Platform**: HarmonyOS 5.0+  
**Project Type**: Mobile app  
**Performance Goals**: 手势跟手无延迟（< 1 帧延迟）  
**Constraints**: 仅修改 ZoomableImage.ets 和 ImageViewerPage.ets，不新增文件  
**Scale/Scope**: 2 文件修改，5 个用户故事

## Project Structure

### Documentation (this feature)

```text
spec/zoomable-image-gesture-fix/
├── spec.md              # 需求规格
├── plan.md              # 本文件
└── tasks.md             # 任务拆分
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── components/viewer/
│   └── ZoomableImage.ets    # [修改] PanGestureOptions + .priorityGesture()
└── pages/detail/
    └── ImageViewerPage.ets  # [修改] 适配 onZoomChange 契约（无变化，确认兼容）
```

**Structure Decision**: 遵循现有项目架构（pages/components/stores 分层），不新增目录或文件。本次修复是纯 Bug Fix，只改 2 个现有文件。

## Research & Decisions

### RD-001: PanGesture distance 动态化机制

**Decision**: 使用 `PanGestureOptions` 对象 + `setDistance()` 方法动态更新 distance

**Rationale**: 
- PanGesture 构造函数的 `distance` 参数是快照式读取，不响应 @State 变化
- 官方文档明确说明："通过 PanGestureOptions 对象接口可以动态修改滑动手势的属性，从而避免通过状态变量修改属性（状态变量修改会导致 UI 刷新）"
- `PanGestureOptions.setDistance(value: number)` 在 API 11+ 可用，项目 API 12+ 满足要求
- 在 PinchGesture.onActionEnd 和 TapGesture.onAction 中，修改 scaleValue 后同步调用 `panOptions.setDistance(scale > 1 ? 3 : 50)`

**Alternatives considered**:
- 用 @State 变量直接传给 PanGesture 构造参数 → 不可行，distance 参数不响应状态变化
- 重建 PanGesture 对象 → 不可行，GestureGroup 内部手势对象在挂载后不可替换
- 在 PanGesture.onActionStart 中判断 scale 并手动忽略 → 可行但用户体验差，手势已触发后延迟判断会卡顿

### RD-002: 手势绑定优先级

**Decision**: 将 `.gesture()` 改为 `.priorityGesture()`

**Rationale**:
- `.gesture()` 是默认优先级，与父组件 Swiper 内置 PanGesture 竞争时处于劣势
- Swiper 的内置手势优先消费单指左右滑动事件，子组件的 PanGesture 被吞掉
- `.priorityGesture()` 让当前组件的手势优先识别，仅在当前组件手势未识别时才传递给父组件
- 配合 PanGesture distance=50vp（scale=1 时），PanGesture 不触发（需要滑动 50vp），Swiper 内置手势正常消费左右滑动翻页
- scale>1 时 PanGesture distance=3vp 优先触发，Swiper.disableSwipe=true 禁止翻页

**Alternatives considered**:
- `.parallelGesture()` → 并行触发会导致 Swiper 翻页和图片平移同时发生，体验混乱
- 在 Swiper 层面拦截手势 → 过于侵入，需改动 Swiper 组件内部逻辑

### RD-003: GestureGroup 模式选择

**Decision**: 维持 `GestureGroup(GestureMode.Parallel, PinchGesture, PanGesture, TapGesture)` 不变

**Rationale**: 
- Parallel 模式允许三个手势同时参与竞争，各手势独立识别
- PinchGesture（2 指）和 PanGesture（1 指）天然不冲突
- TapGesture（双击 2 指）和 PanGesture（1 指拖动）也不冲突
- 与当前设计一致，只需修复 distance 和优先级问题

### RD-004: onZoomChange 契约

**Decision**: 维持现有 onZoomChange(isZoomed: boolean) 契约不变

**Rationale**: 
- ImageViewerPage 中 Swiper.disableSwipe 已绑定 isZoomed
- PinchGesture/TapGesture 中通过 applyScale() → onZoomChange() 更新状态
- PanGesture 边界释放时 onZoomChange(false) / 松手恢复 onZoomChange(true) 逻辑正确
- 不需要改 ImageViewerPage 的契约，只需修复 ZoomableImage 内部实现

## Data Model

无新增数据模型。ZoomableImage 现有状态：

| 字段 | 类型 | 用途 | 变化 |
|------|------|------|------|
| scaleValue | @State number | 当前缩放比 | 不变 |
| offsetX/offsetY | @State number | 平移偏移 | 不变 |
| panOptions | PanGestureOptions | PanGesture 动态配置 | **新增** |
| baseScale | private number | Pinch 起始缩放 | 不变 |
| panStartX/panStartY | private number | Pan 起始偏移 | 不变 |
| releasedAtEdge | private boolean | 边界释放标记 | 不变 |

## Contracts & Interfaces

### ZoomableImage 对外契约（不变）

| 属性/回调 | 类型 | 说明 |
|-----------|------|------|
| url | @Prop string | 图片 URL |
| maxScale | number | 最大缩放比（默认 5） |
| onZoomChange | (isZoomed: boolean) => void | 缩放状态变更通知 |

### ImageViewerPage 交互契约（不变）

| 绑定 | 说明 |
|------|------|
| Swiper.disableSwipe = isZoomed | 放大时禁用翻页 |
| ZoomableImage.onZoomChange → isZoomed | 缩放状态同步 |

### 内部变更点（仅 ZoomableImage.ets）

1. 新增 `private panOptions: PanGestureOptions = new PanGestureOptions({ fingers: 1, distance: 50 })`
2. `PanGesture(this.panOptions)` 替代 `PanGesture({ fingers: 1, distance: this.scaleValue > 1 ? 3 : 50 })`
3. 在 applyScale() 末尾调用 `this.panOptions.setDistance(this.scaleValue > 1 ? 3 : 50)`
4. `.gesture(GestureGroup(...))` 改为 `.priorityGesture(GestureGroup(...))`
