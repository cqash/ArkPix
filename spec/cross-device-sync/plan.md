# Implementation Plan: 多端流转与鸿蒙设备间数据同步（Cross-Device Sync）

**Input**: Feature specification from `spec/cross-device-sync/spec.md`

## Summary

为 ArkPix 增加两项能力：

1. **多端流转（应用接续）**：`module.json5` 开启 `continuable`（launchType 默认 singleton 已满足），`EntryAbility` 实现 `onContinue` 保存"当前页面+上下文参数"轻量载荷（<100KB），对端 `onCreate/onNewWant` 以 `LaunchReason.CONTINUATION` 接收并写入 AppStorage，由 SplashPage 在路由决策前消费载荷跳转到目标页面。
2. **设备间同步**：新增 `DistributedSyncService`，基于 `distributedDataObject`（单对象、根属性为 JSON 字符串、固定 sessionId）在可信组网内实时同步设置/屏蔽/EXIF 配置/裁剪历史。复用现有 Relay 同步体系已铺好的 applier 辅助方法（`upsertXxx`/`deleteXxx`/`getXxxTimestamp`）与写钩子模式，与既有 `SyncService`（HTTP Relay）**双通道共存、互不耦合**。

**Structure Decision**: 遵循项目现有架构（`stores/` + `services/` + `models/` + `pages/`，非 MVVM 目录），不引入新分层。新增 3 个文件（1 模型 + 2 服务），修改 8 个既有文件，符合项目"服务单例 + 写钩子解耦"的既有惯例。

## Technical Context

**Language/Version**: ArkTS（严格模式），API 12+ / SDK 6.1.0(23)
**Primary Dependencies**: `@kit.AbilityKit`（UIAbility 接续：onContinue/onCreate/onNewWant、AbilityConstant.LaunchReason.CONTINUATION）、`@kit.ArkData`（distributedDataObject）、`@kit.BasicServicesKit`（abilityAccessCtrl 运行时授权）
**Storage**: 既有 `PreferenceService`（pixiv_settings）+ `DatabaseService`（pixiv.db, RDB S1）；分布式对象为内存同步层，落地仍走既有本地持久化
**Testing**: 构建验证 + 双真机人工验证（接续/同步均需真实组网，模拟器不支持接续）
**Target Platform**: HarmonyOS 手机/2in1（module.json5 `deviceTypes: ["phone","2in1"]`）
**Constraints**:
- 接续 wantParam 载荷 < 100KB（只传页面类型+ID，详情数据对端重新拉取）
- 单分布式对象 ≤500KB、单应用 ≤16 实例、建议 ≤3 设备协同
- 复杂类型仅支持根属性修改 → 同步载荷用**根属性 = JSON 字符串**方案
- 接续：API 12+ 免 DISTRIBUTED_DATASYNC 权限；分布式数据对象 setSessionId 需该权限 → 声明 + 运行时申请
- 冷启动约束：`PreferenceService` 依赖 AppStorage 中的 context，任何依赖它的单例必须 lazy import（EntryAbility 既有教训）

**Scale/Scope**: 新增 3 文件 + 修改 8 文件；同步数据域 4 个（settings+mute+exif_config 合并为一个设置载荷、history、search_history）

## Project Structure

### Documentation (this feature)

```text
spec/cross-device-sync/
├── spec.md
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

新增文件：

```text
entry/src/main/ets/
├── models/
│   └── ContinuationPayload.ets     # 流转载荷模型 + 同步载荷模型（序列化/解析纯函数）
└── services/
    ├── ContinuationService.ets     # 页面状态登记 + 载荷构建/解析（单例）
    └── DistributedSyncService.ets  # 分布式对象生命周期 + 双向同步编排（单例）
