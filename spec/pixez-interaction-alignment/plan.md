# Implementation Plan: pixez 交互全面对齐（含 R2/R3 增量）

**Input**: Feature specification from `spec/pixez-interaction-alignment/spec.md`（R3 修订版）

## Summary

在 ArkPix 现有架构上增量落地 pixez 交互模式：新增全局触觉反馈工具（@ohos.vibrator 预置效果四级语义封装 + 节流 + 设置开关）、卡片长按直存与可交互星标、底栏 Tab 再点回顶（AppStorage 令牌广播 + WaterFlow Scroller）、带标签收藏面板（新增 bookmark-tags 端点 + 复用内联底部弹层模式）、详情页作品间滑动（列表上下文注册表 + 详情内容抽取为可复用 Pane + Swiper 懒加载）、详情页屏蔽占位、三态关注按钮组件、搜索 URL 直达与自动补全。全部遵循 ArkPix 既有弹窗/状态/同步约定。**R2 增量**：滑动上下文扩展至详情页相关作品与历史记录网格（一切有上级列表的入口），修复下载管理器任务行标题格式化缺陷。

## Technical Context

- **Language/Version**: ArkTS（严格模式），API 12+ / SDK 6.1.0(23)
- **Primary Dependencies**: `@kit.SensorServiceKit`（vibrator，新增）、`@kit.NetworkKit`（既有 http）、ArkUI（Tabs/Swiper/WaterFlow/LazyForEach）
- **State Management**: 既有 State Management V1（@State/@Prop/@StorageLink/@Watch + AppStorage），不迁移
- **Storage**: PreferenceService（KV，新设置项）、无新表
- **Testing**: 构建验证 + 真机/模拟器人工验证（构建 + 部署，可选 UI 验证）
- **Target Platform**: HarmonyOS 手机
- **Constraints**: ArkTS 禁 any/as/动态属性；弹窗禁 ActionSheet 与 hitTestBehavior Block；ForEach key 陷阱（可变字段入 key）；Scroll 需 align TopStart；路由参数仅传轻量可序列化数据
- **Scale/Scope**: R1 约 15 个既有文件修改 + 5 个新文件（已完成）；R2 增量 3 个既有文件修改

## Project Structure

### Documentation (this feature)

```text
spec/pixez-interaction-alignment/
├── spec.md              # R2 修订版
├── plan.md              # 本文件（含 R2 增量设计）
└── tasks.md             # 含 R1 已完成任务 + R2 新增任务
```

### Source Code（遵循现有架构，增量修改）

```text
entry/src/main/ets/
├── utils/
│   ├── HapticUtils.ets                    # 【R1 新增】四级语义触觉反馈 + 节流 + 开关
│   └── PixivLinkParser.ets                # 【R1 新增】pixiv URL → {kind,id} 纯函数
├── services/
│   └── DetailListContextRegistry.ets      # 【R1 新增】作品间滑动上下文注册表（模块级 Map，纯内存）
├── components/
│   ├── common/FollowButton.ets            # 【R1 新增】三态关注按钮 + 长按精细菜单
│   └── illust/
│       ├── IllustCard.ets                 # 【R1 改】长按直存、星标可交互、震动接入
│       ├── IllustWaterfall.ets            # 【R1 改】Scroller+回顶令牌、上下文注册、星标回调透传
│       └── BookmarkTagPanel.ets           # 【R1 新增】带标签收藏内联底部弹层
├── components/detail/
│   └── IllustDetailPane.ets               # 【R1 新增】详情内容面板；【R2 改】相关作品点击注册上下文
├── pages/
│   ├── home/HomePage.ets                  # 【R1 改】Tab 再点广播
│   ├── home/{RecomPage,FollowPage,RankPage}.ets  # 【R1 改】回顶令牌接收转发
│   ├── detail/IllustDetailPage.ets        # 【R1 改】Pane 化 + Swiper 模式 + 屏蔽占位 + FAB 长按标签面板
│   ├── detail/ImageViewerPage.ets         # 【R1 改】震动接入
│   ├── search/SearchPage.ets              # 【R1 改】URL 直达 + 补全下拉 + 多词末词替换
│   ├── settings/GeneralSettingsPage.ets   # 【R1 改】触觉反馈开关
│   ├── settings/DownloadSettingsPage.ets  # 【R1 改】长按保存确认开关
│   ├── settings/SettingWidgets.ets        # 【R1 改】SwitchItem 震动
│   ├── settings/DownloadPage.ets          # 【R2 改】任务行标题格式化参数类型修复
│   ├── settings/HistoryPage.ets           # 【R2 改】点击注册历史滑动上下文
│   └── user/UserProfilePage.ets           # 【R1 改】换用 FollowButton
├── stores/
│   ├── UserSettingStore.ets               # 【R1 改】两个设备本地设置项
│   └── BookmarkStateStore.ets             # 【R1 改】star 支持 tags
├── models/
│   └── AppSettings.ets                    # 【R1 改】hapticFeedback/longPressSaveConfirm 字段
├── network/
│   ├── ApiService.ets                     # 【R1 改】getBookmarkTags
│   └── PixivEndpoints.ets                 # 【R1 改】bookmark-tags 端点
└── module.json5                           # 【R1 改】声明 ohos.permission.VIBRATE
```

