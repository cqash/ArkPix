# Implementation Plan: Relay Server 客户端集成

**Input**: Feature specification from `spec/relay-server-integration/spec.md`

## Summary

为 ArkPix（既有 HarmonyOS ArkTS Stage 单模块项目）接入自托管 Relay Server：新增第四种网络模式 `relay`（API/OAuth 走 `/relay/v1/request` 包装请求、图片走 `/img/v1/fetch`）、服务账号认证（register/refresh + 401 自刷新）、六域数据同步（启动 pull + 10s 防抖 push + LWW/墓碑合并）、已删除作品恢复（快照兜底 + 轮询 + 查看器展示）。实现策略：在 HttpClient.doRequest 末端按模式分流（不动拦截器链与 API 模型层），新增 `RelayClient`/`SyncService`/`RecoverService` 三个服务与一组中继模型，图片链路两处同构改造，设置页新增"中继服务器"组，详情页扩展 404 快照兜底。

## Technical Context

**Language/Version**: ArkTS（strict mode），API 12+ / SDK 6.1.0(23)
**Primary Dependencies**: `@kit.NetworkKit`（http）、`@ohos.net.socket`（既有 TLSSocket，relay 模式旁路）、relationalStore、preferences；无新增三方依赖
**Storage**: PreferenceService（KV，relay 令牌/同步游标/每域最后同步时间）、DatabaseService（新增 bookmark_snapshots 表）、AppStorage（appSettings 引用替换驱动刷新）
**Testing**: `@ohos/hypium` 单元测试（entry/src/test/）；验证以构建 + 真机/模拟器运行为主
**Target Platform**: HarmonyOS 手机/平板
**Project Type**: 既有移动应用的功能扩展
**Performance Goals**: relay 模式首屏加载 ≤ 普通模式 1.5 倍；本地变更 ≤ 15s 自动上行；同步不阻塞 UI 线程
**Constraints**: 不动现有 API 模型层与拦截器注册顺序；服务凭据与 Pixiv 凭据完全分离、敏感字段永不上行；ArkTS 严格约束（禁 any/unknown/as 断言（fromJson 内部层除外）/动态属性）；后端并行开发中，以 docs/backend-design.md v1.0 为协议契约
**Scale/Scope**: 新增 4 个 .ets 文件，修改约 12 个既有文件，3 个用户故事

## Project Structure

### Documentation (this feature)

```text
spec/relay-server-integration/
├── spec.md
├── plan.md              # This file
└── tasks.md
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── entryability/EntryAbility.ets          # 修改：启动后 5s 空闲触发全域 pull（syncEnabled 时）
├── models/
│   ├── AppSettings.ets                    # 修改：新增 relayServerUrl / syncEnabled / 上一可用模式字段
│   └── RelayModels.ets                    # 新增：RelayAccount/SyncItem/BookmarkSnapshot/RecoverResult 等模型与 fromJson
├── network/
│   ├── HttpClient.ets                     # 修改：resolveMode 放行 relay；doRequest 末端 relay 分流（包装/解包/401 刷新/失败计数回落）
│   ├── OAuthService.ets                   # 修改：relay 模式下 postTokenNoSni 旁路，改走 HttpClient 中继
│   └── RelayClient.ets                    # 新增：服务认证（register/refresh/令牌持久化/401 自刷新）+ relay 请求封装 + img/recover 直连请求
├── services/
│   ├── DatabaseService.ets                # 修改：新增 bookmark_snapshots 表及 CRUD
│   ├── ImageCacheService.ets              # 修改：relay 模式图片 URL 包装 /img/v1/fetch，跳过直连 IP/Referer 注入
│   ├── DownloadService.ets                # 修改：同上（下载链路）
│   ├── SyncService.ets                    # 新增：六域同步调度（防抖 push/启动 pull/游标持久化/LWW 合并/墓碑/全量重建）
│   └── RecoverService.ets                 # 新增：恢复查询与轮询封装
├── stores/
│   ├── UserSettingStore.ets               # 修改：新字段 load/save/getSettings 拷贝/setter
│   ├── BookmarkStateStore.ets             # 修改：star/unstar 成功后触发快照 push（经回调注册，防循环依赖）
│   └── IllustDetailStore.ets              # 修改：404 识别 + 快照兜底数据 + 恢复流程编排
├── utils/Constants.ets                    # 修改：MODE_RELAY 常量、normalizeMode 放行、isRelayMode()
└── pages/
    ├── settings/SettingsPage.ets          # 修改：网络组新增"中继"选项 + "中继服务器"配置组（地址/注册/同步开关/立即同步/每域同步时间/accountKey 导出导入）
    ├── bookmark/BookmarkPage.ets          # 修改：已删除作品灰色占位卡片渲染
    └── detail/IllustDetailPage.ets        # 修改：404 快照兜底 UI + "尝试从第三方恢复"入口 + 轮询进度
```

