# 构建与开发

应用标识为 `com.rustpalm.client`，使用 API 26 SDK，支持 ARM64 手机和 x86_64 模拟器。先按 [Windows 开发环境](windows-setup.md)准备工具链。

## 构建

在项目根目录执行，替换 DevEco 安装路径：

```powershell
$devecoRoot = 'D:\DevEcoStudio'
pwsh -File .\scripts\build.ps1 -DevEcoRoot $devecoRoot
```

脚本自动获取[固定上游源码](upstream.md)、应用补丁、构建双架构原生库、运行测试并打包校验。首次构建需要联网。产物为 `dist/RustPalm-0.1.6-universal-unsigned.hap` 和对应 SHA-256 文件。

如需代理，添加 `-Proxy $env:HTTPS_PROXY`。成功完成一次完整构建后，仅修改界面时可复用原生库：

```powershell
pwsh -File .\scripts\build.ps1 -DevEcoRoot $devecoRoot -SkipNative
```

`-SkipNative` 会检查源码、补丁与原生库哈希；核心发生变化时需要重新完整构建。

## 签名与安装

工程默认生成未签名 HAP。真机安装步骤：

1. 手机开启 USB 调试并授权开发机。
2. 用 DevEco Studio 打开 `app`，在 Project Structure → Signing Configs 中配置自己的调试证书及包含目标设备的 Profile。签名材料和口令保存在仓库外，勿提交本地签名配置。
3. 保留构建生成的 `app/entry/libs`，重新构建 signed HAP，再用 DevEco 运行或执行以下命令：

```powershell
$hdc = "$devecoRoot\sdk\default\openharmony\toolchains\hdc.exe"
& $hdc list targets
& $hdc install -r '完整路径\entry-default-signed.hap'
```

签名步骤参见[华为签名说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hmos-signing/)。

## 测试

运行输入、坐标、会话和常用连接的逻辑测试：

```powershell
& "$devecoRoot\tools\node\node.exe" --test tests/remote-geometry.test.mjs tests/session-messages.test.mjs tests/remote-mouse.test.mjs tests/remote-gesture.test.mjs tests/remote-keys.test.mjs tests/favorite-model.test.mjs
```

运行原生包校验器测试，或单独检查生成的 HAP：

```powershell
$ndk = "$devecoRoot\sdk\default\openharmony\native"
python tests/test_verify_hap.py --ndk $ndk
python scripts/verify_hap.py dist/RustPalm-0.1.6-universal-unsigned.hap --ndk $ndk
```

修改远控交互后，在真机检查连接认证、点击/右键/滚动、文字与组合键、横竖屏、后台恢复和断开锁屏；分别验证直连与中继。
