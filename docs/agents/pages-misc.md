# 页面行为细节：详情交互 / 历史 / Token / 搜索 / 评论 / 防社死

> 从 AGENTS.md 拆分。改动对应页面时阅读并同步更新本文档。

## 防社死模式

- `AppSettings.antiSocialDeath`：R18 图片在 IllustCard/IllustDetailPage/ImageViewerPage 显示纯色遮罩 + 🔒 锁图标（卡片/详情为灰色 `#E0E0E0`，查看器为深灰 `#2C2C2C`，无模糊效果）
- 详情页/查看器点击遮罩单向揭示（无再次点击恢复逻辑）；IllustCard 无揭示交互（点击整卡直接进详情页）

## 详情页交互

- Tag 长按菜单（bindContextMenu）：复制标签名 / 屏蔽该标签 / 备注中屏蔽 / 备注中合并
- 图片长按菜单（bindContextMenu）：保存当前页 / 保存全部页——仅多页作品长按才弹菜单；单页作品长按直接保存，不弹菜单
- 合并对话框：输入主 tag 名 → `addExifMergeRule`；输入框带补全建议（本地 exifMergedTags mainTag/fromTags + 本作品 tag 即时前缀匹配去重，仅本地零匹配且停顿 ≥300ms 才调 getAutoComplete API，点选回填；纯函数在 `utils/MergeSuggest.ets`）
- InfoRow 展示 `PID: {id}`，长按复制到剪贴板（ClipboardUtils + toast）；统计区含发布日期行（`formatCreateDate(illust.createDate)` 本地时区 yyyy-MM-dd HH:mm，空串不渲染该行）与分辨率行（`{width}×{height}`，任一维度为 0 不渲染）
- **简介富文本行（R4）**：tag 胶囊区后、评论入口前，`CaptionParser.parseCaptionHtml(illust.caption)` 分段 → `Text(){ ForEach(segments, Span) }` 渲染；链接段蓝字 #0096FA 可点——PixivLinkParser 命中应用内跳详情/画师页，否则 `UIAbilityContext.openLink` 开系统浏览器（静默失败）；空 caption（解析后空数组）不渲染该行
- **详情页顶栏（R4）**：Pane 根 Stack 顶部叠加层（半透明黑底白字药丸按钮 + hitTestBehavior Transparent 不挡滚动，内容 Column padding top 44）：左「‹」router.back()、右「⋮」bindContextMenu 六项——分享（@kit.ShareKit systemShare，SharedData 文本记录=作品 web URL）、复制链接、复制文案（标题+captionToPlainText）、画师信息、多图保存（仅多页，开既有选页弹窗）、屏蔽作者（复用 addMuteUser+toast）；菜单内 toast/弹窗统一先收菜单再 setTimeout(300)；药丸勿加 systemMaterial 沉浸光感（该区域不生效会渲染为透明，已回退，见 docs/agents/immersive-material.md）
- **相关作品触底自动加载（R4）**：根 List `.onReachEnd` → Pane `loadMoreRelated()`（`@State hasMoreRelated` + store.relatedLoading 双门控，rebuildRows 时同步 hasMoreRelated）；List 尾部保留「加载更多」文字按钮作失败兜底
- 画师行 = 头像+用户名（点击进画师主页）+ 行内右侧 FollowButton（三态关注按钮，初始态取详情接口 `user.is_followed`）；画师行长按 bindContextMenu：屏蔽该作者（addMuteUser+toast）/ 复制 UID（承接卡片长按菜单迁移项）
- 操作区 = 根 Stack（BottomEnd）右下角双 FAB（均套 `MaterialFab` 沉浸光感玻璃球，原理与坑见 docs/agents/immersive-material.md）：收藏 FAB（bookmarkState() 驱动——未收藏=Text('♡') 浅灰 #999999、已收藏=Text('❤') 红 #FF4081、请求中灰色，点按 toggleBookmark（走 onFabClick + 长按后 500ms 抑制误触 `bookmarkLongPressAt`），**长按=带标签收藏面板 BookmarkTagPanel**，可见性并入面板，仅未收藏时响应）+ 下载 FAB（**SaveButton 安全控件**，`SaveIconStyle.LINES` 线条图标 + `backgroundColor('#1AFFFFFF')`（10% 白纱，安全控件背景 alpha<0x1a 会被系统强制不透明，这是下限），点击授权成功后单击=handleSaveAll()（多页）/handleSavePage(0)（单页），长按仅多页=打开选页弹窗；安全控件不支持深度自定义，勿换成普通按钮——普通按钮拿不到图库临时授权，静默保存会失效回退到系统确认弹窗）；EXIF Picker/合并审查/合并对话框/选页弹窗/收藏标签面板任一打开时隐藏 FAB；原 InfoRow 按钮区已移除
- **选页弹窗**（IllustDetailPage 内联覆盖层，半透明遮罩+底部弹层）：4 列缩略图网格（CachedImage squareMedium 方图 + 勾选角标 + 页码角标，防社死页纯色遮罩不揭示），全选/清空，取消/确定下载(N)（空选择不发起）；多选交互=单击单格切换 + 长按≥300ms 激活拖选（起始格定方向、PanGesture 滑动按经过格区间批量置目标状态、拖前快照重算）；Grid 用 `.priorityGesture(PanGesture(PanGestureOptions))` + 动态 distance（普通 10000vp 让位滚动，拖选 1vp 即触）+ `onDidScroll` 累计滚动偏移换算触点格索引；确认走 `handleSavePages(selected)`（合并审查预检→EXIF Picker 续走 `exifPickerPendingPages`→`store.savePages`）；EXIF Picker 续走状态为 `exifPickerPendingPages: number[]`（单页=[i]、全集、子集三分支 resumeSaveAfterPicker）
- "查看评论"= tag 云之后、相关作品之前的居中小号文字按钮 → CommentPage `{ illustId, illustTitle }`