**Structure Decision**: 遵循现有项目架构（pages/components/stores/network/services/utils 分层 + Store 单例 + AppStorage），不引入 MVVM 迁移。新增文件均为单一职责的工具/组件，符合既有分层惯例。

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| IllustDetailPage 拆分为 Page + Pane 两个文件 | Swiper 复用要求详情内容必须是可多次实例化的子组件 | 单文件内嵌套 @Component 会使本已超千行的页面文件进一步膨胀，且 Pane 需被 Page 引用、职责不同 |

## Research & Decisions

### D1: 触觉反馈实现

- **Decision**: `utils/HapticUtils.ets` 静态工具类，四级语义映射 vibrator 预置效果：selectionClick→SOFT(40)、light→SOFT(70)、medium→HARD(80)、heavy→HARD(100)；读 settings.hapticFeedback 开关 + 50ms 全局节流；`{usage:'touch'}`；`isSupportEffectSync` 探测缓存，不支持降级 VibrateTime 时长分档（10/20/35/50ms）；全程 try/catch 静默。module.json5 声明 `ohos.permission.VIBRATE`。
- **Rationale**: 预置效果与系统振感一致；usage='touch' 受系统触感开关管控；探测+降级保证无马达设备不崩。
- **Alternatives considered**: 全 VibrateTime（触感粗糙）；VibrateFromPattern（API 18+ 过度设计）；NOTICE_SUCCESS 等（API 12 基线不可用）。

### D2: 底栏 Tab 再点回顶

- **Decision**: HomePage TabBuilder 项 onClick：点击项=当前项时写 AppStorage `tabRetapToken`（`"<tabIndex>:<epochMs>"`）；各列表页 @StorageLink+@Watch 解析转发给 IllustWaterfall 新增 `@Prop @Watch scrollTopToken` → 内部 Scroller `scrollEdge(Edge.Top)`。RankPage 单瀑布流直接响应。
- **Rationale**: AppStorage 令牌是项目既有跨页通信惯例；Tabs onChange 捕获不到"再点当前项"。
- **Alternatives considered**: emitter 事件总线（无先例）；Tabs onChange（不触发同索引点击）。

### D3: 卡片长按直存与星标交互

- **Decision**: 长按：heavy 震动 → longPressSaveConfirm 开启时 AlertDialog 确认 → 直接保存（单页 p0、多页全部页）→ 复用 isDownloaded 检测与 autoBookmark 联动。旧菜单移除；「屏蔽作者」迁至详情页画师行长按菜单。星标改可交互：单击快收/取消；长按上抛打开 BookmarkTagPanel。
- **Alternatives considered**: 保留菜单加首项（未达一步保存目标）；星标保持只读（不符合 pixez 语义）。

### D4: 带标签收藏

- **Decision**: 新端点 `/v1/user/bookmark-tags/illust`；ApiService.getBookmarkTags；BookmarkStateStore.star 加可选 tags。`BookmarkTagPanel` 内联底部弹层（遮罩+弹层+`.onClick(()=>{})` 防冒泡），宿主两处：详情页 FAB 长按、IllustWaterfall 根 Stack（卡片星标长按上抛）。
- **Alternatives considered**: CustomDialog（无先例）；bindContextMenu 多选（不支持）；仅详情页入口（spec 要求卡片也是入口）。

