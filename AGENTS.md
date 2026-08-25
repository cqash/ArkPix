# AGENTS.md — ArkPix

HarmonyOS ArkTS Stage Model 应用（单模块 `entry`），API 12+ / SDK 6.1.0(23)，Hvigor 构建。Pixiv 第三方客户端。

## 构建与运行

- **构建**：`build_project` 工具（或 `hvigor assembleHap`）。运行前必须先构建。
- **运行**：`start_app`（模块 `entry`，Ability `EntryAbility`）。
- **调试**：`hdc_log collect` 或 `hdc hilog`。真机需完整路径 `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe`。
- 无 `package.json` 脚本；构建逻辑在 `hvigorfile.ts` / `entry/hvigorfile.ts`。

## 入口与导航

- `EntryAbility` → `AppStorage.setOrCreate('context', this.context)` + `webview.WebviewController.customizeSchemes(['pixiv'])`（注册 pixiv 自定义协议到 Web 内核，**必须在任何 Web 组件初始化之前**，否则 OAuth 完成跳 pixiv:// 会被系统 AppLinking 吞掉拿不到 code）+ `hoster.init()` + `hoster.refreshAll()`（DoH 主机解析）+ `localProxyServer.start()`（本地中继，供 WebView 走绕过）→ 加载 `pages/splash/SplashPage`；`onForeground` 经 **`import lazy`** 调 `syncService.onAppForeground()` 做回前台补偿同步（lazy 首次访问才加载模块，规避 onCreate 前模块求值闪退，见"常见陷阱"）；onCreate 末尾同法 lazy 调 `distributedSyncService.init()`（设备间同步，同样依赖 UserSettingStore 链）
- **多端流转（应用接续）**：module.json5 `continuable: true`；`onContinue(wantParam)` 版本校验（对端 versionCode < 1000000 返回 MISMATCH）后写入 `continuationService.buildWantParam()`（页面主动登记载荷，键 `continuationPayload`，<200B）；对端 `onCreate`/`onNewWant` 判 `LaunchReason.CONTINUATION` 时 `parseWant` 落 `AppStorage('continuationPayload')`；接续拉起走 **`onWindowStageRestore`**（非 onWindowStageCreate，不使用系统页面栈恢复，自行 loadContent SplashPage）；SplashPage 路由决策最前 `consumePendingPayload()` 一次性消费并按 page 类型 replaceUrl（illust_detail/home{tabIndex}/user_profile，未知回退主页，未登录回退既有逻辑）
- 页面状态登记（ContinuationService.setCurrentPageState，aboutToAppear 登记/aboutToDisappear 清 null）：IllustDetailPage（illustId）、HomePage（tabIndex，`.onChange` 同步更新；aboutToAppear 读路由参数 tabIndex 并 `tabsController.changeIndex()` 恢复）、UserProfilePage（userId）
- `SplashPage` 等 1.5s → `router.replaceUrl` 到 `HomePage`（已登录）或 `LoginPage`（`needsRelogin` 时先 toast 提示重新登录）
- `LoginPage` 右上角「设置」入口 → pushUrl 设置首页（登录前配置网络/中继；SettingsPage 同时是 @Entry 路由页与 HomePage Tab 子组件，两用法兼容）
- `HomePage` = `Tabs` 容器（RecomPage、FollowPage、RankPage、SearchPage、SettingsPage）
- 深层页用 `router.pushUrl` / `router.replaceUrl`（非 Navigation）。路由上限 32 页。
- 子登录页（WebViewLogin/TokenLogin）成功回调：`router.clear()` 清栈 + `router.replaceUrl` 到 HomePage（LoginPage 用 pushUrl 压底，仅 replace 换栈顶仍会退回登录页）
- WebViewLoginPage 的 code 捕获**双通道**：`onLoadIntercept`（https 回调）+ `WebSchemeHandler`（pixiv:// 自定义协议——onLoadIntercept 收不到它，须 `customizeSchemes` 注册 + `onControllerAttached` 里 `controller.setWebSchemeHandler('pixiv', handler)`，handler 内返回空 200 响应并 doLogin）
- TokenLoginPage：`extractToken` 兼容粘贴 JSON 导出内容（refreshToken/refresh_token 字段）并去内部空白；`accountStore.loginWithRefreshToken` 返回错误描述字符串（''=成功），区分凭证失效（含 refresh_token 轮换提醒）与网络错误，同 user.id 账号去重更新而非重复堆叠
- 所有注册页面在 `main_pages.json`（28 个，上限 32）：Index、Splash、Login、WebViewLogin、TokenLogin、Home、IllustDetail、ImageViewer、TagSearch、Bookmark、**Settings + 7 个设置分类子页（Browse/Download/Filter/Network/Relay/General/Account）**、Download、FilenameTemplate、ExifTemplate、ExifTagConfig、About、Mute、History、Comment、UserProfile

## 架构（entry/src/main/ets/）

