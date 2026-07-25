# Implementation Plan: 浏览体验对标 PixEz 全面升级

**Input**: Feature specification from `spec/browse-experience-upgrade/spec.md`

## Summary

对标 PixEz Flutter 版，对现有鸿蒙 PixEz 客户端做 11 个用户故事级的体验升级。核心技术路线：(1) 以 `WaterFlow + LazyForEach + 预计算 FlowItem 高度` 实现真实宽高比瀑布流，并抽取 `@Reusable` 公共插画卡片与可复用列表容器，消灭 6 处复制代码；(2) `ApiService` 增加 `fetchNext(nextUrl)` 通用游标分页；(3) 新建全局 `BookmarkStateStore` 注册表（AppStorage 引用替换驱动 UI 同步）实现收藏状态三态与跨页同步；(4) 详情页重构为单 `List` 纵向连续滚动（图片页 + 信息区 + 相关推荐）；(5) 全屏查看器用 `Swiper + 自定义手势（Pinch/Pan/双击）` 实现缩放翻页；(6) 修复 OAuth 刷新链路：响应校验 + 错误分类（凭证失效 vs 网络错误）+ 节流，杜绝误登出与 token 写坏。

## Technical Context

**Language/Version**: ArkTS（严格模式），API 12+ / SDK 6.1.0(23)
**Primary Dependencies**: `@kit.NetworkKit`(http/rcp)、ArkUI（WaterFlow/Swiper/List/gesture/bindContextMenu/DatePickerDialog）、`@ohos/hypium`（测试）
**State Management**: 保留项目现有 State Management V1（`@State`/`@StorageLink`/`AppStorage`/单例 Store），不迁移 V2
**Storage**: 现有 `PreferenceService`（KV）+ `DatabaseService`（relationalStore：历史/搜索历史/屏蔽/下载/缓存索引），不新增表
**Testing**: `@ohos/hypium` 单元测试（entry/src/test/），聚焦纯逻辑（MuteFilter、分页去重、token 响应校验）
**Target Platform**: HarmonyOS 手机/平板（API 12+）
**Project Type**: 既有移动应用功能增强（非新建）
**Performance Goals**: 瀑布流滚动 60fps（LazyForEach + @Reusable + 预计算高度）；详情页大图相邻项预取
**Constraints**: ArkTS 严格模式（禁 any/unknown/as 断言/动态访问）；router 栈 ≤ 32 页；图片请求需 Referer + 专用 UA（既有能力）
**Scale/Scope**: 改造 ~10 个页面，新增 ~7 个文件，修改 ~10 个文件

## Project Structure

### Documentation (this feature)

```text
spec/browse-experience-upgrade/
├── spec.md
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── components/
│   ├── common/                      # 既有：CachedImage、CommonViews（CachedImage 支持自定义 aspectRatio）
│   ├── illust/                      # 【新增目录】
│   │   ├── IllustCard.ets           # 【新增】@Reusable 公共插画卡片（宽高比/角标/红心/长按菜单）
│   │   └── IllustWaterfall.ets      # 【新增】可复用瀑布流容器（IDataSource+分页+尾部状态+屏蔽过滤+下拉刷新）
│   └── viewer/
│       └── ZoomableImage.ets        # 【新增】可缩放图片（Pinch/Pan/双击/边界约束）
├── pages/
│   ├── home/                        # 修改：RecomPage、RankPage（+多榜单/日期）、FollowPage
│   ├── search/                      # 修改：SearchPage（+历史展示/写入）、TagSearchPage
│   ├── bookmark/                    # 修改：BookmarkPage（公开/私密+分页+刷新）
│   ├── detail/                      # 重构：IllustDetailPage（纵向连续滚动+相关推荐）、ImageViewerPage（Swiper+缩放）
│   ├── settings/                    # 修改：SettingsPage（+屏蔽管理区）
│   └── user/                        # 修改：UserProfilePage（关注失败提示）
├── stores/
│   ├── BookmarkStateStore.ets       # 【新增】收藏状态注册表 + 三态 + 跨页同步 + 收藏联动编排
│   └── IllustDetailStore.ets        # 【新增】详情页数据编排（行模型、相关推荐分页、历史写入）
├── network/
│   ├── ApiService.ets               # 修改：+fetchNext(nextUrl) 通用续页
│   ├── OAuthService.ets             # 修改：刷新响应校验 + 类型化错误
│   └── AuthInterceptor.ets          # 修改：重放校验 + 刷新节流 + 失败分类上报
├── utils/
│   └── MuteFilter.ets               # 【新增】屏蔽词/屏蔽作者/AI 过滤纯函数
└── resources/                       # 复用既有字符串/颜色资源（必要时新增文案）
main_pages.json                      # 修改：注册 UserProfilePage
```