```

修改文件：

```text
entry/src/main/module.json5                    # continuable: true + DISTRIBUTED_DATASYNC 权限声明
entry/src/main/ets/entryability/EntryAbility.ets  # onContinue/onCreate/onNewWant 接续处理 + lazy 初始化分布式同步
entry/src/main/ets/pages/splash/SplashPage.ets    # 路由决策前消费接续载荷
entry/src/main/ets/pages/home/HomePage.ets        # 登记页面状态(tabIndex) + 支持外部恢复 Tab
entry/src/main/ets/pages/detail/IllustDetailPage.ets  # 登记页面状态(illustId)
entry/src/main/ets/pages/user/UserProfilePage.ets     # 登记页面状态(userId)
entry/src/main/ets/models/AppSettings.ets         # 新增 deviceSyncEnabled 字段（设备本地，默认 true）
entry/src/main/ets/stores/UserSettingStore.ets    # 新字段存取 + 写钩子支持多监听器（fan-out）
entry/src/main/ets/services/DatabaseService.ets   # 写钩子支持多监听器（fan-out）
entry/src/main/ets/pages/settings/GeneralSettingsPage.ets  # "设备间同步"开关 + 状态说明
```

**Structure Decision**: 遵循既有项目架构，不做 MVVM 迁移。页面只做状态登记（一行调用），业务编排在两个新 Service 单例内；序列化/解析纯函数收敛在 models 文件，符合项目 `utils/*` 纯函数惯例。

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 与既有 Relay SyncService 双通道共存 | Relay 面向自托管服务器远程同步（需用户配置服务器）；分布式对象面向同华为账号近场设备零配置同步。两者用户群与前置条件不同，Phase 1 已确认技术路线 | 废弃 Relay 迁移到分布式对象：Relay 支持跨网络/跨账号体系，分布式对象无法替代；合并实现会引入传输层抽象，复杂度更高 |

## Research & Decisions

- **Decision**: 接续载荷只传 `{version, page, illustId?, userId?, tabIndex?}`，详情数据对端重新拉取
  **Rationale**: wantParam <100KB 硬限制；详情接口既有缓存（illust_detail_cache）使对端加载成本可接受
  **Alternatives considered**: 载荷内嵌完整 Illust JSON（易超 100KB、R18 图 URL 泄露到系统层）；迁移完整页面栈（router 栈不可序列化、复杂度爆炸，Phase 1 已排除）

- **Decision**: 页面状态采用"页面主动登记"模式（ContinuationService.setCurrentPageState，aboutToAppear 登记 / aboutToDisappear 清除）
  **Rationale**: router 无 API 查询当前栈顶页面与参数；登记模式侵入最小（每页 2 行）
  **Alternatives considered**: 反射 router.getState()（拿不到业务参数 illustId）；全局路由拦截器（pushUrl 散落各处，拦截不全）

- **Decision**: 对端恢复走 SplashPage 既有路由决策前置分支：检测到接续载荷 → replaceUrl 到目标页（带参数），未登录时按既有逻辑回退登录页
  **Rationale**: SplashPage 本就是唯一路由入口；onCreate 里只做载荷落 AppStorage，不做跳转（此时 WindowStage 未加载）
  **Alternatives considered**: onCreate 直接操作 router（生命周期不允许）；目标页自行读 AppStorage（详情页已被 push 时才读，需要先有跳转者）

- **Decision**: 分布式同步载荷 = 单 DataObject，根属性为 4 个 JSON 字符串（settingsJson/historyJson/searchHistoryJson/metaJson）+ updatedAt
  **Rationale**: 复杂类型仅根属性可变更触发同步；JSON 字符串是官方推荐规避方案；4 个根属性实现域级增量同步（改设置不同步历史）
  **Alternatives considered**: 多 DataObject（每域一个）：每实例占 100-150KB 内存且总数 ≤16，无收益；嵌套对象：下层属性修改不触发同步，不可用

- **Decision**: 历史同步裁剪窗口：浏览最近 100 条、搜索最近 50 条（与 `getHistory(500)`/`getSearchHistory(50)` 默认独立，同步侧另行裁剪）
  **Rationale**: 500KB 上限预算：100 条浏览历史（含 image_url）约 30-50KB，远低于上限
  **Alternatives considered**: 全量同步（历史无界增长，必超上限）；增量条目级同步（分布式对象无条目级语义，需自维护 diff，复杂度不值得）

- **Decision**: 冲突解决复用既有 LWW（`getXxxTimestamp`/`shouldApplyRemote` 思路：strict remote > local 才应用）；设置类整体覆盖按 metaJson.updatedAt 比较
  **Rationale**: 与 Relay 同步语义一致，双通道并发写入时行为可预期
  **Alternatives considered**: 系统默认收敛（粒度为整个根属性，会丢字段级修改）；应用层字段级合并（复杂度远超收益）

- **Decision**: 与 Relay SyncService 的集成 = 仅共享 applier 辅助方法与写钩子多监听 fan-out，不互相调用
  **Rationale**: 写钩子当前是单回调（`setSyncWriteHook`/`setSettingsWriteHook`），需升级为监听器数组，两个同步服务各自注册；applier 辅助方法（upsert/delete 不触发钩子）天然防回声循环，分布式通道直接复用
  **Alternatives considered**: DistributedSyncService 挂在 SyncService 内部（耦合两个传输层，违反单一职责）；各自独立实现 applier（重复代码 + 两通道写库语义漂移）

- **Decision**: 权限策略：module.json5 声明 `ohos.permission.DISTRIBUTED_DATASYNC`，首次开启"设备间同步"开关时通过 abilityAccessCtrl 运行时申请；拒绝则开关回退并 toast
  **Rationale**: setSessionId 接口文档明确要求该权限；接续本身 API 12+ 免权限（已核实官方文档）
  **Alternatives considered**: 不声明权限（setSessionId 201 错误静默失败，违背可观测性）；启动即申请（打扰用户，权限与功能场景分离原则）

- **Decision**: 设备本地开关 `deviceSyncEnabled`（默认 true）不参与任何同步域，且不走 Relay 写钩子
  **Rationale**: 对齐既有 `autoSyncForeground`（设备本地字段）惯例；避免"关同步的操作被同步到对端又关掉对端"的逻辑悖论
  **Alternatives considered**: 复用 `syncEnabled`（语义绑定 Relay 服务器账号，未配置 Relay 的用户会连带失去设备间同步）

- **Decision**: 接续目标版本校验：onContinue 检查 wantParam.version，低于本特性引入版本时返回 MISMATCH 拒绝接续
  **Rationale**: 官方文档推荐模式，防止旧版对端收到不认识的载荷
  **Alternatives considered**: 不校验（旧版静默忽略载荷回退主页，体验降级但可接受——仍选择显式拒绝，语义更清晰）

## Data Model

### ContinuationPayload（流转载荷，≤100KB 实际 <200 字节）

| 字段 | 类型 | 说明 |
|------|------|------|
| version | number | 载荷版本号，当前=1 |
| page | string | `'home'` / `'illust_detail'` / `'user_profile'` |
| illustId | number（可选） | page=illust_detail 时必填 |
| userId | number（可选） | page=user_profile 时必填 |
| tabIndex | number（可选） | page=home 时必填，0-4 |

状态流转：页面 aboutToAppear 登记 → onContinue 读取构建 → wantParam 传输 → 对端 AppStorage → SplashPage 消费清除。

### DistributedSyncObject（单分布式对象，根属性）

| 根属性 | 类型 | 载荷内容 | 大小预算 |
|--------|------|----------|----------|
| settingsJson | string | AppSettings 可同步字段全集（排除 deviceSyncEnabled/autoSyncForeground/relay*/prev* 等设备本地字段）+ muteTags/muteUsers + exifMuted/exifMerged/exifPriority | <20KB |
| historyJson | string | 最近 100 条浏览历史（illustId/title/imageUrl/userName/timestamp） | <50KB |
| searchHistoryJson | string | 最近 50 条搜索历史（keyword/searchType/timestamp） | <10KB |
| metaJson | string | `{deviceId, updatedAt, schemaVersion}`，settingsJson 的 LWW 时间戳载体 | <1KB |

