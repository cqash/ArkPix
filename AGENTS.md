# AGENTS.md — PixEz 鸿蒙版

HarmonyOS ArkTS Stage Model 应用（单模块 `entry`），API 12+ / SDK 6.1.0(23)，Hvigor 构建。Pixiv 第三方客户端。

## 构建与运行

- **构建**：`build_project` 工具（或 `hvigor assembleHap`）。运行前必须先构建。
- **运行**：`start_app`（模块 `entry`，Ability `EntryAbility`）。
- **调试**：`hdc_log collect` 或 `hdc hilog`。
- 无 `package.json` 脚本；构建逻辑在 `hvigorfile.ts` / `entry/hvigorfile.ts`。

## 入口与导航

- `EntryAbility` → `AppStorage.setOrCreate('context', this.context)` → 加载 `pages/splash/SplashPage`
- `SplashPage` 等 1.5s → `router.replaceUrl` 到 `HomePage`（已登录）或 `LoginPage`（`needsRelogin` 时先 toast 提示重新登录）
- `HomePage` = `Tabs` 容器（RecomPage、FollowPage、RankPage、SearchPage、SettingsPage）
- 深层页用 `router.pushUrl` / `router.replaceUrl`（非 Navigation）。路由上限 32 页。
- 所有注册页面在 `main_pages.json`：Index、Splash、Login、WebViewLogin、TokenLogin、Home、IllustDetail、ImageViewer、TagSearch、Bookmark、Download、FilenameTemplate、ExifTemplate、UserProfile

## 架构（entry/src/main/ets/）

```
pages/       — 页面（splash、login、home/*、search/*、detail/*、user/*、bookmark/*、settings/*、novel/*）
components/  — 可复用组件
  common/    — CachedImage（支持自定义 ratio/fit + prefetchCachedImage 静态预取）、CommonViews（Loading/Error/Empty）
  illust/    — IllustCard（@Reusable 公共卡片：宽高比/角标/红心/长按菜单）、IllustWaterfall（瀑布流容器：分页/刷新/过滤/可选 compareFn 排序）
  viewer/    — ZoomableImage（PanGestureOptions.setDistance 动态 distance + .priorityGesture 优先级提升）
stores/      — AccountStore、UserSettingStore、BookmarkStateStore（收藏注册表单例）、IllustDetailStore（详情页编排，非单例）
network/     — HttpClient + 拦截器链 + ApiService / OAuthService / PixivEndpoints
services/    — PreferenceService（KV）、DatabaseService（relationalStore）、ImageCacheService、DownloadService、ImageExifService
models/      — Illust、User、Novel、Comment、Bookmark、SearchHistory、MuteItem、DownloadTask、AppSettings、DohResponse
utils/       — Constants、CryptoUtils、MuteFilter（屏蔽过滤纯函数）、ImageUrlUtils（画质选档/整组页 URL）
```

## 状态管理

- Store 单例导出：`export const store = StoreClass.getInstance()`
- 全局响应式状态通过 `AppStorage.setOrCreate()` / `AppStorage.get()`（如 `isLoggedIn`、`appSettings`）
- 页面用 `@State` / `@StorageLink` 绑定。Store 方法为 `async Promise<void>`。
- `UserSettingStore.getSettings()` 每次返回新 `AppSettings` 实例（防御性拷贝）；修改后需重新赋值 `this.settings = userSettingStore.getSettings()` 触发 UI 刷新。

## HTTP 与网络

- 使用 `@kit.NetworkKit` 的 `http` 模块（bypass 模式走 rcp）。`HttpClient` 单例包装 + 拦截器链。
- 拦截器顺序：AuthInterceptor → RetryInterceptor → LogInterceptor（无 CacheInterceptor）
- `AuthInterceptor`：注入 `Authorization: Bearer` + 401 自动 refresh token + 队列化并发请求 + 120s 刷新节流 + 重放后 401 最终校验
- `OAuthService.refreshToken()`：校验 `responseCode===200 且 access_token 非空` 后才写回 token；失败抛类型化错误 `CredentialInvalidError`（凭证失效，登出并置 needsRelogin）/ `NetworkError`（临时故障，不登出）
- 列表分页：`ApiService.fetchNext(nextUrl)` 通用游标续页，配合 `IllustWaterfall` 分页状态机
- OAuth2 认证（`oauth.secure.pixiv.net`），token 通过 `PreferenceService` 持久化
- `Constants.applyProxy(url)` 在 `HttpClient.request()` 内自动调用，替换 Pixiv 域名 → 代理主机
- 图片下载需 `Referer: https://app-api.pixiv.net/` + `User-Agent: PixivIOSApp/5.8.0`（`Constants.IMAGE_USER_AGENT`），`DownloadService` 内已处理

## 列表与收藏同步

