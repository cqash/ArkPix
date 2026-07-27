# Implementation Plan: FAB 与下载增强（fab-download-enhancements）

**Input**: Feature specification from `spec/fab-download-enhancements/spec.md`

## Summary

五项改动：① PID/UID 直达回归——根因是直达入口被 `hasSearched` 门控永久隐藏（SearchPage 是常驻组件，提交过一次搜索后建议区永不渲染），将直达块移出门控；② FAB 视觉规范（空心轮廓心→红实心、蓝底白 ↓）+ 下载 FAB 单击改 `handleSaveAll()`、长按改缩略图选页弹窗（新增 `savePages(pageIndexes[])` 入口，顺手把 saveAll 的 ActionSheet 遗留迁移为 AlertDialog）；③ 下载服务加内存调度层实现多任务并发（新设置项 downloadConcurrency 1-5 默认 3，FIFO 排队，全部调用点改 fire-and-forget 入队）；④ 详情页统计区加发布日期（新 utils/DateUtils 纯函数，本地时区 yyyy-MM-dd HH:mm）；⑤ tag 跳转写搜索历史放在 TagSearchPage 加载处单点覆盖。

## Technical Context

**Language/Version**: ArkTS（strict mode），API 12+ / SDK 6.1.0(23)  
**Primary Dependencies**: `@kit.NetworkKit`、`@kit.ArkData`（relationalStore/preferences）、`@kit.ArkUI`  
**State Management**: 沿用 State Management V1  
**Storage**: pixiv.db download_tasks（复用已有 `pending` 状态值，无 schema 变更）；preferences 新增 `download_concurrency`  
**Testing**: `@ohos/hypium`（DateUtils/MergeSuggest 类纯函数单测）  
**Target Platform**: HarmonyOS 手机/平板  
**Project Type**: mobile-app  
**Performance Goals**: 并发下载上限可配 1-5；选页弹窗缩略图用 CachedImage 缓存  
**Constraints**: ArkTS 严格约束；弹窗约定（禁 ActionSheet——本轮顺带清掉 saveAll 的 showActionSheet 遗留）；不引入图片图标资源（用 Unicode 文本符号）  
**Scale/Scope**: 约 10 个修改文件 + 1-2 个新文件

## Project Structure

### Documentation (this feature)

```text
spec/fab-download-enhancements/
├── spec.md
└── plan.md              # 本文件
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/
│   ├── search/
│   │   ├── SearchPage.ets            # 修改：数字直达块移出 hasSearched 门控
│   │   └── TagSearchPage.ets         # 修改：aboutToAppear 写搜索历史（illust 类型）
│   ├── detail/
│   │   ├── IllustDetailPage.ets      # 修改：FAB 图标视觉（♡/❤/蓝底白↓）；下载 FAB 单击 handleSaveAll；
│   │   │                             #       长按改选页弹窗（内联覆盖层：缩略图网格多选/全选/确认取消）；
│   │   │                             #       InfoRow 统计区加发布日期行；exifPicker 续走状态扩展为页集合
│   │   └── ImageViewerPage.ets       # 修改：downloadToCache 调用点改入队模式
│   ├── settings/
│   │   ├── SettingsPage.ets          # 修改：下载组加"下载线程数"TextPickerDialog 项
│   │   └── DownloadPage.ets          # 修改：排队状态（pending）展示
│   └── ...
├── stores/
│   ├── IllustDetailStore.ets         # 修改：+savePages(pageIndexes[])（isDownloaded 过滤+AlertDialog 确认）；
│   │                               #       doSaveAll 重构复用 doSavePages；saveAll 的 showActionSheet 迁 AlertDialog；
│   │                               #       下载调用点改入队；汇总 toast 改"已加入 N 个下载任务"
│   └── UserSettingStore.ets          # 修改：downloadConcurrency 读写/防御拷贝/setter
├── services/
│   ├── DownloadService.ets           # 修改：enqueue 调度层（FIFO 队列+activeCount+上限读设置）；
│   │                               #       downloadToCache 转 private；applyToGallery 并入任务体；
│   │                               #       retryAllFailed/调用点全部走 enqueue
│   └── DatabaseService.ets           # 不改（download_tasks 的 pending 状态值已兼容）
├── models/
│   └── AppSettings.ets               # 修改：+downloadConcurrency: number = 3
├── components/illust/IllustCard.ets  # 修改：长按保存调用点改入队模式
└── utils/
    └── DateUtils.ets                 # 新增：formatCreateDate(iso): string（本地时区 yyyy-MM-dd HH:mm）
```

