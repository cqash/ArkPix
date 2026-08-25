# ArkPix 后端服务设计文档

版本：v1.0 定稿
适用范围：ArkPix 客户端第四种网络模式（服务端中继）+ 数据同步备份 + 已删除作品恢复；Web 端（PC / 移动端浏览器）复用全部端点（见 §6.5）

---

## 1. 概述

后端服务（下称 Relay Server）部署在可正常访问 Pixiv 的网络环境中，为 ArkPix 客户端提供三类能力：

| 能力 | 说明 |
|---|---|
| 网络中继 | 代理 Pixiv API / OAuth / 图片请求，客户端新增第四种网络模式 `relay` |
| 数据同步 | 浏览历史、搜索历史、收藏快照、屏蔽列表、EXIF 配置、应用设置的上行备份与下行恢复 |
| 删除图恢复 | 通过 PID 从第三方图床/缓存拉回已被 Pixiv 删除的作品图片 |

设计目标：

- 协议无状态、可水平扩展（同步游标除外）
- 客户端改造最小化：新增模式值 + 一个 RelayInterceptor，不动现有 API 模型层
- 多用户隔离，凭据不下发服务器持有（客户端 token 仅在中继请求头中透传，不落库）

---

## 2. 总体架构

```
┌────────────┐   HTTPS    ┌──────────────────────────────────┐   HTTPS    ┌─────────────┐
│ ArkPix 客户端 │ ────────▶ │ Relay Server                     │ ────────▶  │ Pixiv API   │
│            │           │  ├─ /relay/*   API/OAuth 中继      │            │ i.pximg.net │
│            │           │  ├─ /img/*    图片中继(带Referer)  │ ────────▶  │ 第三方图床   │
│            │           │  ├─ /sync/*   数据同步             │            │ (pixiv.cat  │
│            │           │  ├─ /recover/* 删除图恢复          │            │  pixiv.re…) │
│            │           │  └─ /auth/*   服务账号/设备注册    │            └─────────────┘
└────────────┘           │  DB: 用户表 / 同步域表 / 恢复缓存表 │
                          └──────────────────────────────────┘
```

---

## 3. 客户端集成：第四种网络模式 `relay`

### 3.1 模式定义

- `NetworkMode` 新增枚举值：`relay`
- `Constants.normalizeMode()`：`relay` 原样保留；`standard`/`compatible`/`ech` 不变；旧值 `sni`/`doh`/`bypass` 仍归一化为 `compatible`
- `AppSettings` 新增字段：
  - `relayServerUrl: string`（默认空，空时 `relay` 模式不可用，设置页引导填写）
  - `relayAccessToken: string`（Relay Server 签发的访问令牌，见 §5）
  - `syncEnabled: boolean`、`syncLastToken: string`（同步游标，见 §7）

### 3.2 请求分流

`HttpClient.request()` 在模式为 `relay` 时：

1. `applyDirectIp` / `applyImageHost` 全部跳过（域名不改写、SNI 不处理）
2. 目标 URL 原样放入中继请求体，由服务端访问真实域名
3. 指向 `relayServerUrl`，证书校验正常（不做 `remoteValidation:'skip'`）
4. 注入 `Authorization: Bearer <relayAccessToken>`（服务级，非 Pixiv token）

图片加载（`ImageCacheService`/`DownloadService`）在 `relay` 模式下改走 `GET {relay}/img/v1/fetch?url=<encoded>`，不再自行注入 Referer（由服务端注入）。

---

## 4. 通用协议约定

### 4.1 传输与格式

- 全程 HTTPS，请求/响应体均为 JSON（图片/文件流除外）
- 字符编码 UTF-8；时间统一为 Unix 毫秒时间戳（`number`）
- 所有响应含 `requestId`（服务端生成，排障用）

### 4.2 错误格式

```json
{
  "error": {
    "code": "SYNC_CONFLICT",
    "message": "human readable",
    "requestId": "..."
  }
}
```

HTTP 状态码语义：

| 状态码 | 含义 |
|---|---|
| 200 | 成功 |
| 202 | 已受理，异步处理中（恢复任务） |
| 400 | 参数错误 |
| 401 | relayAccessToken 缺失/失效 |
| 403 | 无权限（如配额超限） |
| 404 | 资源不存在（含恢复失败） |
| 429 | 限流，响应头带 `Retry-After`（秒） |
| 502 | 上游 Pixiv 不可达 |

### 4.3 分页

列表端点统一游标分页：

- 请求：`?cursor=<opaque>&limit=<1..100>`（默认 30）
- 响应：`{ "items": [...], "nextCursor": "..." }`，`nextCursor` 为空串表示末页