**Structure Decision**: 遵循项目现有架构（pages/components/stores/network/services/utils 分层 + 单例 Store + State V1），不引入 MVVM 目录迁移。新增文件控制在 7 个：两个列表层组件（消灭 6 份复制代码的必要抽象）、一个查看器组件、两个 Store（收藏注册表与详情编排，均为跨页共享状态的最小载体）、一个纯函数过滤工具。列表页状态从页面私有 `@State` 收敛到 `IllustWaterfall` 组件内聚管理，属于组件级封装而非架构变更。

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 新增 BookmarkStateStore 全局注册表 | router 只能传参数无法传对象引用，Flutter 版"共享 IllustStore 实例"模式在 ArkTS 下必须用注册表等价替代，否则 FR-013 跨页同步无解 | 事件总线 emitter：需各页面手动订阅/退订，生命周期管理易遗漏；AppStorage 引用替换方案由框架自动驱动 UI |

## Research & Decisions

### R1 瀑布流实现方案
- **Decision**: `WaterFlow + LazyForEach + 自定义 IDataSource`，`FlowItem` 高度在数据进入时按 `列宽 × (height/width) + 信息区固定高度` 预计算；尾部用 `WaterFlow footer` 自定义三态（加载中/无更多/失败重试）；触底前预加载（倒数第 N 项 onAppear 触发）；卡片 `@Reusable`。
- **Rationale**: 官方高性能指导方案；预计算高度避免图片加载后布局抖动；`List.lanes` 无法做不等高。
- **Alternatives considered**: `Grid`（等高，不符合瀑布流语义）；保留 List.lanes + 宽高比（lanes 仍按行均分，非瀑布流）。

### R2 公共卡片与列表容器抽象
- **Decision**: 新增 `IllustCard`（@Reusable，入参 Illust + 点击/长按回调）与 `IllustWaterfall`（入参 `fetchPage(url?: string)` 数据回调 + 可选隐藏刷新）。六个列表页 + 详情相关推荐全部复用。
- **Rationale**: 当前 IllustCard/pickPreviewUrl 复制 6 份，任何卡片改动要改 6 处；过滤/分页/尾部状态逻辑也需单点落地。
- **Alternatives considered**: 每页各自封装（重复依旧）；@Builder 传参（无法承载分页状态机）。

### R3 分页机制
- **Decision**: `ApiService.fetchNext(nextUrl)` 裸 GET 返回原始 JSON 字符串解析结果；`IllustWaterfall` 内部分页状态机：`idle/loading/noMore/error`，防重入锁 + 按 illust.id 去重；首屏 URL 与解析逻辑由各页以回调注入。
- **Rationale**: Pixiv 所有列表接口统一返回 `illusts + next_url` 结构，一个方法即可服务全部页面；状态机内聚保证 FR-007/008 一致行为。
- **Alternatives considered**: 每个 API 方法各自封装 next 版本（25 个端点膨胀）。

### R4 收藏状态跨页同步
- **Decision**: `BookmarkStateStore` 单例持有 `Map<illustId, 0|1|2>`（未收藏/请求中/已收藏），变更时以**新对象引用**写入 `AppStorage` key `bookmarkStates`；卡片与详情按钮用 `@StorageLink` 绑定后按 id 读取，无记录时回退 `illust.isBookmarked`。`star()/unstar()` 内含请求中锁、失败回滚 + toast、成功后同步 `illust.isBookmarked` 并使详情 DB 缓存失效。公开/私密选择用长按触发 `ActionSheet`/半模态。
- **Rationale**: AppStorage 依赖引用变化驱动刷新（已验证知识），Map 整体替换引用是最小可靠同步手段；注册表模式替代 Flutter 的共享实例。
- **Alternatives considered**: emitter 事件总线（手动订阅管理）；每卡片 @StorageLink 独立 key（key 爆炸）。