### D5: 详情页作品间滑动

- **Decision**: DetailListContextRegistry（模块级 Map，上限 8）承载 ids+nextUrl+fetchNext 闭包；IllustWaterfall 默认 onCardClick 注册后 pushUrl 传 `{illustId, contextToken, contextIndex}`；IllustDetailPage 壳：无 token=单 Pane，有 token=Swiper+LazyForEach(cachedCount 1) 多 Pane（各自独立 IllustDetailStore、isActive 门控懒加载与接续登记）；滑至倒数第 2 项且 nextUrl 非空预取追加；尾部 No More/失败重试占位。
- **Alternatives considered**: 路由传 ids 数组（过大且无法携带闭包）；相关作品网格不启用（**R2 已推翻**，见 D10）。

### D6: 详情页屏蔽占位

- **Decision**: Pane 加载完成后 MuteFilter.isMuted 判定，命中且 tempRevealed=false 时整页占位（提示+跳 MutePage+临时查看）；组件内存态满足"仅本次会话"。

### D7: 三态关注按钮

- **Decision**: `FollowButton` 组件（实心/描边/请求中原地小菊花），单击快关、长按 bindContextMenu 精细关注；UserProfilePage 替换 + 详情页画师行新增；画师行长按承接屏蔽作者/复制 UID。

### D8: 搜索 URL 直达与补全

- **Decision**: `PixivLinkParser` 纯函数解析 artworks/users/member_illust.php/pixiv:// 链接；SearchPage 直达行 + getAutoComplete 300ms 防抖下拉；多词仅替换末词不提交，单词回填并提交。

### D9: 新设置项的同步归属

- **Decision**: hapticFeedback/longPressSaveConfirm 设备本地，不进 Relay/分布式同步载荷。

### D10（R2）: 相关作品滑动上下文

- **Decision**: IllustDetailPane 相关作品 IllustCard 的 onCardClick 从"直接 pushUrl {illustId}"改为：先从本 Pane store 快照上下文（ids=relatedIllusts 的 id 序列——该列表加载时已 MuteFilter 过滤；nextUrl=relatedNextUrl 快照；fetchNext 闭包持有局部游标变量，内部 apiService.fetchNext + parseIllustListPage + MuteFilter 过滤 + 去重后返回），注册到 DetailListContextRegistry，再 pushUrl 传 `{illustId, contextToken, contextIndex}`（contextIndex=点击项在 relatedIllusts 中的下标）。
- **Rationale**: 快照+闭包自持游标，不依赖原 Pane/store 存活（新页面入栈后原 Pane 可能销毁）；注册侧已过滤满足 FR-021。
- **Alternatives considered**: 闭包引用原 store 实时读取（弃用——原 Pane 销毁后悬垂引用，且相关列表继续加载会改变序列语义）；相关作品仍不滑动（弃用——用户明确要求）。

### D11（R2）: 历史记录滑动上下文

- **Decision**: HistoryPage 浏览历史网格点击时注册上下文：ids=当前展示序列的 illust_id（时间倒序、已按 illust_id 去重）、nextUrl=''、fetchNext 返回空页（无续页）；pushUrl 传 contextToken/contextIndex。搜索历史回放的 pid 直达不注册（单作品语义）。
- **Rationale**: 历史一次性取回（默认 500 上限），无分页游标，末尾自然 No More。
- **Alternatives considered**: 历史也做续页（弃用——getHistory 无游标接口，超出范围的查询改动收益低）。

### D12（R2）: 下载任务行标题修复

- **Decision**: DownloadPage 中 `getStrf(dl_task_prefix, task.illust_id)` 的 number 实参与资源 `%s` 占位不匹配（getStringSync 抛错被 getStrf 静默吞为 ''）→ 改为显式传字符串（`illust_id.toString()`）。同时全量排查 getStrf 调用点的占位符/实参类型一致性（%d 配 number、%s 配 string），一并修复。
- **Rationale**: 四语言资源不动，仅修调用点，零资源回归风险。
- **Alternatives considered**: 资源 `%s` 改 `%d`（弃用——需同步改 4 个语言文件，且其它调用点可能有同类问题，统一在调用侧修正+排查更彻底）。

