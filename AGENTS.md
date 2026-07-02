# AGENTS.md — PixEz 鸿蒙版

HarmonyOS ArkTS Stage Model 应用（单模块 `entry`），API 12+ / SDK 6.1.0(23)，Hvigor 构建。Pixiv 第三方客户端。

## 构建与运行

- **构建**：`build_project` 工具（或 `hvigor assembleHap`）。运行前必须先构建。
- **运行**：`start_app`（模块 `entry`，Ability `EntryAbility`）。
- **调试**：`hdc_log collect` 或 `hdc hilog`。
- 无 `package.json` 脚本；构建逻辑在 `hvigorfile.ts` / `entry/hvigorfile.ts`。

## 入口与导航

- `EntryAbility` → `AppStorage.setOrCreate('context', this.context)` → 加载 `pages/splash/SplashPage`
- `SplashPage` 等 1.5s → `router.replaceUrl` 到 `HomePage`（已登录）或 `LoginPage`
- `HomePage` = `Tabs` 容器（RecomPage、RankPage、SearchPage、SettingsPage）
- 深层页用 `router.pushUrl` / `router.replaceUrl`（非 Navigation）。路由上限 32 页。
- 所有注册页面在 `main_pages.json`：Index、Splash、Login、WebViewLogin、TokenLogin、Home、IllustDetail、ImageViewer、TagSearch、Bookmark、Download、FilenameTemplate

## 架构（entry/src/main/ets/）

```
pages/       — 页面（splash、login、home/*、search/*、detail/*、user/*、bookmark/*、settings/*）
components/  — 可复用组件（common/、illust/、user/、comment/）
stores/      — 单例 Store：AccountStore、UserSettingStore、HomeStore、SearchStore、IllustDetailStore、UserStore、BookmarkStore、HistoryStore、DownloadStore
network/     — HttpClient + 拦截器链 + ApiService / OAuthService / PixivEndpoints
services/    — PreferenceService（KV）、DatabaseService（relationalStore）、ImageCacheService、DownloadService、ImageExifService
models/      — Illust、User、Novel、Comment、Bookmark、SearchHistory、MuteItem、DownloadTask、AppSettings
utils/       — Constants、CryptoUtils、DateUtils、StringUtils
```

## 状态管理

- Store 单例导出：`export const store = StoreClass.getInstance()`
- 全局响应式状态通过 `AppStorage.setOrCreate()` / `AppStorage.get()`（如 `isLoggedIn`、`appSettings`）
- 页面用 `@State` / `@StorageLink` 绑定。Store 方法为 `async Promise<void>`。
- `UserSettingStore.getSettings()` 每次返回新 `AppSettings` 实例（防御性拷贝）；修改后需重新赋值 `this.settings = userSettingStore.getSettings()` 触发 UI 刷新。

## HTTP 与网络

- 使用 `@kit.NetworkKit` 的 `http` 模块（非 rcp）。`HttpClient` 单例包装 + 拦截器链。
- 拦截器顺序：AuthInterceptor → RetryInterceptor → CacheInterceptor → LogInterceptor
- `AuthInterceptor`：注入 `Authorization: Bearer` + 401 自动 refresh token + 队列化并发请求
- OAuth2 认证（`oauth.secure.pixiv.net`），token 通过 `PreferenceService` 持久化
- `Constants.applyProxy(url)` 在 `HttpClient.request()` 内自动调用，替换 Pixiv 域名 → 代理主机
- 图片下载需 `Referer: https://app-api.pixiv.net/` + `User-Agent: PixivIOSApp/5.8.0`（`Constants.IMAGE_USER_AGENT`），`DownloadService` 内已处理

## 下载与 EXIF

- `DownloadService` 单例：下载到 `cacheDir/downloads/`，可选写入相册（`photoAccessHelper`）
- 文件名模板：默认 `{illust_id}_p{part}`，支持 `{user_id}`、`{user_name}`、`{title}`。模板在 `FilenameTemplatePage` 配置。
- `ImageExifService` 单例：嵌入 EXIF 元数据（标题→ImageDescription、用户名→Artist、标签→UserComment、日期→DateTimeOriginal）。嵌入时强制转 JPEG（非 GIF）。
- 下载任务状态通过 `DatabaseService` 追踪（downloading/completed/failed）。

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