约束：总载荷 <500KB；历史条目 timestamp 用于条目级 LWW 合并（写入走 `upsertHistory`/`upsertSearchHistory` 既有 applier，自动判新）。

### AppSettings 新增字段

| 字段 | 类型 | 默认 | 同步域 |
|------|------|------|--------|
| deviceSyncEnabled | boolean | true | 设备本地（不同步） |

### 关键既有实体复用

- `HistoryItem` / `SearchHistoryItem`（DatabaseService 导出接口）——同步载荷条目与其字段对齐
- `ExifTagMergeRule`（AppSettings）——随 settingsJson 序列化
- AppStorage 键：新增 `'continuationPayload'`（一次性消费）

## Contracts & Interfaces

### ContinuationService（单例，`services/ContinuationService.ets`）

- `setCurrentPageState(state: ContinuationPayload | null): void` — 页面登记/清除（aboutToAppear/aboutToDisappear）
- `buildWantParam(): Record<string, Object>` — onContinue 调用，无登记状态时返回仅含 version 的最小载荷
- `parseWant(want: Want): ContinuationPayload | null` — 对端解析，非法/缺失返回 null
- `consumePendingPayload(): ContinuationPayload | null` — SplashPage 一次性消费 AppStorage 中的载荷并清除

### EntryAbility 接续契约