**Structure Decision**: 遵循既有项目架构（pages/components/stores/services/network/models/utils 分层），不引入 MVVM 迁移。新增 4 个文件均落在既有分层内（1 models + 1 network + 2 services），与现有 `HttpClient`/`DatabaseService` 等同层同级，文件数量与复杂度匹配。

## Complexity Tracking

无需说明的违规项。

## Research & Decisions

### D1: relay 请求分流点——doRequest 末端分流，而非新增 RelayInterceptor

- **Decision**: 在 `HttpClient.doRequest()` 末端判断 `mode === 'relay'`，将已注入 Pixiv 头的 `options`（method/url/header/body）包装为 `/relay/v1/request` 请求体，解包响应还原为原始 status/body 返回给上层。
- **Rationale**: 拦截器链（Auth → Retry → Log）在分流前执行，AuthInterceptor 注入的 Pixiv `Authorization`/`Accept-Language` 自然进入包装体的 headers 白名单；服务端回传的 Pixiv 原始状态码（如 401）解包后仍能被 AuthInterceptor 的既有刷新重放逻辑处理。若做成链首 RelayInterceptor，则 Pixiv 头注入与 401 语义会被外层中继响应遮蔽，需重写 AuthInterceptor。
- **Alternatives considered**: (a) RelayInterceptor 挂链首——否决，破坏 AuthInterceptor 401 语义；(b) 复用 `Constants.applyProxy` 空壳——否决，它只做 URL 字符串改写，无法携带 method/body 包装语义。

### D2: relay 模式取值挂载——复用既有 authMode/apiMode 双开关

- **Decision**: `relay` 作为 `authMode`/`apiMode` 的新增合法值（`normalizeMode` 放行）。图片链路（ImageCacheService/DownloadService）以 `apiMode === 'relay'` 为判定（图片跟随 API 通道）。
- **Rationale**: 现有架构就是认证/API 双独立开关，新增第三个开关会破坏设置页一致性；用户把两个开关都切到"中继"即等价于设计文档的单一 relay 模式。回落机制（FR-008）分别记录两个开关的上一可用值。
- **Alternatives considered**: 新增独立 `networkMode` 总开关替代双开关——否决，迁移成本高且违背"客户端改造最小化"。

### D3: 服务令牌存储——PreferenceService 直存，不进 AppSettings

- **Decision**: `relayAccessToken`/`relayRefreshToken`/过期时间/`accountKey` 由 `RelayClient` 直接读写 PreferenceService（key 前缀 `relay_`）；`AppSettings` 只保留可同步的非敏感字段 `relayServerUrl`、`syncEnabled`、各域游标与最后同步时间。
- **Rationale**: 设计文档 §7.2 敏感字段排除清单要求 relayAccessToken 永不上行；settings 域同步直接序列化 AppSettings，令牌放 AppSettings 内会被误带上行。AppSettings 现有 `proxyHost` 等死字段证明"字段进了 AppSettings 即默认持久化+可同步"，敏感凭据必须隔离。
- **Alternatives considered**: 全部进 AppSettings 再在上行时剔除——否决，易在后续字段扩展时泄漏。

### D4: 同步数据源——history/search_history 走 DB，mute/settings/exif 走 AppSettings