### D13（R3）: 下载任务行缩略图三级回退

- **Decision**: DownloadPage 内联轻量子组件 `TaskThumb`（`@Prop localPath: string`、`@Prop imageUrl: string`，内部 `@State useLocal = true`）：useLocal 且 localPath 非空 → `Image('file://' + localPath)` 挂 onError 置 useLocal=false；否则回退 `CachedImage(imageUrl)`（既有图片通道自带错误占位）。56vp 方图 + 4vp 圆角置行首。
- **Rationale**: onError 回退天然覆盖"本地文件被清理"场景，避免每行 fs.access 预检 IO；复用 CachedImage 获得 referer/缓存/占位全套。
- **Alternatives considered**: refresh 时批量 fs.access 预检并把结果编入 ForEach key（弃用——增加轮询 IO 与 key 复杂度，onError 已足够）。

### D14（R3）: 下载任务点击跳详情（复用 R2 无续页上下文模式）

- **Decision**: 行 onClick → `openTaskDetail(task)`：ids=当前筛选后可见任务按 illust_id 去重（保列表顺序）、index=点击任务对应作品下标、nextUrl=''、fetchNext 返回空 IllustListPage（同 HistoryPage 模式），注册 DetailListContextRegistry 后 pushUrl `{illustId, contextToken, contextIndex}`。不抽公共辅助函数（与 HistoryPage 空续页闭包重复 <10 行，保持局部简单）。
- **Rationale**: 任务量有限（一次查询取回），无分页游标；与 R2 D11 完全同构，行为可预期。
- **Alternatives considered**: 跳转不注册上下文（弃用——与"一切有上级列表的入口都支持滑动"原则冲突）。

### D15（R3）: 下载任务状态筛选

- **Decision**: `@State filterMode: string`（'all'|'active'|'completed'|'failed'，active=pending+downloading），标题栏下一行筛选 chips（选中态高亮 #0096FA）；成员方法 `getFilteredTasks()` 过滤 this.tasks 供 ForEach；1.5s 轮询 refreshTasksSilently 仅更新数据源、不打断筛选；批量按钮语义不变作用于全部任务。
- **Rationale**: 纯展示层过滤，不动 DownloadService/DB。
- **Alternatives considered**: Tabs 组件分组（弃用——单列表过滤更轻，与 pixez SortGroup chip 语义一致）。

### D16（R4）: 简介富文本（CaptionParser + Text/Span 分段渲染）

- **Decision**: 新增纯函数 `utils/CaptionParser.ets`：`parseCaptionHtml(html): CaptionSegment[]`（`{text, href}`），处理 `<a href>`（提取 href 与文本）、`<br>`→`\n`、基础 HTML 实体（&amp;/&lt;/&gt;/&quot;/&#39;）、其余标签剥离、畸形输入兜底纯文本。`models/Illust.ets` 补 `caption` 字段（Options + fromJson 解析 `caption`，证实现缺）。渲染：Pane 在 tag 区后插入简介行——`Text(){ ForEach(segments, Span) }`，链接 Span 高亮 #0096FA + `.onClick`：PixivLinkParser.parse(href) 命中 → 应用内跳详情/画师页；否则外部链接走 UIAbilityContext.openLink 开系统浏览器。空 caption 不渲染该行。
- **Rationale**: Text+Span 为 ArkUI 标准行内混排；纯函数解析可单测、零 UI 依赖；链接语义复用 R1 的 PixivLinkParser。
- **Alternatives considered**: RichEditor/Web 组件渲染 HTML（弃用——重，且链接拦截成本高）；StyledString（备选——若 Text+ForEach(Span) 编译受限则切换）。
- **风险**: Text 内 ForEach(Span) 兼容性需实现期验证，失败降级为 StyledString 方案。

### D17（R4）: 详情页顶栏（Pane 内叠加层）

