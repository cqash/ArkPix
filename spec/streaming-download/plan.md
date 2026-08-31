# Implementation Plan: 流式下载改造（Streaming Download）

**Input**: Feature specification from `spec/streaming-download/spec.md`

## Summary

将 `DownloadService.downloadToCache` 由 `http.request` + `ARRAY_BUFFER` 整图内存缓冲改造为 `requestInStream` + `on('dataReceive')` 流式写盘：数据块直接以偏移写入按任务命名的临时文件（`part_<taskId>.<ext>`），彻底解除 5MB/50MB 单次传输上限（2300023 根因）；在流式传输外层套自动重试循环（指数退避，最多 3 次尝试）并将 readTimeout 由 30s 调至 60s；重试/重下时以临时文件大小为偏移携带 `Range` 头断点续传（响应 206 追加、200 回退整下）；进度按百分比节流写入既有 `download_tasks.progress` 列，DownloadPage 复用既有轮询渲染，无需 UI 结构改动。

## Technical Context

**Language/Version**: ArkTS（Strict Mode），HarmonyOS API 12+ / SDK 6.1.0(23)  
**Primary Dependencies**: `@kit.NetworkKit` http（requestInStream/dataReceive/dataEnd/headersReceive）、`@kit.CoreFileKit` fileIo（偏移写/stat/rename/unlink）  
**State Management**: 沿用 V1；DownloadPage 既有 1.5s 轮询 + 任务变更事件 + key 含 status/progress 的行刷新机制  
**Storage**: 既有 `download_tasks` 表（progress INTEGER 列已存在，**不做 DB 迁移**）；断点偏移 = 临时文件实际大小  
**Testing**: 无 CLI 测试脚本；Phase 5 build + deploy 验证  
**Target Platform**: HarmonyOS 手机/平板（单模块 entry）  
**Project Type**: mobile-app（既有项目增量改造）  
**Performance Goals**: 大文件下载峰值内存与文件大小解耦（SC-005）；进度 DB 写入按 ≥2% 增量节流  
**Constraints**: ArkTS 严格约束；不改并发调度/自动收藏/EXIF/写图库语义；relay 与直连双模式均须兼容  
**Scale/Scope**: 核心改动集中于 `services/DownloadService.ets` 单文件（downloadToCache/finalize/clearTasksByStatus），辅以超时常量与 DownloadPage 微调（如需要）

## Project Structure

### Documentation (this feature)

```text
spec/streaming-download/
├── spec.md
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

遵循既有架构，不新增目录：

```text
entry/src/main/ets/
├── services/
│   └── DownloadService.ets     # 核心改造：流式下载 + 重试循环 + 断点续传 + 进度写库 + 临时文件生命周期
├── utils/
│   └── Constants.ets           # 下载超时/重试参数常量（DOWNLOAD_READ_TIMEOUT、DOWNLOAD_MAX_ATTEMPTS、退避基数）
└── pages/settings/
    └── DownloadPage.ets        # 仅当进度文案/展示态需要微调时触碰（预期零改动或小改）
