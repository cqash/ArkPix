# Implementation Plan: 多语言全球化（Multi-language Internationalization）

**Input**: Feature specification from `spec/multi-language-i18n/spec.md`

## Summary

将 ArkPix 全部用户可见文本（约 700–850 条硬编码中文，分布于 ~68 个 .ets 文件）资源化为 HarmonyOS 资源限定词目录下的多语言字符串（zh_CN / zh_TW / en_US，base 作为英文兜底），复用已存在但未被消费的 `AppSettings.language` 字段作为语言偏好载体，通过 `I18n.System.setAppPreferredLanguage` 实现运行时语言切换（含"跟随系统"），并将 `AuthInterceptor` 中硬编码的 `Accept-Language: zh-CN` 改为随生效语言动态取值。登录页与设置-通用页各提供一个语言选择入口。

## Technical Context

**Language/Version**: ArkTS（Strict Mode），HarmonyOS API 12+ / SDK 6.1.0(23)  
**Primary Dependencies**: `@ohos.i18n`（`I18n.System.setAppPreferredLanguage` / `getSystemLanguage`）、`@kit.ArkData` preferences（既有 PreferenceService）、ArkUI `$r` 资源引用  
**State Management**: 沿用项目现有 State Management V1（`@State` / `@StorageLink` / AppStorage），不迁移  
**Storage**: PreferenceService（KV `pixiv_settings`），复用既有 `language` 键  
**Testing**: 无 CLI 测试脚本；验证走 Phase 5 build + 模拟器 UI 验证  
**Target Platform**: HarmonyOS 手机/平板（单模块 `entry`）  
**Project Type**: mobile-app（既有项目增量改造）  
**Performance Goals**: 语言切换即时生效（< 1s，SC-002）；资源化为编译期机制，无运行时性能损耗  
**Constraints**: ArkTS 严格约束（禁 any/as/动态属性）；EntryAbility 不得静态 import 含 Store 单例的模块；`@Builder` 内不能 `let`；`$r` 引用必须在组件/资源上下文可用  
**Scale/Scope**: ~700–850 条 UI 字符串，68 个 .ets 文件，28 个注册页面；3 种语言 × 全量翻译

## Project Structure

### Documentation (this feature)

```text
spec/multi-language-i18n/
├── spec.md              # Phase 1 需求规格
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

遵循既有项目架构，不引入 MVVM 重组。改动与新增如下：

```text
entry/src/main/resources/
├── base/element/string.json          # 改写为英文全集（作为不支持语种的回退兜底）
├── zh_CN/element/string.json         # 新增：简体中文全集
├── zh_TW/element/string.json         # 新增：繁体中文全集
└── en_US/element/string.json         # 新增：英文全集（与 base 一致）
AppScope/resources/base/element/string.json   # app_name 如需本地化则配套建 zh_CN/en_US（本期 app_name=ArkPix 不变，可不动）