- **Decision**: IllustDetailPane 根 Stack 顶部叠加顶栏（左返回/右 ⋮，半透明背景 + hitTestBehavior Transparent 风格，同查看器顶栏模式；每 Pane 自带，随滑动切换）。⋮ 用 bindContextMenu 六项：分享（@kit.ShareKit systemShare，SharedData 文本记录=作品 URL https://www.pixiv.net/artworks/{id}）、复制链接（ClipboardUtils.copyText+toast）、复制文案（标题+简介纯文本拼接，复用 CaptionParser 纯文本输出）、画师信息（goToUserProfile）、多图保存（打开既有选页弹窗，与 FAB 长按同路径）、屏蔽作者（复用 addMuteUser+toast）。
- **Rationale**: 菜单项全部复用既有逻辑，仅新增入口；Pane 内叠加不改动详情壳结构。
- **Alternatives considered**: 壳级顶栏（弃用——需跨 Pane 取当前 illust，通信复杂；pixez 每页独立 appbar）。

### D18（R4）: 缩放页底栏（HD 切换/复制图片/全屏）

- **Decision**: ImageViewerPage 底部居中叠加工具栏（半透明黑底胶囊，与页码指示合并一行）：①HD 切换——`@State showOriginal`，当前页 URL = showOriginal ? downloadUrls[i] : urls[i]，ZoomableImage url 切换依赖 CachedImage 既有 @Watch('onUrlChange') 重载；②复制图片——ImageCacheService 取缓存文件路径 → image.createImageSource → createPixelMap → pasteboard createData(MIMETYPE_PIXELMAP) setData；任一失败回退 ClipboardUtils.copyText(url) + toast"已复制图片链接"；③全屏开关——window.getLastWindow → setSpecificSystemBarEnabled('status', false/true)，aboutToDisappear 强制恢复。
- **Rationale**: urls/downloadUrls 双数组已存在，HD 切换零网络层改动；pixelmap 剪贴板为 pasteboard 标准能力（写剪贴板免权限）。
- **Alternatives considered**: 复制图片仅复制 URL（弃用——与 pixez 语义差距大，pixelmap 可行）。

### D19（R4）: 下载反馈四态（enqueue 返回状态）

- **Decision**: `DownloadService.enqueue` 增加同步返回值 `'enqueued' | 'inflight'`（inflightTaskIds 命中时返回 'inflight' 且不入队）；各调用点按返回值 toast：enqueued→"已加入下载队列"（复用 common_added_download）、inflight→新增资源"已在下载队列中"。调用点：IllustDetailPane（savePage/savePages/saveAll 汇总提示）、ImageViewerPage.doSave、IllustCard 长按直存。ALREADY 保留现有 AlertDialog、SUCCESS 保留完成 toast。
- **Rationale**: 最小签名变更（fire-and-forget 调用方忽略返回值即兼容）；四态语义对齐 pixez 且无 action banner。
- **Alternatives considered**: 事件流通知（弃用——调用点就在现场，同步返回更直接）。

### D20（R4）: 信息区分辨率

- **Decision**: InfoRow 统计区追加一行 `{width}×{height}`（Illust 字段现成），0 值不渲染。

### D21（R4）: 相关作品触底自动加载

- **Decision**: Pane 根 List 加 `.onReachEnd(() => { if (hasMoreRelated && !relatedLoading) loadMoreRelated() })`，保留手动"加载更多"按钮作为失败兜底。

### 变更文件清单（R4）
- 新增：`utils/CaptionParser.ets`
- 修改：`models/Illust.ets`（caption）、`components/detail/IllustDetailPane.ets`（简介行/顶栏/分辨率/onReachEnd/INQUEUE toast）、`pages/detail/ImageViewerPage.ets`（底栏三功能/INQUEUE toast）、`services/DownloadService.ets`（enqueue 返回值）、`components/illust/IllustCard.ets`（INQUEUE toast）、四语言 string.json

### D22（R5）: 查看器底栏 pixez 化重排