- `onContinue(wantParam)`：版本校验 → 写入 `ContinuationService.buildWantParam()` → 返回 AGREE / MISMATCH
- `onCreate/onNewWant`：`launchReason === CONTINUATION` 时 `parseWant` → 非空则 `AppStorage.setOrCreate('continuationPayload', payload)`；onCreate 中继续既有初始化顺序不变（customizeSchemes 仍最优先）
- module.json5：`continuable: true`；权限数组追加 `ohos.permission.DISTRIBUTED_DATASYNC`

### DistributedSyncService（单例，`services/DistributedSyncService.ets`）

- `init(): void` — lazy 初始化（EntryAbility onCreate 末尾 lazy import 调用）：读 `deviceSyncEnabled` → 创建 DataObject → 注册 change/status 监听 → 申请权限后 setSessionId（`'arkpix_device_sync'`）
- `setEnabled(enabled: boolean): void` — 设置页开关：开启=权限申请+入会话；关闭=退出会话（setSessionId('')）+ 保留本地数据
- `isActive(): boolean` — 会话状态（设置页显示）
- 内部：本地写监听（注册进 UserSettingStore/DatabaseService 写钩子 fan-out）→ 防抖 2s → 重建对应根属性 JSON 并赋值；远端 change 监听 → 按域解析 → LWW 判定 → 走既有 applier 落库/落偏好 → 触发 AppStorage 刷新
- 错误处理：create/setSessionId/save 全部 try-catch + hilog，任何失败降级纯本地，不抛到调用方

### 写钩子 fan-out 升级（UserSettingStore / DatabaseService）

- 现状：`setSyncWriteHook(hook)` 单回调
- 升级：`addSyncWriteHook(hook): void` + `removeSyncWriteHook(hook): void`（监听器数组）；保留原 setter 作为兼容包装（Relay SyncService 调用点不动）
- 分布式 applier 应用远端数据时只调既有 hook-free 辅助方法（`upsertXxx`/`deleteXxx`/`setMuteTags`/`setMuteUsers` 等），不回写分布式对象（suppress 标志位防回声）

### 设置页契约（GeneralSettingsPage）

- 新增"设备间同步"分组项：开关（deviceSyncEnabled）+ 状态文字（未开启/未授权/已连接 N 设备/同步时间）
- 首次开启触发系统权限弹窗；拒绝 → 开关回退 + toast 提示前往系统设置

### 外部系统契约（不做实现，仅记录前置条件）

