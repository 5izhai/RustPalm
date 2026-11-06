# RustPalm 源码与许可记录

RustPalm 复用了 RustDesk 的鸿蒙移植，并保留上游源码、版权与许可证。根目录的 `LICENSE` 来自固定提交的 `LICENCE`，内容为 GNU Affero General Public License version 3。

| 项目 | 固定来源 |
| --- | --- |
| RustDesk 鸿蒙候选 | `wanghd114/rustdesk_harmonyos` 提交 `d53391e9b0b87a94c5ee1f8f40252acb25867395` |
| hbb_common | `rustdesk/hbb_common` 提交 `75ef5d8cd9b2e817047fb2eb4c2a1cdac7141dbf` |
| vcpkg | `microsoft/vcpkg` 提交 `9eec002df1cd109f8f104cd966a763daf9751489` |
| libvpx | 1.16.0，依赖脚本按固定 vcpkg 元数据中的 SHA-512 校验 |
| libyuv / Opus / libsodium | 由固定 vcpkg 清单构建，当前分别为 1916 / 1.6.1 / 1.0.22 |
| Rust crates | 固定源码中的 `Cargo.lock`，构建使用 `--locked` |

源码准备工具从上述官方项目/原作者仓库获取固定版本，随后应用 `patches/rustdesk-ohos.patch`。其余 Rust Git 依赖和 crate 版本均可在 `third_party/rustdesk/Cargo.lock` 中查看。[上游快照](https://github.com/wanghd114/rustdesk_harmonyos/tree/d53391e9b0b87a94c5ee1f8f40252acb25867395) · [上游许可证](https://github.com/wanghd114/rustdesk_harmonyos/blob/d53391e9b0b87a94c5ee1f8f40252acb25867395/LICENCE)

RustPalm 的主要修改为原生控制端首页及会话页、应用标识与原创图标、前后台会话生命周期、会话事件隔离、加密连接约束、临时认证、桥接与 Surface 边界处理，以及 Windows 可复现构建脚本。RustDesk C ABI 名称保留，便于核对上游接口。应用品牌为 RustPalm。

原生依赖各自的完整许可和版权文本随源码及 vcpkg 安装目录保留。默认可在用户目录下的 `.rustdesk-ohos/vcpkg/installed/<triplet>/share/<库名>/copyright` 查找，libvpx 的许可位于其下载源码目录。对外分发时需一起提供对应源码、补丁、构建说明和依赖版权文本。公开发行流程另行验收。