```
pages/       — 页面（splash、login、home/*、search/*、detail/*、user/*、bookmark/*、settings/*；novel/NovelPage 未注册进 main_pages.json、无引用，是死代码占位）
             settings/ = 分类聚合结构：SettingsPage（首页 7 分类入口+摘要）+ SettingWidgets（共享行组件/Picker/选项数组/labelOf）+ 7 个分类子页（Browse/Download/Filter/Network/Relay/General/AccountSettingsPage）+ 既有功能页（DownloadPage/MutePage/HistoryPage 等）
components/  — 可复用组件
  common/    — CachedImage（@Watch('onUrlChange') 支持自定义 ratio/fit + 模块级导出函数 prefetchCachedImage 预取）、CommonViews（Loading/Error/Empty）、TagExifPicker（@CustomDialog，已无任何引用，死代码——实际 EXIF Picker 是 IllustDetailPage 内联弹层）
  illust/    — IllustCard（@Reusable 公共卡片：宽高比/角标/红心/长按菜单）、IllustWaterfall（瀑布流容器：分页/刷新/过滤/可选 compareFn 排序）
  viewer/    — ZoomableImage（PanGestureOptions.setDistance 动态 distance + .priorityGesture 优先级提升）
stores/      — AccountStore、UserSettingStore、BookmarkStateStore（收藏注册表单例）、IllustDetailStore（详情页编排，非单例）、CommentStore（评论页编排，非单例，主楼/回复楼双模式）
network/     — HttpClient + 拦截器链 + ApiService / OAuthService / PixivEndpoints + Hoster（DoH 主机解析）+ LocalProxyServer（本地 TCP 中继，WebView 用）+ RelayClient（自托管中继：register/refresh/relayRequest/buildImageUrl + 401 自刷新 + 502 回落）
services/    — PreferenceService（KV）、DatabaseService（relationalStore）、ImageCacheService、DownloadService、ImageExifService、SyncService（六域同步 LWW+墓碑）、RecoverService（已删作品恢复轮询）、RelaySelfTestService（六端点自检）、ContinuationService（接续页面状态登记+载荷构建/解析，纯内存+AppStorage 可静态 import）、DistributedSyncService（分布式数据对象设备间同步，EntryAbility 须 lazy import）
models/      — Illust、User、Novel、Comment、Bookmark、SearchHistory、MuteItem、DownloadTask、AppSettings、DohResponse、RelayModels、ContinuationPayload（接续/同步载荷模型+序列化解析纯函数，as 断言收敛于此）
utils/       — Constants（containsCjk/isAsciiOnly/filterTranslatedName、applyDirectIp/extractHost/normalizeMode/applyImageHost/isOauthUrl/isApiUrl/isImageUrl/直连 IP 常量）、CryptoUtils、MuteFilter（屏蔽过滤纯函数）、ImageUrlUtils（画质选档/整组页 URL）、ClipboardUtils（copyText 复制 + pasteText 读取，读取须在 PasteButton 临时授权窗口内）、HistoryExport（历史导出内容构建纯函数）、MergeSuggest（合并对话框补全候选纯函数）、DateUtils（formatCreateDate：ISO→本地时区 yyyy-MM-dd HH:mm，失败返回 ''）
```

## 状态管理

- Store 单例导出：`export const store = StoreClass.getInstance()`
- 全局响应式状态通过 `AppStorage.setOrCreate()` / `AppStorage.get()`（如 `isLoggedIn`、`appSettings`）
- 页面用 `@State` / `@StorageLink` 绑定。Store 方法返回值不统一（UserSettingStore setter 多为同步 `void`；BookmarkStateStore.star/unstar 返回 `Promise<boolean>`）。
- `UserSettingStore.getSettings()` 每次返回新 `AppSettings` 实例（防御性拷贝）；修改后需重新赋值 `this.settings = userSettingStore.getSettings()` 触发 UI 刷新。
- AppStorage 同步依赖引用变化：`bookmarkStates` 每次变更必须整体替换新 Map 引用。

## HTTP 与网络

- 使用 `@kit.NetworkKit` 的 `http` 模块（兼容模式走 `http` 直连 IP；OAuth token 接口走 `@ohos.net.socket` 的 `TLSSocket` 手写 no-SNI POST）。`HttpClient` 单例包装 + 拦截器链。
- **网络模式三档（对齐 pixez）**：`standard`（标准直连）/ `compatible`（兼容：直连 Pixiv 真实 IP + 不发 SNI + 跳过证书校验，绕过 GFW SNI 封锁）/ `ech`（增强：ECH，鸿蒙无原生支持，行为等价 compatible）。认证与 API 服务各一个独立开关（`authMode`/`apiMode`），旧值 `sni`/`doh`/`bypass` 经 `Constants.normalizeMode()` 归一化为 `compatible`。
- **OAuth token 接口按 auth_mode 三档分流**（`OAuthService.postToken`）：`standard` → `postTokenStandard`（正常 `http` 模块 HTTPS，走系统 DNS/VPN/代理，开 VPN 时必须用这档）；`compatible`/`ech` → `postTokenNoSni`（`TLSSocket` 手写 no-SNI POST：先 `bind 0.0.0.0:0` 再 connect——不修会报 2303600 No bind socket；IP 优先取 `hoster.resolveIps` 的 DoH 结果而非硬编码常量；connect timeout 15s + 20s 兜底定时器防挂起卡死）；`relay` → `postTokenViaRelay`
- **X-Client-Time / X-Client-Hash 必须用同一次 `CryptoUtils.getIsoDate()`**（精度到秒，分两次取跨秒即不匹配 → Pixiv 400 → 被误判 CredentialInvalidError 误登出，这是历史"容易掉登录"根因）；refresh_token 拼表单须 `encodeURIComponent`
- 兼容模式实现（API/图片 `http` 请求）：`Constants.applyDirectIp(url)` 把 Pixiv 域名改写为直连 IP（app-api/oauth→`210.140.139.155`，i.pximg/s.pximg→`210.140.139.133`），`Constants.extractHost()` 提取原域名写入 `Host` 头，`http` 请求加 `remoteValidation:'skip'` + `sniHostName:''`
- 图片（`ImageCacheService`/`DownloadService`）：`applyImageHost`（图床 default/optional/custom 域名切换）→ `applyDirectIp`（直连 IP）→ `Host` 头 + `remoteValidation:'skip'`。
- 拦截器顺序：AuthInterceptor → RetryInterceptor → LogInterceptor（无 CacheInterceptor）
- `AuthInterceptor`：注入 `Authorization: Bearer` + `Accept-Language: zh-CN`；鉴权错误（401，或 400 且错误体含 invalid access token / invalid_grant 等 OAuth 错误，见 `isAuthErrorResponse()`）自动 refresh token + 队列化并发请求 + 120s 刷新节流 + 重放后用同一宽判定最终校验
- `OAuthService.refreshToken()`：校验 `responseCode===200 且 access_token 非空 且 user.id 非空` 后才写回 token；失败抛类型化错误 `CredentialInvalidError`（凭证失效，登出并置 needsRelogin）/ `NetworkError`（临时故障，不登出）
- `LocalProxyServer`（单例，`127.0.0.1:10809`）：本地 TCP 中继，`on('connect')` 解析 CONNECT/HTTP 请求，上游用 `TCPSocket` 直连。目前仅 WebView 登录页（`webview.ProxyController.applyProxyOverride` + `insertProxyRule`）走它；HTTP/API 已改走 `http` 直连 IP，不再经过中继。SNI 分片（fragment）逻辑已保留但实测无效。
- 列表分页：`ApiService.fetchNext(nextUrl)` 通用游标续页，配合 `IllustWaterfall` 分页状态机
- OAuth2 认证（`oauth.secure.pixiv.net`），token 通过 `PreferenceService` 持久化（access_token 约 1 小时有效；refresh_token 轮换制，每次刷新后新 refresh_token 写回 `AccountStore.saveAccounts()`，多设备共用同一 refresh_token 会导致旧 token 作废）
- `Constants.applyProxy(url)`（`PROXY_HOST` 为空，目前是空壳）在 `HttpClient.request()` 内仍会调用；真正的域名改写走 `applyDirectIp`/`applyImageHost`
- 图片下载需 `Referer: https://app-api.pixiv.net/` + `User-Agent: PixivIOSApp/5.8.0`（`Constants.IMAGE_USER_AGENT`），在 `DownloadService` 和 `ImageCacheService` 内处理（拦截器不注入图片头）