- **Decision**: `history`（DatabaseService.history 表）、`search_history`（search_history 表）以 DB 为事实来源；`mute` 域数据 = `AppSettings.muteTags + muteUsers + aiFilter`（MuteFilter 的真实数据源，DB `mutes` 表是死代码不用）；`exif_config`/`settings` 域 = AppSettings 对应字段集。
- **Rationale**: 调研确认屏蔽列表事实来源是 AppSettings（PreferenceService），DB mutes 表无任何消费方；跟随真实数据源避免双向不一致。
- **Alternatives considered**: 先把屏蔽迁移到 DB mutes 表再同步——否决，超出本特性范围。

### D5: 收藏快照本地存储——新增 bookmark_snapshots 表

- **Decision**: DatabaseService 新增 `bookmark_snapshots(illust_id INTEGER PRIMARY KEY, data TEXT, updated_at INTEGER, deleted INTEGER)`（沿用 CREATE TABLE IF NOT EXISTS 模式，无版本迁移）。用途：(a) 待上行快照的本地暂存与失败重试；(b) 详情页 404 兜底与收藏页占位卡片的数据来源。
- **Rationale**: 快照需离线可查（详情页 404 时网络可能仍通但作品已删）；DB 既有 `data TEXT` JSON 桶模式（recommend_cache 等）已验证可行。
- **Alternatives considered**: 快照只存在服务端、404 时实时 pull——否决，404 兜底要求本地立即可得，且未开同步用户也应保留本地快照。

### D6: star/unstar 快照触发——回调注册解耦

- **Decision**: BookmarkStateStore 新增 `onBookmarkChanged` 回调注册表（star/unstar 成功后触发，传 illust 与收藏/取消标记）；SyncService 在初始化时注册该回调生成快照 push。不修改 BookmarkStateStore 对 SyncService 的直接依赖。
- **Rationale**: SyncService 依赖 BookmarkStateStore 的收藏状态，反向直接 import 会成环；回调注册与 DownloadService 既有 `registerTaskChangeListener` 模式一致。
- **Alternatives considered**: BookmarkStateStore 直接 import SyncService——否决，循环依赖风险。

### D7: 404 识别——ensureSuccess 错误携带 statusCode

- **Decision**: 扩展 ApiService.ensureSuccess 抛出的错误对象附带 HTTP statusCode（自定义 Error 子类或挂载属性），IllustDetailStore.load 捕获后按 statusCode === 404 走快照兜底分支，其余错误维持现有 errorMessage 行为。
- **Rationale**: 现状 ensureSuccess 只拼消息字符串，404 无法与网络故障区分；设计文档要求 404 才展示恢复入口，无快照的 404 仍是普通错误态。
- **Alternatives considered**: 解析错误消息文本匹配 "404"——否决，脆弱。

### D8: relay 模式 OAuth——旁路 TLSSocket 走 HttpClient

- **Decision**: OAuthService.exchangeToken/refreshToken 在 `authMode === 'relay'` 时跳过 postTokenNoSni，改为经 `HttpClient.post` 向 `https://oauth.secure.pixiv.net/auth/token` 发常规请求（由 doRequest 分流包装进中继）。
- **Rationale**: 设计文档 §6.1 明确 relay 模式服务端用常规 TLS 无 SNI 封锁问题；客户端复用中继通道即自动获得 relay 令牌注入与 401 处理。
- **Alternatives considered**: 保留 TLSSocket 直连——否决，完全无法直连环境下必失败，违背 relay 模式定义。

### D9: 失败回落（FR-008）——RelayClient 内连续失败计数 + 提示性回落

- **Decision**: RelayClient 对 502/超时维护连续失败计数，≥3 时 toast 提示并把 authMode/apiMode 回写为各自上一可用值（UserSettingStore setter），成功后计数清零。上一可用值在切换到 relay 时记录进 AppSettings。
- **Rationale**: 计数放 RelayClient（所有 relay 请求唯一出口）最集中；"仅提示回落、保留 relayServerUrl 配置"符合 FR-008。
- **Alternatives considered**: 在 HttpClient 计数——否决，非 relay 请求会污染计数。

### D10: 启动 pull 挂载点——EntryAbility.onCreate 延迟 5s

