# RESUME — Relay Server 客户端集成：新会话快速恢复指南

> 面向"新会话快速恢复进度进行端到端测试与修复"。读完本文件 + spec/plan/tasks 三份规格即可接续工作。

## 特性概述

为 ArkPix（HarmonyOS ArkTS 客户端）接入自托管 Relay Server：新增第四种网络模式 `relay`（API/OAuth 走 `POST /relay/v1/request` 包装、图片走 `GET /img/v1/fetch`）、六域数据同步（history/search_history/bookmark_snapshot/mute/exif_config/settings，LWW+墓碑）、已删除收藏作品恢复（快照兜底 + /recover 轮询 + 查看器展示），另内置"后端自检"六端点探测功能。

## 关键文档路径

- 规格：`D:\work\pixiv-\spec\relay-server-integration\spec.md`（需求与验收场景）
- 计划：`D:\work\pixiv-\spec\relay-server-integration\plan.md`（架构决策 D1–D10）
- 任务：`D:\work\pixiv-\spec\relay-server-integration\tasks.md`（T001–T024 已全部勾掉；T025–T027 为 Verification 阶段）
- 本文件：`D:\work\pixiv-\spec\relay-server-integration\RESUME.md`
- 后端契约（最终权威）：`D:\work\pix_backend\docs\api.md`

## 实现完成状态摘要

T001–T024 全部完成，build_project（hvigorw assembleHap）通过。新增 5 文件 + 修改 18 文件：

**新增**
- `entry/src/main/ets/models/RelayModels.ets`（RelayAccount/SyncItem/BookmarkSnapshot/RecoverResult 等 + fromJson）
- `entry/src/main/ets/network/RelayClient.ets`（单例：register/refresh/relayRequest/authorizedRequest/buildImageUrl/logout + 401 自刷新 + 连续 3 次 502/超时回落）
- `entry/src/main/ets/services/SyncService.ets`（单例：六域 collector/applier、10s 防抖 push、启动 pull、409 全量重建、敏感字段递归剔除）
- `entry/src/main/ets/services/RecoverService.ets`（单例：query + pollUntilReady 可取消轮询）
- `entry/src/main/ets/services/RelaySelfTestService.ets`（单例：六端点自检，入口在设置页"中继服务器"组"后端自检"按钮）
- `entry/src/test/RelaySync.test.ets`（12 个纯函数单测，已注册进 List.test.ets）

**修改要点**：Constants（MODE_RELAY/isRelayMode/normalizeMode 放行）、AppSettings+UserSettingStore（relayServerUrl/syncEnabled/prevAuthMode/prevApiMode 四字段 + 同步写入 hook）、HttpClient（doRequest 末端 relay 分流）、OAuthService（relay 旁路 TLSSocket）、ApiService（HttpStatusError 携带 statusCode）、DatabaseService（bookmark_snapshots 表 + 同步 hook + 墓碑收集）、BookmarkStateStore（变更回调注册表）、IllustDetailStore/Page（404 快照兜底 + 恢复编排）、BookmarkPage + IllustCard + Illust（已删除灰色占位卡片）、ImageCacheService/DownloadService（relay 图片包装）、SplashPage（启动 5s 后 startupPull，见下方已修复事故）、SettingsPage（中继组 + 同步组 + 后端自检覆盖层）。

**已修复事故（2026-08-15 冷启动闪退）**：EntryAbility 曾静态 import SyncService → 模块求值链触发 UserSettingStore 模块级单例 `getInstance()` → 构造函数 loadSettings 访问 PreferenceService 时 `context` 尚未注入 AppStorage（onCreate 未执行）→ `UIAbilityContext not found in AppStorage` jscrash。修复：启动同步 pull 挂载点从 EntryAbility.onCreate 移至 SplashPage.aboutToAppear（页面模块在 context 注入后才加载）。**规则：EntryAbility（及任何在 onCreate 前求值的模块）不得静态 import 依赖链上含模块级 Store 单例的模块**（UserSettingStore/BookmarkStateStore/AccountStore 等均为此类）。

