# Feature Specification: Relay Server 客户端集成（中继模式 / 数据同步 / 删除图恢复）

**Created**: 2026-08-14
**Status**: Draft
**Input**: User description: "根据 docs/backend-design.md 开始构建功能；后端在 D:\work\pix_backend 由 kimi code 并行编写中（尚未完成）；实现范围：全部实现"

## Overview

为 ArkPix 客户端接入自托管后端 Relay Server，新增第四种网络模式 `relay`（API/OAuth/图片全部经服务端中转）、账号级数据同步（浏览历史/搜索历史/收藏快照/屏蔽列表/EXIF 配置/应用设置）与已删除作品恢复能力。使处于完全无法直连 Pixiv 网络环境的用户可正常使用应用，并能跨设备备份/恢复个人数据、找回已被 Pixiv 删除的收藏作品。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 配置中继服务器并以 relay 模式浏览 (Priority: P1)

用户在设置页"中继服务器"配置组填写服务器地址并完成设备注册（可选导入 accountKey 加入已有账号），随后将网络模式切换为 `relay`。此后推荐/排行/搜索等所有 API 请求、OAuth 登录/刷新、图片加载全部经中继服务器转发，客户端不再做任何直连 IP/SNI 处理，在完全无法直连 Pixiv 的网络下也能正常浏览。

**Why this priority**: 这是整个特性的地基。中继配置与服务认证是所有后续功能（同步、恢复）的前提；relay 网络模式本身就是核心价值（解决"完全无法直连"场景），仅此一项即可独立交付 MVP。

**Independent Test**: 在无 Pixiv 直连能力的网络环境下，配置中继地址 → 注册 → 切换 relay 模式 → 打开推荐页正常出图、详情页可加载、登录刷新 token 成功，即验证本故事独立成立。

**Acceptance Scenarios**:

1. **Given** 用户未配置 relayServerUrl，**When** 尝试将网络模式切换为 relay，**Then** 系统引导用户先填写服务器地址，relay 选项不可生效
2. **Given** 用户已填写有效服务器地址，**When** 点击注册（不传 accountKey），**Then** 获得服务令牌对并持久化，设置页显示已连接状态
3. **Given** relay 模式已启用，**When** 浏览推荐/排行/搜索/详情，**Then** 所有请求经 `/relay/v1/request` 转发、图片经 `/img/v1/fetch` 加载，行为与 compatible 模式体验一致
4. **Given** relay 模式下 OAuth token 过期，**When** 触发刷新，**Then** 刷新请求经中继转发（不走 TLSSocket no-SNI 路径），成功后继续浏览
5. **Given** relay 模式下服务返回 401，**When** 客户端检测到，**Then** 自动用 refreshToken 刷新一次并重放；仍失败则提示"中继服务登录失效"并停留在设置页，不清空 Pixiv 登录态
6. **Given** relay 模式下中继连续 3 次 502/超时，**When** 发生失败，**Then** toast 提示并自动回落到用户上一可用模式（仅提示，不静默改设置）

---

### User Story 2 - 多设备数据同步（上行备份与下行恢复） (Priority: P2)

用户在设置页开启同步开关。应用启动后空闲时自动拉取各同步域的远端增量；本地产生浏览历史、搜索历史、屏蔽变更、EXIF 配置变更、应用设置变更、收藏/取消收藏后，经防抖批量上行。用户可通过"导出/导入同步账号"（accountKey 字符串复制）让第二台设备加入同一 Relay 账号，从而在设备间恢复全部同步数据。设置页提供"立即同步"手动入口与每域最后同步时间展示。

**Why this priority**: 同步是后端第二大能力，依赖 Story 1 的服务认证但可独立交付；对多设备用户价值高（换机不丢数据、多设备一致）。

**Independent Test**: 设备 A 产生浏览历史/屏蔽词/设置变更 → 立即同步 → 设备 B 导入同一 accountKey → 拉取后 B 端出现对应数据；在 B 端修改后 A 端下一轮同步可见，即验证独立成立。

**Acceptance Scenarios**:

1. **Given** 同步开关开启，**When** 应用启动后约 5 秒空闲，**Then** 触发一次全域 pull，各域 syncToken 持久化
2. **Given** 用户新增一条浏览历史/搜索历史/屏蔽项，**When** 本地写入后约 10 秒，**Then** 该域变更经防抖批量 push 上行，最后同步时间更新
3. **Given** push 时 baseToken 与服务端差距超过保留期，**When** 服务端返回 SYNC_FULL_REQUIRED，**Then** 客户端清空本地该域后全量 pull 重建
4. **Given** 同一 illust_id 的浏览历史在两端均有记录，**When** 同步合并，**Then** 按 viewed_at 大者胜（LWW）保留较新一条
5. **Given** 用户删除某同步条目（如清空屏蔽项），**When** push 上行，**Then** 以墓碑（deleted 标记）传播，其他设备拉取后同样移除
6. **Given** 用户在设置页导出同步账号，**When** 执行导出，**Then** 展示 accountKey 并提供复制，带泄露风险提示
7. **Given** 同步内容包含敏感字段，**When** 构建上行数据，**Then** Pixiv access/refresh token、relayAccessToken 等凭据永不上行

---

### User Story 3 - 收藏快照与已删除作品恢复 (Priority: P3)

用户收藏作品成功后，客户端异步生成收藏快照（元数据 + 原图 URL 列表）上行。此后若某收藏作品被 Pixiv 删除：打开详情页 API 返回 404 时，客户端检查本地/同步的收藏快照，有快照则展示快照元数据（标题/作者/页数等）与"尝试从第三方恢复"按钮；点击后轮询恢复查询接口，成功后用查看器展示恢复出的图片；服务端确认不可恢复时给出明确提示。收藏页可用快照渲染"已被删除"占位条目（灰色卡片 + 标题 + 恢复入口）。

**Why this priority**: 依赖 Story 1（中继通道）与 Story 2 的收藏快照上行，是最高层的增值能力，可最后交付。

**Independent Test**: 收藏某作品 → 触发快照上行 → 模拟该作品 API 404 → 详情页显示快照兜底 UI 与恢复按钮 → 点击后若服务端有缓存直接展示，否则轮询直至成功/失败提示，即验证独立成立。

**Acceptance Scenarios**:

1. **Given** 同步开启且用户收藏成功，**When** star 完成，**Then** 客户端异步 push 收藏快照（含 imageUrls），失败时下轮重试，不阻塞收藏操作本身
2. **Given** 用户取消收藏，**When** unstar 完成，**Then** push 墓碑快照
3. **Given** 详情页请求返回 404（作品已删除），**When** 本地/同步快照存在，**Then** 展示快照元数据与"尝试从第三方恢复"按钮，而非普通错误页
4. **Given** 点击恢复按钮且服务端返回 fetching，**When** 客户端轮询，**Then** 按 retryAfterSec 间隔轮询（最多 30 次），期间展示进度提示，可取消
5. **Given** 恢复成功返回 pages 列表，**When** 轮询命中 ready，**Then** 用查看器展示恢复图片，图片 URL 可直接喂给现有图片组件
6. **Given** 服务端返回 not_found，**When** 轮询或查询命中，**Then** 明确提示"暂无法从第三方恢复该作品"
7. **Given** 收藏页存在已删除作品的快照，**When** 展示列表，**Then** 渲染灰色占位卡片（标题 + 恢复入口），点击进详情走 Story 3 兜底流程

---

### Edge Cases

- 未配置服务器地址/未注册时切换 relay：阻止切换并引导配置
- relay 模式下服务器不可达（网络断开、502 连续失败）：toast + 回落上一可用模式，不清除配置
- 服务令牌 401：自动刷新一次重放；refreshToken 也失效 → 停留在设置页提示重新注册/导入
- 同步时设备离线：push/pull 静默失败，保留本地游标，下轮重试；不丢本地数据
- 同一账号多设备同时写同一域：LWW 合并，最终以 updatedAt 大者为准
- 已删除作品无快照且未开启同步：详情页展示普通 404 错误态（无恢复入口）
- 恢复轮询中超时/取消/页面退出：停止轮询，不残留后台任务
- 快照上行失败（网络异常）：记入待重试状态，下轮同步重试，不影响收藏主流程
- 服务端不支持某能力（capabilities 缺失 sync/recover）：设置页与详情页相应入口按能力降级隐藏