- **Decision**: EntryAbility.onCreate 在 `localProxyServer.start()` 后 `setTimeout(5000)` 调 `SyncService.startupPull()`（内部判 syncEnabled + 已注册中继账号）。本地写入侧由各写入点调 `SyncService.schedulePush(domain)`（10s 防抖）：addHistory/addSearchHistory（DatabaseService 内 Hook 或调用方触发）、UserSettingStore 相关 setter、BookmarkStateStore 回调。
- **Rationale**: 调研确认 EntryAbility.onCreate 时 context 已入 AppStorage，全部服务可用；与 DoH 预热同级语义干净。onForeground 补偿 pull 本特性不做（假设同步为尽力而为）。
- **Alternatives considered**: SplashPage/HomePage 挂载——否决，Splash 有登录分支语义，HomePage 随 Tab 重建不干净。

## Data Model

### 新增模型（models/RelayModels.ets）

- **RelayAccount**（内存模型，持久化走 PreferenceService 分立 key）：`accessToken: string`、`refreshToken: string`、`expiresAt: number`（Unix ms）、`accountKey: string`、`serverVersion: string`、`capabilities: string[]`（用于 UI 能力降级，FR-013）
- **SyncItem**：`key: string`、`data: string`（JSON 串，避免 ArkTS 动态对象）、`updatedAt: number`、`deleted: boolean`
- **SyncPushResult**：`accepted: number`、`syncToken: string`、`fullRequired: boolean`（由 409 SYNC_FULL_REQUIRED 映射）
- **SyncPullResult**：`items: SyncItem[]`、`syncToken: string`、`hasMore: boolean`
- **BookmarkSnapshot**：`illustId: number`、`title`、`userId`、`userName`、`restrict`、`pageCount`、`width`、`height`、`tags: string[]`、`createDate: string`、`imageUrls: string[]`、`bookmarkedAt: number`；DB 存 `data TEXT` JSON + `updated_at` + `deleted` 墓碑列
- **RecoverPage**：`page: number`、`url: string`、`width: number`、`height: number`
- **RecoverResult**：`status: string`（'ready' | 'fetching' | 'not_found'）、`pages: RecoverPage[]`、`source: string`、`title: string`、`userName: string`、`retryAfterSec: number`
- **RelayRegisterResult**：accessToken/refreshToken/expiresIn/accountKey/serverVersion/capabilities

### 修改模型（models/AppSettings.ets）

新增字段（同步进 AppSettingsOptions/load/save/getSettings/setter 六处）：
- `relayServerUrl: string = ''`（设置页可编辑；非敏感，可随 settings 域上行）
- `syncEnabled: boolean = false`
- `prevAuthMode: string = 'standard'`、`prevApiMode: string = 'standard'`（回落用，切换 relay 时记录）

### 持久化 key（PreferenceService，非 AppSettings）

`relay_access_token` / `relay_refresh_token` / `relay_expires_at` / `relay_account_key` / `relay_capabilities`（JSON 数组串）/ `sync_token_<domain>` ×6 / `sync_last_<domain>` ×6 / `sync_pending_snapshot` 标记（快照上行失败待重试）

### 数据库变更（DatabaseService）

新增表：`bookmark_snapshots (illust_id INTEGER PRIMARY KEY, data TEXT, updated_at INTEGER, deleted INTEGER DEFAULT 0)`，沿用 CREATE TABLE IF NOT EXISTS，无迁移机制。配套 CRUD：`upsertBookmarkSnapshot` / `getBookmarkSnapshot(illustId)` / `getAliveBookmarkSnapshots`（deleted=0，收藏页占位混排用）/ `markBookmarkSnapshotDeleted`。

### 同步域映射表

| domain | 本地事实来源 | key | 合并规则 |
|---|---|---|---|
| history | DB history 表 | illust_id | viewed_at LWW |
| search_history | DB search_history 表 | keyword+search_type | updatedAt LWW |
| bookmark_snapshot | DB bookmark_snapshots 表 | illust_id | updatedAt LWW + 墓碑 |
| mute | AppSettings.muteTags/muteUsers/aiFilter | tag:xxx / user:xxx / ai | key LWW + 墓碑（集合并集） |
| exif_config | AppSettings exif 四字段 | 固定 'config' | 整条 LWW |
| settings | AppSettings 非敏感字段集 | 固定 'settings' | 整条 LWW |