- **Decision**: ImageViewerPage 移除顶部工具栏（返回+SaveButton 所在 Column），改为底部单行图标栏：Row(width 100%, SpaceEvenly, 底部安全区 padding, hitTestBehavior Transparent 透传) 依次排布——复制图片图标（🖼 或 Glyph 文本图标）、页码文本（仅多页）、返回图标（‹/←）、全屏图标（⛶）、SaveButton（icon-only，FULL_FILLED，去 text）、分享图标（↗）、HD 图标（"HD"文本描边样式，原图档高亮）。图标统一白色 20~22vp，直接悬浮于黑底（不加胶囊背景，对齐截图）。功能回调全部复用 R4 既有实现（handleSave/copyImage/toggleFullScreen/showOriginal/router.back），仅布局重排。
- **Rationale**: 零逻辑变更纯视觉重排，回归风险最小；SaveButton icon-only 为安全控件合法形态。
- **Alternatives considered**: 保留半透明胶囊（弃用——用户明确要求按截图样式）；顶栏保留返回（弃用——用户选"完全按 pixez 重排"）。
- **风险**: SaveButton 安全控件对透明度/尺寸有约束，若白色图标在浅色图上可读性差，给整个底栏加极淡渐变底（rgba(0,0,0,0.25)）缓解，仍属 D22 范围内微调。

### D23（R5）: 查看器分享图片

- **Decision**: 底栏分享按钮 → `shareCurrentImage()`：复用 R4 复制图片的缓存路径解析（当前显示档位 URL → ImageCacheService 缓存路径）→ fs 存在则构造 ShareKit SharedData 图片记录（image utd + 文件 uri，参照 `devecocli docs search 分享图片 fileUri` 官方示例）拉起面板；缓存未命中/异常 → 图标半透明态（@State shareEnabled）+ 点击 toast"图片加载后可分享"。HD 切换后按当前档位取缓存，未缓存回退另一档。详情页 ⋮ 分享保持链接（FR-038 不动）。
- **Rationale**: 图片类型分享是微信/QQ 等通常声明接收的类型，比链接文本更可能出现在面板；缓存路径解析与 copyImage 同源，零新增 IO。
- **Alternatives considered**: 分享 pixelmap 内存对象（备选——若文件 uri 分享受限则切换 utd pixelmap 记录）；分享链接+图片双记录（弃用——语义混乱）。

### D24（R6）: 收藏页判删改为"全列表确认"

- **Decision**: BookmarkPage 重构：①`buildDeletedPlaceholders` 拆为两步——`filterCandidates()`（restrict 匹配过滤）与 `classifyDeletedSnapshots(nextUrl)`（后台走查）；②fetchFirst 返回纯 API 数据不插占位；③classify 复用 `apiService.fetchNext` 走完收藏列表全部分页（上限 20 页收集 id），**完整走完**（nextUrl 空）后差集确认 → 构造占位 Illust 存 `@State confirmedPlaceholders` → `reloadToken++` 触发列表重载，fetchFirst 检测到 confirmedPlaceholders 非空且属当前 restrict 时前置插入；④走查中网络失败/超上限 → 静默放弃（`classifyFailed` 置位不再重试本轮）；⑤`switchRestrict` 重置 confirmedPlaceholders 与分类标志。
- **Rationale**: 原"不在第一页即判删"在收藏超一页时全量误报；全列表走查是唯一可靠的缺席判定；失败放弃符合"宁漏勿误"（占位卡是增强信息，误报直接破坏列表可用性）。走查请求与瀑布流自身分页独立（游标各持一份），最多 20 页开销可控。
- **Alternatives considered**: 逐候选调 detail 接口探测 404（弃用——候选可达数百，请求量不可控）；直接移除占位卡特性（弃用——用户选择保留，跨设备同步的已删作品可见性有价值）。
- **风险**: 收藏数 >600（超 20 页上限）时尾部作品判删不可确认 → 按失败处理不插入，行为可预期。

### D25（R7）: 详情页滑动相邻作品预取