```

**Structure Decision**: 遵循既有项目架构（services 承载下载编排），不引入新分层。预期改动 2–3 个存量文件，零新增文件；流式状态（fd、偏移、Content-Length）以 downloadToCache 内闭包局部变量承载，无需新增类。

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 断点续传自行管理 Range/偏移 | spec 已确认支持续传；HarmonyOS http 无内建续传 | 用 @ohos.request 后台下载代理——会脱离既有 DB 任务模型/EXIF/图库双通道链路，改动面更大且后台语义不符 |

## Research & Decisions

### R1: 流式 API 选型与事件编排

- **Decision**: 使用 `httpRequest.requestInStream(url, options, cb)`：订阅事件必须在发起请求前注册——`on('headersReceive')` 捕获状态码与 Content-Length；`on('dataReceive')` 接收 ArrayBuffer 块并以递增偏移 `writeSync` 落盘；`on('dataEnd')` 关闭 fd 并 resolve；`requestInStream` 回调的 err 或状态码 ≥400 → reject。整体包一层 Promise 供既有 async 任务体 await；结束后 `off` 事件并 `destroy()` 防泄漏。
- **Rationale**: 官方 FAQ（faqs-network-81）确认该用法为大文件标准方案；官方 FAQ（faqs-network-64）明确 >5M 应使用 requestInStream——正是当前 2300023 失败的官方推荐修复。`dataReceiveProgress` 依赖 Content-Length 且不保证触发，进度改为 dataReceive 内手动累计字节数，更可靠。
- **Alternatives considered**: ① `http.request` + `maxLimit: 100M`——只把上限抬到 100M，整图内存缓冲与弱网一次性失败问题仍在，排除；② `@ohos.request` 后台下载代理——脱离既有任务模型，见 Complexity Tracking。

### R2: 临时文件与断点续传机制

- **Decision**: 下载一律先落临时文件 `cacheDir/downloads/part_<taskId>.<ext>`（taskId=illustId_pageIndex，天然唯一）；fd 在传输期间保持打开，按偏移追加写。续传判定：`fs.statSync(partPath).size > 0` 时请求头加 `Range: bytes=N-`；`headersReceive` 状态码为 **206** → 保留已有内容继续追加（偏移从 N 起）；为 **200**（上游不支持 Range）→ 截断临时文件从头写。完成后走既有 `finalizeDownload`（EXIF 嵌入或重命名为成品）。临时文件大小即偏移，**不做 DB 迁移**。
- **Rationale**: 文件名确定性使命重启后仍可续传（FR-005/Edge Case）；206/200 分流是 Range 语义的标准处理；复用既有 finalize 保持 EXIF/降级路径不变。
- **Alternatives considered**: DB 新增 downloaded_bytes 列——需表迁移，违背 spec 假设；内存记录偏移——重启即失效。
- **校验规则**：有 Content-Length 且临时文件大小 ≥ 总量 → 视为已完成直接 finalize；大小异常（>总量）→ 删临时文件整下（对应"临时文件损坏"边界）。

### R3: 自动重试策略

- **Decision**: 在流式传输外包裹尝试循环：最多 3 次尝试（1 初始 + 2 重试），退避间隔 1s→2s（指数基数 2，可参数化）。**可重试**：requestInStream 网络错误（含 2300028 超时类）、连接中断、5xx、传输中断（dataEnd 时字节数 < Content-Length）。**不可重试**：4xx（403/404 等资源/权限错误）立即失败。每次重试自动携带当前临时文件大小走 R2 续传。重试全部失败 → 置 failed + 既有 toast（行为不变）。
- **Rationale**: FR-003；续传与重试共用同一偏移机制使重试几乎零重复流量；4xx 重试无意义且会放大服务端压力。
- **Alternatives considered**: 无限重试——弱网长断会卡死队列位，违背并发调度语义。

### R4: 超时阈值

- **Decision**: `connectTimeout` 保持 30s；`readTimeout` 由 30s 调至 **60s**（弱网停滞容忍，FR-004 记录于此）。流式模式下 readTimeout 语义为相邻数据块间隔上限，60s 无字节到达判定链路僵死进入重试。
- **Rationale**: 30s 在丢包重传严重的链路偏紧；60s 配合 3 次尝试，最坏卡死耗时可控（60s×3 + 退避 ≈ 3 分钟/任务）。
- **Alternatives considered**: 120s——单任务最坏占用并发位过久，影响批量下载吞吐。

### R5: 进度产出与写库节流

- **Decision**: `dataReceive` 内累计 `receivedBytes`；有 Content-Length 时 `percent = floor(received/total*100)`，无 Content-Length 时进度按 0 处理（UI 显示现状文案，功能不受影响）。**节流**：percent 较上次写库提升 ≥2 时才 `updateDownloadStatus(taskId, 'downloading', percent)`；完成/失败终态强制写 100/保持。写库后不调 `notifyTaskChanged`（DownloadPage 1.5s 轮询已覆盖刷新，避免事件风暴）；状态跃迁（pending→downloading→completed/failed）维持既有 notify。
- **Rationale**: FR-002/FR-006；DB 既有 progress 列与 UI key（id|status|progress）机制天然支持；≥2% 节流使 50MB 文件最多 50 次写库。
- **Alternatives considered**: 每块写库——小文件块多，DB 写入放大；事件驱动实时推送——需改 DownloadPage 机制，收益不成比例。

### R6: 临时文件生命周期

- **Decision**: 完成 → finalize 内删除/重命名（既有逻辑覆盖）；失败 → 保留供续传；`clearTasksByStatus` 删除记录前按任务清单删除对应 `part_*` 临时文件（新增清理步骤）；应用重启后 downloading/pending 重置 failed 的既有规则不变，残留临时文件自然成为续传素材。
- **Rationale**: FR-008；防止临时文件无限堆积的唯一出口是任务清理动作。
- **Alternatives considered**: 启动时全量清理 part_*——会杀死重启后续传能力，排除。

### R7: 直连/中继双模式兼容

- **Decision**: 流式改造仅替换传输层，URL 构建（relay 包装 / applyImageHost+applyDirectIp+Host 头+remoteValidation:'skip'）与请求头构建（图片 Referer/UA 或 relay Bearer）逻辑原样保留；Range 头在两种模式下均可选附加（relay 上游不支持时按 R2 的 200 分支回退整下）。
- **Rationale**: FR-007；AGENTS.md 记载的两条链路均有既有测试基础，改动面最小化。
- **Alternatives considered**: relay 模式禁用续传——R2 的 200 回退分支已天然覆盖，无需特判。

## Data Model

无新增持久化实体。复用与语义升级：

| 项 | 内容 |
|---|---|
| `download_tasks.progress`（既有 INTEGER 列） | 由恒 0 升级为真实百分比（0–100）；downloading 期间节流写入，completed 写 100 |
| 临时文件 `part_<taskId>.<ext>` | 下载中半成品；文件大小 = 续传偏移；完成转成品、失败保留、任务清理时删除 |
| 传输期闭包状态（不持久化） | fd、写偏移、Content-Length、receivedBytes、上次写库百分比、尝试次数 |

## Contracts & Interfaces

### DownloadService 内部契约（改动点）

| 成员 | 改动 |
|---|---|
| `downloadToCache(url, illust, pageIndex)` | 私有方法整体重写为流式实现：尝试循环（R3）× 单次流式传输（R1）× 续传判定（R2）；签名与返回值不变（成品路径或 ''） |
| `streamOnce(...)`（新增私有方法） | 单次流式传输 Promise 封装：headersReceive 状态/长度捕获 → dataReceive 偏移写盘+进度节流 → dataEnd 校验完成量 → resolve/reject（含可重试性分类） |
| `finalizeDownload(...)` | 不变（输入始终为临时文件路径，既有逻辑已覆盖） |
| `clearTasksByStatus(status)` | 删记录前新增：枚举匹配任务的 `part_*` 临时文件并删除（FR-008） |
| `Constants.ets` | 新增下载传输参数常量：readTimeout 60s、最大尝试 3、退避基数 |

### 外部系统契约

- `http.createHttp().requestInStream(url, options, cb)`：cb 返回响应码（number）；数据经事件订阅交付。
- `on('headersReceive')`：状态码 + Content-Length 捕获点；206=续传接受、200=整下回退。
- `on('dataReceive', (data: ArrayBuffer))` / `on('dataEnd')`：数据块与结束信号；`destroy()` 必须调用防泄漏。
- Range 请求头 `bytes=N-`；上游不支持时返回 200 全量（回退分支）。
- `fileIo.writeSync(fd, buffer, { offset })`：偏移追加写；`fileIo.statSync().size`：续传偏移来源。

### UI 契约

- `DownloadPage`：既有行 key `id|status|progress` 自动驱动进度行重建；`dl_task_progress` 文案已有；预期零改动（若 downloading 态进度文案需隐藏 0% 抖动可微调，实施时定）。
