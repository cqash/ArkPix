# Implementation Plan: 历史记录与导出、Token 导出、搜索扩展、详情页 PID 与评论区

**Input**: Feature specification from `spec/history-search-comments/spec.md`

## Summary

在现有 ArkPix 架构上接线四组能力：(1) 新增 `HistoryPage`（浏览/搜索双 Tab）展示已有 `history`、`search_history` 表数据，并支持 JSON / PID 纯文本两种导出（复用 EXIF 导出的 DocumentViewPicker 模式）；(2) 设置页账户组新增"导出 Token"，单 AlertDialog 警告 + 二选一（复制剪贴板 / 导出 JSON 文件）；(3) `SearchPage` 增加纯数字建议直达（PID→详情、UID→用户主页）与结果区"插画/画师"Tabs（画师 Tab 复用已有 `searchUsers` API）；(4) 详情页 InfoRow 展示 PID（长按复制）+ "查看评论"入口，新增 `CommentPage`（列表/分页/发表/回复）与 `CommentStore`，新增回复拉取与发表评论两个 Pixiv 端点。

## Technical Context

**Language/Version**: ArkTS（strict mode），API 12+ / SDK 6.1.0(23)  
**Primary Dependencies**: `@kit.NetworkKit`（http）、`@kit.ArkData`（relationalStore、preferences）、`@kit.BasicServicesKit`（pasteboard，新增）、`@kit.CoreFileKit`（picker/fileIo，沿用 EXIF 导出模式）  
**State Management**: 沿用项目现有 State Management V1（@State/@StorageLink/AppStorage），不迁移 V2  
**Storage**: 现有 SQLite（pixiv.db，`history`/`search_history` 表，无 schema 变更）；导出走用户选定目录文件  
**Testing**: `@ohos/hypium` 单元测试（entry/src/test/），针对纯函数（评论解析、导出格式构建）  
**Target Platform**: HarmonyOS 手机/平板  
**Project Type**: mobile-app（单模块 entry）  
**Performance Goals**: 历史列表 1000 条内 1s 渲染；评论分页与现有瀑布流一致（游标续页）  
**Constraints**: ArkTS 严格约束（禁 any/unknown/as 断言、对象字面量需显式类型、@Builder 内禁 let）；弹窗遵循 AGENTS.md 弹窗风格约定（bindContextMenu 多选菜单 / showAlertDialog 二选一 / 不用 ActionSheet）；评论表情占位符按纯文本展示  
**Scale/Scope**: 5 个新文件 + 8 个修改文件；3 个新页面路由中的 2 个（HistoryPage、CommentPage）

## Project Structure

### Documentation (this feature)

```text
spec/history-search-comments/
├── spec.md
└── plan.md              # 本文件
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/
│   ├── settings/
│   │   ├── HistoryPage.ets          # 新增：历史记录页（浏览/搜索 Tabs + 导出 + 清空）
│   │   └── SettingsPage.ets         # 修改：+“历史记录”条目；账户组 +“导出 Token”
│   ├── detail/
│   │   ├── CommentPage.ets          # 新增：评论页（列表/分页/发表/回复；回复楼复用同页）
│   │   └── IllustDetailPage.ets     # 修改：InfoRow +PID 展示（长按复制）+“查看评论”入口
│   └── search/
│       └── SearchPage.ets           # 修改：数字直达建议入口 + 结果区插画/画师 Tabs
├── stores/
│   └── CommentStore.ets             # 新增：评论编排（非单例，同 IllustDetailStore 模式）
├── models/
│   └── Comment.ets                  # 修改：修复 UserPreview 坏 import（./User→./Illust）；
│                                    #       +replyToUserName 字段 + commentFromJson 解析
├── network/
│   ├── PixivEndpoints.ets           # 修改：+illustCommentReplies、+illustCommentAdd
│   └── ApiService.ets               # 修改：+getIllustCommentReplies、+addIllustComment
├── services/
│   └── DatabaseService.ets          # 修改：addHistory 按 illust_id 去重（先 DELETE 再 INSERT）；
│                                    #       getHistory 默认 limit 提高供历史页使用
├── utils/
│   ├── ClipboardUtils.ets           # 新增：copyText 纯文本复制（pasteboard）
│   └── HistoryExport.ets            # 新增：导出内容构建纯函数（JSON / PID 文本）
└── entry/src/main/resources/base/profile/
    └── main_pages.json              # 修改：注册 HistoryPage、CommentPage
```

**Structure Decision**: 遵循项目现有架构（pages/stores/services/models/utils 五层 + State V1），不引入 MVVM。理由：本特性是对既有页面的接线和两个新页面，与 IllustDetailStore 同级的非单例 `CommentStore` 足以承载评论编排；历史页为只读 DB 查询 + 文件导出，无需独立 store。新增 5 个文件为最小充分拆分。