---

## 5. 服务认证（/auth）

Relay Server 自有账号体系，与 Pixiv 账号解耦。多设备通过 `accountKey` 加入同一 Relay 账号实现同步（见 §5.1）。

### 5.1 设备注册

`POST /auth/v1/register`

```json
// 请求
{ "deviceName": "Mate 60", "inviteCode": "可选，私有部署用", "accountKey": "可选，加入已有账号" }
// 响应
{
  "accessToken": "rl_at_xxx",
  "refreshToken": "rl_rt_xxx",
  "expiresIn": 2592000,
  "accountKey": "rk_xxx"
}
```

- accessToken 有效期 30 天，refreshToken 有效期 180 天，轮换制（对齐 Pixiv refresh 轮换经验）
- `POST /auth/v1/refresh` 用 refreshToken 换新 token 对
- 账号与多设备：注册不传 `accountKey` 时创建新账号；传入有效 `accountKey` 时该设备加入对应账号，共享其同步数据；`accountKey` 无效按 400 拒绝（不静默新建账号，避免用户误以为已加入）。`accountKey` 在同一账号下恒定，客户端设置页提供"导出/导入同步账号"（复制字符串）
- `accountKey` 是账号级凭据，泄露等于同步数据泄露：客户端导出时风险提示；服务端只存其哈希，不落明文
- 私有部署可用固定 inviteCode 或直接预置 token，跳过注册流程

客户端侧 401 时自动 refresh 一次并重放，失败则提示"中继服务登录失效"并停留在设置页，不清空 Pixiv 登录态。

---

## 6. 网络中继协议（/relay、/img）

### 6.1 API / OAuth 中继

`POST /relay/v1/request`

```json
// 请求
{
  "method": "GET",
  "url": "https://app-api.pixiv.net/v1/illust/recommended?filter=for_android",
  "headers": {
    "Authorization": "Bearer <pixiv_access_token>",
    "Accept-Language": "zh-CN"
  },
  "bodyBase64": "",
  "timeoutMs": 30000
}
// 响应
{
  "status": 200,
  "headers": { "content-type": "application/json" },
  "bodyBase64": "..."
}
```

约束：

- `url` 域名白名单：`app-api.pixiv.net`、`oauth.secure.pixiv.net`、`www.pixiv.net`（排行榜页面等）
- `headers` 转发白名单：`Authorization`、`Accept-Language`、`Content-Type`、`User-Agent`、`Referer`；其余忽略
- 服务端**不记录** `Authorization` 头与 body（日志只记 method + 域名 + 状态码 + 耗时）
- body 上限 1 MB；超时上限 60 s，服务端钳制
- 服务端注入 Pixiv 要求的 `User-Agent: PixivIOSApp/5.8.0`（若客户端未传）
- OAuth token 接口（`oauth.secure.pixiv.net/auth/token`）同样走此端点，服务端使用常规 TLS（无 SNI 封锁问题），客户端 `OAuthService` 在 `relay` 模式下不再走 `TLSSocket` 手写 no-SNI 路径

### 6.2 图片中继

`GET /img/v1/fetch?url=<urlencoded>&disposition=inline`

- `url` 域名白名单：`i.pximg.net`、`i-f.pximg.net`、`s.pximg.net`；可通过 `IMG_EXTRA_HOSTS` 配置追加——恢复模块（§8）使用的第三方源域名必须在此显式声明，默认不放开任意域名，防止被当开放代理滥用
- 服务端注入 `Referer: https://app-api.pixiv.net/` + `User-Agent`
- 响应透传 `Content-Type`、`Content-Length`、`Cache-Control`；额外响应头 `X-Upstream-Status`
- 服务端可选磁盘缓存（键 = URL SHA-256，LRU，默认上限 20 GB，私有部署可配）
- 缓存命中 `X-Cache: HIT`；客户端忽略此头，仅作运维观测
- 单图上限 50 MB；失败映射：上游 404 → 404，超时 → 502

### 6.3 与现有模式的对比与降级

| 模式 | 适用网络 | 客户端改动 |
|---|---|---|
| standard | 可直连 | — |
| compatible | 被 SNI 封锁 | 现有 |
| ech | 同 compatible | 现有 |
| relay | 完全无法直连 / 需要同步 | 本文档 |

客户端在 `relay` 模式请求失败（连续 3 次 502/超时）时，toast 提示并自动回落到用户上一可用模式（仅提示，不静默改设置）。

### 6.4 存储布局与机械硬盘（HDD）优化选项

