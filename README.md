# ArkPix

HarmonyOS 第三方 Pixiv 客户端，ArkTS / ArkUI 实现，API 12+（HarmonyOS NEXT / 5.x / 6.x）。

## 相关项目

| 仓库 | 说明 |
| --- | --- |
| [pixiv-relay](https://github.com/cqash/pixiv-relay) | 自托管服务端：网络中继 + 多设备数据同步 + 已删作品恢复（Go，NAS/小 VPS 友好） |
| [pixiv-web](https://github.com/cqash/pixiv-web) | Web 前端（Vue 3），经中继访问 Pixiv，产物可嵌入 pixiv-relay 同源托管 |

## 功能

- 推荐 / 关注 / 排行 / 搜索（插画与画师，支持 PID / UID 直达）瀑布流浏览
- 作品详情、多页查看器（双指缩放 + 平移手势）、评论区（主楼 / 回复楼）
- 收藏（公开 / 私密）、收藏状态全列表实时同步
- 下载管理：多任务并发、文件名模板、保存到图库
- **特色：作品信息自动写入图片元数据（EXIF / XMP）** —— 下载时自动把标题、作者、PID、标签写入图片文件本身，系统图库 / 相册 App 可直接检索：
  - 备注模板可自定义变量：`{title}`、`{user_name}`、`{illust_id}`、`{tags}`、`{tags_translated}`、`{tags_localized}` 等
  - 标签管理：屏蔽指定标签、同义标签合并（如 `女の子` / `女孩子` 自动去重）、优先级排序、超限截断保护
  - 双载体写入：JPEG 走 APP1 EXIF + XMP，PNG 走 EXIF + iTXt XMP，不重编码、不损画质
- 屏蔽过滤：屏蔽词 / 屏蔽作者 / AI 作品过滤，防社死模式
- 浏览与搜索历史（可导出）、用户主页
- 网络模式：标准直连 / 兼容模式（免 VPN 直连）/ 自托管中继
- 登录方式：WebView 登录 / Refresh Token 导入（支持多账号）
- 自托管中继（pixiv-relay）：多设备同步设置 / 历史 / 屏蔽，已删作品恢复
- 多设备协同：分布式数据同步、应用接续（跨设备继续浏览）

## 安装（侧载自签）

ArkPix 未上架应用市场，通过 Releases 提供**未签名 HAP 包**，需自行签名后安装：

1. 从 [Releases](https://github.com/cqash/ArkPix/releases) 下载最新的 `ArkPix-*-unsigned.hap`
2. 下载 [小白调试助手（auto-installer）](https://github.com/likuai2010/auto-installer)（支持 Windows / macOS / Linux / Android，在其 Releases 页获取）
   - Windows：首次打开若提示安装 Java，按提示安装即可
   - macOS：首次运行需终端执行 `xattr -d com.apple.quarantine xxx/hap_installer.app`
   - Linux：不要用 root 启动，需先 `sudo apt-get install zenity`
3. 手机上开启 **开发者模式**（设置 → 关于手机 → 连点版本号）
4. 打开小白调试助手，配置签名证书（工具支持自定义证书生成/更换），通过 USB 或无线连接手机
5. 将下载的 `.hap` 拖入工具，签名并安装

> 提示：自行签名安装的包与你的证书绑定，后续升级请继续使用同一证书签名，否则需先卸载旧版（本地数据会丢失）。

## 自行构建

1. 安装 [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/)（6.x，SDK 6.1.0(23) / API 23）
2. 克隆本仓库并用 DevEco Studio 打开
3. File → Project Structure → Signing Configs → 勾选自动生成签名（仓库故意不含签名配置）
4. Build → Build Hap(s)/APP(s)，或直接 Run 到设备

## 使用说明

- **登录**：推荐 WebView 登录（内置绕过，无需代理）；也可在「设置 → 账户 → 导入 Token」粘贴 Refresh Token
- **网络不通时**：登录页右上角「设置」可切换认证/ API 网络模式；有自建服务器可切换到中继模式（配合 pixiv-relay）
- **多设备同步**：在「设置 → 中继」注册自托管服务器后开启数据同步；或在「设置 → 通用」开启设备间同步（同华为账号近场设备）

## 致谢

- [PixEz](https://github.com/Notsfsssf/pixez-flutter)：网络绕过方案与交互设计参考
- [auto-installer](https://github.com/likuai2010/auto-installer)：HAP 自签侧载工具

## License

[MIT](LICENSE)
