# RustPalm

基于 RustDesk 的非官方 HarmonyOS 原生远程桌面客户端，用手机查看和操作电脑。

## 功能

- 自建 ID / 中继服务器，密码认证或电脑端授权，支持强制中继。
- 触控点击、右键、拖动、滚动，以及桌面缩放和平移。
- 文字输入和常用组合键，输入框默认遮蔽内容。
- 常用连接管理，可将访问密码保存在系统资产库中。
- 横竖屏布局、只读模式、后台返回恢复会话，以及主动断开时请求远程锁屏。

## 使用

1. 在 HarmonyOS API 26 手机安装应用，构建与签名方法见[开发文档](docs/development.md)。
2. 在电脑端运行 RustDesk，两端配置相同的自建服务器和服务器公钥。
3. 输入电脑 ID，完成密码认证或在电脑端允许连接；也可保存为常用连接。

当前主要验证 Windows 被控端。直连遇到连接重置时可尝试“强制中继”。后台会话受系统调度和网络状态影响；暂不支持音频、文件传输、剪贴板同步和多屏切换。

## 开发

界面使用 ArkTS / ArkUI，通过 C++ Node-API 桥接 RustDesk 核心，构建目标为 ARM64 手机和 x86_64 模拟器。

- [开发环境](docs/windows-setup.md)
- [构建、安装与测试](docs/development.md)
- [上游来源与依赖](docs/upstream.md)

## 许可证

采用 [AGPL-3.0](LICENSE)。感谢 [RustDesk](https://github.com/rustdesk/rustdesk) 和 [HarmonyOS 移植项目](https://github.com/wanghd114/rustdesk_harmonyos)。