## Contracts & Interfaces

### 服务端契约（以 docs/backend-design.md v1.0 为准，客户端消费方）

| 端点 | 客户端调用方 | 说明 |
|---|---|---|
| POST `/auth/v1/register` | RelayClient.register(deviceName, inviteCode?, accountKey?) | 返回令牌对 + accountKey + serverVersion + capabilities |
| POST `/auth/v1/refresh` | RelayClient.refreshAccessToken() | 轮换制，新令牌对写回 PreferenceService |
| POST `/relay/v1/request` | HttpClient.doRequest relay 分支 | 包装 method/url/白名单 headers/bodyBase64；解包 status/headers/bodyBase64 |
| GET `/img/v1/fetch?url=` | ImageCacheService / DownloadService | relay 模式图片与下载 URL 包装 |
| POST `/sync/v1/push` | SyncService.pushDomain(domain) | baseToken + items ≤500/批；409→全量重建 |
| GET `/sync/v1/pull` | SyncService.pullDomain(domain) | since 游标 + hasMore 分页续拉 |
| GET `/recover/v1/illust/{pid}` | RecoverService.query(pid) | 200 ready / 202 fetching(retryAfterSec) / 404 not_found |

### 客户端内部接口

- **RelayClient**（单例）：`register(serverUrl, deviceName, inviteCode?, accountKey?): Promise<boolean>`、`refreshAccessToken(): Promise<boolean>`、`getValidToken(): Promise<string>`（过期前自动刷新）、`isRegistered(): boolean`、`getCapabilities(): string[]`、`relayRequest(options): Promise<http.HttpResponse>`（供 HttpClient.doRequest 调用，含 401 自刷新重放与失败计数回落）、`buildImageUrl(pixivUrl): string`（包装 /img/v1/fetch）、`logout(): void`
- **SyncService**（单例）：`startupPull(): Promise<void>`、`schedulePush(domain: string): void`（10s 防抖）、`syncNow(): Promise<void>`（设置页"立即同步"）、`getLastSyncText(domain): string`、`onBookmarkChanged(illust, bookmarked): void`（注册到 BookmarkStateStore 回调）、`pushBookmarkSnapshot(illust): void` / `pushBookmarkTombstone(illustId): void`
- **RecoverService**（单例）：`query(pid): Promise<RecoverResult>`、`pollUntilReady(pid, onProgress, maxAttempts=30): Promise<RecoverResult>`（支持取消令牌）
- **BookmarkStateStore 扩展**：`registerBookmarkChangeListener(listener): void` / `unregisterBookmarkChangeListener(listener): void`
- **IllustDetailStore 扩展**：`deletedSnapshot: BookmarkSnapshot | null`、`recoverState: string`（idle/polling/ready/failed）、`startRecover(): Promise<void>`
- **Constants 扩展**：`MODE_RELAY: string = 'relay'`、`isRelayMode(mode): boolean`、normalizeMode 放行 relay

### UI 契约

- SettingsPage"中继服务器"组：服务器地址输入 → 注册/登录按钮 → 已连接状态（账号 + 服务器版本）→ 同步开关 → 立即同步 + 每域最后同步时间 → 导出/导入同步账号（accountKey 复制 + 风险提示 AlertDialog）→ 注销；capabilities 缺失时同步/恢复入口隐藏
- 网络组"认证方式/API 方式"选项新增"中继"；relayServerUrl 为空时选中中继弹引导提示且不生效
- IllustDetailPage：404 + 有快照 → 快照元数据卡（标题/作者/页数/标签）+ "尝试从第三方恢复"按钮；轮询中显示进度 + 取消；成功跳 ImageViewerPage；失败 toast "暂无法从第三方恢复该作品"
- BookmarkPage：已删除作品渲染灰色占位卡片（快照标题 + "已删除"角标），点击进详情走兜底流程