- **Decision**: 壳页 `IllustDetailPage` 新增 `prefetchNeighbors(index)`：①仅 contextToken 模式启用；②目标 = dataSource 中 index±1 的 id；③每个目标：`db.getIllustDetailCache(id)` 命中→仅补首图预取，未命中→`apiService.getIllustDetail(id)`→`db.setIllustDetailCache`→`prefetchCachedImage(pickDetailUrl(parsed, 0, userSettingStore.getSettings().detailQuality))`；④`prefetchedIds: Set<number>` 会话级去重，失败时从 Set 移除允许下次触发重试；⑤`prefetchGen` 代数计数：每次触发递增，异步步骤间校验代数变化即中止（快速连滑作废在途预取）。触发点：Pane `onDetailLoaded` 回调（loadDetail 成功后通知壳，壳按 currentIndex 触发）。
- **Rationale**: 预取与激活加载命中同一 DB 缓存与图片 URL 档位是命中关键；`store.load` 会写浏览历史，预取必须独立轻量路径；代数机制防止快速滑动时请求堆积（每滑一下都触发新一轮预取）。
- **Alternatives considered**: 仅预取首图不落库（弃用——API 成本相同却丢掉数据缓存收益）；预取 p1 多页（弃用——流量翻倍收益边际）；扩展注册表存 Illust 对象取列表 URL（弃用——列表缩略图 URL 档位与详情图行不同，缓存不命中）。
- **风险**: 预取流量增加（每相邻作品 1 API + 1 图）；DB 详情缓存被预取数据占用的空间增长（既有缓存无淘汰机制，可接受）。

### D26（R8）: 详情页缓存优先渲染

- **Decision**: `IllustDetailStore` 拆 `load` 为两方法：`loadFromCache(illustId): Promise<boolean>`（DB 缓存读取 + bookmarkStateStore.seedFromList + isBookmarked 对账，复用原缓存分支代码）与 `refreshFromNetwork(illustId): Promise<boolean>`（原网络路径：getIllustDetail→解析→对账→落缓存→写历史→返回；404/解析失败走原 deletedSnapshot/errorMessage 语义）。`IllustDetailPane.loadDetail` 重排：forceRefresh → 原路径；否则 `loadFromCache` 命中 → 渲染（illust/caption/rows/avatar/related 触发）+ 写历史 + 触发 onDetailLoaded → `refreshFromNetwork().then()` 后台静默刷新 UI（rebuildRows/caption/authorFollowed；失败 console.error 不弹错）；未命中 → 原 `load` 完整路径不变。R7 壳页 prefetchOne 补 console.info（成功：id+来源 cache/api；代数中止：id+gen）。
- **Rationale**: store.load 的"命中缓存仍 await 网络"是转圈主体；拆分后滑动激活的渲染路径纯本地（DB 读 + 图片缓存文件），预取效果直接可见；后台刷新保证收藏态/编辑等新鲜度。历史写提前到缓存渲染点（用户已实际查看，先删后插幂等）。
- **Alternatives considered**: 命中即跳过网络刷新（弃用——收藏态/作者改名会长期陈旧）；仅加日志先诊断（弃用——根因已静态定位，日志仅作配套）。
- **风险**: 缓存陈旧场景（作品已被删）显示旧内容直到强刷——符合 FR-048 静默降级语义；refreshFromNetwork 与用户操作并发（如正在保存）——store.illust 替换是原子引用赋值，ArkUI 状态驱动刷新，无撕裂。

## Data Model

### AppSettings 新增字段（设备本地）

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| hapticFeedback | boolean | true | 触觉反馈总开关；GeneralSettingsPage SwitchItem |
| longPressSaveConfirm | boolean | false | 长按保存前确认；DownloadSettingsPage SwitchItem |

### HapticLevel（HapticUtils 内部语义类型）

字符串字面量联合：`'selectionClick' | 'light' | 'medium' | 'heavy'`，模块内映射至预置 effectId + intensity（或降级时长）。

### DetailListContext（DetailListContextRegistry）

| 字段 | 类型 | 说明 |
|---|---|---|
| ids | number[] | 当前已加载作品的 id 有序数组（MutedFilter 过滤后） |
| nextUrl | string | 续页游标，空串=无更多 |
| fetchNext | (nextUrl: string) => Promise<IllustListPage> | 续页闭包（R2 起支持历史类空续页：nextUrl 恒空） |

路由参数：`{ illustId: number, contextToken?: string, contextIndex?: number }`。

### BookmarkTag（ApiService.getBookmarkTags 返回元素）

| 字段 | 类型 | 说明 |
|---|---|---|
| name | string | 标签名（提交收藏时原样回传） |
| count | number | 使用次数（服务端返回则保留，用于排序展示） |

