# Implementation Plan: 设置页分类聚合重构

**Input**: Feature specification from `spec/settings-regroup/spec.md`

## Summary

将 SettingsPage（现 1159 行、约 40 个平铺设置项）重构为「分类首页 + 7 个独立路由二级子页」。所有既有设置项、交互与副作用原样平移；公共设置行组件抽取为共享模块供各子页复用；设置首页分类行带当前值摘要。持久化层（UserSettingStore/PreferenceService）零改动。

## Technical Context

**Language/Version**: ArkTS（严格模式）/ HarmonyOS API 12+，SDK 6.1.0(23)
**Primary Dependencies**: @kit.ArkUI（router/TextPickerDialog/promptAction）、既有 UserSettingStore / AccountStore / RelayClient / SyncService / RelaySelfTestService / Hoster / LocalProxyServer / ImageCacheService
**Storage**: 既有 PreferenceService KV（不改键与格式）
**Testing**: hvigor 构建 + arkts_check 静态检查 + 真机逐项功能回归
**Target Platform**: HarmonyOS 手机（Mate 70 Pro+ 真机验证）
**Project Type**: 既有 ArkPix 单模块应用（entry）
**Constraints**: 遵循既有架构（pages/ 平铺路由页面，非 Navigation）；ArkTS 严格约束（禁 any/as/动态属性）；ForEach keyGenerator 需含可变显示字段（本项目近期两起刷新 bug 根因）；路由上限 32 页（新增 7 页后总量仍远低于上限）
**Scale/Scope**: 10 个文件（7 新页面 + 1 共享组件文件 + SettingsPage 重写 + main_pages.json）

## Project Structure

### Documentation (this feature)

```text
spec/settings-regroup/
├── spec.md
├── plan.md              # 本文件
└── tasks.md
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/settings/
│   ├── SettingsPage.ets            # 重写：7 个分类入口行 + 摘要（保留 struct 名与路由名 pages/settings/SettingsPage）
│   ├── SettingWidgets.ets          # 新增：共享行组件与 Picker 帮助函数（详见 Contracts）
│   ├── BrowseSettingsPage.ets      # 新增：浏览与显示（9 项）
│   ├── DownloadSettingsPage.ets    # 新增：下载与元数据（9 项）
│   ├── FilterSettingsPage.ets      # 新增：屏蔽与过滤（2 项）
│   ├── NetworkSettingsPage.ets     # 新增：网络（4 项 + 模式切换副作用）
│   ├── RelaySettingsPage.ets       # 新增：中继服务器与同步（9 项 + 自检覆盖层）
│   ├── GeneralSettingsPage.ets     # 新增：通用（收藏/历史/清缓存/关于）
│   ├── AccountSettingsPage.ets     # 新增：账户（导出 Token/退出登录）
│   └── （既有 DownloadPage/BookmarkPage/HistoryPage/FilenameTemplatePage/ExifTemplatePage/ExifTagConfigPage/AboutPage/MutePage 不变，改由对应子页进入）
entry/src/main/resources/base/profile/main_pages.json   # 注册 7 个新页面路由
```

**Structure Decision**: 遵循既有项目架构（`pages/` 平铺 + router.pushUrl 子页模式，与 DownloadPage/BookmarkPage 等既有子页一致），不引入 MVVM 迁移。新增 8 个 ArkTS 文件的理由：7 个分类子页各自承载一组内聚设置项（最大 Relay 组含注册/同步/自检约 400 行逻辑），共享行组件抽 1 个文件避免 7 份复制；该文件数是「一组设置一页」划分的自然结果，无过度拆分。

## Complexity Tracking

无违规项。

## Research & Decisions

- **Decision**: 公共行组件（SettingItem/SwitchItem/SectionHeader/TextInputItem）与 Picker 帮助函数抽取到 `pages/settings/SettingWidgets.ets`，以模块级 export 供 7 个子页 import
  - **Rationale**: 四个行组件与 showQualityPicker/选项数组目前在 SettingsPage 文件内私有；7 个子页复用同一样式与交互，抽取消除七份重复
  - **Alternatives considered**: 放 `components/common/`——拒绝，因这些组件仅服务于设置族页面，放 pages/settings/ 内聚更强；每个子页各自复制——拒绝，样式漂移风险

