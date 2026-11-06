# RustPalm 的 Windows 开发环境

本项目使用 Windows x64 宿主工具链交叉编译 HarmonyOS 原生库，再用 DevEco SDK 打包。已验证 ARM64 手机与 x86_64 模拟器双架构构建，版本 0.1.6 的真机验证范围见[开发与验证说明](development.md)。

## 已验证工具链

以下为开发验证所用版本，不代表其他版本已经通过兼容性测试。SDK、源码和编译缓存需要预留足够磁盘空间；系统要求以 [DevEco 官方说明](https://developer.huawei.com/consumer/cn/deveco-studio/)为准。

| 工具 | 已验证版本或配置 |
| --- | --- |
| DevEco Studio | 26.0.0.865，配套 HarmonyOS SDK 26.0.0.105 / API 26 |
| DevEco 配套运行时 | Node.js 24.14.1、JBR / OpenJDK 25.0.2 |
| HarmonyOS 构建工具 | OHPM 26.0.0.630、Hvigor 6.26.9、Clang/LLVM 15.0.4、SDK CMake 3.28.2、Ninja 1.13.2 |
| Visual Studio | Community 2026 18.11.3，C++ 桌面工作负载、x64/x86 MSVC 和 Windows SDK |
| Rust | rustup 1.29.3、rustc / Cargo 1.99.1，宿主 `x86_64-pc-windows-msvc` |
| Git 与 Python | Git for Windows 2.55.0、Python 3.12.1 |
| 原生依赖辅助工具 | Git Bash、GNU Make 4.4.1、POSIX Perl 5.42.3，含 Text::Template 1.61 |
| vcpkg | 固定提交 `9eec002df1cd109f8f104cd966a763daf9751489`，使用项目指定的 OHOS triplet |

## 安装与配置顺序

1. 安装 [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/) 和匹配的 API 26 SDK。本文使用 `D:\DevEcoStudio` 作为示例目录，请替换为自己的安装位置。Native SDK 位于 `sdk\default\openharmony\native`，包括 Clang/LLVM、sysroot、CMake 和 `build\cmake\ohos.toolchain.cmake`。[NDK 编译说明](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/build-with-ndk-cmake/)
2. 安装 Visual Studio 的 C++ 桌面工作负载，包含 x64/x86 MSVC 工具与 Windows SDK。宿主程序和 Cargo build scripts 使用 MSVC，手机目标的链接使用 HarmonyOS NDK。[Rust Windows MSVC 要求](https://rust-lang.github.io/rustup/installation/windows-msvc.html)
3. 安装 [Rust](https://rustup.rs/) 并选择 1.99.1 工具链。ARM64 和 x86_64 的 OHOS 目标及链接参数由固定上游构建脚本分别处理；使用同一 NDK 的 Clang、llvm-ar、libclang 和 sysroot。[Rust OHOS 目标说明](https://doc.rust-lang.org/rustc/platform-support/openharmony.html)
4. 安装 Git for Windows 和 Python，确认 Git Bash 可用。构建脚本当前通过标准 Git for Windows 安装目录查找 Bash；如果使用非标准位置，需要调整相应工具路径。
5. 在用户目录下准备独立的 `.rustdesk-ohos/vcpkg`，固定到上述提交，并准备 Git Bash 相容的 Make、Perl 及所需模块。原生依赖包括 libvpx、libyuv、Opus、libsodium，即使首版未开放声音入口，也需要满足链接依赖。构建缓存按 ABI 隔离。[固定依赖脚本](https://github.com/wanghd114/rustdesk_harmonyos/blob/d53391e9b0b87a94c5ee1f8f40252acb25867395/harmonyos/client/build-ohos-deps.sh) · [固定 Rust 构建脚本](https://github.com/wanghd114/rustdesk_harmonyos/blob/d53391e9b0b87a94c5ee1f8f40252acb25867395/harmonyos/client/build-rust.sh)

首次准备固定 vcpkg 可使用：

```powershell
$vcpkgRoot = Join-Path $env:USERPROFILE '.rustdesk-ohos\vcpkg'
# 仅在该目录尚不存在时克隆；已有安装应先检查其状态。
git clone https://github.com/microsoft/vcpkg.git $vcpkgRoot
git -C $vcpkgRoot checkout 9eec002df1cd109f8f104cd966a763daf9751489
& "$vcpkgRoot\bootstrap-vcpkg.bat" -disableMetrics
```

不要把个人安装器、下载缓存或 SDK 放进源码仓库。下载的工具按发布者提供的签名和校验方式自行验证。

## 检查工具链

在 Visual Studio 的 x64 开发者 PowerShell 中执行。下列环境变量仅作用于当前终端。

```powershell
$devecoRoot = 'D:\DevEcoStudio' # 示例，请替换为自己的安装目录
$env:JAVA_HOME = "$devecoRoot\jbr"
$env:PATH = "$devecoRoot\tools\node;$devecoRoot\jbr\bin;$devecoRoot\tools\ohpm\bin;$devecoRoot\tools\hvigor\bin;$devecoRoot\sdk\default\openharmony\toolchains;$env:PATH"
git --version
Get-Command cl, link
rustup show active-toolchain
rustc -vV
cargo -V
rustup target list --installed
& "$env:USERPROFILE\.rustdesk-ohos\vcpkg\vcpkg.exe" version
ohpm --version
hvigorw --version
hdc -v
hdc list targets
```

Git Bash 中可检查辅助工具。`PERL5LIB` 需指向自己安装模块的目录；Make 必须使用与 Git Bash 相容的运行时。

```bash
export VCPKG_ROOT="$HOME/.rustdesk-ohos/vcpkg"
export PERL5LIB="$HOME/.rustdesk-ohos/perl5lib${PERL5LIB:+:$PERL5LIB}"
export MSYS2_ENV_CONV_EXCL="PERL5LIB${MSYS2_ENV_CONV_EXCL:+;$MSYS2_ENV_CONV_EXCL}"
make --version
perl -MIPC::Cmd -MText::Template -MPod::Man -e 'print "Perl OK\n"'
```

然后在项目根目录运行完整构建：

```powershell
pwsh -File .\scripts\build.ps1 -DevEcoRoot $devecoRoot
```

构建、逻辑测试、HAP 校验及仅重建界面的命令见[开发与验证说明](development.md)。首次完整构建需要联网获取固定源码及依赖，已有库不能代替新环境下的完整构建验证。

## 真机、签名与测试服务

准备 API 26 的 ARM64 HarmonyOS 手机、可传输数据的 USB 线、自己的华为开发者账号，以及获准控制的测试电脑。模拟器适合检查界面，编解码、触控、后台行为及移动网络以实机测试为准。

开启手机开发者模式和 USB 调试，在手机上授权开发机。通过 `hdc list targets` 确认设备在线，再在独立私有工作副本中使用 DevEco 的 Signing Configs 为应用配置自己的调试证书与 Profile。公开工作副本保持空签名配置。设备标识、私钥、口令、签名材料和带本地路径的签名配置保存在私有位置，不能提交到公开仓库。[hdc 文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hdc/) · [真机调试与签名](https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/app-debugging-faq-0012/)

先用官方 RustDesk 客户端验证测试服务的寻址、授权和中继路径，再给 RustPalm 配置相同的 ID 服务器、中继与服务器公钥。测试基线包括 Windows RustDesk 1.4.9、1.5.1 和 RustDesk Server OSS 1.1.16。服务地址与设备 ID 由测试者自行填写，不在仓库提供生产配置。

默认原生会话需要访问服务端 TCP 21115、21116、21117 和 UDP 21116；服务器私钥仅保留在服务端。记录测试结果时保留协议版本、直连/中继路径和脱敏失败原因，不附真实地址、设备 ID 或密码。[RustDesk OSS 安装文档](https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/install/) · [端口说明](https://rustdesk.com/docs/en/self-host/)