## Requirements *(mandatory)*

### Functional Requirements

**中继模式（Relay Mode）**

- **FR-001**: 系统 MUST 在 `NetworkMode` 中新增 `relay` 模式值，`normalizeMode()` 原样放行 `relay`，其余行为不变
- **FR-002**: 系统 MUST 在应用设置中新增 `relayServerUrl`、`relayAccessToken`（及其配套刷新令牌/过期信息）、`syncEnabled`、各域同步游标字段
- **FR-003**: relay 模式下所有 Pixiv API 与 OAuth 请求 MUST 改写为对 `/relay/v1/request` 的包装请求（方法/URL/白名单头/body 原样放入请求体），跳过 `applyDirectIp`/`applyImageHost` 改写与 `remoteValidation:'skip'`
- **FR-004**: relay 模式下 OAuth token 接口 MUST 走中继端点，跳过 `TLSSocket` 手写 no-SNI 路径
- **FR-005**: relay 模式下图片加载与下载 MUST 走 `/img/v1/fetch?url=` 包装，不再自行注入 Referer/User-Agent
- **FR-006**: relay 模式请求 MUST 注入服务级 `Authorization: Bearer <relayAccessToken>`，与 Pixiv token 分离
- **FR-007**: 服务返回 401 时系统 MUST 自动用服务 refreshToken 刷新一次并重放原请求；刷新失败则提示"中继服务登录失效"并停留在设置页，不清空 Pixiv 登录态
- **FR-008**: relay 模式连续 3 次 502/超时失败时，系统 MUST toast 提示并回落到用户上一可用模式（仅提示，不静默修改持久化设置）
- **FR-009**: relayServerUrl 为空时 relay 模式 MUST 不可生效，设置页提供引导填写

**服务认证与账号**

- **FR-010**: 系统 MUST 支持设备注册（`deviceName`，可选 `inviteCode`/`accountKey`），并将 accessToken/refreshToken/过期时间安全持久化
- **FR-011**: 系统 MUST 在服务令牌过期前或 401 时按轮换制刷新令牌对并写回持久化
- **FR-012**: 系统 MUST 提供"导出/导入同步账号"入口（复制 accountKey 字符串），导出时展示泄露风险提示
- **FR-013**: 系统 MUST 根据注册响应的 `capabilities` 对 UI 入口按能力降级（无 sync 能力隐藏同步组，无 recover 能力隐藏恢复入口）

**数据同步**

- **FR-014**: 系统 MUST 实现六个同步域的上行与下行：`history`、`search_history`、`bookmark_snapshot`、`mute`、`exif_config`、`settings`
- **FR-015**: 各域冲突 MUST 按设计文档策略合并：history 按 illust_id 去重 LWW（viewed_at）；search_history 按 keyword+search_type 去重 LWW；bookmark_snapshot 按 illust_id LWW + 墓碑；mute 按 key LWW + 墓碑；exif_config/settings 整条 LWW
- **FR-016**: 系统 MUST 在应用启动后约 5 秒空闲触发一次全域 pull（syncEnabled 时）
- **FR-017**: 系统 MUST 在本地写入后约 10 秒防抖批量 push 对应域
- **FR-018**: 每域 syncToken MUST 持久化，pull 按 since 增量拉取，hasMore 时分页续拉
- **FR-019**: 收到 SYNC_FULL_REQUIRED 时 MUST 清空本地该域并全量 pull 重建
- **FR-020**: 本地删除条目 MUST 以墓碑（deleted）上行传播
- **FR-021**: 单域单次 push 超 500 条 MUST 分批
- **FR-022**: 上行数据 MUST 排除 Pixiv access/refresh token、relayAccessToken 等敏感字段
- **FR-023**: 设置页 MUST 提供"立即同步"手动入口与每域最后同步时间展示
- **FR-024**: 离线/同步失败 MUST 不丢本地数据，保留下轮重试