私有部署常落在机械硬盘上，图片缓存与 DB 提供以下可配置项（默认值即为 HDD 友好取向）：

| 配置项 | 默认 | 说明 |
|---|---|---|
| `CACHE_LAYOUT` | `sharded` | 缓存文件按哈希前缀分两级子目录（如 `ab/cd/<sha256>`），避免单目录数万文件导致目录项随机读；`flat` 仅适合小缓存 |
| `DB_PATH` / `CACHE_DIR` | 独立配置 | 建议 DB 与图片缓存分盘/分卷：小随机 IO（DB）与大顺序 IO（图片）互不干扰 |
| `CACHE_TMP_DIR` | `<CACHE_DIR>/tmp` | 临时文件必须与缓存目录同卷，保证写完 rename 原子落盘；跨卷 rename 会退化为 copy，产生额外随机 IO |
| `CACHE_HIGH_WATERMARK` | 90% | 缓存用量达到水位才触发 LRU 淘汰；淘汰批量限速执行，避免瞬时大量随机删除打满磁盘队列 |
| `CACHE_EVICTION_BATCH` | 500 文件/批，批间隔 100 ms | 淘汰限速参数，可按盘性能调 |

实现层强制约束（非配置项）：

- SQLite：WAL + `synchronous=NORMAL`，写事务合并批量提交；DB 只存结构化小数据与缓存元数据，**绝不存图片 blob**
- 缓存元数据（size/atime/expire）存 DB，LRU 按 DB 内 atime 排序，不依赖文件系统 atime（部署侧建议 `noatime` 挂载）
- 图片读写全程流式：写 = 下载到临时文件 → 校验大小 → rename 落盘；读 = `createReadStream` 管道直出；禁止整文件读入内存
- LRU 扫描只在启动与水位触发时执行，日常命中路径不做 `stat`
- 恢复抓取临时目录独立于缓存目录，避免抓取写与缓存读竞争同一磁盘队列

### 6.5 Web 客户端支持

Web 端（PC 浏览器为主，移动端浏览器兜底）复用本文档全部端点，等价于**只运行 `relay` 模式**的客户端：浏览器无法直连 Pixiv，也不存在 SNI 绕过需求，API/图片请求天然全部走中继。

- **同源托管（推荐）**：Relay Server 直接托管 Web 前端静态资源（SPA），`https://<relay>/` 为网页、`/v1/*` 为 API，同源部署无 CORS 问题；静态资源可嵌入二进制或随镜像分发
- **跨域部署（可选）**：前端托管在其他域名时，服务端按 `CORS_ORIGINS` 白名单放开 `Access-Control-Allow-*`，默认关闭
- **认证**：复用 `/auth/v1/register`（deviceName 标记如 `Web/Chrome`），token 存 `localStorage`；多设备同步通过导入 `accountKey` 加入已有账号（§5.1）。v1 不引入 Cookie 会话
- **Pixiv 登录**：Web 端无法使用 App 的 WebView 抓包登录，采用 refresh_token 导入（App 端"导出 Token"功能的产物）或将账号密码登录请求经 `/relay` 走 OAuth 接口
- **图片加载**：`<img>` 直引 `{relay}/img/v1/fetch?url=...`，Referer 由服务端注入，浏览器无感
- Web 前端为独立工程（Vue/React 等自选），不在 Relay Server 仓库内；服务端只负责静态托管与可选 CORS

---

## 7. 数据同步协议（/sync）

### 7.1 同步域（domain）

| domain | 内容 | 冲突策略 |
|---|---|---|
| `history` | 浏览历史（illust_id、title、user_name、thumb、viewed_at） | 按 illust_id 去重，viewed_at 大者胜（LWW） |
| `search_history` | 搜索历史（keyword、search_type、updated_at） | 按 keyword+search_type 去重，LWW |
| `bookmark_snapshot` | 收藏快照（见 §7.3） | 按 illust_id 去重，LWW；删除用墓碑 |
| `mute` | 屏蔽词/屏蔽作者（MuteItem 列表） | 按 key 的 LWW，删除用墓碑（净效果为集合并集） |
| `exif_config` | exifMutedTags / exifMergedTags / exifTagPriority / exifCommentTemplate | 整条 LWW |
| `settings` | AppSettings 可序列化字段（排除 token 类敏感字段） | 整条 LWW |

### 7.2 推送与拉取

`POST /sync/v1/push`

```json
// 请求
{
  "domain": "history",
  "baseToken": "st_1718000000000_abcd",
  "items": [
    { "key": "12345678", "data": { "...": "..." }, "updatedAt": 1718000000000, "deleted": false }
  ]
}
// 响应
{ "accepted": 10, "syncToken": "st_1718000001234_efgh", "conflicts": [] }
```

