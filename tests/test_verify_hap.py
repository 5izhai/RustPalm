"""Exercise HAP validation with real ARM64 and x86_64 OHOS ELF fixtures.

Run with Python and --ndk pointing to the DevEco native SDK directory.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile


NDK = None
PROJECT = Path(__file__).resolve().parents[1]
TARGETS = {"arm64-v8a": "aarch64-linux-ohos", "x86_64": "x86_64-linux-ohos"}
CORE_EXPORTS = (
    "ohos_init", "ohos_version", "ohos_set_callbacks", "ohos_free_string",
    "ohos_init_video", "ohos_deinit_video", "ohos_session_new",
    "ohos_session_start", "ohos_session_close", "ohos_session_login",
    "ohos_session_send2fa", "ohos_get_option", "ohos_set_option",
    "ohos_send_mouse", "ohos_input_key", "ohos_input_string",
    "ohos_session_refresh", "ohos_toggle_option", "ohos_get_toggle_option",
)


class VerifyHapTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if NDK is None:
            raise unittest.SkipTest("Run this file with --ndk to build the OHOS ELF fixtures")
        cls.temporary = tempfile.TemporaryDirectory(prefix="rustpalm-abi-tests-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.work = Path(cls.temporary.name)
        cls.fixtures = {}
        cls.strong_cores = {}
        cls.weak_cores = {}
        core_source = "\n".join(f"void {name}(void) {{}}" for name in CORE_EXPORTS)
        for abi, target in TARGETS.items():
            directory = cls.work / abi
            directory.mkdir()
            leaf = cls.build_library(directory, target, "libleaf.so", "int leaf(void) { return 7; }")
            dependency = cls.build_library(directory, target, "libdependency.so",
                                           "extern int leaf(void); int dependency(void) { return leaf(); }",
                                           ["-lleaf"])
            bridge = cls.build_library(directory, target, "libentry.so",
                                       "extern int dependency(void); int bridge(void) { return dependency(); }",
                                       ["-ldependency"])
            core = cls.build_library(directory, target, "librustdesk.so", core_source)
            cls.fixtures[abi] = {
                "libentry.so": bridge,
                "librustdesk.so": core,
                "libc++_shared.so": NDK / "llvm/lib" / target / "libc++_shared.so",
                "libdependency.so": dependency,
                "libleaf.so": leaf,
            }
            cls.strong_cores[abi] = cls.build_library(
                directory, target, "strong-core.so",
                core_source + "\nextern void absent_required_symbol(void);"
                "\nvoid probe(void) { absent_required_symbol(); }"
            )
            cls.weak_cores[abi] = cls.build_library(
                directory, target, "weak-core.so",
                core_source + "\nextern void absent_optional_symbol(void) __attribute__((weak));"
                "\nvoid probe(void) { if (absent_optional_symbol) absent_optional_symbol(); }"
            )

    @classmethod
    def build_library(cls, directory, target, name, source, libraries=()):
        code = directory / (name + ".c")
        output = directory / name
        code.write_text(source, encoding="utf-8")
        subprocess.run(
            [NDK / "llvm/bin/clang.exe", f"--target={target}", f"--sysroot={NDK / 'sysroot'}",
             "-shared", "-fPIC", code, f"-Wl,-soname,{name}", f"-L{directory}",
             *libraries, "-o", output],
            check=True, capture_output=True, text=True,
        )
        return output

    def package(self, groups):
        hap = self.work / "fixture.hap"
        metadata = {
            "app": {"bundleName": "com.rustpalm.client", "versionName": "test-fixture"},
            "module": {"deviceTypes": ["phone"], "requestPermissions": [
                {"name": "ohos.permission.INTERNET"},
                {"name": "ohos.permission.GET_NETWORK_INFO"},
            ]},
        }
        with zipfile.ZipFile(hap, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("module.json", json.dumps(metadata))
            archive.writestr("resources/base/profile/main_pages.json",
                             json.dumps({"src": ["pages/Index", "pages/RemotePage"]}))
            for abi, libraries in groups.items():
                for name, file in libraries.items():
                    archive.write(file, f"libs/{abi}/{name}")
        return hap

    def check_package(self, groups, abi=None, error=None):
        hap = self.package(groups)
        for optimization in ([], ["-O"]):
            with self.subTest(abi=abi, optimization=optimization, error=error):
                command = [sys.executable, *optimization, str(PROJECT / "scripts/verify_hap.py"),
                           str(hap), "--ndk", str(NDK)]
                if abi is not None:
                    command.extend(["--abi", abi])
                result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8")
                if error is None:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    report = json.loads(result.stdout)
                    self.assertEqual(set(report["byAbi"]), set(groups))
                    self.assertEqual(report["abi"], abi or "arm64-v8a")
                else:
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertIn(error, result.stderr)

    def test_valid_packages_and_default_abi(self):
        self.check_package({"arm64-v8a": self.fixtures["arm64-v8a"]})
        self.check_package({"x86_64": self.fixtures["x86_64"]}, "x86_64")
        self.check_package({"x86_64": self.fixtures["x86_64"]},
                           error="Requested ABI is missing from package: arm64-v8a")
        self.check_package(self.fixtures)
        self.check_package(self.fixtures, "x86_64")

    def test_each_abi_requires_complete_matching_libraries(self):
        for abi in TARGETS:
            other_abi = next(name for name in TARGETS if name != abi)
            for name in ("librustdesk.so", "libentry.so", "libc++_shared.so"):
                incomplete = dict(self.fixtures[abi])
                incomplete.pop(name)
                self.check_package({abi: incomplete, other_abi: self.fixtures[other_abi]},
                                   other_abi, f"Missing {abi} core or bridge library: {name}")
            for name in ("librustdesk.so", "libentry.so", "libc++_shared.so", "libleaf.so"):
                wrong_architecture = dict(self.fixtures[abi])
                wrong_architecture[name] = self.fixtures[other_abi][name]
                self.check_package({abi: wrong_architecture}, abi,
                                   f"Expected {abi} shared library: {name}")

    def test_dependency_closure_and_undefined_symbols(self):
        for abi in TARGETS:
            libraries = dict(self.fixtures[abi])
            libraries["librustdesk.so"] = self.weak_cores[abi]
            self.check_package({abi: libraries}, abi)
            libraries["librustdesk.so"] = self.strong_cores[abi]
            self.check_package({abi: libraries}, abi, "absent_required_symbol")
            libraries = dict(self.fixtures[abi])
            libraries.pop("libleaf.so")
            other_abi = next(name for name in TARGETS if name != abi)
            self.check_package({abi: libraries, other_abi: self.fixtures[other_abi]}, abi,
                               f"Unresolved {abi} shared library: libleaf.so")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ndk", type=Path, required=True)
    arguments, unittest_arguments = parser.parse_known_args()
    NDK = arguments.ndk.resolve()
    unittest.main(argv=[sys.argv[0], *unittest_arguments])
