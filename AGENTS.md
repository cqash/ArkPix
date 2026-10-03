# AGENTS.md — ArkPix

HarmonyOS ArkTS Stage Model 应用（单模块 `entry`），API 12+ / target SDK 26.0.0（API 26，新点分版本号格式，compileSdkVersion 不显式配置、随 DevEco 内置 SDK）、compatible 6.1.0(23)，Hvigor 构建。Pixiv 第三方客户端。

## 专题文档（按需阅读；改动对应功能时同步更新对应文档）

- `docs/agents/list-detail.md` — 列表/瀑布流/下拉刷新/收藏（含已删除判删 R6）/详情页壳+Pane/相邻预取 R7/R8/ZoomableImage/查看器底栏 R5/首页悬浮胶囊底栏
- `docs/agents/download-exif.md` — 下载管线（并发队列/写图库双通道/文件名模板）/EXIF 嵌入与标签系统/Ugoira 动图（播放 + GIF 导出）
- `docs/agents/relay-sync.md` — Relay 中继/六域同步 LWW+墓碑/设备间分布式同步/多端流转（应用接续）
- `docs/agents/pages-misc.md` — 防社死/详情页交互（顶栏/FAB/选页弹窗/简介富文本）/历史与导出/Token 导出/搜索扩展/评论区
- `docs/agents/immersive-material.md` — 沉浸光感（API 26+，MaterialUtils 唯一入口/落点/红线/模拟器差异）

## 构建与运行

- **构建**：`build_project` 工具（或 `hvigor assembleHap`）。运行前必须先构建。
- **运行**：`start_app`（模块 `entry`，Ability `EntryAbility`）。
- **调试**：`hdc_log collect` 或 `hdc hilog`。真机需完整路径 `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe`。
- 无 `package.json` 脚本；构建逻辑在 `hvigorfile.ts` / `entry/hvigorfile.ts`。

## 入口与导航

- `EntryAbility` → `AppStorage.setOrCreate('context', this.context)` + `webview.WebviewController.customizeSchemes(['pixiv'])`（注册 pixiv 自定义协议到 Web 内核，**必须在任何 Web 组件初始化之前**，否则 OAuth 完成跳 pixiv:// 会被系统 AppLinking 吞掉拿不到 code）+ `hoster.init()` + `hoster.refreshAll()`（DoH 主机解析）+ `localProxyServer.start()`（本地中继，供 WebView 走绕过）→ 加载 `pages/splash/SplashPage`；`onForeground` 经 **`import lazy`** 调 `syncService.onAppForeground()` 做回前台补偿同步（lazy 首次访问才加载模块，规避 onCreate 前模块求值闪退，见"常见陷阱"）；onCreate 末尾同法 lazy 调 `distributedSyncService.init()`（设备间同步，同样依赖 UserSettingStore 链）
- **多端流转（应用接续）**：module.json5 `continuable: true`；细节见 `docs/agents/relay-sync.md`
- `SplashPage` 等 1.5s → `router.replaceUrl` 到 `HomePage`（已登录）或 `LoginPage`（`needsRelogin` 时先 toast 提示重新登录）
- `LoginPage` 右上角「设置」入口 → pushUrl 设置首页（登录前配置网络/中继；SettingsPage 同时是 @Entry 路由页与 HomePage Tab 子组件，两用法兼容）
- `HomePage` = 页签容器（RecomPage、FollowPage、RankPage、SearchPage、SettingsPage），图库式悬浮胶囊底栏——API 26+ 沉浸光感支持端用标准 `Tabs`+ImmersiveMaterial，低版本用 `HdsTabs`+HDS 材质通道（双分支细节见 `docs/agents/immersive-material.md`，去背板细节见 `docs/agents/list-detail.md`）
- 深层页用 `router.pushUrl` / `router.replaceUrl`（非 Navigation）。路由上限 32 页。
- 子登录页（WebViewLogin/TokenLogin）成功回调：`router.clear()` 清栈 + `router.replaceUrl` 到 HomePage（LoginPage 用 pushUrl 压底，仅 replace 换栈顶仍会退回登录页）
- WebViewLoginPage 的 code 捕获**双通道**：`onLoadIntercept`（https 回调）+ `WebSchemeHandler`（pixiv:// 自定义协议——onLoadIntercept 收不到它，须 `customizeSchemes` 注册 + `onControllerAttached` 里 `controller.setWebSchemeHandler('pixiv', handler)`，handler 内返回空 200 响应并 doLogin）
- TokenLoginPage：`extractToken` 兼容粘贴 JSON 导出内容（refreshToken/refresh_token 字段）并去内部空白；`accountStore.loginWithRefreshToken` 返回错误描述字符串（''=成功），区分凭证失效（含 refresh_token 轮换提醒）与网络错误，同 user.id 账号去重更新而非重复堆叠
- 所有注册页面在 `main_pages.json`（28 个，上限 32）：Index、Splash、Login、WebViewLogin、TokenLogin、Home、IllustDetail、ImageViewer、TagSearch、Bookmark、**Settings + 7 个设置分类子页（Browse/Download/Filter/Network/Relay/General/Account）**、Download、FilenameTemplate、ExifTemplate、ExifTagConfig、About、Mute、History、Comment、UserProfile