## 历史记录与导出

- HistoryPage（设置→历史记录）：Tabs（浏览历史 / 搜索历史）。浏览 Tab 网格展示 `history` 表（时间倒序，CachedImage + 标题 + 作者），点击进详情；搜索 Tab 关键词列表，点击进 TagSearchPage
- 搜索历史覆盖 tag 跳转：`TagSearchPage.aboutToAppear` 单点写 `addSearchHistory(keyword, 'illust')`（详情页 tag 点击与历史回放共用入口；回放重写仅刷新时间戳，走既有先删后插去重）
- `DatabaseService.addHistory` 按 illust_id 去重（history 表 illust_id 无 UNIQUE 约束，先 DELETE 再 INSERT）；`getHistory` SQL 按 illust_id 分组取 MAX(id) 合并展示（兼容存量重复数据，不清理 DB），默认 limit 500
- 顶部 ⋮ 菜单（bindContextMenu）：导出 JSON（`buildHistoryExportJson`，version/appName/type/exportedAt/count/items）/ 导出 PID 列表（`buildHistoryPidText`，每行一个）/ 清空浏览历史（AlertDialog 确认）；导出走 DocumentSavePicker（arkpix-history.json / arkpix-history-pids.txt），空历史 toast 不弹选择器

## Token 导出

- 设置→账户组"导出 Token"→ 单 AlertDialog（风险警告 message + primaryButton"复制到剪贴板" + secondaryButton"导出为文件"，遮罩/返回=取消）
- 数据源 `accountStore.getCurrentAccount()`（null/空 token 时 toast"无可用 token"）；文件默认名 `arkpix-token.json`，含 version/userId/userName/account/refreshToken/exportedAt（不含 access token）
- 剪贴板统一走 `ClipboardUtils.copyText(text): Promise<boolean>`（pasteboard createData(MIMETYPE_TEXT_PLAIN) + setData，写剪贴板无需权限）

## 搜索扩展

- SearchPage 输入纯数字时显示"插画 ID 直达"（→IllustDetailPage `{illustId}`）与"画师 ID 直达"（→UserProfilePage `{userId}`）；直达块在 `if (!this.hasSearched)` 门控之外、输入框 Row 之下两分支共用位置（@Builder NumericDirectEntries）——曾在门控内因 hasSearched 永真不可见（回归已修复）；无效 ID 由目标页错误态兜底；PID/UID 直达与搜索提交均写搜索历史
- 结果区 Tabs（插画 / 画师）：插画 Tab 为原 IllustWaterfall；画师 Tab 用 `apiService.searchUsers` + `fetchNext` 游标分页。/v1/search/user 响应 `user_previews[]` 元素是**包装对象** `{user, illusts, novels, is_muted}`，必须先取 `.user` 再喂 `UserPreview.fromJson`（不解包会全部落空成灰头像"@"）；点击进 UserProfilePage
- SearchPage 支持可选路由参数 `{keyword?, tab?}`：keyword 预填并自动提交，tab='user' 初始定位画师 Tab（Tabs 构造参数 index 仅创建时生效）；搜索历史 search_type 四类：`illust`（插画词）/`user`（画师词，按提交时所在 Tab 记录）/`pid`/`uid`（数字直达）；`addSearchHistory` 按 keyword+search_type 先删后插去重
- HistoryPage 搜索历史 Tab：条目带类型标识（插画/画师/PID/UID），点击按类型回放（illust→TagSearchPage、user→SearchPage{keyword,tab:'user'}、pid→详情、uid→用户主页）；浏览历史 `getHistory` SQL 按 illust_id 分组取 MAX(id) 合并展示（不动存量数据，导出共用此查询自动一致）
- **链接直达**：输入 trim 后为可解析 pixiv 链接（artworks/users/member_illust.php/pixiv://illusts|user，经 `PixivLinkParser.parse` 纯函数）时显示"链接直达"行（与 NumericDirectEntries 并列常驻位），点击跳详情/画师页并写搜索历史（复用 pid/uid 类型）；不识别返回 null 静默不显示
- **自动补全下拉**：输入框 onChange 300ms 防抖（纯数字/URL/空输入跳过）调 `getAutoComplete`，输入框下渲染建议列表（最多 10 条去重）；点选：多词（空格分词≥2，含全角空格）仅替换最后一个词、光标置末尾、不提交；单词回填并直接提交；提交/失焦（onBlur）/清空时收起

## 评论区

- CommentPage 路由参数 `{ illustId, illustTitle?, parentCommentId?, replyToName? }`；`parentCommentId` 存在即回复楼模式（同页复用 push，标题"回复列表"）
- CommentStore（非单例）：`loadFirst`（/v3/illust/comments）/ `loadReplies`（/v2/illust/comment/replies）/ `loadMore`（fetchNext 游标，按 id 去重）/ `postComment` / `postReply`（POST /v1/illust/comment/add，form 编码 illust_id/**comment**/可选 parent_comment_id——字段名必须是 comment，误用 text 会触发服务端 500）
- 发表成功主楼插列表头、回复楼追加尾部；失败 toast 且输入内容不丢失；TextInput maxLength 140
- 列表行：头像 + 用户名 + 时间 + 正文（comment 为空且含 stamp 显示"[贴图]"）+ 回复前缀"回复 @xxx"（replyToUserName，来自 parent_comment.user.name）+ 主楼模式 hasReplies 时显示"查看回复"
- `models/Comment.ets`：commentFromJson/parseCommentListPage 遵循 fromJson→Options→new Model 模式；UserPreview 从 ./Illust 导入