## Complexity Tracking

无违规项（未引入新架构层，复用现有模式）。

## Research & Decisions

**Decision**: 评论回复采用"同页复用 push"方案（pixez 模式）  
**Rationale**: `CommentPage` 通过路由参数 `parentCommentId` 区分主列表模式（`/v3/illust/comments`）与回复楼模式（`/v2/illust/comment/replies`），点击"查看回复"以回复楼参数再 push 一个 CommentPage 实例，避免嵌套缩进 UI 与第二套页面  
**Alternatives considered**: 嵌套缩进树（ArkUI List 内实现复杂，与项目行模型习惯不符）；半模态回复面板（偏离项目 router 多页风格）

**Decision**: Token 导出用单个 AlertDialog 完成"警告 + 二选一"  
**Rationale**: AlertDialog 支持 primaryButton/secondaryButton 两个动作 + 遮罩点击取消，正好承载"复制到剪贴板"/"导出为文件"，message 放风险提示；符合弹窗约定且只打断一次  
**Alternatives considered**: 连续两个弹窗（警告→选择，体验割裂）；bindContextMenu（无警告文案位置，安全确认不达标）

**Decision**: 剪贴板用 `@kit.BasicServicesKit` 的 `pasteboard`（`createData(MIMETYPE_TEXT_PLAIN, text)` + `systemPasteboard.setData`），封装为 `ClipboardUtils.copyText`  
**Rationale**: 官方 API 12 推荐方案；写入（复制）不需要 READ_PASTEBOARD 权限；PID 长按复制与 token 复制共用  
**Alternatives considered**: 每处直接调 pasteboard（重复代码，错误处理不一致）

**Decision**: 搜索结果区改为 `Tabs`（插画 / 画师），画师 Tab 内联实现用户列表  
**Rationale**: 与 HomePage 的 Tabs 用法一致；画师列表结构简单（头像+名称+账号+分页），复用 `apiService.searchUsers` + `fetchNext` 游标续页，用户项解析用 `Illust.ets` 的 `UserPreview.fromJson`；点击复用 UserProfilePage `{userId}` 路由  
**Alternatives considered**: 独立 UserSearchPage（多一路由与页面，搜索结果切换体验割裂）

**Decision**: 数字直达入口渲染在搜索建议区（输入监听，纯数字时出现）  
**Rationale**: 与 pixez 一致；直达复用现有路由：PID→`IllustDetailPage {illustId}`、UID→`UserProfilePage {userId}`，无效 ID 由目标页现有错误态兜底  
**Alternatives considered**: 提交后自动跳转（数字也可能是合法标签，不能剥夺用户选择权）

**Decision**: 历史导出入口放 HistoryPage 顶部菜单（bindContextMenu：导出 JSON / 导出 PID 列表 / 清空历史）  
**Rationale**: 符合"多选项菜单用 bindContextMenu"约定；清空带 AlertDialog 确认  
**Alternatives considered**: 设置页放导出条目（入口深、与数据页分离）

**Decision**: `DatabaseService.addHistory` 修正为按 `illust_id` 去重（先 DELETE 同 illust_id 再 INSERT）  
**Rationale**: 现表 `id` 为 PK、`illust_id` 无 UNIQUE 约束，`INSERT OR REPLACE` 实际不去重，历史页会出现同一作品多条；去重是历史页可用性前置  
**Alternatives considered**: 加 UNIQUE 索引需 schema 迁移（项目无迁移框架，风险大于收益）；页面层去重（每次查询浪费）

**Decision**: `Comment.ets` 修复 `UserPreview` 导入来源（`./User` → `./Illust`），新增 `replyToUserName` 字段与 `commentFromJson` 解析函数  
**Rationale**: `User.ets` 无 `UserPreview`（实际定义在 `Illust.ets`），现 import 为坏引用（死代码未暴露）；回复楼需要"回复 @某人"前缀，来源于响应中 `parent_comment.user.name`；解析遵循项目 `fromJson(raw) → Options → new Model(opts)` 模式  
**Alternatives considered**: 新建独立 UserPreview（加重三处同名类混乱）

**Decision**: 评论发表走 `POST /v1/illust/comment/add`（form 编码，字段 `illust_id`、`text`、可选 `parent_comment_id`）  
**Rationale**: pixez 验证过的端点；项目 `ApiService.post` 已实现 form 编码（收藏/关注同款）  
**Alternatives considered**: 不支持发表（已在需求阶段明确需要）

**Decision**: 贴图评论（comment 文本为空且含 stamp 字段）显示占位文本"[贴图]"  
**Rationale**: 需求明确 emoji/stamp 图片化不在本期；占位避免空白行误导  
**Alternatives considered**: 过滤不展示（丢失楼层上下文，回复关系断裂）

