# Windows 开发环境

使用 Windows x64 交叉编译 HarmonyOS 原生库，再由 DevEco SDK 打包。

## 工具链

| 工具 | 版本或要求 |
| --- | --- |
| DevEco Studio | 26.0.0.865，HarmonyOS SDK 26.0.0.105 / API 26，含 Native SDK |
| Node / Java / OHPM / Hvigor | 使用 DevEco 自带版本，由构建脚本配置 |
| Visual Studio | Community 2026 18.11.3，C++ 桌面工作负载、x64/x86 MSVC、Windows SDK |
| Rust | 1.99.1，宿主 `x86_64-pc-windows-msvc` |
| Git / Python / PowerShell | Git for Windows 2.55.0（含 Bash）、Python 3.12.1、PowerShell 7 |
| 原生依赖辅助工具 | GNU Make 4.4.1、POSIX Perl 5.42.3，含 Text::Template 1.61 |
| vcpkg | 固定提交 `9eec002df1cd109f8f104cd966a763daf9751489` |

安装 [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/) 和 [Rust](https://rustup.rs/)。构建脚本通过 Visual Studio Installer 查找 MSVC，并使用 `C:\Program Files\Git\bin\bash.exe`；Git 安装在其他位置时需调整 `scripts/build.ps1` 中的 `$bash`。

在项目根目录选择 Rust 工具链：

```powershell
rustup toolchain install 1.99.1-x86_64-pc-windows-msvc
rustup override set 1.99.1-x86_64-pc-windows-msvc
```

## 原生依赖

首次准备 vcpkg；若目录已存在，先确认其提交版本：

```powershell
$vcpkgRoot = Join-Path $env:USERPROFILE '.rustdesk-ohos\vcpkg'
git clone https://github.com/microsoft/vcpkg.git $vcpkgRoot
git -C $vcpkgRoot checkout 9eec002df1cd109f8f104cd966a763daf9751489
& "$vcpkgRoot\bootstrap-vcpkg.bat" -disableMetrics
```

原生构建脚本使用 `arm64-ohos`、`x64-ohos` triplet，构建 libvpx、libyuv、Opus、libsodium 及宿主依赖。源码版本见[上游来源](upstream.md)。

Make 和 Perl 必须与 Git Bash 的 POSIX 环境兼容。为 Perl 补齐 `IPC::Cmd`、`Text::Template`、`Pod::Man` 模块，放在 `$HOME/.rustdesk-ohos/perl5lib` 或自己的模块目录；在 Git Bash 中检查：

```bash
export PERL5LIB="$HOME/.rustdesk-ohos/perl5lib${PERL5LIB:+:$PERL5LIB}"
export MSYS2_ENV_CONV_EXCL="PERL5LIB${MSYS2_ENV_CONV_EXCL:+;$MSYS2_ENV_CONV_EXCL}"
make --version
perl -MIPC::Cmd -MText::Template -MPod::Man -e 'print "Perl OK\n"'
```

准备完成后，按[构建与开发](development.md)执行构建、签名和安装。