## 列表与收藏同步

- 所有插画列表（推荐/动态/排行/搜索/标签/收藏/用户作品）统一使用 `IllustWaterfall` + `IllustCard`；页面只需提供 `fetchFirst(): Promise<IllustListPage>` 与可选 `reloadToken`（变更触发重载）
- `IllustWaterfall` 可选入参 `compareFn?: (a, b) => number`：提供时入库数据按之排序，分页追加后全量重排；切换排序由页面递增 `compareToken`（@Prop @Watch）触发已加载数据重排。到达序反转比较器 `compareArrivalReverse`（WeakMap 记录入库顺序，收藏"旧→新"用）由容器导出
- 卡片按真实宽高比展示（高/宽>3 降级方图）；数据入库时经 `MuteFilter` 过滤（屏蔽词/屏蔽作者/AI 过滤）并 `BookmarkStateStore.seedFromList` 播种
- 收藏状态三态注册表 `BookmarkStateStore`：`Map<illustId, 0|1|2>`（未收藏/请求中/已收藏），变更时以**新 Map 引用**写入 `AppStorage['bookmarkStates']` 驱动 `@StorageLink` 刷新；star/unstar 含请求中锁、失败回滚、toast、详情缓存失效
- 详情页（IllustDetailPage）= 单 `List` 行模型（image 行×pageCount + info 行 + related_header 行 + related 行，每个 related 行装 3 个作品），数据编排在 `IllustDetailStore`；多页查看器 `ImageViewerPage` = `Swiper + ZoomableImage`
- **ZoomableImage 手势方案（禁止回退条件手势组）**：`GestureGroup(Parallel, Pinch+Pan+Tap)` 静态常驻挂载；`PinchGesture({fingers:2, distance:1})`；`PanGestureOptions.setDistance()` 动态更新 distance（scale=1→50vp 让位 Swiper 翻页，scale>1→3vp 跟手平移），在 `applyScale()` 末尾调用；`.priorityGesture()` 绑定手势组（优先于 Swiper 内置手势）；拖到 X 向边界继续外拖时 `onZoomChange(false)` 释放回 Swiper，松手恢复；契约回调为 `onZoomChange(isZoomed)`，父级 `Swiper.disableSwipe` 直接绑定该标志；双击 1↔2.5 切换，限幅 1~5 + 边界钳制
- 用户主页统计字段在 `/v1/user/detail` 响应的 `profile` 对象内（非 user 对象）：`User.ets` 的 `ProfileStats` + `profileStatsFromJson()` 解析（totalFollowUsers/totalIllusts/totalManga/totalIllustBookmarksPublic）
- 排行页（RankPage）：`@StorageLink('appSettings')` 监听设置，R18 排行开关（showR18Rank）变更即时过滤 R18 排行模式；排行接口失败（如 400）时回退 DB 排行缓存（getRankingCache）

## 下载与 EXIF