- 所有插画列表（推荐/动态/排行/搜索/标签/收藏/用户作品）统一使用 `IllustWaterfall` + `IllustCard`；页面只需提供 `fetchFirst(): Promise<IllustListPage>` 与可选 `reloadToken`（变更触发重载）
- `IllustWaterfall` 可选入参 `compareFn?: (a, b) => number`：提供时入库数据按之排序，分页追加后全量重排；切换排序由页面递增 `compareToken`（@Prop @Watch）触发已加载数据重排。到达序反转比较器 `compareArrivalReverse`（WeakMap 记录入库顺序，收藏"旧→新"用）由容器导出
- 卡片按真实宽高比展示（高/宽>3 降级方图）；数据入库时经 `MuteFilter` 过滤（屏蔽词/屏蔽作者/AI 过滤）并 `BookmarkStateStore.seedFromList` 播种
- 收藏状态三态注册表 `BookmarkStateStore`：`Map<illustId, 0|1|2>`（未收藏/请求中/已收藏），变更时以**新 Map 引用**写入 `AppStorage['bookmarkStates']` 驱动 `@StorageLink` 刷新；star/unstar 含请求中锁、失败回滚、toast、详情缓存失效
- 详情页（IllustDetailPage）= 单 `List` 行模型（image 行×pageCount + info 行 + related 行），数据编排在 `IllustDetailStore`；多页查看器 `ImageViewerPage` = `Swiper + ZoomableImage`
- **ZoomableImage 手势方案（禁止回退条件手势组）**：`GestureGroup(Parallel, Pinch+Pan+Tap)` 静态常驻挂载；`PinchGesture({fingers:2, distance:1})`；`PanGestureOptions.setDistance()` 动态更新 distance（scale=1→50vp 让位 Swiper 翻页，scale>1→3vp 跟手平移），在 `applyScale()` 末尾调用；`.priorityGesture()` 绑定手势组（优先于 Swiper 内置手势）；拖到 X 向边界继续外拖时 `onZoomChange(false)` 释放回 Swiper，松手恢复；契约回调为 `onZoomChange(isZoomed)`，父级 `Swiper.disableSwipe` 直接绑定该标志；双击 1↔2.5 切换，限幅 1~5 + 边界钳制
- 用户主页统计字段在 `/v1/user/detail` 响应的 `profile` 对象内（非 user 对象）：`User.ets` 的 `ProfileStats` + `profileStatsFromJson()` 解析（totalFollowUsers/totalIllusts/totalManga/totalIllustBookmarksPublic）

## 下载与 EXIF

- `DownloadService` 单例：下载到 `cacheDir/downloads/`，可选写入相册（`photoAccessHelper`）
- 文件名模板：默认 `{illust_id}_p{part}`，支持 `{user_id}`、`{user_name}`、`{title}`。模板在 `FilenameTemplatePage` 配置。
- `ImageExifService` 单例：嵌入 EXIF 元数据（标题→ImageDescription、用户名→Artist、标签→UserComment、日期→DateTimeOriginal）。嵌入时强制转 JPEG（非 GIF）。
- 下载任务状态通过 `DatabaseService` 追踪（downloading/completed/failed）。
- `DownloadService` 批量/去重方法：`isDownloaded(illustId, part)`（completed 记录 + `fs.access` 文件存在双条件，DB 异常降级 false）；`retryAllFailed()`（failed 任务逐条重建下载，返回发起数，元信息缺失跳过）；`clearTasksByStatus(status)`（仅删记录不删文件，返回删除数）。DB 侧配套 `getDownloadTaskById` / `deleteDownloadTasksByStatus`
- 下载重复检测：所有下载入口（详情页 savePage/saveAll、查看器保存、卡片长按保存）先按 插画ID+页码 查 `isDownloaded`，命中弹确认（单页 `showAlertDialog` 仍要下载/取消；saveAll `showActionSheet` 跳过已下载/全部重下/取消）。弹窗走 `getUIContext()`（`AlertDialog.show` 静态方法已废弃不可用）；`IllustDetailStore.uiContext` 由宿主页面 aboutToAppear 注入

## ArkTS 严格约束

- 禁止 `any` / `unknown` / `as` 类型断言 / 动态属性访问 / 结构类型
- 对象字面量必须有显式类型上下文
- `build-profile.json5`：`strictMode: { caseSensitiveCheck, useNormalizedOHMUrl }`
- 构建 type-error 时检查：缺少显式类型、不安全转换、动态访问

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

`INTERNET`、`GET_NETWORK_INFO`、`WRITE_MEDIA`、`READ_MEDIA`

## 常见陷阱

- `HttpClient` 单例，不要 new。拦截器在 `AccountStore` 构造时已注册。
- `AccountStore` 构造时自动加载持久化账号 + 同步 token 到 `AuthInterceptor` + 注册 refresh handler。
- `Constants.applyProxy()` 在 `HttpClient.request()` 内已处理，无需手动调用。
- Pixiv 图片 URL 需特殊 Referer/User-Agent 头；拦截器和 DownloadService 内已处理。
- `Index.ets` 是脚手架占位符；真正入口是 `EntryAbility` → `SplashPage`。
- 混淆已禁用（`entry/build-profile.json5` `enable: false`）。
- `User.ets` 和 `Illust.ets` 各自定义了 `ImageUrls` 类（同名但独立），不要混用导入。
- 模型 JSON 反序列化模式：`fromJson(raw)` → 返回 `*Options` 接口 → `new Model(opts)`。`fromJson` 内用 `as RawXxx`（仅限此内部层）。
