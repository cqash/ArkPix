# AGENTS.md — ArkPix

HarmonyOS ArkTS Stage Model 应用（单模块 `entry`），API 12+ / SDK 6.1.0(23)，Hvigor 构建。Pixiv 第三方客户端。

## 构建与运行

- **构建**：`build_project` 工具（或 `hvigor assembleHap`）。运行前必须先构建。
- **运行**：`start_app`（模块 `entry`，Ability `EntryAbility`）。
- **调试**：`hdc_log collect` 或 `hdc hilog`。真机需完整路径 `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe`。
- 无 `package.json` 脚本；构建逻辑在 `hvigorfile.ts` / `entry/hvigorfile.ts`。

## 入口与导航

- `EntryAbility` → `AppStorage.setOrCreate('context', this.context)` → 加载 `pages/splash/SplashPage`
- `SplashPage` 等 1.5s → `router.replaceUrl` 到 `HomePage`（已登录）或 `LoginPage`（`needsRelogin` 时先 toast 提示重新登录）
- `HomePage` = `Tabs` 容器（RecomPage、FollowPage、RankPage、SearchPage、SettingsPage）
- 深层页用 `router.pushUrl` / `router.replaceUrl`（非 Navigation）。路由上限 32 页。
- 所有注册页面在 `main_pages.json`：Index、Splash、Login、WebViewLogin、TokenLogin、Home、IllustDetail、ImageViewer、TagSearch、Bookmark、Download、FilenameTemplate、ExifTemplate、ExifTagConfig、About、Mute、UserProfile

## 架构（entry/src/main/ets/）

```
pages/       — 页面（splash、login、home/*、search/*、detail/*、user/*、bookmark/*、settings/*、novel/*）
components/  — 可复用组件
  common/    — CachedImage（@Watch('onUrlChange') 支持自定义 ratio/fit + prefetchCachedImage 静态预取）、CommonViews（Loading/Error/Empty）、TagExifPicker（@CustomDialog EXIF 标签选择器）
  illust/    — IllustCard（@Reusable 公共卡片：宽高比/角标/红心/长按菜单）、IllustWaterfall（瀑布流容器：分页/刷新/过滤/可选 compareFn 排序）
  viewer/    — ZoomableImage（PanGestureOptions.setDistance 动态 distance + .priorityGesture 优先级提升）
stores/      — AccountStore、UserSettingStore、BookmarkStateStore（收藏注册表单例）、IllustDetailStore（详情页编排，非单例）
network/     — HttpClient + 拦截器链 + ApiService / OAuthService / PixivEndpoints
services/    — PreferenceService（KV）、DatabaseService（relationalStore）、ImageCacheService、DownloadService、ImageExifService
models/      — Illust、User、Novel、Comment、Bookmark、SearchHistory、MuteItem、DownloadTask、AppSettings、DohResponse
utils/       — Constants（containsCjk/isAsciiOnly/filterTranslatedName）、CryptoUtils、MuteFilter（屏蔽过滤纯函数）、ImageUrlUtils（画质选档/整组页 URL）
```

## 状态管理

- Store 单例导出：`export const store = StoreClass.getInstance()`
- 全局响应式状态通过 `AppStorage.setOrCreate()` / `AppStorage.get()`（如 `isLoggedIn`、`appSettings`）
- 页面用 `@State` / `@StorageLink` 绑定。Store 方法为 `async Promise<void>`。
- `UserSettingStore.getSettings()` 每次返回新 `AppSettings` 实例（防御性拷贝）；修改后需重新赋值 `this.settings = userSettingStore.getSettings()` 触发 UI 刷新。
- AppStorage 同步依赖引用变化：`bookmarkStates` 每次变更必须整体替换新 Map 引用。

## HTTP 与网络

- 使用 `@kit.NetworkKit` 的 `http` 模块（bypass 模式走 rcp）。`HttpClient` 单例包装 + 拦截器链。
- 拦截器顺序：AuthInterceptor → RetryInterceptor → LogInterceptor（无 CacheInterceptor）
- `AuthInterceptor`：注入 `Authorization: Bearer` + `Accept-Language: zh-CN` + 401 自动 refresh token + 队列化并发请求 + 120s 刷新节流 + 重放后 401 最终校验
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
- `ImageExifService`：嵌入 EXIF 元数据（标题→ImageDescription、用户名→Artist、标签→UserComment、日期→DateTimeOriginal）。嵌入时强制转 JPEG（非 GIF）。
- 下载任务状态通过 `DatabaseService` 追踪（downloading/completed/failed）。DB 初始化时将 downloading/pending 重置为 failed。
- `DownloadService` 批量/去重方法：`isDownloaded(illustId, part)`（completed 记录 + `fs.access` 文件存在双条件，DB 异常降级 false）；`retryAllFailed()`（failed 任务逐条重建下载，含 applyToGallery + onTaskDone 回调，返回发起数，元信息缺失跳过）；`clearTasksByStatus(status)`（仅删记录不删文件，返回删除数）。DB 侧配套 `getDownloadTaskById` / `deleteDownloadTasksByStatus`
- 下载重复检测：所有下载入口（详情页 savePage/saveAll、查看器保存、卡片长按保存）先按 插画ID+页码 查 `isDownloaded`，命中弹确认（单页/多页均用 `getUIContext().showAlertDialog`；`AlertDialog.show` 静态方法已废弃不可用）；`IllustDetailStore.uiContext` 由宿主页面 aboutToAppear 注入

