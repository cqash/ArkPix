# Implementation Plan: 查看器与用户主页修复 + 下载/收藏管理增强

**Input**: Feature specification from `spec/viewer-profile-download-fixes/spec.md`

## Summary

(1) 按官方图片预览样例模式根治查看器手势竞争：Pinch/Pan/Tap 手势**常驻静态挂载**，`PanGesture.distance` 动态化（未缩放 50vp 让位 Swiper，缩放后 3vp 跟手拖动），`isDisableSwipe` 标志位共享，拖到 X 边界释放回 Swiper；(2) 用户主页解析 `user/detail` 响应的 `profile` 对象修复统计恒 0，作品列表接入既有 `IllustWaterfall`；(3) `DownloadService` 增加批量操作（重试失败/清空失败/清空完成）与 `isDownloaded(illustId, part)` 重复检测（DB 记录+文件存在性），所有下载入口加确认弹窗；(4) 收藏页本地排序（4 种规则）通过容器 `compareFn` 钩子落地。

## Technical Context

**Language/Version**: ArkTS（严格模式），API 12+ / SDK 6.1.0(23)
**Primary Dependencies**: ArkUI（Swiper/GestureGroup/matrix4/AlertDialog）、既有 IllustWaterfall/IllustCard、DownloadService/DatabaseService
**State Management**: State Management V1（沿用项目现状）
**Storage**: 既有 relationalStore 下载任务表（不新增表）；不新增持久化项（排序不持久化）
**Testing**: 现有 hypium 单测体系；本轮以真机 UI 验证为主
**Target Platform**: HarmonyOS API 12+
**Project Type**: 既有应用缺陷修复 + 小功能增强
**Performance Goals**: 查看器手势 60fps 跟手
**Constraints**: ArkTS 严格模式；遵循既有目录/单例约定
**Scale/Scope**: 修改 ~7 个文件，可能新增 0~1 个文件

## Project Structure

### Documentation (this feature)

```text
spec/viewer-profile-download-fixes/
├── spec.md
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── components/
│   ├── viewer/ZoomableImage.ets        # 重构：官方手势竞争方案（静态手势组+动态 distance+边界释放）
│   └── illust/IllustWaterfall.ets      # 增强：可选 compareFn 排序钩子（变更即重排已加载数据）
├── pages/
│   ├── detail/ImageViewerPage.ets      # 适配新 ZoomableImage 契约（isDisableSwipe 联动）
│   ├── user/UserProfilePage.ets        # 修复：解析 profile 统计 + 作品列表接入 IllustWaterfall
│   ├── download/DownloadPage.ets       # 增强：顶部批量操作栏（重试失败/清空失败/清空完成+确认弹窗）
│   └── bookmark/BookmarkPage.ets       # 增强：排序切换入口（ActionSheet）+ compareFn 接入
├── services/
│   └── DownloadService.ets             # 增强：retryAllFailed/clearByStatus/isDownloaded（DB+文件存在性）
├── stores/
│   └── IllustDetailStore.ets           # 增强：savePage/saveAll 下载前重复检测与确认回调
└── models/
    └── User.ets                        # 增强：UserProfile 统计解析（或新接口承载 profile 字段）
```

**Structure Decision**: 遵循现有架构与目录约定，零新增目录；预计 0 个新文件（若 profile 统计独立成接口则直接放在 User.ets 内）。所有增强均挂在既有组件/服务上，属于增量改造。

## Complexity Tracking

无违反项（全部复用既有抽象）。

## Research & Decisions

### R1 查看器手势竞争根治方案
- **Decision**: 采用官方图片预览样例模式重写 `ZoomableImage` 手势层：
  1. `GestureGroup(GestureMode.Parallel, Pinch + Pan + Tap)` **静态常驻挂载**（不再按 scale 条件切换手势组——条件重建手势正是当前失效根因）；
  2. `PanGesture({ distance: 动态值 })`：scale=1 时 distance=50（滑动 50vp 内手势不触发，Swiper 赢得竞争→翻页）；scale>1 时 distance=3（即触即发→跟手平移）；
  3. `Swiper.disableSwipe(isZoomed)` 与手势共享同一标志位；图片拖到 X 向边界时将标志写回 false，Swiper 接管翻页；
  4. 双击 TapGesture(count:2) 保留：1↔2.5 倍切换；Pinch distance 设 1 提升灵敏度；限幅 1~5 与边界钳制逻辑保留。
- **Rationale**: 官方样例验证过的竞争仲裁方式；当前实现的条件手势组在 scale 状态切换瞬间重建 gesture 对象，导致识别链断裂（捏合与滑动双失效）。
- **Alternatives considered**: priorityGesture+Exclusive 冒泡方案（官方另一模式，边界透传逻辑更复杂）；onTouch 手动多点计算（完全自研，维护成本高）；matrix4 锚点缩放（体验更好但非本轮必需，偏移补偿作为后续增强记录）。

