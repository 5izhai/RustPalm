# RustPalm HarmonyOS 工程

在 DevEco Studio 中打开此目录。应用标识为 `com.rustpalm.client`，当前版本为 0.1.6，使用 API 26 SDK，包含 ARM64 手机与 x86_64 本地模拟器原生库。

完整构建从工作区的 `scripts/build.ps1` 运行。脚本先构建 RustDesk 核心，分别复制到 `entry/libs/arm64-v8a` 和 `entry/libs/x86_64`，然后调用 OHPM 和 Hvigor，最后校验 HAP 的核心库、权限、ABI 与接口。

原生库由本地构建生成，不包含在公开源码仓库中。首次安装前，按[开发与验证说明](../docs/development.md)在独立的私有工作副本中配置自己的调试签名；公开工程保持空签名配置。签名私钥、证书口令、设备标识和本地配置不随源码发布。

此工程基于固定 RustDesk 鸿蒙移植源码，并以 AGPL-3.0 分发。上游来源、修改范围与依赖见[源码与许可记录](../docs/upstream.md)。