## EXIF 标签系统

### 核心数据结构

- `ExifTag`: `{ name: string, translatedName: string }` — 原始 tag 名 + API 翻译名
- `ExifTagMergeRule`: `{ mainTag: string, fromTags: string[] }` — 去重式合并规则
- `MergeGroup`: `{ translatedName: string, tags: ExifTag[] }` — 同义 tag 组（审查弹窗用）
- `AppSettings` EXIF 相关字段：`embedExifMetadata`、`exifCommentTemplate`、`exifMutedTags`、`exifMergedTags`、`exifTagPriority`、`autoMergeTranslatedTags`、`showTranslatedTags`

### 翻译过滤（filterTranslatedName）

Pixiv API 在 `Accept-Language: zh-CN` 时会将 CJK tag "翻译"成英文（爱莉希雅→Elysia），对中文用户无意义。
- `Constants.filterTranslatedName(tagName, translatedName)`：tagName 含 CJK + translatedName 纯 ASCII → 视为无意义翻译，返回空串
- 日文→英文同理被过滤（エリシア→Ellicia）
- 所有显示和 EXIF 写入点统一调用此函数

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

排除已在 `exifMergedTags` 规则中覆盖的组（组内所有 tag 名都在某条规则的 mainTag/fromTags 中）。

### 合并审查弹窗流程

1. 时机：点击**保存**按钮时触发（`handleSavePage/handleSaveAll`），不在页面加载时打断
2. `hasUnresolvedMergeGroups()` 预检 → `checkMergeReview()` 弹窗
3. 用户每组选一个主 tag → 确认 → 写入 `exifMergedTags` 规则 → toast 提示"请再次点击保存"
4. 跳过则不持久化，下次保存仍会弹出
5. 弹窗内层内容区用 `.hitTestBehavior(HitTestMode.Block)` 防止点击冒泡到外层遮罩关闭弹窗

### EXIF Picker（TagExifPicker @CustomDialog）

- EXIF 字段超 65535 字节时弹出
- 可写入区：勾选/取消勾选（取消=跳过本次，不持久化）；拖拽排序（`onItemDragStart`/`onItemDrop`，确认后写入 `exifTagPriority`）
- 长按 tag → 二次确认 → 移入屏蔽区（永久屏蔽，写入 `exifMutedTags`）
- 屏蔽区"恢复"按钮移回可写入区
- 预览区实时显示渲染结果和字节数

### 模板变量

- `{tags}`：原始 tag 名（逗号分隔）
- `{tags_translated}`：带翻译的 tag 输出（tag名(翻译) 格式）
- `{tags_localized}`：纯目标语言 tag 输出（优先中文翻译，无翻译保留原文）
- 替换顺序：`{tags_localized}` → `{tags_translated}` → `{tags}`（最长前缀优先防误替换）
- 其他变量：`{illust_id}`、`{user_id}`、`{user_name}`、`{title}`、`{part}`

### EXIF 标签管理页（ExifTagConfigPage）

- 查看/编辑合并规则、屏蔽列表、优先级排序
- 导入/导出（JSON 格式）

## 弹窗风格约定

- 多选项菜单：`bindContextMenu`
- 二选一确认：`AlertDialog`（通过 `getUIContext().showAlertDialog`）
- 多值选择：`TextPickerDialog`
- 不使用 `ActionSheet`（底部大弹窗）
- 弹窗覆盖层内层内容区必须加 `.hitTestBehavior(HitTestMode.Block)` 防点击冒泡关闭

## 防社死模式

- `AppSettings.antiSocialDeath`：R18 图片在 IllustCard/IllustDetailPage/ImageViewerPage 显示模糊遮罩
- 点击揭示，再次点击恢复遮罩

## 详情页交互

- Tag 长按菜单（bindContextMenu）：复制标签名 / 屏蔽该标签 / 备注中屏蔽 / 备注中合并
- 图片长按菜单（bindContextMenu）：单页保存 / 多页保存
- 合并对话框：输入主 tag 名 → `addExifMergeRule`

## ArkTS 严格约束

- 禁止 `any` / `unknown` / `as` 类型断言 / 动态属性访问 / 结构类型
- 对象字面量必须有显式类型上下文
- `@Builder` 内不能用 `let` 声明局部变量，用成员方法代替
- `build-profile.json5`：`strictMode: { caseSensitiveCheck, useNormalizedOHMUrl }`
- 构建 type-error 时检查：缺少显式类型、不安全转换、动态访问
- ArkUI List 拖拽排序用 `onItemDragStart`/`onItemDrop`（非 onDragStart/onDrop），回调签名 `(event: ItemDragInfo, index: number)`

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
- 应用名 **ArkPix**（bundle 仍为 `com.example.pixez`）。
- `arkts_check` 对 `@kit.*` 引用固定报 6 条 SDK d.ts 错误，属环境噪音，可忽略。
- 合并审查弹窗在保存时触发，不在浏览时触发。同义词检测无法覆盖所有语义关联（如 `爱莉希雅（崩坏3）` 与 `爱莉希雅`），需用户手动在 ExifTagConfigPage 管理。