### R5 详情页纵向连续滚动
- **Decision**: 单 `List + LazyForEach` 承载扁平化"行模型"：`image_row(i)`（i=0..pageCount-1，按 metaPages 宽高比 aspectRatio + 页码占位）、`info_row`（标题/作者/统计/标签/操作）、`related_header`、`related_row(j)`（每行 3 列相关推荐）。`IllustDetailStore` 负责行模型组装、相关推荐分页（getRelatedIllusts + fetchNext）、浏览历史写入。作者区点击跳 UserProfilePage。
- **Rationale**: 单滚动容器天然实现"图片→信息→相关"连续流；行模型避免嵌套滚动冲突；对标 Flutter 的 CustomScrollView+Sliver 结构。
- **Alternatives considered**: Scroll+Column（全量建节点，大图内存风险）；Swiper 纵滚（无法混排非图片内容）。

### R6 全屏查看器缩放
- **Decision**: `Swiper`（多页翻页 + indicator 自定义页码）每页嵌 `ZoomableImage`：`ParallelGesture(PinchGesture + PanGesture)` + `TapGesture(count:2)` 双击；`scale` 限幅 1~5，offset 边界钳制，scale=1 时 offset 归零；`scale>1` 时禁用 Swiper 滑动（`disableSwipe` 联动）解决手势冲突。相邻页通过 `ImageCacheService` 预取（index±1）。
- **Rationale**: 官方手势冲突指导模式（缩放时让位拖动、未缩放让位翻页）；自研手势是当前 ArkUI 唯一途径（无 photo_view 等价物）。
- **Alternatives considered**: 仅 Pinch 不支持拖动（体验不达标）；第三方库（无成熟鸿蒙等价物且引入风险）。

### R7 登录持久化修复
- **Decision**:
  1. `OAuthService.refreshToken()`：校验 `responseCode===200 && access_token 非空`，否则抛类型化错误 `CredentialInvalidError`（400 系/含 OAuth 错误信息）或 `NetworkError`（网络层异常）；**校验通过前不写回任何 token**。
  2. `AccountStore.refreshToken()`：捕获 `CredentialInvalidError` → 置 `needsRelogin` 标记并提示重新登录（此时才 forceLogout）；捕获 `NetworkError` → 保持现状返回 false，**不登出**。
  3. `AuthInterceptor`：增加刷新节流（距上次刷新 < 120s 直接复用当前 token）；401 重放后仍 401 时按错误分类处理；刷新失败返回空 token 时不重放。
- **Rationale**: 根因是错误 JSON 被当成功解析写坏 token + 网络错误误登出；对标 PixEz RefreshTokenInterceptor 的错误分类与节流策略。
- **Alternatives considered**: 记录 token 过期时间主动刷新（Pixiv 返回 expires_in 但现有模型未存，被动 401 刷新已足够且改动小）。

### R8 屏蔽过滤落点
- **Decision**: 纯函数 `MuteFilter.isMuted(illust, settings)`：标题或任一标签名**包含**屏蔽词（不区分大小写）、作者在 muteUsers、aiFilter 开启且 illustAIType===2。在 `IllustWaterfall` 数据入库时统一过滤（所有列表自动生效）；详情页不拦截（对标 Flutter 的"列表过滤+详情可临时查看"，本期仅列表）。设置页新增屏蔽管理区：屏蔽词/屏蔽作者列表展示 + 删除 + 手动添加屏蔽词。
- **Rationale**: 单点过滤随公共列表容器覆盖全部页面；纯函数可单测。
- **Alternatives considered**: 各页面自行过滤（6 处重复）；正则屏蔽（Flutter 支持，本期不做，ArkTS 正则也可后续加）。

### R9 长按交互载体
- **Decision**: 卡片与标签使用 `bindContextMenu(builder, ResponseType.LongPress)` 自定义菜单；详情页图片长按用 `LongPressGesture` + `ActionSheet.show`（保存当前页/全部页）。菜单动作：保存→DownloadService；收藏→BookmarkStateStore；屏蔽→UserSettingStore 追加并即时过滤当前列表。
- **Rationale**: bindContextMenu 是长按菜单官方载体且支持自定义布局；ActionSheet 适合少量动作。
- **Alternatives considered**: bindMenu（点击触发为主，长按语义不符）。