`GET /sync/v1/pull?domain=history&since=<syncToken>&limit=100`

```json
{
  "items": [ { "key": "...", "data": {}, "updatedAt": 0, "deleted": false } ],
  "syncToken": "st_...",
  "hasMore": false
}
```

规则：

- `syncToken` 按（账号 × domain）单调递增（时间戳+随机串），不同账号/域之间互不可比；客户端每域持久化最近一次
- `baseToken` 与服务端当前不一致且差窗口超过保留期（90 天）→ 返回 `409 + code:SYNC_FULL_REQUIRED`，客户端清空本地该域后全量 pull
- 删除传播：客户端删除条目时 push `deleted: true` 墓碑；墓碑服务端保留 90 天
- 推送幂等：同 key 重复推送按 updatedAt 取大者，天然幂等
- 单域单次 push 上限 500 条；超限分批
- 敏感字段排除清单（永不离开设备）：Pixiv access/refresh token、`relayAccessToken`

### 7.3 收藏快照结构（bookmark_snapshot）

```json
{
  "key": "<illust_id>",
  "data": {
    "illustId": 12345678,
    "title": "...",
    "userId": 111, "userName": "...",
    "restrict": "public",
    "pageCount": 3,
    "width": 1000, "height": 1400,
    "tags": ["..."],
    "createDate": "2024-01-01T00:00:00+09:00",
    "imageUrls": [
      "https://i.pximg.net/img-original/img/.../12345678_p0.jpg"
    ],
    "bookmarkedAt": 1718000000000
  },
  "updatedAt": 1718000000000,
  "deleted": false
}
```

- 客户端在 star 成功后异步生成快照 push（fire-and-forget，失败下轮重试）
- unstar → push 墓碑
- 快照是"已删除作品恢复"（§8）的元数据与 URL 来源
- 客户端首页/收藏页可用快照渲染"已被删除"占位条目（灰色卡片 + 标题 + 恢复按钮）

### 7.4 同步时机

- 应用启动后 5 s 空闲触发一次全域 pull
- 本地写入后 10 s 防抖批量 push
- 设置页提供"立即同步"手动入口与每域最后同步时间展示

**客户端顺序约束（勿回退）**：由于 §7.2 的 syncToken 水位随 push 跳到≈当前时间戳、pull 只返回 `seq > since`，任何 push 前必须已完成一次全量 pull，否则游标会越过后端已有条目且之后增量 pull 永远拉不到。客户端实现：每域偏好 `sync_initial_pulled_<domain>` 记录全量 pull 是否完成；未完成时 push 前重置游标做全量拉取（LWW 合并不清本地）；push 后按 push 前游标补拉一轮捕获窗口期其他设备写入；history/search_history 墓碑 applier 亦走 LWW。

---

## 8. 已删除作品恢复（/recover）

### 8.1 恢复查询

`GET /recover/v1/illust/{pid}`

```json
// 200 已有缓存
{
  "status": "ready",
  "pages": [
    { "page": 0, "url": "https://<relay>/img/v1/fetch?url=<第三方源URL>", "width": 1000, "height": 1400 }
  ],
  "source": "pixiv_cat",
  "meta": { "title": "...", "userName": "..." }
}
// 202 首次请求，后台抓取中
{ "status": "fetching", "retryAfterSec": 5 }
// 404 所有源均无
{ "status": "not_found" }
```

### 8.2 服务端抓取流程

1. 收到请求 → 查恢复缓存表（pid → pages[]），命中直接 200
2. 未命中 → 入异步队列，返回 202
3. 抓取器按优先级尝试数据源：
   - 客户端 push 的收藏快照中保存的原图 URL（可能仍在 CDN 存活期）
   - 第三方镜像/图床（如 pixiv.cat、pixiv.re 等，按 `https://<mirror>/<pid>.jpg`、`<pid>_p<N>.jpg` 规则探测，可配置源列表与优先级）
   - 其他可配置源（插件化，HTTP 探测 + 内容校验）
4. 抓取成功 → 图片落服务端缓存 + 记录 source → 后续请求 200
5. 全部失败 → 记录负缓存（7 天）→ 404；负缓存过期后允许重试

约束：

- 抓取并发每源 ≤ 2，全局 ≤ 8；单源探测间隔 ≥ 1 s（礼貌策略，配置可调）
- 第三方源同样需要 Pixiv 风格 Referer 的由源配置声明
- 可见性分两层：`/img` 磁盘缓存按 URL 哈希跨用户共享（内容为公开图片，仅作存储复用）；`/recover` 查询结果按账号隔离，不做跨账号共享命中（私有部署可通过配置放开共享）