- `DownloadService` 单例：下载到 `cacheDir/downloads/`，写图库走双通道（见下）
- **写图库双通道（勿回退）**：`WRITE_IMAGEVIDEO` 是 ACL 白名单权限（普通签名装不上，安装报 9568289），`WRITE_MEDIA/READ_MEDIA` 声明对媒体库无效。①**静默通道**：`applySilentToGallery`（`MediaAssetChangeRequest.createImageAssetRequest` + `applyChanges`）——仅在 **SaveButton 安全控件点击后的临时授权窗口内**可用（首次点击 SaveButton 系统弹一次授权，之后不弹；API≤19 窗口 10s，API≥20 窗口 1 分钟）；②**兜底通道**：静默失败的路径攒入 `pendingGalleryPaths`，队列排空后 `flushGalleryIfIdle` 一次 `showAssetsCreationDialog` 批量系统确认弹窗——**该弹窗只创建目标 uri，必须用 `fileIo.copyFile` 把沙箱内容拷入**，否则媒体库是空壳不显示（历史"保存成功但图库无图"根因）
- **多任务并发调度层**：公开入口 `enqueue(url, illust, pageIndex)`（fire-and-forget）：先写 DB `pending` 记录入内存 FIFO 队列，`activeCount < 上限` 立即执行否则排队，任务结束补位；上限每次调度时读 `userSettingStore.getSettings().downloadConcurrency`（1-5 默认 3，配置即时生效，进行中任务不受影响）；`downloadToCache` 已转 private，任务体=下载+finalize+静默写图库（失败攒批）+状态落库+notifyTaskChanged；`retryAllFailed` 内部走 enqueue（started=入队数，succeeded/failed 不再同步统计）；`inflightTaskIds` 在途去重防止同一页并发重复入队；下载时自动收藏（autoBookmarkOnDownload）在入队时触发（非完成时）；应用重启后残留 pending/downloading 按既有规则重置 failed，不自动恢复排队；完成/失败有 toast（showToastSafe：已保存到图库 / 已保存 N 张到图库 / 下载失败）
- 下载任务状态：`pending`（排队中）/ `downloading` / `completed` / `failed`，DownloadPage 列表展示"排队中"
- 文件名模板：默认 `{illust_id}_p{part}`，支持 `{user_id}`、`{user_name}`、`{title}`。模板在 `FilenameTemplatePage` 配置。
- `ImageExifService`：嵌入 EXIF 元数据（ImageDescription=`{title} | PID:{id}`、Artist=`{userName} (UID:{id})`、UserComment=模板渲染、Copyright='Pixiv'），另写 XMP 旁挂（JPEG APP1 / PNG iTXt），字段值超 120 UTF-8 字节时截断（`clampExifField`）。按格式分流：JPEG 保留 JPEG（系统 API 重打包或字节级注入不重编码）、PNG 保留 PNG（`embedPng` 系统 API EXIF + iTXt XMP 双载体，失败降级纯 XMP）、GIF 不嵌入。
- 下载任务状态通过 `DatabaseService` 追踪（pending/downloading/completed/failed）。DB 初始化时将 downloading/pending 重置为 failed。
- `DownloadService` 批量/去重方法：`isDownloaded(illustId, part)`（completed 记录 + `fs.access` 文件存在双条件，DB 异常降级 false）；`retryAllFailed()`（failed 任务逐条重建入队，onTaskDone 回调，返回分类计数 `RetryAllResult{started,succeeded,failed,skipped}`，started=入队数，succeeded/failed 不再同步统计，元信息缺失计 skipped）；`clearTasksByStatus(status)`（仅删记录不删文件，返回删除数）。DB 侧配套 `getDownloadTaskById` / `deleteDownloadTasksByStatus`
- 任务变更事件：DownloadService `register/unregisterTaskChangeListener` 回调注册表，任务完成/失败时触发；DownloadPage 可见期注册 + 1.5s 轮询静默刷新（refreshTasksSilently 不置 isLoading 防闪烁），aboutToDisappear 清理
- 下载重复检测：所有下载入口（详情页 savePage/savePages/saveAll、查看器保存、卡片长按保存）先按 插画ID+页码 查 `isDownloaded`，命中统一走 `getUIContext().showAlertDialog`（跳过已下载页/全部重新下载，`AlertDialog.show` 静态方法已废弃不可用）；`IllustDetailStore.uiContext` 由宿主页面 aboutToAppear 注入。saveAll 的原 showActionSheet 例外已迁移为 AlertDialog，ActionSheet 例外清零

## EXIF 标签系统

### 核心数据结构

- `ExifTag`: `{ name: string, translatedName: string }` — 原始 tag 名 + API 翻译名（定义在 `services/ImageExifService.ets`）
- `ExifTagMergeRule`: `{ mainTag: string, fromTags: string[] }` — 去重式合并规则（定义在 `models/AppSettings.ets`）
- `MergeGroup`: `{ translatedName: string, tags: ExifTag[] }` — 同义 tag 组（审查弹窗用，定义在 `services/ImageExifService.ets`）
- `AppSettings` EXIF 相关字段：`embedExifMetadata`、`exifCommentTemplate`、`exifMutedTags`、`exifMergedTags`、`exifTagPriority`、`showTranslatedTags`、`autoMergeTranslatedTags`（**死开关**：管线自动合并步骤移除后已无任何代码读取，仅剩持久化和设置页开关，勿依赖其行为）

### 翻译过滤（filterTranslatedName）

Pixiv API 在 `Accept-Language: zh-CN` 时会将 CJK tag "翻译"成英文（爱莉希雅→Elysia），对中文用户无意义。
- `Constants.filterTranslatedName(tagName, translatedName)`：tagName 含 CJK + translatedName 纯 ASCII → 视为无意义翻译，返回空串
- 日文→英文同理被过滤（エリシア→Ellicia）
- 所有显示和 EXIF 写入点统一调用此函数（例外：合并审查弹窗内有意展示原始未过滤的 translatedName，供用户判断同义关系）

### EXIF 标签处理管线（filterTagsForExif）

4 步管线，输入 `ExifTag[]` + `AppSettings`，输出过滤后 `ExifTag[]`：
1. **屏蔽**：移除 `exifMutedTags` 中的 tag
2. **手动合并**：遍历 `exifMergedTags` 规则——mainTag 在列表则移除 fromTags；mainTag 不在则将首个 fromTag 替换为 mainTag（保留翻译名）
3. _(Step 2.5 已移除自动合并，改由审查弹窗处理)_
4. **优先级排序**：按 `exifTagPriority` 顺序排前，其余保持原序追加

