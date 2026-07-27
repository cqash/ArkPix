# Implementation Plan: 验证问题修复第一轮（verification-fixes-round1）

**Input**: Feature specification from `spec/verification-fixes-round1/spec.md`

## Summary

修复上一轮功能验证发现的 11 个问题。根因已全部定位，多为小范围精准修复：评论 500=form 字段名 `text` 应为 `comment`；画师搜索灰头像=`user_previews[]` 是包装对象需先取 `.user`；登录返回=子登录页 replace 只换栈顶、LoginPage 压底，需 `router.clear()`；历史重复=查询层 SQL 按 illust_id 分组去重；空历史导出无提示=菜单未关 toast 被弹层吞掉；下载管理=进度无上报机制、retryAllFailed 计数口径误导；合并对话框=移除 hitTestBehavior(Block)。另含两项体验改造：详情页操作区改右下角双 FAB + "查看评论"改 tag 云下方小号文字按钮；合并对话框输入补全（本地合并规则/本作品 tag 优先，API 兜底）。

## Technical Context

**Language/Version**: ArkTS（strict mode），API 12+ / SDK 6.1.0(23)  
**Primary Dependencies**: `@kit.NetworkKit`、`@kit.ArkData`（relationalStore）、`@kit.ArkUI`（router/bindContextMenu）  
**State Management**: 沿用 State Management V1  
**Storage**: 现有 pixiv.db（无 schema 变更；history/search_history 仅查询与写入逻辑修正）  
**Testing**: `@ohos/hypium`（纯函数/解析层单测，视改动需要）  
**Target Platform**: HarmonyOS 手机/平板  
**Project Type**: mobile-app（单模块 entry）  
**Performance Goals**: 下载页轮询刷新 ≤2s 感知；补全本地匹配即时、API 防抖 300ms  
**Constraints**: ArkTS 严格约束；弹窗约定（bindContextMenu/showAlertDialog，禁 ActionSheet，覆盖层禁 hitTestBehavior(Block) 改用 .onClick(()=>{})）；不改变存量 DB 数据  
**Scale/Scope**: 约 10 个修改文件 + 0-1 个新文件

## Project Structure

### Documentation (this feature)

```text
spec/verification-fixes-round1/
├── spec.md
└── plan.md              # 本文件
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── network/
│   ├── ApiService.ets              # 修改：addIllustComment 字段名 text→comment；ensureSuccess 错误消息带响应体
│   └── PixivEndpoints.ets          # 修改：searchAutoComplete 追加 merge_plain_keyword_results=true
├── pages/
│   ├── search/SearchPage.ets       # 修改：user_previews 解包 .user；搜索历史四类记录（illust/user/pid/uid）；
│   │                               #       支持可选路由参数 {keyword?, tab?} 供历史回放定位画师 Tab
│   ├── settings/
│   │   ├── HistoryPage.ets         # 修改：菜单项先关菜单再延迟执行导出（toast 不被吞）；
│   │   │                           #       搜索历史按类型回放；toast 走 UIContext promptAction
│   │   └── DownloadPage.ets        # 修改：可见期轮询静默刷新（不置 isLoading）；重试结果分类 toast
│   ├── detail/IllustDetailPage.ets # 修改：根 Stack 挂双 FAB（收藏/下载），InfoRow 移除按钮区；
│   │                               #       "查看评论"改 tag 云下方小号居中文字按钮；MergeDialogOverlay 去 Block
│   │                               #       改 .onClick(()=>{})；合并对话框加输入补全建议列表
│   └── login/
│       ├── WebViewLoginPage.ets    # 修改：登录成功 router.clear() + replaceUrl HomePage
│       └── TokenLoginPage.ets      # 修改：同上
├── services/
│   ├── DatabaseService.ets         # 修改：getHistory SQL 按 illust_id 分组取最新；addSearchHistory 先删后插去重
│   └── DownloadService.ets         # 修改：retryAllFailed 计数口径（发起/成功/失败/跳过）+ 任务变更事件通知
├── stores/
│   └── CommentStore.ets            # 修改（可选）：错误消息透传服务端响应体
└── utils/
    └── MergeSuggest.ets            # 新增（可选）：补全候选构建纯函数（本地来源合并去重）
```

**Structure Decision**: 遵循现有架构，全部为就地修复；唯一可能的新文件是补全候选构建纯函数（为可测试性），不引入任何新层。

## Complexity Tracking

无违规项。

## Research & Decisions