**Structure Decision**: 遵循现有架构，全部就地改造；新文件仅 DateUtils（纯函数，可单测）。选页弹窗复用项目内联覆盖层模式（同 EXIF Picker），不做独立组件文件。

## Complexity Tracking

无违规项。

## Research & Decisions

**Decision**: 直达回归修复 = 数字直达块移出 `if (!this.hasSearched)` 门控，放在输入框 Row 之下、建议区/结果区两分支共用位置  
**Rationale**: 根因是 `hasSearched` 一旦 true 永不复位（SearchPage 为 Home Tabs 常驻组件），门控内所有建议内容永久消失；移出后两种状态下都可见，且不打乱结果区  
**Alternatives considered**: 输入变化时重置 hasSearched=false（改变结果区停留语义，用户切回输入框看结果的习惯被破坏）

**Decision**: 收藏 FAB 未收藏态用空心轮廓心 `♡`（浅灰 `#999999`）、已收藏红实心 `❤`（#FF4081）、请求中灰色；下载 FAB 蓝底（#0096FA）白 `↓`  
**Rationale**: 用户要求"白色轮廓"——但 FAB 为白底圆，纯白图标不可见，浅灰轮廓在白底上呈现"空心未选中"视觉，已收藏红色实心形成明确对比；下载蓝底白箭头即用户指定样式  
**Alternatives considered**: 纯白轮廓（白底不可行）；引入 SVG/图片资源（约束不引入）

**Decision**: 下载 FAB 单击 = `handleSaveAll()`（多页）/ `handleSavePage(0)`（单页）；长按（仅多页）= 打开选页弹窗  
**Rationale**: handleSaveAll 前置流程（合并审查→EXIF Picker）天然复用；选页弹窗为新增内联覆盖层  
**Alternatives considered**: 单击保持保存当前页（用户明确否决）

**Decision**: 选页下载新入口 `IllustDetailStore.savePages(pageIndexes: number[])`：逐页 isDownloaded 过滤，有重复走 `showAlertDialog`（跳过已下载/仍要下载），确认后 `doSavePages(pageIndexes)`；`doSaveAll(skipPages)` 重构为复用 `doSavePages`；EXIF Picker 续走状态由 `exifPickerIsSaveAll: boolean` 扩展为 `exifPickerPendingPages: number[]`  
**Rationale**: 现有 doSaveAll 语义是"全部减跳过"，无法表达任意页集合；AlertDialog 与弹窗约定一致  
**Alternatives considered**: 继续用 skipPages 反向表达（选 2 页要算补集，语义绕）

**Decision**: 顺手将 `saveAll` 重复确认的 `showActionSheet` 迁移为 AlertDialog  
**Rationale**: AGENTS.md 标注已久的弹窗约定例外，本轮恰好重写保存路径，一次清账  
**Alternatives considered**: 保留（持续违反约定）

**Decision**: 并发调度 = DownloadService 加内存调度层：`enqueue(url, illust, pageIndex)` 公开入口（先写 DB `pending` 记录入 FIFO 队列；`activeCount < 当前上限` 立即执行否则排队；任务结束 activeCount-- 并补位）；上限每次任务启动时读 `userSettingStore.getSettings().downloadConcurrency`（防御拷贝保证新值）；`downloadToCache` 转 private；`applyToGallery` 并入任务体；5 个调用点（doSavePage/doSavePages/IllustCard/ImageViewerPage/DownloadPage 重试/retryAllFailed）全部改 fire-and-forget 入队；doSaveAll 汇总 toast 改"已加入 N 个下载任务"  
**Rationale**: 最小侵入，不动 HTTP 下载本体；DB `pending` 状态值表结构已兼容（启动重置规则已覆盖）；getSettings 每次新实例天然支持即时生效  
**Alternatives considered**: 全局信号量库（无此依赖）；持久化队列（spec 明确重启重置 failed，不做）；单文件 Range 分段（用户已否决）

**Decision**: 选页弹窗多选支持长按滑动连选（拖选）  
**Rationale**: 用户明确要求（对齐相册拖选体验）；页数多时逐格点击低效  
**Alternatives considered**: 仅单击逐格切换（保留为兜底交互，单击单格切换依然有效）  
**实现要点**: 缩略图网格容器绑 PanGesture，记录起始格索引与起始格的目标状态（选中↔未选切换方向），滑动中按触点坐标命中计算经过的格子索引，将起始格与经过格之间的连续区间（按网格行优先序）统一置为目标状态；单击手势保留单格切换；与 Grid 滚动手势冲突时以长按（≥300ms）激活拖选模式区分手势