### 同义标签合并检测（findUnresolvedMergeGroups）

3 种检测方式，不受 `autoMergeTranslatedTags` 开关门控（审查弹窗本身需用户确认）：
- **A) 原始 translatedName 相同**：如 女の子/女孩子 都翻译为"女孩子"
- **B) 有效翻译匹配另一 tag 名**：如 崩壊3rd→崩坏3rd + tag 崩坏3rd 存在；崩坏3rd→崩坏3 + tag 崩坏3 存在
- **C) CJK→ASCII 被过滤的翻译匹配另一 tag 名**：如 爱莉希雅→Elysia（过滤）+ tag Elysia 存在

排除已在 `exifMergedTags` 规则中覆盖的组（组内所有 tag 名都在**所有规则**的 mainTag/fromTags **并集**中，允许跨多条规则拼覆盖）。

### 合并审查弹窗流程

1. 时机：点击**保存**按钮时触发（`handleSavePage/handleSaveAll`），不在页面加载时打断
2. `hasUnresolvedMergeGroups()` 预检 → `checkMergeReview()` 弹窗
3. 用户每组选一个主 tag → 确认 → 写入 `exifMergedTags` 规则 → toast 提示"请再次点击保存"
4. 跳过则不持久化，下次保存仍会弹出
5. 弹窗内层内容区用 `.onClick(() => {})` 消费点击事件防止冒泡到外层遮罩关闭弹窗；禁止对覆盖层容器使用 `.hitTestBehavior(HitTestMode.Block)`——实测会导致自带手势子组件选中需点两次/有延迟（cd20189），且会完全挡住 TextInput/按钮交互（MergeDialogOverlay 原 Block 已移除，统一为 .onClick 方案）

### EXIF Picker（IllustDetailPage 内联底部弹层）

- 实现形态：IllustDetailPage 内联 Stack 底部弹层（`exifPickerShown`）。`components/common/TagExifPicker.ets`（@CustomDialog）是早期独立组件版本，已无任何引用，属死代码
- 触发：渲染后的 EXIF 备注超 **120 UTF-8 字节**（`EXIF_FIELD_MAX_BYTES`，设备图库扫描器约 128 字节上限）且 `embedExifMetadata` 开启时，保存前弹出（在合并审查通过之后）
- 可写入区：勾选/取消勾选（取消=跳过本次，不持久化）；拖拽排序（`onMove`，确认后写入 `exifTagPriority`）；长按屏蔽手势仅绑在左侧 Checkbox+文字区域，右侧把手 `≡` 不绑长按以避免与拖拽排序冲突
- 长按 tag → 二次确认 → 移入弹层内屏蔽区列表；点"确认"时才写入 `exifMutedTags` 持久化（点"跳过"则屏蔽不持久化）
- 屏蔽区"恢复"按钮移回可写入区
- 预览区实时显示渲染结果和字节数（x / 120 字节，超限变红）

### 模板变量

- `{tags}`：原始 tag 名（逗号分隔）
- `{tags_translated}`：带翻译的 tag 输出（tag名(翻译) 格式）
- `{tags_localized}`：纯目标语言 tag 输出（优先中文翻译，无翻译保留原文）
- 替换顺序：`{tags_localized}` → `{tags_translated}` → `{tags}`（最长前缀优先防误替换）
- 其他变量：`{illust_id}`、`{user_id}`、`{user_name}`、`{title}`、`{part}`

### EXIF 标签管理页（ExifTagConfigPage）

- 查看/编辑合并规则、屏蔽列表、优先级排序
- 导入/导出（JSON 格式）

## Relay 与数据同步