### R10 排行榜与 R18 可见性
- **Decision**: 顶部横向滚动 mode 标签条：day/week/month/rookie/original/male/female + day_r18/week_r18/day_r18g；R18 组默认隐藏，设置页新增"显示 R18 榜单"开关（默认关）控制展示；日期用 `DatePickerDialog` 选择（不晚于昨天）。
- **Rationale**: 当前账号模型未持久化 xRestrict，用显式设置开关是最可控的可见性 gate；API 不支持时走既有 ErrorView。
- **Alternatives considered**: 拉取 user/detail 判 xRestrict（额外请求 + 缓存复杂度，后续可加）。

## Data Model

### IllustListPage（分页数据包，各列表回调返回）
| 字段 | 类型 | 说明 |
|---|---|---|
| illusts | Illust[] | 本页插画（已按 MuteFilter 过滤） |
| nextUrl | string | 下一页游标，空串=无更多 |

### BookmarkState（注册表值）
| 值 | 含义 | UI |
|---|---|---|
| 0 | 未收藏 | 空心灰心 |
| 1 | 请求中 | 实心灰心（防连点） |
| 2 | 已收藏 | 实心红心 |

存储：`AppStorage['bookmarkStates']: Map<number, number>`（每次变更整体替换引用）；内存态在 `BookmarkStateStore` 单例。

### DetailRow（详情页行模型，判别联合）
| kind | 载荷 | 高度策略 |
|---|---|---|
| image | pageIndex、imageUrl、宽/高 | aspectRatio=宽/高，页码占位 |
| info | Illust 全量 | 自适应 |
| related_header | 标题文案 | 固定 |
| related | Illust[≤3] | 3 列等宽，按各自宽高比 |

### TokenRefreshResult（OAuth 层内部）
- 成功：`{ accessToken, refreshToken, user }`（校验后）
- 失败分类：`CredentialInvalidError`（凭证失效，需重新登录）/ `NetworkError`（临时故障，可重试）

### RankMode（枚举）
`day | week | month | rookie | original | male | female | day_r18 | week_r18 | day_r18g`

### 既有实体复用
`Illust`（isBookmarked/width/height/pageCount/illustAIType/tags 已就绪）、`User.isFollowed`、`AppSettings`（muteTags/muteUsers/aiFilter/crossCount/四档画质）、DB 表（浏览历史/搜索历史/详情缓存）均不改动结构。

## Contracts & Interfaces

### ApiService（新增/调整签名）
| 方法 | 签名 | 说明 |
|---|---|---|
| fetchNext | `(nextUrl: string) => Promise<Object>` | 通用游标续页，直接 GET 完整 next_url，返回解析后 JSON |
| getRankingIllusts | `(mode: string, date?: string)` 不变 | 调用方传入扩展 mode 与所选日期 |
| getRelatedIllusts | 既有 | 详情相关推荐首屏，续页走 fetchNext |
| addBookmark | 既有 `(illustId, restrict, tags)` | 消费端从写死 'public' 改为可选公开/私密 |

### BookmarkStateStore（新增公共方法）
| 方法 | 说明 |
|---|---|
| `stateOf(illustId, fallback): number` | 读取三态，无记录回退 isBookmarked |
| `star(illust, restrict): Promise<boolean>` | 收藏（含请求中锁/失败回滚/toast/联动编排入口） |
| `unstar(illustId): Promise<boolean>` | 取消收藏 |
| `seedFromList(illusts): void` | 列表/详情数据到达时播种注册表 |

### IllustWaterfall（组件入参契约）
| 参数 | 类型 | 说明 |
|---|---|---|
| fetchFirst | `() => Promise<IllustListPage>` | 首屏数据回调 |
| enableRefresh | boolean | 是否启用下拉刷新（默认 true） |
| onCardClick | `(illust) => void` | 卡片点击（默认跳详情） |

### IllustDetailStore（新增公共方法）
`load(illustId)`（缓存→网络→播种注册表→写浏览历史）、`buildRows()`、`loadMoreRelated()`、`toggleBookmark()`、`savePage(i)/saveAll()`（含 autoBookmarkOnDownload 联动）

### ZoomableImage（组件入参契约）
`url`、`onScaleChange(scale)`（供父级联动 Swiper.disableSwipe）、`maxScale=5`

### 路由
`main_pages.json` 新增 `pages/user/UserProfilePage`；详情页作者区 `router.pushUrl` 携带 `userId`。