### R2 用户统计解析
- **Decision**: `/v1/user/detail` 响应结构为 `{ user, profile, profile_publicity, workspace }`；在 User.ets 新增 `ProfileStats` 接口（totalFollowUsers/totalIllusts/totalManga/totalIllustBookmarksPublic 等常用字段）与 `profileStatsFromJson()`，页面解析 `response.profile` 渲染统计。
- **Rationale**: 统计字段本就在 profile 对象，独立小接口不污染 User 模型。
- **Alternatives considered**: 合并进 User 模型（user 对象本身不含这些字段，合并语义错误）。

### R3 用户主页作品列表
- **Decision**: 直接接入既有 `IllustWaterfall`，`fetchFirst` 封装 `getUserIllusts(userId)` 返回 IllustListPage（复用 `parseIllustListPage`）；自动获得分页/过滤/卡片角标/长按菜单。
- **Rationale**: 上一轮容器已内聚全部能力，接入成本最低。

### R4 下载批量操作
- **Decision**: `DownloadService` 新增：`retryAllFailed(): Promise<number>`（查 failed 任务逐条重新下载，返回重试数）、`clearTasksByStatus(status): Promise<number>`（删 DB 记录不删文件）；`DownloadPage` 顶部操作行三个文字按钮 + `AlertDialog` 确认 + 完成后刷新列表与 toast。
- **Rationale**: 任务表已含 status/illustId/part/url 等重试所需字段（重试用任务记录的下载 URL 与插画元信息重建下载；元信息缺失的条目跳过并计数）。
- **Alternatives considered**: 下载任务持久化完整 Illust JSON（改动表结构，过度设计）。

### R5 收藏本地排序
- **Decision**: `IllustWaterfall` 增加可选入参 `compareFn`；容器在数据入库后与 compareFn 变更时对已加载数据整体重排（IDataSource reload）。BookmarkPage 顶栏加排序按钮弹 ActionSheet：收藏新→旧（默认）/收藏旧→新/上传时间/收藏数。上传时间用 `illust.createDate`，收藏数用 `illust.totalBookmarks`（模型字段已存在则直接用，缺失则补解析）。
- **Rationale**: 排序属列表容器通用能力，挂在容器一次到位；分页追加后重排全量已加载数据保证全局有序（本地排序语义内）。
- **Alternatives considered**: 页面层每页排序（跨页无序，体验错误）。

### R6 下载重复检测
- **Decision**: `DownloadService.isDownloaded(illustId, part): Promise<boolean>` = 存在 completed 任务记录 **且** 对应文件 fs.access 存在。调用点（IllustDetailStore.savePage/saveAll、ImageViewerPage.handleSave、IllustCard 菜单保存）命中时弹 `AlertDialog`（仍要下载/取消）；saveAll 汇总命中页一次弹窗（"跳过已下载/全部重下/取消"）。
- **Rationale**: DB+文件双条件避免"记录残留但文件已删"的误判；弹窗策略用户已确认。
- **Alternatives considered**: 静默跳过（用户否决）；以相册为准检测（相册查询慢且不可控）。

## Data Model

### ProfileStats（用户统计，解析自 user/detail 的 profile 对象）
| 字段 | 来源 JSON | 说明 |
|---|---|---|
| totalFollowUsers | total_follow_users | 关注数 |
| totalIllusts | total_illusts | 插画作品数 |
| totalManga | total_manga | 漫画数（展示备用） |
| totalIllustBookmarksPublic | total_illust_bookmarks_public | 公开收藏数（备用） |

### 收藏排序规则（BookmarkSortMode 枚举）
| 值 | 比较键 | 方向 |
|---|---|---|
| bookmarkDesc（默认） | 接口原始顺序 | 不变 |
| bookmarkAsc | 接口原始顺序 | 反转 |
| uploadDesc | illust.createDate | 新→旧 |
| totalBookmarksDesc | illust.totalBookmarks | 高→低 |

### 下载重复检测判定
`isDownloaded = ∃ task(illustId, part, status=completed) && fs.access(task.filePath)`

## Contracts & Interfaces

### ZoomableImage（变更后契约）
- 入参：`url`、`onZoomChange(isZoomed: boolean)`（替代 onScaleChange，语义即 disableSwipe 标志）
- 行为：静态手势组；Pan distance 动态（50/3）；X 边界到达时回调 onZoomChange(false)

### DownloadService（新增方法）
| 方法 | 签名 | 说明 |
|---|---|---|
| isDownloaded | `(illustId: number, part: number) => Promise<boolean>` | DB completed 记录 + 文件存在 |
| retryAllFailed | `() => Promise<number>` | 重试全部失败任务，返回成功发起数 |
| clearTasksByStatus | `(status: string) => Promise<number>` | 删除指定状态任务记录，返回删除数 |

### IllustWaterfall（新增可选入参）
`compareFn?: (a: Illust, b: Illust) => number` — 提供时入库数据按之排序；引用变更触发已加载数据重排。

### 下载确认交互契约（各调用点统一）
- 单页命中：`AlertDialog` "该图片已下载过" [仍要下载/取消]
- saveAll 命中 N 页：`AlertDialog` "其中 N 页已下载过" [跳过已下载/全部重下/取消]