**Decision**: 发布日期 = 新 `utils/DateUtils.ets` 纯函数 `formatCreateDate(iso: string): string`：`new Date(iso)` 解析（兼容 +09:00），手动 padStart 拼 `yyyy-MM-dd HH:mm`（本地时区），解析失败返回空串（UI 不显示该行）  
**Rationale**: 对齐 pixez 本地时区语义；ArkTS 无 intl 需手工 pad；纯函数可单测  
**Alternatives considered**: substring 截取（保留 +09:00 原时区，与 pixez 语义不符）

**Decision**: tag 跳转写搜索历史放在 `TagSearchPage.aboutToAppear`（`addSearchHistory(keyword, 'illust')`）  
**Rationale**: 入口有 3 处（详情页两个 TagChip 分支 + 历史页回放），加载处单点覆盖调用方零改动；回放重写历史只会刷新时间戳（既有先删后插去重），副作用可接受  
**Alternatives considered**: 详情页两个点击处分别写（遗漏未来入口）；路由参数加 fromHistory 跳过（增加契约复杂度，收益小）

## Data Model

**AppSettings 扩展**
- `downloadConcurrency: number = 3`（范围 1-5）；preferences key `download_concurrency`

**下载任务状态（扩展语义，无 schema 变更）**
- `pending`：已入队待调度（新增实际写入）；`downloading`：执行中；`completed/failed` 不变
- 启动重置规则已覆盖 pending（现有 SQL 将 downloading/pending → failed），无需迁移

**选页弹窗状态（页面内存态）**
- `pageSelectShown: boolean`、`pageSelectChecked: boolean[]`（按 pageCount 索引）
- 缩略图源：illust 各页 imageUrls（经 CachedImage，沿用图片头）

**发布日期**
- 源：`Illust.createDate`（ISO 8601 带时区）→ 展示 `yyyy-MM-dd HH:mm`（本地时区）

## Contracts & Interfaces

**DownloadService**
- `enqueue(imageUrl: string, illustId: number, pageIndex: number, meta: DownloadMeta): void`——fire-and-forget 入队（含 DB pending 记录）；内部调度执行
- `downloadToCache` 转 private；任务体 = 下载 + finalize + applyToGallery + 状态落库 + notifyTaskChanged + 补位
- `retryAllFailed` 内部改走 enqueue，分类计数语义保持（started=入队数）

**IllustDetailStore**
- `savePages(pageIndexes: number[]): Promise<void>`——重复检测 + AlertDialog 确认 + doSavePages
- `saveAll()`：重复确认改 AlertDialog（跳过已下载页=doSavePages(补集) / 全部重新下载=doSavePages(全集)）
- doSave 系列不再 await 下载结果（入队即返），汇总 toast 语义改为"已加入 N 个下载任务"

**IllustDetailPage 选页弹窗（内联覆盖层）**
- 状态：`pageSelectShown`、`pageSelectChecked: boolean[]`
- UI：半透明遮罩 + 底部弹层（缩略图网格 3-4 列，每格 CachedImage + 勾选角标 + 页码）；顶部"全选/清空"；底部"取消/确定下载(N)"
- 多选交互：单击单格切换选中；**长按（≥300ms 激活拖选）+ 滑动**按经过格区间连续批量选中/取消（起始格定方向）
- 可见性：弹窗打开时 FAB 隐藏（并入现有可见性条件）
- 确认：`handleSavePages(selected)` → 合并审查预检 → EXIF Picker（pendingPages 续走）→ store.savePages
- 防社死：R18 页缩略图用纯色遮罩+锁样式（仅展示，弹层内不揭示）

**UserSettingStore / SettingsPage**
- `setDownloadConcurrency(value: number): void`；SettingsPage 下载组 SettingItem"下载线程数"，TextPickerDialog 选项 1-5（参照 showQualityPicker 模式）

**DateUtils**
- `formatCreateDate(iso: string): string`——本地时区 `yyyy-MM-dd HH:mm`；解析失败返回 ''

**TagSearchPage**
- `aboutToAppear`：`db.addSearchHistory(keyword, 'illust')`（既有去重）