**5 条偏离决策**（详见实现报告）：
1. OAuth relay 路径走 `relayClient.relayRequest` 而非 HttpClient.post（避免 AuthInterceptor 递归刷新死锁）
2. 收藏页占位卡片置列表头部（API 列表无收藏时间戳，无法真实混排）
3. exif_config 域四字段 = exifMutedTags/exifMergedTags/exifTagPriority/exifCommentTemplate
4. settings 域下行不覆盖本机 syncEnabled；authMode/apiMode/proxy*/sniHost 不上行
5. RelayClient 公共 `authorizedRequest()` 供 Sync/Recover/SelfTest 复用

**契约对齐修复（对照 api.md 终版）**：refresh 仅 401 清凭据（400 上抛）；relay 信封补 `timeoutMs:30000`；sync push 的 `data` 改为 JSON **对象**（本地模型内仍为 JSON 串，wire 层转换）、pull 补 `limit=100`；recover 元数据改从 `meta` 对象解析；`buildImageUrl` 加"已是本中继 URL 不重复包装"守卫（recover pages[].url 已是 `{base}/img/v1/fetch?url=...` 形式）。

## 后端工程（D:\work\pix_backend）

- M0–M8 已全部完成（含 /recover 与部署、验收）。启动方式：
  - `go run ./cmd/server`（或 `bin/` 下既有二进制；Windows 可用根目录 `start.bat`）
  - 详见其 `PLAN.md` / `README.md` / `.env.example`
- 常用环境变量（复制 `.env.example` 为 `.env` 或直接设环境变量）：
  - `PORT=8080`（监听端口）
  - `INVITE_CODES=code1,code2`（公网部署必须配置，空=开放注册仅限私有网络；客户端注册时在"邀请码"填入其一）
  - `IMG_EXTRA_HOSTS=i.pixiv.cat,i.pixiv.re`（**恢复源镜像域名必须在此声明，否则客户端取恢复图 403**）
  - `UPSTREAM_PROXY=http://127.0.0.1:7890`（服务器自身无法直连 Pixiv 时配上游代理）
  - 可选：`STATIC_TOKENS`、`RATE_*`、`RECOVER_*`、`DATA_ENC_KEY`、`RELAY_EXTRA_HOSTS`
- 注意：relay/img 端点强制上游 https；客户端 relayServerUrl 也需是服务端可达的合法 HTTPS（自签证书 v1 不支持）。**纯局域网 HTTP 测试需确认服务端是否允许 http 监听地址直连**——客户端对 relayServerUrl 本身不强制 https（仅包装的上游 URL 强制 https）。

## 端到端验证步骤清单

1. **启动后端**：`cd D:\work\pix_backend` → 配好 `.env`（至少 PORT；公网配 INVITE_CODES；要验证 US3 恢复则 IMG_EXTRA_HOSTS 含恢复源域名）→ `go run ./cmd/server` → 浏览器或 curl 访问 `http://<host>:<PORT>/healthz` 确认 `{"status":"ok"}`。
2. **App 注册**：设置页 → "中继服务器"组 → 填服务器地址（如 `https://relay.example.com`）→（可选邀请码）→ 点"注册 / 登录"→ 状态行显示"已连接 · v1.x.x"。
3. **切中继模式**：网络组"认证方式"与"API 方式"均选"中继"（两个都要切）。
4. **后端自检**：中继组点"后端自检"→ 弹层逐项实时刷新，全部通过应显示"后端功能全部就绪 (6/6)"。
5. **US1 冒烟**：推荐/排行/搜索/详情正常加载出图；杀掉 App 重进（触发 token 过期刷新链路）仍正常。
6. **US2 同步**：开启"数据同步"→ 点"立即同步"→ 六域显示最后同步时间；单端验证：产生浏览历史/屏蔽词 → 等 10s 防抖或立即同步 → 后端 DB（`data/relay.db`）可见对应条目；双端验证：设备 B "同步账号"栏粘贴设备 A"导出同步账号"的 accountKey → 注册加入 → 立即同步 → B 出现 A 的历史/屏蔽/设置。
7. **US3 恢复**：同步开启状态下收藏某作品（产生快照）→ 模拟该作品 404（或挑选已被 Pixiv 删除的作品 id 直接 `搜索页输入纯数字 → 插画 ID 直达`）→ 详情页出现快照元数据卡 + "尝试从第三方恢复"→ 点击后轮询进度/可取消 → ready 跳查看器；not_found 弹"暂无法从第三方恢复该作品"。收藏页头部应出现已删除作品灰色占位卡片。

