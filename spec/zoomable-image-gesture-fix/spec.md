# Feature Specification: ZoomableImage 手势修复

**Created**: 2026-07-26  
**Status**: Draft  
**Input**: 用户反馈：大图模式（ImageViewerPage）中图片不能缩放，也不能滑动到下一张图

## Overview

修复全屏图片查看器中 ZoomableImage 组件的手势失效问题。当前 PinchGesture 双指缩放、PanGesture 单指拖动、TapGesture 双击缩放以及 Swiper 左右翻页均无法正常工作，根本原因是 PanGesture distance 参数不响应状态变化（快照式读取）以及手势绑定优先级低于 Swiper 内置手势导致被吞噬。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 双指缩放放大图片 (Priority: P1)

用户在全屏查看器中对图片做双指捏合/拉开手势，图片跟随手指实时缩放，缩放中心稳定不漂移，松手后缩放值在 1~5 范围内保持。

**Why this priority**: 缩放是查看器核心功能，不可用则查看器基本失效

**Independent Test**: 打开任意多页插画详情 → 点击图片进入查看器 → 双指拉开放大 → 预期图片跟随放大

**Acceptance Scenarios**:

1. **Given** 查看器显示原始尺寸图片，**When** 用户双指拉开，**Then** 图片跟随双指中心实时放大
2. **Given** 图片已放大到 2.5 倍，**When** 用户双指捏合缩小，**Then** 图片跟随缩小，最低不低于 1 倍
3. **Given** 图片放大到超过 5 倍，**When** 松手，**Then** 缩放值自动钳制回 5 倍
4. **Given** 图片缩小到接近 1 倍，**When** 松手，**Then** 缩放值自动回弹到 1 倍并重置偏移

---

### User Story 2 - 放大后单指拖动平移图片 (Priority: P1)

用户放大图片后，单指拖动可跟手平移图片查看不同区域，到达边界后图片被钳制不出现黑边。

**Why this priority**: 放大后平移是缩放的配套操作，缺一则放大无意义

**Independent Test**: 打开查看器 → 双指放大图片 → 单指拖动 → 预期图片跟手平移

**Acceptance Scenarios**:

1. **Given** 图片已放大（scale>1），**When** 用户单指拖动，**Then** 图片立即跟手平移（触发距离 ≤ 3vp）
2. **Given** 图片已放大且拖动到 X 向边界，**When** 继续向外拖，**Then** 偏移被钳制在边界，不出现黑边
3. **Given** 图片已放大且拖动到 Y 向边界，**When** 继续向外拖，**Then** 偏移被钳制在边界，不出现黑边
4. **Given** 图片缩放回 1 倍，**When** 单指拖动，**Then** 图片不跟随移动（平移被禁止）

---

### User Story 3 - 未放大时 Swiper 左右翻页 (Priority: P1)

图片未放大时，单指左右滑动可以切换到上一张/下一张图，Swiper 翻页手势不被 ZoomableImage 的 PanGesture 吞掉。

**Why this priority**: 多页查看的翻页是基本导航，与缩放同等重要

**Independent Test**: 打开多页插画查看器 → 在原始尺寸下左右滑动 → 预期翻到下一页

**Acceptance Scenarios**:

1. **Given** 图片未放大（scale=1），**When** 用户单指向左/右滑动，**Then** Swiper 翻到下一页/上一页
2. **Given** 图片未放大，**When** 用户轻微拖动（< 50vp），**Then** ZoomableImage 的 PanGesture 不触发，不干扰 Swiper 翻页
3. **Given** 图片已放大，**When** Swiper.disableSwipe 生效，**Then** 左右滑动不会触发翻页，而是平移图片

---

### User Story 4 - 双击切换缩放 (Priority: P2)

用户双击图片可在 1 倍和 2.5 倍之间切换，切换后 PanGesture 的 distance 参数同步更新。

**Why this priority**: 快捷缩放是效率增强，非核心路径但影响体验

**Independent Test**: 打开查看器 → 双击图片 → 预期放大到 2.5 倍 → 再双击 → 回到 1 倍

**Acceptance Scenarios**:

1. **Given** 图片在 1 倍，**When** 双击，**Then** 图片放大到 2.5 倍，且后续单指拖动可跟手平移
2. **Given** 图片已放大（>1 倍），**When** 双击，**Then** 图片缩回 1 倍，偏移重置，后续单指滑动变为 Swiper 翻页

---

### User Story 5 - 放大后到达 X 边界释放回 Swiper (Priority: P3)

放大后单指向左/右拖到边界并继续外拖时，临时释放回 Swiper 让其接管翻页手势，松手后恢复放大状态的 disableSwipe。

**Why this priority**: 边界释放是高级交互，提升流畅度但不影响基本功能

**Independent Test**: 打开查看器 → 放大图片 → 拖到右边界继续向右拖 → 预期 Swiper 接管翻到下一页

**Acceptance Scenarios**:

1. **Given** 图片已放大且拖到 X 向右边界，**When** 继续向右拖超过边界，**Then** onZoomChange(false) 被调用，Swiper 可接管翻页
2. **Given** 已释放到 Swiper 后用户松手，**Then** onZoomChange 恢复为 true（如 scale>1），Swiper 重新禁用翻页

### Edge Cases

- 图片加载失败时点击重试，加载成功后手势应正常工作
- 单页插画（无 Swiper 翻页需求）时手势不受 Swiper 影响
- 极端缩放（1.05 倍附近）不应出现闪烁（scale 在 1 和 1.05 间反复弹跳）
- 放大后旋转设备，边界钳制应基于新屏幕尺寸重新计算

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: PanGesture 的 distance 参数必须动态响应缩放状态变化（scale=1 → 50vp，scale>1 → 3vp），使用 PanGestureOptions.setDistance() 机制
- **FR-002**: ZoomableImage 的手势绑定必须使用 .priorityGesture() 而非 .gesture()，确保子组件手势优先于 Swiper 内置手势
- **FR-003**: PinchGesture/TapGesture 每次修改 scaleValue 后，必须同步调用 panOptions.setDistance() 更新 PanGesture 触发阈值
- **FR-004**: Swiper.disableSwipe 必须与 isZoomed 状态实时同步，放大时禁用翻页，缩回时恢复翻页
- **FR-005**: 图片缩放限幅 1~5 倍，边界钳制偏移量不出现黑边，接近 1 倍（< 1.05）时自动回弹

### Key Entities

- **ZoomableImage**: 可缩放图片组件，持有 scaleValue/offsetX/offsetY 状态和 PanGestureOptions 实例
- **ImageViewerPage**: 查看器页面，持有 Swiper 容器和 isZoomed 状态，管理 disableSwipe

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 用户在查看器中双指缩放，图片 100% 跟随手指实时变化，无延迟或无响应
- **SC-002**: 放大后单指拖动，图片在 3vp 触发距离内跟手平移，无 Swiper 翻页干扰
- **SC-003**: 未放大时单指左右滑动，Swiper 正常翻页，ZoomableImage 的 PanGesture 不干扰
- **SC-004**: 双击切换缩放后，后续手势行为（平移/翻页）立即适配新的缩放状态

## Assumptions

- 当前 Image.scale() + Image.translate() 变换方案不变（不迁移到 matrix4）
- PanGestureOptions.setDistance() 在 API 12+ 可靠工作
- .priorityGesture() 在 Swiper 子组件上能正确让子组件手势优先于 Swiper 内置手势
- 项目继续使用 State Management V1（@State/@Prop/@StorageLink）

## Open Questions

- 无（根因和修复方案已明确）