### 8.3 客户端交互

- 详情页打开已删除作品（API 404）→ 检查本地/同步的收藏快照 → 有快照则展示快照元数据 + "尝试从第三方恢复"按钮
- 点击后轮询 `GET /recover/v1/illust/{pid}`（间隔 `retryAfterSec`，最多 30 次）
- 恢复成功后走 `ImageViewerPage` 展示，`url` 直接可喂 `CachedImage`（已带中继包装）

---

## 9. 安全与隐私

- 服务认证与 Pixiv 凭据完全分离；服务端日志不落 Pixiv token（日志中间件头部脱敏）
- 同步数据在服务端静态加密（如 AES-256-GCM，密钥由部署方管理；高隐私需求可后续升级为客户端侧加密，v1 不做）
- 所有写端点限流：认证用户 60 req/min，图片中继 300 req/min
- 恢复缓存默认 TTL 90 天，可配置
- 公网部署必须配置 `INVITE_CODES` 或 `STATIC_TOKENS`：未配置时 `/auth/v1/register` 为开放注册，等于向公众提供免费中继与存储；注册端点单独限流（默认 10 次/小时/IP）防批量注册
- 私有部署建议：HTTPS 反代 + 防火墙白名单 + inviteCode 注册

---

## 10. 部署形态

| 形态 | 说明 |
|---|---|
| 私有单用户 | Docker 单容器，SQLite，内置 inviteCode 注册；服务端亦可直接运行在有代理的环境并配置上游 HTTP 代理出口 |
| 多用户小实例 | 外置 PostgreSQL + 本地磁盘缓存 |
| 机械硬盘部署 | 采用 §6.4 默认配置即可；建议 `noatime` 挂载缓存卷、DB 与缓存分卷 |
| Web 托管 | 服务端同源托管 SPA 静态资源（可嵌入二进制，§6.5）；跨域部署时配置 `CORS_ORIGINS` |
| 上游出口 | 服务端支持 `UPSTREAM_PROXY=http://...` 环境变量，中继与抓取请求经代理出网（即"内置代理功能"） |

---

## 11. 客户端改造清单（对应现有代码）

| 位置 | 改动 |
|---|---|
| `models/AppSettings.ets` | 新增 `relayServerUrl`、`relayAccessToken`、`syncEnabled`、`syncLastToken`（按域拆分 Map） |
| `utils/Constants.ets` | `normalizeMode` 放行 `relay`；新增 `isRelayMode()` |
| `network/HttpClient.ets` | 新增 RelayInterceptor（或 request 内分流）：`relay` 模式下改写为 `/relay/v1/request` 包装请求 |
| `network/OAuthService.ets` | `relay` 模式下 token 接口走中继端点，跳过 `TLSSocket` no-SNI 路径 |
| `services/ImageCacheService.ets`、`services/DownloadService.ets` | `relay` 模式下图片 URL 包装为 `/img/v1/fetch?url=`，跳过 `applyDirectIp`/Referer 注入 |
| `services/` 新增 `SyncService.ets` | 域同步调度（防抖 push、启动 pull、游标持久化） |
| `services/` 新增 `RecoverService.ets` | 恢复查询与轮询 |
| `pages/detail/IllustDetailPage` | 404 时快照兜底 UI + 恢复入口 |
| `pages/settings/` | 中继服务器配置组（地址、登录、同步开关、立即同步） |
| `stores/BookmarkStateStore.ets` | star/unstar 成功后触发收藏快照 push |

---

## 12. 版本兼容

- 所有端点路径带 `/v1/`；破坏性变更升级 `/v2/`，旧版本至少保留 6 个月
- 客户端在 `/auth/v1/register` 响应中获得 `serverVersion` 与支持能力列表 `capabilities: ["relay","img","sync","recover"]`，按能力降级 UI

---

## 13. 端点汇总

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/auth/v1/register` | 设备注册 |
| POST | `/auth/v1/refresh` | 刷新服务令牌 |
| POST | `/relay/v1/request` | API/OAuth 通用中继 |
| GET | `/img/v1/fetch` | 图片中继 |
| POST | `/sync/v1/push` | 增量上行 |
| GET | `/sync/v1/pull` | 增量下行 |
| GET | `/recover/v1/illust/{pid}` | 删除图恢复查询 |
| GET | `/healthz` | 存活探针（无需鉴权，部署监控用） |