## Data Model

**浏览历史条目（HistoryItem，现有，不变更 schema）**
- 表 `history`：`id PK, illust_id, title, image_url, user_name, timestamp`
- 行为变更：`addHistory` 按 illust_id 去重；查询按 timestamp DESC

**搜索历史条目（SearchHistoryItem，现有）**
- 表 `search_history`：`id PK, keyword, search_type, timestamp`
- 历史页只读；清空沿用现有入口（搜索页已支持，历史页提供同样能力——仅浏览历史清空，搜索历史清空复用现有方法）

**Comment（扩展 models/Comment.ets）**
- 既有字段：`id, parentCommentId, user: UserPreview, comment, date`
- 新增：`replyToUserName: string`（回复目标用户名，来自 `parent_comment.user.name`，顶层评论为空串）
- 解析：`commentFromJson(raw)` → `CommentOptions` → `new Comment(opts)`；user 用 `Illust.ets UserPreview.fromJson`
- 列表响应契约：`{ comments: RawComment[], next_url: string | null }`（回复楼同构）

**历史导出 JSON（buildHistoryExportJson 输出）**
- `{ version: 1, appName: 'ArkPix', type: 'browse_history', exportedAt: ISO8601, count: number, items: [{ illustId, title, userName, imageUrl, timestamp }] }`
- PID 文本：`buildHistoryPidText` 输出每行一个 illust_id

**Token 导出 JSON**
- `{ version: 1, appName: 'ArkPix', type: 'token', userId, userName, account, refreshToken, exportedAt }`
- 数据源：`accountStore.getCurrentAccount()`（现有访问器，返回 Account | null；null 时提示无可用 token）

## Contracts & Interfaces

**新增 Pixiv 端点（PixivEndpoints）**
- `illustCommentReplies(commentId: number)` → `GET /v2/illust/comment/replies?comment_id={id}`
- `illustCommentAdd()` → `POST /v1/illust/comment/add`（form 字段：`illust_id`、`text`、可选 `parent_comment_id`）

**新增 ApiService 方法**
- `getIllustCommentReplies(commentId: number): Promise<Object>`
- `addIllustComment(illustId: number, text: string, parentCommentId?: number): Promise<Object>`
- 评论分页续用现有 `fetchNext(nextUrl)`（响应含 `next_url`）

**路由契约**
- `pages/settings/HistoryPage`：无参数
- `pages/detail/CommentPage`：`{ illustId: number, illustTitle?: string, parentCommentId?: number, replyToName?: string }`；`parentCommentId` 存在即回复楼模式
- 历史页浏览条目点击 → `pages/detail/IllustDetailPage { illustId }`（现有契约）
- 历史页搜索条目点击 → `pages/search/TagSearchPage { keyword }`（现有契约，以该词执行插画搜索）
- 数字直达 PID → `IllustDetailPage { illustId }`；UID → `pages/user/UserProfilePage { userId }`（现有契约）

**ClipboardUtils**
- `copyText(text: string): Promise<boolean>`——成功 true；异常捕获返回 false（调用方据结果 toast）

**HistoryExport（纯函数）**
- `buildHistoryExportJson(items: HistoryItem[]): string`
- `buildHistoryPidText(items: HistoryItem[]): string`

**CommentStore（非单例，页面持有）**
- 状态：`comments: Comment[]`、`isLoading`、`isLoadingMore`、`nextUrl`、`error`、`replyTarget`（回复对象或 null）
- 方法：`loadFirst(illustId)`、`loadReplies(commentId)`、`loadMore()`、`postComment(illustId, text)`、`postReply(illustId, parentCommentId, text)`
- 发表成功后把新评论插入列表头部（主楼）或尾部追加并提示（回复楼），140 字上限在输入层限制

**UI 契约**
- 详情页 InfoRow：统计区新增一行 `PID: {id}`，LongPressGesture → `ClipboardUtils.copyText` + toast"已复制 PID"；按钮区新增"查看评论"按钮 → pushUrl CommentPage
- 搜索建议区：输入为纯数字时顶部显示"插画 ID 直达：{n}""画师 ID 直达：{n}"两项
- HistoryPage：顶部标题栏 + 菜单（bindContextMenu）；Tabs 两个子页均为 List/Grid + 空态（CommonViews.EmptyView）；清空仅作用于当前 Tab 数据源（浏览历史清空；搜索历史 Tab 提供清空搜索历史）
- 导出文件默认名：`arkpix-history.json` / `arkpix-history-pids.txt` / `arkpix-token.json`，保存位置由系统 DocumentSavePicker 决定（沿用 ExifTagConfigPage 模式）