- **Decision**: 子页状态模式沿用现状：每页持有 `@State settings: AppSettings = userSettingStore.getSettings()`，修改后整对象重读赋值触发刷新；设置首页在 aboutToAppear 重读（router.back 返回时该生命周期会触发，摘要自动刷新）
  - **Rationale**: 与 AGENTS.md 记载的现状模式一致（getSettings 返回防御性拷贝，须重新赋值）；零持久化改动
  - **Alternatives considered**: @StorageLink('appSettings') 双向绑定——拒绝，现状 Store setter 多为同步 void 且部分副作用（hoster 刷新等）需要显式编排，现状模式已验证稳定

- **Decision**: 网络模式切换副作用（setPrevAuthMode/PrevApiMode 记录、hoster.init/refreshAll、localProxyServer.start、ensureRelayReady 未配置引导弹窗）随「认证方式/API 方式」两项移入 NetworkSettingsPage，逻辑原样搬运
  - **Rationale**: 这两个设置项归属网络分类，其副作用与项同页内聚
  - **Alternatives considered**: 留在首页监听——拒绝，项已不在首页

- **Decision**: 中继组整体（服务器地址/邀请码/同步账号输入、注册登录、状态行、数据同步开关+六域时间、立即同步、导出同步账号、后端自检覆盖层、注销）移入 RelaySettingsPage，含 SelfTestOverlay @Builder 与其全部 @State
  - **Rationale**: 该组是独立功能闭环；覆盖层随页面移动不影响其已修复的实时刷新行为（ForEach key 含 status|durationMs 不变）
  - **Alternatives considered**: 自检留在首页——拒绝，自检语义属于中继分组

- **Decision**: 设置首页分类行摘要取值规则（P3）：浏览与显示=`预览:{label} · 网格:{n}列`；下载与元数据=`{下载质量label} · {n}线程`；屏蔽与过滤=`AI过滤:{开/关}`；网络=`认证:{label} · API:{label}`；中继服务器与同步=`{未配置/未注册/已连接 vX} · 同步:{开/关}`；通用=缓存占用（ImageCacheService 现有统计，如无现成接口则留空）；账户=当前登录用户名
  - **Rationale**: 摘要均为既有状态的可派生文字，无需新存储
  - **Alternatives considered**: 无摘要——降级方案，P3 裁剪时采用

- **Decision**: 选项 label 反查（value→label）提供共享帮助函数（SettingWidgets 内），供各子页显示当前值与首页摘要复用
  - **Rationale**: 选项数组移出 SettingsPage 后，首页摘要与子页 value 列都需要同一映射
  - **Alternatives considered**: 各处硬编码——拒绝，双份维护

## Data Model

无数据模型变更。AppSettings 字段、PreferenceService 键、持久化格式全部不变（SC-004 升级零丢失由"不触碰持久化层"保证）。

## Contracts & Interfaces

仅内部 UI 契约（SettingWidgets.ets 导出物，全部为既有私有实现的公开化，签名不变）：

| 导出物 | 形态 | 契约 |
|---|---|---|
| `SettingItem` | @Component struct | @Prop title/value；onItemClick 回调；点击态样式 |
| `SwitchItem` | @Component struct | @Prop title/isOn；onToggle 回调（语义=用户拨动后调用，现状如此） |
| `SectionHeader` | @Component struct | @Prop title |
| `TextInputItem` | @Component struct | @Prop title/placeholder/value；isPassword；onTextChange |
| `QualityOption` | interface | { label: string, value: number } |
| `showQualityPicker(title, options, currentValue, onSelect)` | 模块级函数 | TextPickerDialog 多值选择，仅值变化时回调 |
| 选项数组（preview/detail/illustManga/downloadConcurrency 质量、networkMode、imageHost、proxyType 选项与取值数组） | 模块级 const | 与现状逐项一致 |
| `labelOf(options, value)` | 模块级函数 | value→label 反查，供子页 value 列与首页摘要共用 |

路由契约（main_pages.json 新增 7 项，均无参数）：
`pages/settings/BrowseSettingsPage`、`pages/settings/DownloadSettingsPage`、`pages/settings/FilterSettingsPage`、`pages/settings/NetworkSettingsPage`、`pages/settings/RelaySettingsPage`、`pages/settings/GeneralSettingsPage`、`pages/settings/AccountSettingsPage`

既有路由 `pages/settings/SettingsPage` 保留（HomePage Tabs 引用不变）。