**Decision**: 评论 500 修复 = `addIllustComment` form 字段名 `'text'` → `'comment'`  
**Rationale**: 与 pixez 参考实现逐字段比对，路径/编码/parent_comment_id 逻辑均一致，唯一差异是字段名；Pixiv 对缺必填字段的 form 请求返回 500  
**Alternatives considered**: 改端点版本（无依据）；顺带把 `ensureSuccess` 错误消息附加响应体（采纳，便于未来定位）

**Decision**: 画师搜索解析 = `user_previews[]` 元素先取 `.user` 再喂 `UserPreview.fromJson`  
**Rationale**: /v1/search/user 响应元素为包装对象 `{user, illusts, novels, is_muted}`，扁平 fromJson 读取全部落空（name=''、account=''、头像空、id=0 连 ForEach key 冲突与跳转 userId=0）  
**Alternatives considered**: 改 fromJson 兼容两种结构（污染模型层，拒绝；在调用处解包）

**Decision**: 搜索历史四类记录 = 写入点扩展到数字直达 onClick（类型 pid/uid），`search()` 按当前结果 Tab 记类型（illust/user）；`addSearchHistory` 改先 DELETE（keyword+search_type）再 INSERT  
**Rationale**: 直达绕过唯一写入点；search_type 原硬编码 'illust'；原 INSERT OR REPLACE 因无 UNIQUE 约束不去重（与 addHistory 同款存量 bug）  
**Alternatives considered**: 表加 UNIQUE 索引（项目无迁移框架，拒绝）

**Decision**: 搜索历史回放 = SearchPage 支持可选路由参数 `{keyword?, tab?}`，HistoryPage 按 search_type 分发（illust→TagSearchPage、user→SearchPage{keyword,tab:'user'}、pid→IllustDetailPage、uid→UserProfilePage）  
**Rationale**: 复用现有页面与路由契约，改动最小  
**Alternatives considered**: 新建统一搜索结果页（过度设计）

**Decision**: 历史展示去重 = `getHistory` SQL 改为 `SELECT * FROM history WHERE id IN (SELECT MAX(id) FROM history GROUP BY illust_id) ORDER BY timestamp DESC LIMIT ?`  
**Rationale**: MAX(id) 分组在同毫秒 timestamp 下仍唯一；ResultSet 列名不变、解析代码零改动；不动存量数据（用户明确选择）；导出复用 getHistory 自动一致  
**Alternatives considered**: JOIN MAX(timestamp)（同 timestamp 极端情况可能多行）；展示层内存去重（浪费 IO）

**Decision**: 登录返回栈修复 = 两个子登录页成功回调改 `router.clear()` + `router.replaceUrl(HomePage)`  
**Rationale**: LoginPage 用 pushUrl 开子登录页压栈，子页 replace 只换栈顶；clear 保证 Home 之下无残留。不改动 LoginPage 的 pushUrl（保留子登录页可返回到登录方式选择）  
**Alternatives considered**: LoginPage pushUrl 改 replaceUrl（子登录页返回无页可退，拒绝）

**Decision**: 下载进度刷新 = DownloadPage 可见期 1.5s 轮询静默刷新（不置 isLoading）+ DownloadService 任务完成事件通知；retryAllFailed 返回分类计数（发起/成功/失败/跳过），toast 展示明细  
**Rationale**: 当前下载为整包 ArrayBuffer 一次写盘，无中间进度可报（0→100）；轮询满足"状态无需退出重进"且风险最低；列表闪 Loading 的观感问题由静默刷新解决；计数口径修复"以为只重试一个"的误导  
**Alternatives considered**: 流式下载上报真实百分比（http on('dataReceive')/rcp downloadToFile，改动面大、影响图片头/重试逻辑，本轮拒绝，列为后续优化）

**Decision**: 详情页操作区 = 根 Stack 主 Column 之后、弹层之前挂双 FAB 容器（BottomEnd 对齐）：收藏 FAB（书签图标，bookmarkState() 着色，点按 toggleBookmark，长按公开/私密菜单）、下载 FAB（点按 handleSavePage(0)，长按 bindContextMenu 含"保存当前页/下载全部"，多页才显示下载全部）；弹层（EXIF Picker/合并审查/合并对话框）打开时隐藏 FAB；InfoRow 删除原按钮区，"查看评论"改为 tag 云行之后、related_header 之前的居中小号文字按钮  
**Rationale**: FAB 逻辑全部复用现有方法（零行为变更只移触发点）；挂载点在所有弹层之下避免层级冲突；查看评论低频，小号文字按钮符合用户指定位置  
**Alternatives considered**: 单 FAB 展开菜单（用户已明确选双 FAB）；按钮区两行排列（已被用户否决，改重设计）