**收藏快照与删除图恢复**

- **FR-025**: star 成功后系统 MUST 异步生成收藏快照（illustId/title/user/restrict/pageCount/尺寸/tags/createDate/imageUrls/bookmarkedAt）push 上行（fire-and-forget，失败下轮重试）
- **FR-026**: unstar 成功后 MUST push 墓碑快照
- **FR-027**: 详情页 API 返回 404 时，若存在本地/同步快照，MUST 展示快照元数据 + "尝试从第三方恢复"按钮
- **FR-028**: 点击恢复后 MUST 按 retryAfterSec 间隔轮询恢复查询（最多 30 次），支持取消
- **FR-029**: 恢复成功 MUST 用现有查看器展示恢复图片（URL 直接可用）
- **FR-030**: 恢复失败（not_found）MUST 给出明确文案提示
- **FR-031**: 收藏列表中已删除作品 MUST 可渲染灰色占位卡片（标题 + 恢复入口）

### Key Entities

- **RelayAccount**: 服务账号（accessToken/refreshToken/过期时间/accountKey/serverVersion/capabilities），与 Pixiv 账号完全解耦
- **SyncItem**: 同步条目（key / data / updatedAt / deleted），按域分组
- **SyncCursor**: 每域同步游标（syncToken、最后同步时间）
- **BookmarkSnapshot**: 收藏快照（作品元数据 + 原图 URL 列表 + bookmarkedAt）
- **RecoverResult**: 恢复查询结果（ready 的 pages 列表 / fetching 的 retryAfterSec / not_found）

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 在完全无法直连 Pixiv 的网络环境下，用户完成中继配置后可正常浏览推荐/搜索/详情，图片加载成功率 ≥ 95%
- **SC-002**: relay 模式下浏览体验与非 relay 模式无显著差异（列表首屏加载不超过普通模式的 1.5 倍耗时）
- **SC-003**: 用户在第二台设备导入 accountKey 后，5 分钟内可恢复全部六类同步数据
- **SC-004**: 本地数据变更（历史/屏蔽/设置等）在 ≤ 15 秒内自动上行，无需手动操作
- **SC-005**: 已删除且有快照的收藏作品，用户从详情页 3 步内可发起恢复；服务端已有缓存时 ≤ 5 秒展示图片
- **SC-006**: 同步/中继失败时本地数据零丢失，且用户可回落到原有网络模式继续使用

## Assumptions

- 后端 Relay Server 由另一工程（D:\work\pix_backend）按 docs/backend-design.md v1.0 实现，端点、错误码、字段名以该文档为准；本特性仅做客户端改造
- 后端尚在开发中，客户端实现以协议文档为契约先行；联调问题后续迭代处理
- relay 模式下证书校验正常（服务端需配置合法 HTTPS 证书；私有部署自签证书场景不在 v1 范围）
- 同步为尽力而为（best-effort）：应用未启动期间不产生同步；不做实时推送
- 收藏快照上行仅在 syncEnabled 时进行；未开启同步则无快照，删除图恢复不可用的降级属预期行为
- 墓碑保留期、限流配额、抓取并发等均为服务端约束，客户端仅需正确处理对应响应
- 图片中继 URL 包装结果与普通图片 URL 在客户端展示层完全等价（可直接喂 CachedImage / 查看器）
- settings 域上行仅包含 AppSettings 可序列化非敏感字段；明确排除 token 类字段

## Open Questions

- 后端实际实现的字段名/错误码若与设计文档有出入，联调阶段以哪方为准？（默认：以文档为契约，后端对齐文档）
- 收藏页"已被删除"占位卡片与正常收藏列表的混合排序规则（默认：按 bookmarkedAt 倒序混排，占位卡片置灰）
- recover 恢复出的图片是否允许用户保存到相册/嵌入 EXIF（默认：允许保存，EXIF 使用快照元数据渲染，源标注 recovered）