- **写钩子多监听 fan-out**：UserSettingStore/DatabaseService 写钩子已升级为监听器数组（`addSettingsWriteHook`/`removeSettingsWriteHook`、`addSyncWriteHook`/`removeSyncWriteHook`；`setXxxWriteHook` 保留为"清空后单注册"兼容包装）。Relay SyncService 与 DistributedSyncService 均用 add 语义注册，互不覆盖（注意 init 顺序：Distributed 在 EntryAbility onCreate，SyncService.init 在其方法内惰性触发——若用 set 语义后者会清掉前者的钩子）
- **push/pull 游标顺序铁律（勿回退）**：服务端 syncToken 的 seq 水位随 push 跳到 ≈ 当前时间戳（后端 `max(上一水位+1, nowMs)`），pull 只返回 `seq > since` 的条目。因此**任何 push 前必须已做过一次全量 pull**，否则游标会越过后端已有条目且之后增量 pull 永远拉不到（历史"同步不下来了"的根因）。实现：① `ensureInitialPull(domain)`——每域偏好 `sync_initial_pulled_<domain>` 记录"是否完成过全量 pull"；未标记且游标非空（存量被污染）→ 重置为 `''` 做全量 pull（LWW 合并，不清本地）；② `pushDomain` 开头先 `ensureInitialPull`，push 后按 **push 前游标** 补拉一轮（`pullDomain(domain, prePushCursor)`），捕获窗口期其他设备的写入（自推条目 LWW 幂等跳过）；③ `pullDomain` 支持 `sinceOverride`，全量 pull 成功后置初始标记；④ `startupPull`/`onAppForeground` 每域先 `ensureInitialPull` 再增量 pull，存量被污染游标会在下次启动/回前台自动修复。另：history/search_history 的墓碑 applier 同样走 LWW（`shouldApplyRemote`），避免全量重拉时旧墓碑误删本地更新条目
- **设备间同步（DistributedSyncService，分布式数据对象通道）**：与 Relay SyncService 双通道共存互不耦合。单 distributedDataObject，根属性 = `settingsJson`/`historyJson`/`searchHistoryJson`/`metaJson` 四个 JSON 字符串 + `updatedAt`（复杂类型仅根属性变更触发同步，载荷必须保持根属性 JSON 字符串设计）；固定 sessionId `arkpix_device_sync`。设置域载荷含 AppSettings 可同步字段（含 muteTags/muteUsers/exifMutedTags/exifMergedTags/exifTagPriority），排除 deviceSyncEnabled/autoSyncForeground/syncEnabled/relayServerUrl/prevAuthMode/prevApiMode 设备本地字段；浏览相关设置（picture/manga/preview/detail/fullScreen 画质 + crossCount + isTopMode）亦为设备本地（因屏幕尺寸差异），分布式与 Relay 双通道均不同步（FR-012 全通道排除，Relay 侧接口无声明天然跳过旧残留字段）；历史裁剪最近 100 条浏览 + 50 条搜索。冲突复用 LWW：设置整体按 metaJson.updatedAt 严格大于才应用（本地已应用时间存偏好 `distributed_sync_applied_settings_at`，metaJson.deviceId 识别自身回声）；历史条目级走 hook-free `upsertHistory`/`upsertSearchHistory`（内部 getXxxTimestamp 判新，无回声）。下行应用期间 `applyingRemote` suppress 本地写钩子防回声。DataObject 根属性读写经 `Reflect.get/set`（ArkTS 禁动态索引，DataObject 接口无字段声明）。权限 `ohos.permission.DISTRIBUTED_DATASYNC`（module.json5 已声明）：首开 GeneralSettingsPage 开关时 `abilityAccessCtrl.requestPermissionsFromUser` 运行时申请，拒绝则开关回退 + toast；init 时仅尝试入会话不弹窗（201 静默降级纯本地）
- `AppSettings.deviceSyncEnabled`（默认 true）：设备本地开关，不参与任何同步域、不触发写钩子（避免"关同步被同步到对端"悖论）；GeneralSettingsPage 顶部"设备间同步"分组（开关 + 状态文字 未开启/未授权/已加入会话）
- 中继设置页（RelaySettingsPage）：服务器地址/注册登录、数据同步开关、**自动同步开关**（`autoSyncForeground` 默认开，设备本地不同步上行；回前台经 SyncService `onAppForeground` 5 分钟节流补偿 pull+flush push）、立即同步、**导入/导出同步账号**（导入=PasteButton 剪贴板/DocumentSelectPicker 文件，兼容纯文本 key 与 `arkpix-sync-account.json`；导出=复制/文件双通道）、后端自检、注销
- 自检探针目标：API 中继打 `app-api.pixiv.net/v1/walkthrough/illusts`（勿用 www.pixiv.net——经代理出口易被 Cloudflare 拦出 500）；图片中继用 `s.pximg.net/common/images/no_profile.png`（novel_bg.png 上游已 404）
- 导入账号 = `relayClient.register(serverUrl, deviceName, '', accountKey)` 覆盖本机注册并加入既有同步账号，成功后自动触发一轮 syncNow
- 服务端部署：`.env` 必须 CRLF 换行（`start.bat` 的 `for /f` 解析不了 LF）；`UPSTREAM_PROXY` 配上游代理（Go `http.ProxyURL` 支持 http/socks5，v2rayN 10808 混合端口可直接用）；`IMG_EXTRA_HOSTS` 须声明恢复源镜像域名

## 弹窗风格约定

- 多选项菜单：`bindContextMenu`
- 二选一确认：`AlertDialog`（通过 `getUIContext().showAlertDialog`）
- 多值选择：`TextPickerDialog`
- 不使用 `ActionSheet`（底部大弹窗）。原 `IllustDetailStore.saveAll` 的 showActionSheet 例外已迁移为 AlertDialog，例外清零
- 弹窗覆盖层内层内容区用 `.onClick(() => {})` 消费点击事件防冒泡关闭；禁止 `.hitTestBehavior(HitTestMode.Block)`（会挡住子组件交互，MergeDialogOverlay 的 Block 例外已移除）
- 读剪贴板必须走 **PasteButton 安全控件**（点击获临时授权窗口，窗口内调 `ClipboardUtils.pasteText()`；普通读取需 READ_PASTEBOARD 受限权限，勿申请）；写剪贴板 `copyText` 无需权限
- bindContextMenu 菜单项内若要 toast/弹窗：先 `menuShown=false` 并 `setTimeout(300)` 后再执行（否则 toast 被菜单弹层吞掉）；页面内 toast 优先走 `getUIContext().getPromptAction().showToast()`（HistoryPage 已按此修复）

## 防社死模式

- `AppSettings.antiSocialDeath`：R18 图片在 IllustCard/IllustDetailPage/ImageViewerPage 显示纯色遮罩 + 🔒 锁图标（卡片/详情为灰色 `#E0E0E0`，查看器为深灰 `#2C2C2C`，无模糊效果）
- 详情页/查看器点击遮罩单向揭示（无再次点击恢复逻辑）；IllustCard 无揭示交互（点击整卡直接进详情页）

## 详情页交互