entry/src/main/ets/
├── utils/
│   ├── Constants.ets                 # ACCEPT_LANGUAGE 断链常量改造为按生效语言取值的映射逻辑
│   └── I18nUtils.ets                 # 新增：非组件上下文取串辅助（getStr/getStrf，经 AppStorage context 的 resourceManager）+ 语言映射纯函数（preference→locale/tag）
├── pages/
│   ├── login/LoginPage.ets           # 新增语言选择入口（右上角"设置"旁）
│   ├── settings/GeneralSettingsPage.ets   # "通用"分组新增"语言"设置项
│   ├── settings/SettingWidgets.ets        # 新增 LANGUAGE_OPTIONS 选项数组（label 走资源）
│   └── （其余全部页面）                    # 硬编码字符串 → $r('app.string.xxx') 替换
├── components/                       # IllustCard / IllustWaterfall / CommonViews 等同样替换（TagExifPicker 死代码排除）
├── stores/                           # toast/提示语 → I18nUtils.getStr
├── services/                         # toast/错误描述/自检项名 → I18nUtils.getStr（注释与 EXIF 默认模板不动）
├── network/
│   ├── AuthInterceptor.ets           # Accept-Language 由字面量改为按生效语言动态取值
│   └── （其余网络文件错误描述同样替换）
└── entryability/EntryAbility.ets     # onCreate 启动时按持久化偏好应用语言（绕开 Store 静态 import 陷阱）
```

**Structure Decision**: 本计划完全遵循既有项目架构（pages/components/stores/services/network/utils 分层 + Store 单例 + AppStorage），不引入 MVVM 目录或重组。唯一新增源码文件为 `utils/I18nUtils.ets`（一个文件承载取串辅助与语言映射纯函数），其余均为存量文件的内容替换与小范围修改。资源文件全部位于 `entry/src/main/resources/` 限定词目录下。

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| base 资源改写为英文（而非保留中文） | spec 要求不支持的系统语言（如日语）回退英文（FR-003）；HarmonyOS 资源解析对无匹配限定词的语种回退 base | base 保留中文会导致日文用户看到中文界面，违反已确认需求 |

## Research & Decisions

### R1: 语言切换机制选型

- **Decision**: 使用 `I18n.System.setAppPreferredLanguage(locale)`（`@ohos.i18n`）实现应用内切换；传 `'default'` 恢复跟随系统。语言取值：简中 `zh-Hans`、繁中 `zh-Hant`、英文 `en-Latn-US`。
- **Rationale**: 官方 FAQ（faqs-localization-16）确认该接口为应用内单独设置偏好语言的标准途径，设置后应用优先加载对应限定词资源，且 `$r` 引用随配置变更即时刷新（官方示例为按钮点击即时切换，无需重启）。系统侧持久化应用偏好语言，重启后保持（叠加应用内 AppSettings 记录，双保险满足 FR-005）。
- **Alternatives considered**: ① 自建 AppStorage 文案表 + 手动 key 查表——放弃：需自管刷新与复数/格式化，且 700+ 处引用改动量更大；② `ApplicationContext.setLanguage()`——仅影响后续 resourceManager 行为，对已渲染 `$r` 刷新不可靠，项目内无先例。

### R2: 资源限定词目录与回退链

- **Decision**: 新建 `zh_CN`、`zh_TW`、`en_US` 三个限定词目录；`base/element/string.json` 改写为英文全集作为兜底（不支持语种如日语 → base → 英文，满足 FR-003 回退英文）。zh-Hans 偏好命中 zh_CN，zh-Hant 偏好命中 zh_TW，en-Latn-US 命中 en_US。
- **Rationale**: 官方 FAQ 确认"偏好语言为其他语言时显示 base 内容"；base=英文是唯一同时满足"回退英文"与"三语全覆盖"的布局。
- **Alternatives considered**: base 保留中文 + 日语等回退中文——违反 spec；使用 zh-Hans/zh-Hant 目录名——HarmonyOS 资源限定词惯例为 `zh_CN`/`zh_TW`，与文档示例一致。

### R3: 语言偏好字段复用与同步语义

- **Decision**: 复用 `AppSettings.language: string`（已存在，默认 `'zh-CN'`，持久化/读写链路完备）承载语言偏好，取值归一化为 `'system' | 'zh-Hans' | 'zh-Hant' | 'en-Latn-US'`；存量值 `'zh-CN'` 在读取时归一化为 `'system'`。将 `language` 从 Relay SyncService 与 DistributedSyncService 的同步载荷中移除（4 处），使语言偏好成为纯设备本地设置。
- **Rationale**: spec 假设明确"应用内语言偏好属于设备本地设置，不参与任何数据同步域"；语言是每台设备的显示偏好，多设备同步无意义且会造成"手机改语言把平板也改了"的困惑。
- **Alternatives considered**: 新增独立 `appLanguage` 字段——冗余，既有 `language` 字段正是为此预留；保持参与同步——违反 spec 假设。

### R4: Accept-Language 动态化

- **Decision**: `AuthInterceptor` 注入 Accept-Language 时按当前生效语言动态取值：zh-Hans→`zh-CN`，zh-Hant→`zh-TW`，en-Latn-US→`en-US`；"跟随系统"时按系统语言实时解析（解析结果不属于三语则用 `en-US`）。生效语言的判定逻辑收敛为 `I18nUtils` 中的纯函数，拦截器直接调用。既有断链常量 `Constants.ACCEPT_LANGUAGE` 移除或改造（全仓库无引用）。
- **Rationale**: FR-006 要求联动；判定收敛于一处避免拦截器与设置页逻辑分叉。
- **Alternatives considered**: 固定 zh-CN——已被用户在 Phase 1 明确否决。
- **影响记录**: `filterTranslatedName` 及 EXIF 合并检测 A/B/C 的行为依赖 API 翻译名语义；Accept-Language 变化后 translatedName 内容随语言变化属预期行为（spec US3），相关过滤纯函数无需修改。

### R5: 启动时语言应用

- **Decision**: `EntryAbility.onCreate` 在 `AppStorage.setOrCreate('context', ...)` 之后，直接通过 preferences API 读取 `pixiv_settings` 的 `language` 键（与 PreferenceService 同模式的最小读取，不静态 import UserSettingStore），若非 `'system'` 则调 `setAppPreferredLanguage`。SplashPage 不做额外处理。
- **Rationale**: 规避 AGENTS.md 记载的 EntryAbility 静态 import Store 单例冷启动闪退陷阱；系统侧偏好语言本身跨重启持久，此处为兜底重放，保证"应用内清除数据后重装/异常"场景一致。接续拉起（onWindowStageRestore → SplashPage）场景因 onCreate 已执行而天然覆盖。
- **Alternatives considered**: `import lazy` UserSettingStore——可行但为重读单个键引入整个 Store 模块链，过重。

### R6: 非组件上下文取串

- **Decision**: 新增 `utils/I18nUtils.ets`，提供基于 `AppStorage.get('context')` 的 resourceManager 同步取串（含 `%s`/`%d` 格式化变体），供 stores/services/network 等非组件代码使用；页面/组件内一律用 `$r`。
- **Rationale**: toast、错误描述、自检项名等约 200 条字符串产生自非 UI 层；resourceManager 的 getStringSync 尊重当前偏好语言配置，与 `$r` 行为一致。
- **Alternatives considered**: 把文案全部上提到页面层——改动面大且破坏既有"服务返回错误描述字符串"的架构约定。

### R7: 字符串资源化范围与 key 命名

- **Decision**: 纳入范围 = 全部用户可见文本（页面、组件、菜单、对话框、toast、空态/错误态、设置项、服务层错误描述）。排除 = 代码注释、`pages/novel/NovelPage.ets` 与 `components/common/TagExifPicker.ets` 死代码、用户自定义内容（文件名/EXIF 模板）、日志字符串、功能性常量（IP、URL、User-Agent）。key 命名按页面/功能前缀分组（如 `settings_general_language`、`detail_save_success`），同一语义复用同一 key。
- **Rationale**: spec FR-001 要求消除界面层硬编码；排除项均为非用户可见或用户自定义内容（spec 假设）。
- **Alternatives considered**: 按字母序单一大表——不可维护；逐页面独立资源文件——HarmonyOS 不支持页面级资源拆分。

### R8: 登录页语言入口形态

- **Decision**: `LoginPage` 右上角既有"设置"入口旁新增"语言"入口，点击弹出语言选择（TextPickerDialog 或等效多值选择，遵循项目弹窗约定），与设置页共用同一选项集与 setter。
- **Rationale**: FR-004 要求登录前可切换；登录页已有右上角 Stack 入口区，挂载成本最低；项目弹窗约定中多值选择用 TextPickerDialog。
- **Alternatives considered**: 仅依赖"设置→通用→语言"路径——登录前虽可达但不直观，不满足"最初的登录页面就要能选择语言"的用户原话。

## Data Model

### 语言偏好（复用既有 `AppSettings.language`）

| 项 | 内容 |
|---|---|
| 存储 | PreferenceService KV `pixiv_settings`，键 `language`（既有键，值语义升级） |
| 取值 | `'system'`（跟随系统，默认）/ `'zh-Hans'` / `'zh-Hant'` / `'en-Latn-US'` |
| 迁移 | 存量值 `'zh-CN'`（及任何非法值）读取时归一化为 `'system'` |
| 同步 | 不参与 Relay / Distributed 任一同步域（从 4 处载荷移除） |
| 系统侧 | `setAppPreferredLanguage` 同步写入系统偏好（重启保持） |

### 生效语言（派生值，不持久化）

| 偏好值 | setAppPreferredLanguage 参数 | Accept-Language | 资源目录 |
|---|---|---|---|
| `system` + 系统为简中 | `'default'` | `zh-CN` | zh_CN |
| `system` + 系统为繁中 | `'default'` | `zh-TW` | zh_TW |
| `system` + 系统为其他 | `'default'` | `en-US` | base/en_US |
| `zh-Hans` | `'zh-Hans'` | `zh-CN` | zh_CN |
| `zh-Hant` | `'zh-Hant'` | `zh-TW` | zh_TW |
| `en-Latn-US` | `'en-Latn-US'` | `en-US` | en_US |

### 字符串资源（新增/改写）

| 文件 | 内容 |
|---|---|
| `resources/base/element/string.json` | 英文全集（兜底）+ 既有 6 条系统条目 |
| `resources/zh_CN/element/string.json` | 简体中文全集 |
| `resources/zh_TW/element/string.json` | 繁体中文全集 |
| `resources/en_US/element/string.json` | 英文全集（与 base 一致） |
| 约束 | 三个限定词目录与 base 的 key 集合完全一致；含参数文案用 `%s`/`%d` 占位；各语言 value 按 key 对齐翻译 |

## Contracts & Interfaces

### I18nUtils（新增，utils/I18nUtils.ets）

| 成员 | 签名（描述） | 说明 |
|---|---|---|
| `getStr` | `(res: Resource) => string` | 非组件上下文同步取串，经 AppStorage context 的 resourceManager |
| `getStrf` | `(res: Resource, ...args) => string` | 带 `%s`/`%d` 参数格式化取串 |
| `normalizeLanguagePref` | `(raw: string) => LanguagePref` | 存量/非法值归一化为四值之一（`'zh-CN'`→`'system'`） |
| `prefToLocale` | `(pref: LanguagePref) => string` | 偏好→`setAppPreferredLanguage` 参数（`'system'`→`'default'`） |
| `effectiveAcceptLanguage` | `(pref: LanguagePref) => string` | 偏好（system 时结合 `I18n.System.getSystemLanguage()`）→ Accept-Language 头值 |

类型 `LanguagePref` 为字符串字面量联合语义的常量组（ArkTS 禁动态索引，采用既有项目常量+显式比较模式）。

### 修改点契约

| 位置 | 改动 |
|---|---|
| `network/AuthInterceptor.ets` | Accept-Language 注入由字面量 `'zh-CN'` 改为 `I18nUtils.effectiveAcceptLanguage(当前偏好)` |
| `stores/UserSettingStore.ets` | `setLanguage` 归一化入参；`loadSettings` 读取时归一化；`saveSettings` 后追加 `setAppPreferredLanguage` 调用（语言变更即时生效） |
| `services/SyncService.ets` / `services/DistributedSyncService.ets` | 设置域载荷移除 `language` 字段（collect/build 2 处 + apply 2 处） |
| `pages/settings/SettingWidgets.ets` | 新增 `LANGUAGE_OPTIONS`（四选项，label 走 `$r` 资源） |
| `pages/settings/GeneralSettingsPage.ets` | "通用"分组新增"语言"行，复用 showQualityPicker 模式 |
| `pages/login/LoginPage.ets` | 右上角新增语言入口与选择弹窗 |
| `entryability/EntryAbility.ets` | onCreate 启动重放偏好语言（preferences 直读 + setAppPreferredLanguage） |

### 外部系统契约

- `I18n.System.setAppPreferredLanguage(locale: string)`：`zh-Hans` / `zh-Hant` / `en-Latn-US` / `'default'`；运行时即时生效，`$r` 引用随配置变更刷新（官方 FAQ 验证）。
- `I18n.System.getSystemLanguage()`：返回系统语言（如 `zh-Hans`），用于 `system` 模式下 Accept-Language 解析。
- HarmonyOS 资源解析：精确限定词匹配 → base 兜底；`zh-Hant` 偏好可命中 `zh_TW` 目录。