**Decision**: MergeDialogOverlay 修复 = 删除 `.hitTestBehavior(HitTestMode.Block)`，内层改 `.onClick(() => {})` 消费点击  
**Rationale**: 用户设备实测 Block 挡住了 TextInput/按钮交互（406ad14 的假设不成立）；.onClick 方案在合并审查弹窗已验证无冲突，且为 US7 补全建议列表（可点击项）扫清障碍；同步更新 AGENTS.md 删除"已知例外"表述  
**Alternatives considered**: 保留 Block 仅调整子组件（用户实测不可点，不可保留）

**Decision**: 合并输入补全 = 本地优先（exifMergedTags 的 mainTag+fromTags 全量 + 当前作品 tags，即时前缀匹配、跨来源去重），仅当本地零匹配且输入停顿 ≥300ms 时调 `getAutoComplete`；API 解析 `tags[].name`（translated_name 过 filterTranslatedName）；端点追加 `merge_plain_keyword_results=true`；建议列表内联在对话框输入框下方，点选回填  
**Rationale**: 用户明确的优先级策略；API 仅在本地无匹配时调用，省流量且避免干扰  
**Alternatives considered**: 每次输入都并发请求 API 合并展示（用户明确否决）

**Decision**: 空历史导出提示 = 菜单项 onClick 先 `menuShown=false`，`setTimeout(300ms)` 后执行导出逻辑；toast 改用 `this.getUIContext().getPromptAction().showToast()`  
**Rationale**: 根因是 bindContextMenu 弹层未关闭时模块级 promptAction 的 toast 被吞；延迟到菜单关闭动画后执行；UIContext promptAction 是当前推荐 API  
**Alternatives considered**: 改 AlertDialog 提示（重交互，杀鸡用牛刀）

## Data Model

**搜索历史条目（行为变更，无 schema 变更）**
- 表 `search_history`：`search_type` 取值扩展为 `illust | user | pid | uid`
- 写入：同 keyword+search_type 先 DELETE 再 INSERT（去重）
- 回放映射：illust→TagSearchPage{keyword}、user→SearchPage{keyword,tab:'user'}、pid→IllustDetailPage{illustId}、uid→UserProfilePage{userId}

**浏览历史（查询变更）**
- getHistory：按 illust_id 分组取 MAX(id) 行，时间倒序；导出共用此查询

**补全候选（内存模型）**
- `{ name: string, translatedName: string, source: 'local_rule' | 'current_illust' | 'api' }`
- 本地来源即时产生；api 来源防抖后追加（仅本地为空时）

**下载重试结果（返回值扩展）**
- `{ started: number, succeeded: number, failed: number, skipped: number }`（原返回 number，页面 toast 据此展示明细）

## Contracts & Interfaces

**ApiService**
- `addIllustComment(illustId, text, parentCommentId?)`：form 字段 `{ illust_id, comment, parent_comment_id? }`（字段名修正）
- `getAutoComplete(word)`：响应解析 `{ tags: [{name, translated_name}] }`（调用方解析或新增解析辅助）
- `ensureSuccess`：错误消息附加截断后的响应体（如 200 字符）

**SearchPage 路由参数（扩展，向后兼容）**
- `{ keyword?: string, tab?: 'illust' | 'user' }`：存在 keyword 时预填并自动提交；tab='user' 时结果区初始定位画师 Tab

**DownloadService**
- `retryAllFailed(onTaskDone?)`：返回值 `number` → `RetryAllResult { started, succeeded, failed, skipped }`
- 任务变更通知：注册/注销回调（页面可见期注册）或 AppStorage 计数器——实现时二选一，倾向回调注册表

**IllustDetailPage FAB 契约**
- 收藏 FAB：`bookmarkState()` 驱动颜色（灰/红/请求中），点按 `store.toggleBookmark()`，长按 bindContextMenu（公开/私密收藏）
- 下载 FAB：点按 `handleSavePage(0)`；长按 bindContextMenu（保存当前页 / 下载全部——仅 pageCount>1 显示后者）
- 可见性：`illust.id > 0 && !exifPickerShown && !mergeReviewShown && !mergeDialogShown`

**合并对话框补全**
- 本地来源：`userSettingStore.getSettings().exifMergedTags`（mainTag+fromTags 拍平去重）+ `illust.tags[].name`
- API：`apiService.getAutoComplete(prefix)`，防抖 300ms，仅本地零匹配时触发
- 点选建议 → `mergeInputText = name`，建议列表清空
