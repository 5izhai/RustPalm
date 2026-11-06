"""Check the packaged controller, including libraries loaded with dlopen."""
import argparse
from dataclasses import dataclass
import json
from pathlib import Path, PurePosixPath
import re
import struct
import subprocess
import tempfile
import zipfile


ABI_TARGETS = {
    "arm64-v8a": (183, "aarch64-linux-ohos"),
    "x86_64": (62, "x86_64-linux-ohos"),
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


@dataclass
class ElfLibrary:
    needed: list[str]
    exports: set[str]
    undefined: set[str]


def inspect_library(path: Path, readelf: Path, abi: str = "arm64-v8a") -> ElfLibrary:
    require(abi in ABI_TARGETS, f"Unsupported ABI: {abi}")
    machine, _ = ABI_TARGETS[abi]
    with path.open("rb") as stream:
        header = stream.read(64)
    require(len(header) == 64 and header[:6] == b"\x7fELF\x02\x01", f"Invalid ELF64 LE: {path.name}")
    require(struct.unpack_from("<HH", header, 16) == (3, machine),
            f"Expected {abi} shared library: {path.name}")
    output = subprocess.check_output(
        [readelf, "--dynamic", "--dyn-syms", "--wide", path], text=True, encoding="utf-8"
    )
    needed = re.findall(r"\(NEEDED\).*?\[([^\]]+)\]", output)
    exports = set()
    undefined = set()
    for line in output.splitlines():
        fields = line.split()
        if len(fields) < 8 or not re.fullmatch(r"\d+:", fields[0]):
            continue
        binding, visibility, index, name = fields[4:8]
        if binding not in {"GLOBAL", "WEAK", "UNIQUE", "GNU_UNIQUE"}:
            continue
        if index == "UND":
            if binding != "WEAK":
                undefined.add(name)
        elif visibility in {"DEFAULT", "PROTECTED"}:
            exports.add(name.replace("@@", "@"))
            if "@@" in name:
                exports.add(name.split("@@", 1)[0])
    return ElfLibrary(needed, exports, undefined)


def resolve_libraries(packaged: dict[str, Path], ndk: Path, readelf: Path,
                      abi: str = "arm64-v8a") -> dict[str, ElfLibrary]:
    require(abi in ABI_TARGETS, f"Unsupported ABI: {abi}")
    _, target = ABI_TARGETS[abi]
    system_dir = ndk / "sysroot/usr/lib" / target
    libraries = {}
    pending = list(packaged)
    while pending:
        name = pending.pop()
        if name in libraries:
            continue
        require(PurePosixPath(name).name == name and "\\" not in name,
                f"Invalid shared library dependency: {name}")
        path = packaged.get(name, system_dir / name)
        require(path.is_file(), f"Unresolved {abi} shared library: {name}")
        library = inspect_library(path, readelf, abi)
        libraries[name] = library
        pending.extend(library.needed)

    # Each package library must load using its declared dependency closure.
    # In particular, RTLD_LOCAL loading of the Rust core cannot rely on an
    # unrelated package library happening to export a required symbol.
    for root in packaged:
        closure = set()
        pending = [root]
        while pending:
            name = pending.pop()
            if name in closure:
                continue
            closure.add(name)
            pending.extend(libraries[name].needed)
        available = set().union(*(libraries[name].exports for name in closure))
        for name in sorted(closure):
            missing = libraries[name].undefined - available
            require(not missing,
                    f"Unresolved {abi} strong symbols in {name} while loading {root}: {', '.join(sorted(missing))}")
    return libraries


def verify(hap: Path, ndk: Path, abi: str = "arm64-v8a") -> dict:
    require(abi in ABI_TARGETS, f"Unsupported ABI: {abi}")
    readelf = ndk / "llvm/bin/llvm-readelf.exe"
    required_symbols = {
        "ohos_init", "ohos_version", "ohos_set_callbacks", "ohos_free_string",
        "ohos_init_video", "ohos_deinit_video", "ohos_session_new",
        "ohos_session_start", "ohos_session_close", "ohos_session_login",
        "ohos_session_send2fa", "ohos_get_option", "ohos_set_option",
        "ohos_send_mouse", "ohos_input_key", "ohos_input_string",
        "ohos_session_refresh", "ohos_toggle_option", "ohos_get_toggle_option",
    }
    with zipfile.ZipFile(hap) as archive, tempfile.TemporaryDirectory(prefix="rustpalm-hap-") as work:
        metadata = json.loads(archive.read("module.json"))
        require(metadata["app"]["bundleName"] == "com.rustpalm.client", "Unexpected bundle name")
        permissions = {item["name"] for item in metadata["module"].get("requestPermissions", [])}
        require(permissions == {"ohos.permission.INTERNET", "ohos.permission.GET_NETWORK_INFO"},
                f"Unexpected permissions: {sorted(permissions)}")
        require(metadata["module"]["deviceTypes"] == ["phone"], "Unexpected device types")
        pages = json.loads(archive.read("resources/base/profile/main_pages.json"))["src"]
        require(set(pages) == {"pages/Index", "pages/RemotePage"}, f"Unexpected pages: {pages}")
        entries = [item for item in archive.namelist() if item.startswith("libs/") and item.endswith(".so")]
        groups = {}
        for entry in entries:
            parts = PurePosixPath(entry).parts
            require(len(parts) == 3 and parts[1] in ABI_TARGETS and "\\" not in entry,
                    f"Unexpected ABI or native library directory: {entry}")
            group = groups.setdefault(parts[1], {})
            require(parts[2] not in group, f"Duplicate native library entry: {entry}")
            group[parts[2]] = entry
        require(abi in groups, f"Requested ABI is missing from package: {abi}")
        reports = {}
        for group_abi, group in sorted(groups.items()):
            missing = {"libentry.so", "librustdesk.so", "libc++_shared.so"} - group.keys()
            require(not missing,
                    f"Missing {group_abi} core or bridge library: {', '.join(sorted(missing))}")
            directory = Path(work) / group_abi
            directory.mkdir()
            packaged = {name: directory / name for name in group}
            for name, entry in group.items():
                packaged[name].write_bytes(archive.read(entry))
            libraries = resolve_libraries(packaged, ndk, readelf, group_abi)
            missing = required_symbols - libraries["librustdesk.so"].exports
            require(not missing, f"Missing {group_abi} FFI symbols: {', '.join(sorted(missing))}")
            reports[group_abi] = {
                "dependencies": {name: libraries[name].needed for name in packaged},
                "checkedLibraries": len(libraries),
                "strongUndefinedSymbolsChecked": sum(len(library.undefined) for library in libraries.values()),
            }
        return {"bundle": metadata["app"]["bundleName"], "version": metadata["app"]["versionName"],
                "permissions": sorted(permissions), "abi": abi, "byAbi": reports,
                **reports[abi],
                "verification": "package and ELF checks passed; device execution pending"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("hap", type=Path)
    parser.add_argument("--ndk", type=Path, required=True)
    parser.add_argument("--abi", choices=ABI_TARGETS, default="arm64-v8a",
                        help="Required ABI. Every ABI present in the package is checked.")
    args = parser.parse_args()
    print(json.dumps(verify(args.hap, args.ndk, args.abi), ensure_ascii=False, indent=2))