## 已知待联调风险

- 图片请求（/img/v1/fetch）不计入 502/超时回落计数（仅 relayRequest 计数）；图片 401 不重放。
- 收藏快照仅覆盖开启同步后新收藏的作品；收藏页占位卡片与后续分页存在极小概率重复显示。
- 自检第 5 项会向 search_history 域真实 push `__selftest__` 条目再推墓碑清理；若恰在窗口期内客户端 pull，搜索历史可能短暂出现 `__selftest__` 条目（随后墓碑清除）。
- 非 relay 模式下查看恢复图片：recover 返回的 img URL 指向中继服务器，ImageCacheService 非 relay 分支不注入 relay Bearer → 可能 401（恢复功能本身要求已注册中继，实际使用中通常已切 relay）。
- 429 RATE_LIMITED 目前按普通错误冒泡（sync 静默下轮重试；recover 按服务端 retryAfterSec 轮询），未单独做退避。
- 同步为尽力而为：App 未启动期间不产生同步。**回前台补偿 pull 已实现**（`EntryAbility.onForeground` → `syncService.onAppForeground`，受 `autoSyncForeground` 开关 + 5 分钟节流门控，见 AGENTS.md"Relay 与数据同步"节）。
- **push/pull 顺序已加固（勿回退）**：曾出现"ArkPix 历史推上去了，但后端已有历史在 ArkPix 拉不下来"——根因是服务端 syncToken 水位随 push 跳到≈当前时间戳、pull 只返回 `seq > since`，设备在首次全量 pull 前 push 导致游标越过后端条目。现已加 `ensureInitialPull`（每域 `sync_initial_pulled_<domain>` 标记，未全量拉取过即重置游标全量拉）+ `pushDomain` 内 push 后按 push 前游标补拉 + 墓碑 LWW 防护（history/search_history）。存量被污染的游标会在下次启动/回前台/立即同步时自动修复。详见 AGENTS.md"Relay 与数据同步"节。

## 客户端新增功能（设置页聚合重构后）

- 设置入口已重构为分类首页 + 7 个子页（中继设置=RelaySettingsPage）；登录页右上角有"设置"入口可登录前配置网络/中继
- 中继子页新增：**自动同步开关**（默认开）、**导入同步账号**（PasteButton 剪贴板 / DocumentSelectPicker 文件，覆盖本机注册并自动 syncNow）、导出增加"导出为文件"（arkpix-sync-account.json）
- 自检探针已更新：API 中继打 `app-api.pixiv.net/v1/walkthrough/illusts`（www.pixiv.net 经代理易 500）；图片用 `no_profile.png`（novel_bg.png 已 404）
- 服务端联调备忘：`.env` 必须 CRLF 换行；本机联调 `UPSTREAM_PROXY=http://127.0.0.1:10808`（v2rayN 混合端口）

## 新会话提示词模板（可直接粘贴）

```
继续在项目 D:\work\pixiv- 中进行 Relay Server 客户端集成的端到端验证与修复。
请先阅读：
1. D:\work\pixiv-\spec\relay-server-integration\RESUME.md（接续指南）
2. D:\work\pixiv-\spec\relay-server-integration\tasks.md（T001–T024 已完成；若有新发现的问题新增任务再执行）
3. D:\work\pix_backend\docs\api.md（后端最终契约）
客户端实现关键文件：entry/src/main/ets/network/RelayClient.ets、services/SyncService.ets、
services/RecoverService.ets、services/RelaySelfTestService.ets、models/RelayModels.ets。
验证流程：① 启动后端（cd D:\work\pix_backend，参考其 PLAN.md/.env.example，go run ./cmd/server）
② build_project 构建并 start_app 部署 ③ 设置页填中继地址注册 → 认证/API 方式切"中继"
④ 用"后端自检"验证六端点 ⑤ 按 RESUME.md 的端到端清单逐项验证 US1/US2/US3。
发现契约或行为不一致时：以 docs/api.md 为准修复客户端，遵守 ArkTS 严格约束
（禁 any/as/动态属性，模型 fromJson 内部层除外），修改后跑 arkts_check，最后 build_project 确认通过。
```
