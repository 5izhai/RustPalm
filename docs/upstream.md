# 上游来源与依赖

RustPalm 基于 RustDesk 的 HarmonyOS 移植，采用 [AGPL-3.0](../LICENSE)，保留上游版权与许可声明。

| 项目 | 固定版本 |
| --- | --- |
| [RustDesk HarmonyOS 移植](https://github.com/wanghd114/rustdesk_harmonyos) | `d53391e9b0b87a94c5ee1f8f40252acb25867395` |
| [hbb_common](https://github.com/rustdesk/hbb_common) | `75ef5d8cd9b2e817047fb2eb4c2a1cdac7141dbf` |
| [vcpkg](https://github.com/microsoft/vcpkg) | `9eec002df1cd109f8f104cd966a763daf9751489` |
| 原生库 | libvpx 1.16.0、libyuv 1916、Opus 1.6.1、libsodium 1.0.22 |
| Rust 依赖 | 固定源码中的 `Cargo.lock`，构建使用 `--locked` |

`scripts/prepare-upstream.ps1` 获取固定源码并应用 `patches/rustdesk-ohos.patch`。

修改说明（2026-11-06）：重写连接与远控界面，增加触控输入、常用连接和会话生命周期管理；调整加密连接、原生桥接及 Surface 处理，并适配 Windows 构建流程。

各依赖沿用其自身许可证。分发时保留相应版权文本，并提供对应源码、补丁和构建说明。依赖版权文件位于 vcpkg 的 `installed/<triplet>/share/<库名>/copyright` 等源码目录；RustDesk 许可见[上游原文](https://github.com/wanghd114/rustdesk_harmonyos/blob/d53391e9b0b87a94c5ee1f8f40252acb25867395/LICENCE)。