## 架构（entry/src/main/ets/）

```
pages/       — 页面（splash、login、home/*、search/*、detail/*、user/*、bookmark/*、settings/*）
             settings/ = 分类聚合结构：SettingsPage（首页 7 分类入口+摘要）+ SettingWidgets（共享行组件/Picker/选项数组/labelOf）+ 7 个分类子页（Browse/Download/Filter/Network/Relay/General/AccountSettingsPage）+ 既有功能页（DownloadPage/MutePage/HistoryPage 等）
components/  — 可复用组件
  common/    — CachedImage（@Watch('onUrlChange') 支持自定义 ratio/fit + 模块级导出函数 prefetchCachedImage 预取）、CommonViews（Loading/Error/Empty）、FollowButton（三态关注按钮：实心/描边/请求中原地小菊花，单击快关+长按精细关注 bindContextMenu）、MaterialFab（沉浸光感玻璃球 FAB 容器：迷你单 Tab Tabs 悬浮 Bar 承载内容，材质按 Bar 轮廓渲染，Tabs/HdsTabs 双分支，API 23+ 均可用，详见 docs/agents/immersive-material.md）
  illust/    — IllustCard（@Reusable 公共卡片：宽高比/角标/可交互星标/长按直存/ugoira "GIF" 角标）、IllustWaterfall（瀑布流容器：分页/刷新/过滤/可选 compareFn 排序/回顶令牌/详情滑动上下文注册/带标签收藏面板缺省宿主）、BookmarkTagPanel（带标签收藏内联底部弹层）、UgoiraPlayer（动图播放：UgoiraService 取帧 + ImageAnimator 无限循环，封面兜底回退）
  detail/    — IllustDetailPane（详情内容面板：图片行/信息行/相关作品/双 FAB/EXIF Picker/合并审查/选页弹窗/画师行菜单/带标签收藏面板/屏蔽占位全套，每实例独立 IllustDetailStore，isActive 门控懒加载）
  viewer/    — ZoomableImage（PanGestureOptions.setDistance 动态 distance + .priorityGesture 优先级提升）
stores/      — AccountStore、UserSettingStore、BookmarkStateStore（收藏注册表单例）、IllustDetailStore（详情页编排，非单例）、CommentStore（评论页编排，非单例，主楼/回复楼双模式）
network/     — HttpClient + 拦截器链 + ApiService / OAuthService / PixivEndpoints + Hoster（DoH 主机解析）+ LocalProxyServer（本地 TCP 中继，WebView 用）+ RelayClient（自托管中继：register/refresh/relayRequest/buildImageUrl + 401 自刷新 + 502 回落）
services/    — PreferenceService（KV）、DatabaseService（relationalStore）、ImageCacheService、DownloadService、ImageExifService、SyncService（六域同步 LWW+墓碑）、RecoverService（已删作品恢复轮询）、RelaySelfTestService（六端点自检）、ContinuationService（接续页面状态登记+载荷构建/解析，纯内存+AppStorage 可静态 import）、DistributedSyncService（分布式数据对象设备间同步，EntryAbility 须 lazy import）、DetailListContextRegistry（详情页作品间滑动上下文注册表，模块级 Map 纯内存，上限 8）、UgoiraService（动图：metadata/zip 帧包下载解压/帧缓存/系统 API GIF 编码）
models/      — Illust、User、Novel、Comment、Bookmark、SearchHistory、MuteItem、DownloadTask、AppSettings、DohResponse、RelayModels、ContinuationPayload（接续/同步载荷模型+序列化解析纯函数，as 断言收敛于此）、UgoiraMetadata（动图 metadata + 帧缓存 meta 序列化）
utils/       — Constants（containsCjk/isAsciiOnly/filterTranslatedName、applyDirectIp/extractHost/normalizeMode/applyImageHost/isOauthUrl/isApiUrl/isImageUrl/直连 IP 常量）、CryptoUtils、MuteFilter（屏蔽过滤纯函数）、ImageUrlUtils（画质选档/整组页 URL）、ClipboardUtils（copyText 复制 + pasteText 读取，读取须在 PasteButton 临时授权窗口内）、HistoryExport（历史导出内容构建纯函数）、MergeSuggest（合并对话框补全候选纯函数）、DateUtils（formatCreateDate：ISO→本地时区 yyyy-MM-dd HH:mm，失败返回 ''）、HapticUtils（全局触觉反馈唯一入口：四级语义 selectionClick/light/medium/heavy + hapticFeedback 开关 + 50ms 节流 + isSupportEffectSync 探测降级 VibrateTime，全程静默）、PixivLinkParser（pixiv URL→{kind,id} 纯函数：artworks/users/member_illust.php/pixiv://illusts|user，不识别返回 null）、CaptionParser（简介 HTML→CaptionSegment{text,href} 纯函数：`<a>` 提取/`<br>`→\n/基础实体解码/其余标签剥离/畸形兜底纯文本；captionToPlainText 供复制文案）、MaterialUtils（沉浸光感唯一入口，见 docs/agents/immersive-material.md）
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

## 弹窗风格约定

- 多选项菜单：`bindContextMenu`
- 二选一确认：`AlertDialog`（通过 `getUIContext().showAlertDialog`）
- 多值选择：`TextPickerDialog`
- 不使用 `ActionSheet`（底部大弹窗）。原 `IllustDetailStore.saveAll` 的 showActionSheet 例外已迁移为 AlertDialog，例外清零
- 弹窗覆盖层内层内容区用 `.onClick(() => {})` 消费点击事件防冒泡关闭；禁止 `.hitTestBehavior(HitTestMode.Block)`（会挡住子组件交互，MergeDialogOverlay 的 Block 例外已移除）
- 读剪贴板必须走 **PasteButton 安全控件**（点击获临时授权窗口，窗口内调 `ClipboardUtils.pasteText()`；普通读取需 READ_PASTEBOARD 受限权限，勿申请）；写剪贴板 `copyText` 无需权限
- bindContextMenu 菜单项内若要 toast/弹窗：先 `menuShown=false` 并 `setTimeout(300)` 后再执行（否则 toast 被菜单弹层吞掉）；页面内 toast 优先走 `getUIContext().getPromptAction().showToast()`（HistoryPage 已按此修复）

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

`INTERNET`、`GET_NETWORK_INFO`、`VIBRATE`（触觉反馈，normal 级免运行时申请）、`WRITE_MEDIA`、`READ_MEDIA`、`DISTRIBUTED_DATASYNC`（设备间同步，运行时申请，见 `docs/agents/relay-sync.md`；WRITE_MEDIA/READ_MEDIA 对媒体库写入无实际效力，写图库靠 SaveButton 临时授权 / showAssetsCreationDialog，见 `docs/agents/download-exif.md`；`WRITE_IMAGEVIDEO` 为 ACL 白名单权限，勿声明——会导致安装失败 9568289）

## 常见陷阱

- `HttpClient` 单例，不要 new。拦截器在 `ApiService` 构造函数中注册（Auth → Retry → Log）。
- `AccountStore` 构造时自动加载持久化账号 + 同步 token 到 `AuthInterceptor` + 注册 refresh handler。
- `Constants.applyProxy()` 在 `HttpClient.request()` 内已处理（空壳）；实际域名改写由 `Constants.applyDirectIp()`（兼容模式）与 `Constants.applyImageHost()`（图床）负责，均在 HttpClient/ImageCacheService/DownloadService 内部自动调用，无需手动调用。
- Pixiv 图片 URL 需特殊 Referer/User-Agent 头；在 DownloadService 和 ImageCacheService 内处理（拦截器只注入 Authorization/Accept-Language，不管图片头）。
- **UI 自动化坐标系**：`devecocli ui click/drag` 用设备物理坐标（Mate 70 Pro+ 模拟器 1316×2832），`ui screenshot` 截图被缩放（1260×2736），按截图目测坐标需乘 ~1.044/1.035；精确坐标用 `ui layout --mode simplified` 查节点 bounds
- `Index.ets` 是脚手架占位符；真正入口是 `EntryAbility` → `SplashPage`。
- 混淆已禁用（`entry/build-profile.json5` `enable: false`）。
- `User.ets`、`Illust.ets`、`Novel.ets` 各自定义了 `ImageUrls` 类（同名但独立），不要混用导入。
- 模型 JSON 反序列化模式：`fromJson(raw)` → 返回 `*Options` 接口 → `new Model(opts)`。`fromJson` 内用 `as RawXxx`（仅限此内部层）。
- 应用名 **ArkPix**（bundle 仍为 `com.example.pixez`）。
- `arkts_check` 对 `@kit.*` 引用固定报 6 条 SDK d.ts 错误，属环境噪音，可忽略；另对 `this.$xxx`（@State 的 $ 绑定属性）有误报，以 hvigor 全量构建为准。
- **ForEach 行不刷新陷阱**：`@State` 数组 + 自定义 keyGenerator 时，同 key 子组件复用不重建，普通对象（非 @Observed）属性变化观察不到——行内显示的可变字段必须参与 key 生成（如自检 `name|status|durationMs`、下载任务 `id|status|progress`），或 Service 端替换元素引用而非原地改属性
- **Scroll 内容居中陷阱**：Scroll 设了高度限制（layoutWeight/height）后内容不足一屏时**默认垂直居中**而非顶部对齐，必须显式 `.align(Alignment.TopStart)`（设置族页面已全部修复）
- **EntryAbility 不得静态 import 含模块级 Store 单例的模块**（SyncService→UserSettingStore 链）：模块求值早于 onCreate 的 context 注入会冷启动闪退；需要时改用 `import lazy { x }`（API 12+，首次访问才加载）
- 合并审查弹窗在保存时触发，不在浏览时触发。同义词检测无法覆盖所有语义关联（如 `爱莉希雅（崩坏3）` 与 `爱莉希雅`），需用户手动在 ExifTagConfigPage 管理。
- **quickfix 坑**：`devecocli run --apply` 对 MaterialFab.ets 这类新组件/Bar 结构改动**静默不生效**（界面全是旧代码假象），改这些文件后必须全量 `devecocli run`。