- Tag 长按菜单（bindContextMenu）：复制标签名 / 屏蔽该标签 / 备注中屏蔽 / 备注中合并
- 图片长按菜单（bindContextMenu）：保存当前页 / 保存全部页——仅多页作品长按才弹菜单；单页作品长按直接保存，不弹菜单
- 合并对话框：输入主 tag 名 → `addExifMergeRule`；输入框带补全建议（本地 exifMergedTags mainTag/fromTags + 本作品 tag 即时前缀匹配去重，仅本地零匹配且停顿 ≥300ms 才调 getAutoComplete API，点选回填；纯函数在 `utils/MergeSuggest.ets`）
- InfoRow 展示 `PID: {id}`，长按复制到剪贴板（ClipboardUtils + toast）；统计区含发布日期行（`formatCreateDate(illust.createDate)` 本地时区 yyyy-MM-dd HH:mm，空串不渲染该行）
- 操作区 = 根 Stack（BottomEnd）右下角双 FAB：收藏 FAB（bookmarkState() 驱动——未收藏=Text('♡') 浅灰 #999999、已收藏=Text('❤') 红 #FF4081、请求中灰色，点按 toggleBookmark，长按公开/私密菜单）+ 下载 FAB（**SaveButton 安全控件**，Circle 图标+蓝底 #0096FA，点击授权成功后单击=handleSaveAll()（多页）/handleSavePage(0)（单页），长按手势挂在外层 Stack 上仅多页=打开选页弹窗；安全控件不支持深度自定义，勿换成普通按钮——普通按钮拿不到图库临时授权，静默保存会失效回退到系统确认弹窗）；EXIF Picker/合并审查/合并对话框/选页弹窗任一打开时隐藏 FAB；原 InfoRow 按钮区已移除
- **选页弹窗**（IllustDetailPage 内联覆盖层，半透明遮罩+底部弹层）：4 列缩略图网格（CachedImage squareMedium 方图 + 勾选角标 + 页码角标，防社死页纯色遮罩不揭示），全选/清空，取消/确定下载(N)（空选择不发起）；多选交互=单击单格切换 + 长按≥300ms 激活拖选（起始格定方向、PanGesture 滑动按经过格区间批量置目标状态、拖前快照重算）；Grid 用 `.priorityGesture(PanGesture(PanGestureOptions))` + 动态 distance（普通 10000vp 让位滚动，拖选 1vp 即触）+ `onDidScroll` 累计滚动偏移换算触点格索引；确认走 `handleSavePages(selected)`（合并审查预检→EXIF Picker 续走 `exifPickerPendingPages`→`store.savePages`）；EXIF Picker 续走状态为 `exifPickerPendingPages: number[]`（单页=[i]、全集、子集三分支 resumeSaveAfterPicker）
- "查看评论"= tag 云之后、相关作品之前的居中小号文字按钮 → CommentPage `{ illustId, illustTitle }`

## 历史记录与导出

- HistoryPage（设置→历史记录）：Tabs（浏览历史 / 搜索历史）。浏览 Tab 网格展示 `history` 表（时间倒序，CachedImage + 标题 + 作者），点击进详情；搜索 Tab 关键词列表，点击进 TagSearchPage
- 搜索历史覆盖 tag 跳转：`TagSearchPage.aboutToAppear` 单点写 `addSearchHistory(keyword, 'illust')`（详情页 tag 点击与历史回放共用入口；回放重写仅刷新时间戳，走既有先删后插去重）
- `DatabaseService.addHistory` 按 illust_id 去重（history 表 illust_id 无 UNIQUE 约束，先 DELETE 再 INSERT）；`getHistory` SQL 按 illust_id 分组取 MAX(id) 合并展示（兼容存量重复数据，不清理 DB），默认 limit 500
- 顶部 ⋮ 菜单（bindContextMenu）：导出 JSON（`buildHistoryExportJson`，version/appName/type/exportedAt/count/items）/ 导出 PID 列表（`buildHistoryPidText`，每行一个）/ 清空浏览历史（AlertDialog 确认）；导出走 DocumentSavePicker（arkpix-history.json / arkpix-history-pids.txt），空历史 toast 不弹选择器

## Token 导出

- 设置→账户组"导出 Token"→ 单 AlertDialog（风险警告 message + primaryButton"复制到剪贴板" + secondaryButton"导出为文件"，遮罩/返回=取消）
- 数据源 `accountStore.getCurrentAccount()`（null/空 token 时 toast"无可用 token"）；文件默认名 `arkpix-token.json`，含 version/userId/userName/account/refreshToken/exportedAt（不含 access token）
- 剪贴板统一走 `ClipboardUtils.copyText(text): Promise<boolean>`（pasteboard createData(MIMETYPE_TEXT_PLAIN) + setData，写剪贴板无需权限）

## 搜索扩展

- SearchPage 输入纯数字时显示"插画 ID 直达"（→IllustDetailPage `{illustId}`）与"画师 ID 直达"（→UserProfilePage `{userId}`）；直达块在 `if (!this.hasSearched)` 门控之外、输入框 Row 之下两分支共用位置（@Builder NumericDirectEntries）——曾在门控内因 hasSearched 永真不可见（回归已修复）；无效 ID 由目标页错误态兜底；PID/UID 直达与搜索提交均写搜索历史
- 结果区 Tabs（插画 / 画师）：插画 Tab 为原 IllustWaterfall；画师 Tab 用 `apiService.searchUsers` + `fetchNext` 游标分页。/v1/search/user 响应 `user_previews[]` 元素是**包装对象** `{user, illusts, novels, is_muted}`，必须先取 `.user` 再喂 `UserPreview.fromJson`（不解包会全部落空成灰头像"@"）；点击进 UserProfilePage
- SearchPage 支持可选路由参数 `{keyword?, tab?}`：keyword 预填并自动提交，tab='user' 初始定位画师 Tab（Tabs 构造参数 index 仅创建时生效）；搜索历史 search_type 四类：`illust`（插画词）/`user`（画师词，按提交时所在 Tab 记录）/`pid`/`uid`（数字直达）；`addSearchHistory` 按 keyword+search_type 先删后插去重
- HistoryPage 搜索历史 Tab：条目带类型标识（插画/画师/PID/UID），点击按类型回放（illust→TagSearchPage、user→SearchPage{keyword,tab:'user'}、pid→详情、uid→用户主页）；浏览历史 `getHistory` SQL 按 illust_id 分组取 MAX(id) 合并展示（不动存量数据，导出共用此查询自动一致）

