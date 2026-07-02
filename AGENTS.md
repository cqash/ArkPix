# AGENTS.md — PixEz 鸿蒙版

## 项目类型

鸿蒙 HarmonyOS ArkTS Stage Model 应用（单模块 `entry`），API 12+ / SDK 6.1.0(23)，使用 Hvigor 构建。这是从 Flutter 重写的 Pixiv 第三方客户端。

## 构建与运行

- **构建**：使用 `build_project` 工具（或 `hvigor assembleHap` / `hvigor clean` + `hvigor assembleHap`）。在设备/模拟器上运行前必须先构建。
- **运行**：使用 `start_app`（从 `entry` 模块启动 `EntryAbility`）。
- **调试**：使用 `hdc hilog` 或 `hdc_log collect` 获取运行时日志。可通过 `build_project` 的 `log_path` 参数保存构建日志。
- 没有 `package.json` 脚本；构建逻辑在 `hvigorfile.ts` 和 `entry/hvigorfile.ts` 中。

## 入口与导航流程

- `EntryAbility`（`entry/src/main/ets/entryability/EntryAbility.ets`）设置 `AppStorage.setOrCreate('context', this.context)`，并加载 `pages/splash/SplashPage`。
- `SplashPage` 等待 1.5 秒，然后通过 `router.replaceUrl` 跳转到 `HomePage`（已登录）或 `LoginPage`。
- `HomePage` 是 `Tabs` 容器，包含四个标签页：`RecomPage`、`RankPage`、`SearchPage`、`SettingsPage`。
- 深层页面使用 `router.pushUrl` / `router.replaceUrl`（非 `Navigation` 组件）。注意路由有 32 页限制。

## 架构（entry/src/main/ets/）

```
pages/          — 页面（splash、login、home/*、search/*、detail/*、user/*、novel/*、settings/*）
components/     — 可复用组件（common/、illust/、user/、comment/）
stores/         — 单例 Store 类，包含业务逻辑（AccountStore、UserSettingStore、HomeStore、SearchStore、IllustDetailStore、UserStore、BookmarkStore、HistoryStore、DownloadStore）
network/        — HttpClient.ets + 拦截器（AuthInterceptor → RetryInterceptor → CacheInterceptor → LogInterceptor）+ ApiService.ets / OAuthService.ets / PixivEndpoints.ets
services/       — PreferenceService（KV）、DatabaseService（relationalStore）、ImageCacheService、DownloadService
models/         — 数据模型（Illust、User、Novel、Comment、Bookmark、SearchHistory、MuteItem、DownloadTask、AppSettings）
utils/          — Constants.ets、CryptoUtils.ets、DateUtils.ets、StringUtils.ets
```

## 状态管理

- Store 以单例形式导出：`export const store = StoreClass.getInstance()`。
- Store 使用 `AppStorage.setOrCreate()` / `AppStorage.get()` 管理全局响应式状态（如 `isLoggedIn`）。
- 页面通过 `@State` 或 `@StorageLink` 绑定 Store 数据。Store 方法为异步 `Promise<void>`。

## HTTP 与网络

- 使用 `@kit.NetworkKit` 的 `http` 模块（非 `rcp`）。`HttpClient.ets` 对其进行包装并添加拦截器链。
- 通过 OAuth2 认证 Pixiv（`oauth.secure.pixiv.net`）。Token 通过 `PreferenceService` 持久化。
- `Constants.applyProxy(url)` 在设置了 `Constants.PROXY_HOST` 时替换 Pixiv 域名为代理主机。
- `AuthInterceptor` 注入 `Authorization: Bearer {token}` 和 Pixiv 专用哈希头（`X-Client-Time`、`X-Client-Hash`）。

## ArkTS 严格约束

- **禁止 `any` 或 `unknown`**。禁止使用 `as` 类型断言。
- **禁止动态属性访问**（`obj[dynamicKey]`）。
- **禁止结构类型**；使用显式继承/接口。
- 对象字面量必须有显式类型上下文（类型化变量或参数）。
- `build-profile.json5` 启用了 `strictMode`，包含 `caseSensitiveCheck` 和 `useNormalizedOHMUrl`。
- 如果构建因类型错误失败，检查是否缺少显式类型、存在不安全类型转换或动态访问。

## 代码质量

- `code-linter.json5` 对 `**/*.ets` 运行（忽略 `test/`、`ohosTest/`、`mock/`、`build/`、`node_modules/`）。
- 规则集：`plugin:@performance/recommended`、`plugin:@typescript-eslint/recommended`。
- 安全规则严格（`@security/no-unsafe-aes`、`no-unsafe-hash` 等设为 `error`/`warn`）。仅使用安全加密 API。

## 测试

- **单元测试**：使用 `@ohos/hypium`，位于 `entry/src/test/`
- **仪器化测试**：位于 `entry/src/ohosTest/`
- **Mock**：`@ohos/hamock` 是开发依赖。
- 没有明显的 CLI 测试运行脚本；通常通过 DevEco Studio 或 `hvigor test` 运行。

## 权限

在 `entry/src/main/module.json5` 中声明：
- `ohos.permission.INTERNET`
- `ohos.permission.GET_NETWORK_INFO`
- `ohos.permission.WRITE_MEDIA`
- `ohos.permission.READ_MEDIA`

## 重要文件

- `entry/src/main/ets/entryability/EntryAbility.ets` — 应用入口，设置上下文
- `entry/src/main/ets/pages/splash/SplashPage.ets` — 启动页 / 路由网关
- `entry/src/main/ets/pages/home/HomePage.ets` — 根标签容器
- `entry/src/main/ets/network/HttpClient.ets` — 带拦截器的 HTTP 客户端
- `entry/src/main/ets/stores/AccountStore.ets` — 认证与多账号状态
- `entry/src/main/ets/utils/Constants.ets` — API 地址、客户端密钥、代理配置、排行模式
- `entry/src/main/ets/services/PreferenceService.ets` — KV 持久化
- `entry/src/main/ets/services/DatabaseService.ets` — SQLite 持久化
- `entry/src/main/module.json5` — 模块配置、权限、Ability
- `build-profile.json5` — 签名配置、SDK 版本、构建模式
- `code-linter.json5` — 代码检查与安全规则

## 规格/规划文档

- `spec/pixiv-client/spec.md` — 完整功能规格（用户故事、数据模型、API 契约）
- `spec/pixiv-client/plan.md` — 架构决策（HTTP 客户端、状态管理、图片加载、导航、持久化、OAuth2）
- `spec/pixiv-client/tasks.md` — 任务列表及各阶段依赖图

## 常见陷阱

- `HttpClient` 是单例，不要直接实例化。在首次请求前通过 `addInterceptor()` 添加拦截器。
- `AccountStore` 在构造时自动加载持久化账号，并将 Token 同步到 `AuthInterceptor`。
- `Constants.applyProxy()` 必须在所有 Pixiv URL 请求前调用；`HttpClient` 内部已处理。
- Pixiv API 返回的图片 URL 可能需要 `Referer: https://app-api.pixiv.net/` 头；拦截器/服务中已处理。
- `Index.ets` 页面是脚手架占位符；真正的启动页是通过 `EntryAbility` 加载的 `SplashPage`。
- 混淆已禁用（`entry/build-profile.json5` 中 `enable: false`）；调试时保持关闭。