- 双端同华为账号、WLAN/蓝牙开启、"多设备协同 > 接续"开启、双端安装同 bundleName 应用
- 接续与分布式同步均不支持模拟器验证，Phase 5 以构建验证 + 代码审查为主，真机验证由用户执行

## Changelog

### 2026-08-15 变更轮次 1：浏览设置排除 / 授权状态即时刷新 / 接续返回栈修复

对应 spec.md FR-012 / FR-013 / FR-014，设计调整如下：

**① 浏览相关设置排除出同步载荷（FR-012）**
- `DistributedSyncService.buildSettingsPayload()` 移除 7 个字段：pictureQuality、mangaQuality、previewQuality、detailQuality、fullScreenQuality、crossCount、isTopMode
- 下行应用侧同步移除对应 `applyNumberField/applyBooleanField` 分支（对端旧载荷中残留这些字段时跳过不应用，天然兼容）
- `downloadQuality`、下载并发、网络模式、防社死、屏蔽、EXIF 配置等**继续同步**
- 范围限定分布式设备间同步通道；Relay 后端同步域不在本次调整范围（用户需求语境为近距离设备同步）
- `models/AppSettings.ets` 对应字段补注释"设备本地，不参与设备间同步"

**② 授权后状态即时刷新（FR-013）**
- 根因：`sessionActive` 是 Service 私有字段，设置页只能手动轮询（固定 1.5s 延时刷新）；`setSessionId` 首次授权后入会话耗时不可控，轮询窗口错过即永远显示"未授权"，重启后 init 重走 joinSession 才成功
- 修复设计：
  - `DistributedSyncService` 在 `sessionActive` 每次变更时写入 `AppStorage.setOrCreate('deviceSyncActive', v)`，状态变化事件化
  - `GeneralSettingsPage` 改用 `@StorageLink('deviceSyncActive')` 替代手动轮询/延时刷新，入会话成功瞬间 UI 自动更新
  - `setEnabled(true)` 授权成功后 `joinSession()` 增加一次失败重试（延迟 2s 重试一次，仍失败则保持降级）
  - init() 时也写入 AppStorage 初值，保证键始终存在

**③ 接续返回栈修复（FR-014）**
- 根因：SplashPage `routeByContinuation` 对 detail/user_profile 直接 `replaceUrl` 目标页，页面栈仅一页，返回键退出应用
- 修复设计：
  - `illust_detail`：`router.replaceUrl(HomePage)` → `router.pushUrl(IllustDetailPage, {illustId})`
  - `user_profile`：`router.replaceUrl(HomePage)` → `router.pushUrl(UserProfilePage, {userId})`
  - `home`：维持 `replaceUrl(HomePage, {tabIndex})`（主页即栈底，返回退出属预期行为）
  - 效果：对端恢复后返回键逐级回主页，与源端浏览路径的导航体验一致

### 2026-08-16 变更轮次 2：浏览设置排除扩展到 Relay 通道（FR-012 全通道化）

**根因**：变更轮次 1 只改了分布式通道；Relay SyncService 的 settings 域上行（`collectSettings`，约 line 680）与下行（`applySettings`，约 line 898）仍携带/应用全部 7 个浏览字段，开启后端同步的设备仍会互相同步列数等浏览设置。

**修复设计**（`services/SyncService.ets`）：
- `SettingsSyncPayload` 接口（line 120-129）移除 pictureQuality/mangaQuality/previewQuality/detailQuality/fullScreenQuality/crossCount/isTopMode 7 个可选字段
- `collectSettings()` 上行载荷移除对应 7 行赋值
- `applySettings()` 下行移除对应 7 个 `if (raw?.xxx !== undefined)` 应用分支
- 兼容性：服务器/对端旧数据中的残留字段因接口与应用分支均不存在而天然跳过，无需版本迁移；downloadQuality 保留同步
- 分布式通道已在轮次 1 排除，本轮回合后两通道语义一致（FR-012 全通道）