## 评论区

- CommentPage 路由参数 `{ illustId, illustTitle?, parentCommentId?, replyToName? }`；`parentCommentId` 存在即回复楼模式（同页复用 push，标题"回复列表"）
- CommentStore（非单例）：`loadFirst`（/v3/illust/comments）/ `loadReplies`（/v2/illust/comment/replies）/ `loadMore`（fetchNext 游标，按 id 去重）/ `postComment` / `postReply`（POST /v1/illust/comment/add，form 编码 illust_id/**comment**/可选 parent_comment_id——字段名必须是 comment，误用 text 会触发服务端 500）
- 发表成功主楼插列表头、回复楼追加尾部；失败 toast 且输入内容不丢失；TextInput maxLength 140
- 列表行：头像 + 用户名 + 时间 + 正文（comment 为空且含 stamp 显示"[贴图]"）+ 回复前缀"回复 @xxx"（replyToUserName，来自 parent_comment.user.name）+ 主楼模式 hasReplies 时显示"查看回复"
- `models/Comment.ets`：commentFromJson/parseCommentListPage 遵循 fromJson→Options→new Model 模式；UserPreview 从 ./Illust 导入

## ArkTS 严格约束

- 禁止 `any` / `unknown` / `as` 类型断言 / 动态属性访问 / 结构类型
- 对象字面量必须有显式类型上下文
- `@Builder` 内不能用 `let` 声明局部变量，用成员方法代替
- `build-profile.json5`：`strictMode: { caseSensitiveCheck, useNormalizedOHMUrl }`
- 构建 type-error 时检查：缺少显式类型、不安全转换、动态访问
- ArkUI List 拖拽排序优先用 `onMove`（官方推荐，API 12+，天然兼容 List 滚动，无需长按触发）；旧方案 `onItemDragStart`/`onItemDrop` 需长按触发，与 LongPressGesture 冲突

## 代码质量

- `code-linter.json5`：`**/*.ets`，忽略 test/ohosTest/mock/build/node_modules/oh_modules/.preview
- 规则：`@performance/recommended`、`@typescript-eslint/recommended`
- 安全规则：`@security/no-unsafe-aes`、`no-unsafe-hash` 等为 error/warn

## 测试

- 单元测试：`@ohos/hypium`，`entry/src/test/`
- 仪器化测试：`entry/src/ohosTest/`
- Mock：`@ohos/hamock`（开发依赖）
- 无 CLI 测试脚本；通过 DevEco Studio 或 `hvigor test`

## 权限（module.json5）

`INTERNET`、`GET_NETWORK_INFO`、`WRITE_MEDIA`、`READ_MEDIA`、`DISTRIBUTED_DATASYNC`（设备间同步，运行时申请，见"Relay 与数据同步"节；WRITE_MEDIA/READ_MEDIA 对媒体库写入无实际效力，写图库靠 SaveButton 临时授权 / showAssetsCreationDialog，见"下载与 EXIF"节；`WRITE_IMAGEVIDEO` 为 ACL 白名单权限，勿声明——会导致安装失败 9568289）

## 常见陷阱

- `HttpClient` 单例，不要 new。拦截器在 `ApiService` 构造函数中注册（Auth → Retry → Log）。
- `AccountStore` 构造时自动加载持久化账号 + 同步 token 到 `AuthInterceptor` + 注册 refresh handler。
- `Constants.applyProxy()` 在 `HttpClient.request()` 内已处理（空壳）；实际域名改写由 `Constants.applyDirectIp()`（兼容模式）与 `Constants.applyImageHost()`（图床）负责，均在 HttpClient/ImageCacheService/DownloadService 内部自动调用，无需手动调用。
- Pixiv 图片 URL 需特殊 Referer/User-Agent 头；在 DownloadService 和 ImageCacheService 内处理（拦截器只注入 Authorization/Accept-Language，不管图片头）。
- `Index.ets` 是脚手架占位符；真正入口是 `EntryAbility` → `SplashPage`。
- 混淆已禁用（`entry/build-profile.json5` `enable: false`）。
- `User.ets`、`Illust.ets`、`Novel.ets` 各自定义了 `ImageUrls` 类（同名但独立），不要混用导入。
- 模型 JSON 反序列化模式：`fromJson(raw)` → 返回 `*Options` 接口 → `new Model(opts)`。`fromJson` 内用 `as RawXxx`（仅限此内部层）。
- 应用名 **ArkPix**（bundle 仍为 `com.example.pixez`）。
- `arkts_check` 对 `@kit.*` 引用固定报 6 条 SDK d.ts 错误，属环境噪音，可忽略。
- **ForEach 行不刷新陷阱**：`@State` 数组 + 自定义 keyGenerator 时，同 key 子组件复用不重建，普通对象（非 @Observed）属性变化观察不到——行内显示的可变字段必须参与 key 生成（如自检 `name|status|durationMs`、下载任务 `id|status|progress`），或 Service 端替换元素引用而非原地改属性
- **Scroll 内容居中陷阱**：Scroll 设了高度限制（layoutWeight/height）后内容不足一屏时**默认垂直居中**而非顶部对齐，必须显式 `.align(Alignment.TopStart)`（设置族页面已全部修复）
- **EntryAbility 不得静态 import 含模块级 Store 单例的模块**（SyncService→UserSettingStore 链）：模块求值早于 onCreate 的 context 注入会冷启动闪退；需要时改用 `import lazy { x }`（API 12+，首次访问才加载）
- 合并审查弹窗在保存时触发，不在浏览时触发。同义词检测无法覆盖所有语义关联（如 `爱莉希雅（崩坏3）` 与 `爱莉希雅`），需用户手动在 ExifTagConfigPage 管理。