### 回顶令牌（AppStorage `tabRetapToken`）

字符串 `"<tabIndex>:<epochMs>"`；各页仅响应自身 tabIndex。

## Contracts & Interfaces

### 内部接口

| 接口 | 签名（描述） | 说明 |
|---|---|---|
| HapticUtils.selectionClick / light / medium / heavy | 无参静态方法，返回 void | 全局唯一震动入口；内部开关+节流+降级 |
| IllustWaterfall.scrollTopToken | `@Prop @Watch` number，默认 0 | 值变更即 scrollEdge(Top) |
| IllustWaterfall.onStarLongPress | 可选回调 `(illust: Illust) => void` | 缺省时容器内自建 BookmarkTagPanel 宿主 |
| BookmarkTagPanel | 入参：visible 双向绑定、illust、onConfirm(tags, restrict)、onCancel | 内联底部弹层组件 |
| FollowButton | 入参：userId、isFollowed、onChanged(newState) | 三态+长按菜单 |
| BookmarkStateStore.star | 既有签名追加可选 `tags: string[]` | 向后兼容，默认 `[]` |
| ApiService.getBookmarkTags | `(restrict: string) => Promise<BookmarkTag[]>` | 失败抛既有类型化错误，面板层捕获显错误态 |
| PixivLinkParser.parse | `(input: string) => PixivLinkTarget \| null`（纯函数） | 无副作用，可单测 |
| DetailListContextRegistry.register / get / append | register(ctx)→token；get(token)→ctx \| null；append(token, page) 追加续页 | 模块级单例 Map，上限 8 |
| IllustDetailPane | 入参：illustId、isActive（控制懒加载与接续登记时机） | 详情内容全套（图片行/信息行/相关/FAB/EXIF 弹层） |

### 外部接口（Pixiv app-api，新增）

| 端点 | 方法 | 参数 | 返回 |
|---|---|---|---|
| `/v1/user/bookmark-tags/illust` | GET | restrict=public/private | bookmark_tags 数组（name/count），经既有拦截器链与模型解析模式 |

### 权限变更

module.json5 `requestPermissions` 追加 `ohos.permission.VIBRATE`（normal 级，免运行时申请）。

## Changelog

- 2026-09-17 R2：新增 D10（相关作品滑动上下文）/D11（历史记录滑动上下文）/D12（下载行标题格式化修复）；D5 的"相关作品不启用滑动"备选结论被用户反馈推翻；Data Model 中 DetailListContext 增补"支持空续页"说明；Source Code 增补 R2 修改点（IllustDetailPane/HistoryPage/DownloadPage）。缘起：用户实测反馈（相关作品不可滑动、下载管理器异常）。
- 2026-09-17 R3：新增 D13（任务行缩略图 onError 三级回退）/D14（下载任务点击跳详情，复用 D11 无续页上下文）/D15（状态筛选 chips 纯展示层过滤）；写相册权限模型经官方文档核实为平台约束（SaveButton 点击授权窗口 vs 批量确认弹窗），维持现状不改（FR-028）。唯一修改文件：DownloadPage.ets。缘起：用户对齐 pixez JobPage 的反馈。
- 2026-09-17 R4：新增 D16（CaptionParser 纯函数 + Text/Span 简介富文本，Illust 补 caption 字段）/D17（Pane 内叠加顶栏+六项溢出菜单）/D18（缩放页底栏：HD 切换/复制图片 pixelmap/全屏开关）/D19（enqueue 返回 enqueued|inflight 四态 toast）/D20（分辨率行）/D21（相关作品 onReachEnd 自动加载）；翻译/举报/长按只存不收藏经用户确认排除（FR-035）。缘起：用户要求详情页全面对齐 pixez §2.2~2.5。
- 2026-09-17 R5：新增 D22（查看器底栏 pixez 化：去顶栏、底部单行图标栏、功能回调复用 R4）/D23（查看器分享图片：缓存文件 image utd 记录，未缓存置灰+toast；详情页分享保持链接）；加载百分比经用户确认不做（FR-039）。唯一修改文件：ImageViewerPage.ets。缘起：用户提供 pixez 截图要求底栏对齐 + 分享到微信/QQ 诉求（已说明面板目标由系统决定）。
