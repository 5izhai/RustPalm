"""Publication guard tests use synthetic values and isolated Git repositories."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "check-public-source.py"
SPEC = importlib.util.spec_from_file_location("public_source", SCRIPT)
CHECK = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CHECK
SPEC.loader.exec_module(CHECK)


def signing(value):
    return json.dumps({"store" + "Password": value})


class PublicSourceTest(unittest.TestCase):
    def test_private_paths_do_not_block_application_source_or_example_env(self):
        for path in (
            ".local/report.txt", "dist/demo.hap", "third_party/library/file.c",
            "src/upstream/file.rs", "app/.idea/workspace.xml", "app/entry/build/result",
            "app/entry/libs/arm64-v8a/native.so", "signing/client.p12",
            "app/.env.production", "app/local.properties", "cache/debug.txt",
        ):
            with self.subTest(path=path):
                self.assertTrue(CHECK.scan_path(path))
        for path in (
            "app/entry/src/main/ets/pages/Index.ets", "scripts/build.ps1",
            "docs/development.md", ".env.example", "app/.env.sample",
        ):
            with self.subTest(path=path):
                self.assertFalse(CHECK.scan_path(path))

    def test_key_and_token_reports_never_contain_values(self):
        private_header = "-----BEGIN " + "PRIVATE KEY-----"
        token = "ghp_" + "a" * 36
        cloud_key = "AKIA" + "A" * 16
        contents = "heading\n" + private_header + "\n" + token + "\n" + cloud_key
        findings = CHECK.scan_content("example.txt", contents)
        self.assertEqual(
            [(item.line, item.category) for item in findings],
            [(2, "private_key"), (3, "github_token"), (4, "aws_access_key")],
        )
        report = repr(findings)
        for value in (private_header, token, cloud_key):
            self.assertNotIn(value, report)

    def test_signing_password_placeholders_and_multiline_assignment(self):
        for value in ("", "EXAMPLE_PASSWORD", "TEST_ONLY_PASSWORD", "${SIGNING_PASSWORD}", "<password>"):
            with self.subTest(value=value):
                self.assertFalse(CHECK.scan_content("config.json5", signing(value)))
        value = "synthetic-" + "credential"
        content = signing(value).replace(": ", ":\n") + " // EXAMPLE"
        findings = CHECK.scan_content("config.json5", content)
        self.assertEqual(findings, [CHECK.Finding("config.json5", 1, "signing_password")])
        self.assertNotIn(value, repr(findings))

    def test_private_denylist_is_literal_and_redacted(self):
        private_value = "synthetic." + "example+identifier"
        content = "heading\n" + private_value + "\n" + private_value
        findings = CHECK.scan_content("notes.md", content, [private_value])
        self.assertEqual([item.line for item in findings], [2, 3])
        self.assertTrue(all(item.category == "private_literal" for item in findings))
        self.assertNotIn(private_value, repr(findings))
        self.assertFalse(CHECK.scan_content("notes.md", "syntheticXexampleidentifier", [private_value]))

    def test_staged_scan_checks_index_and_forced_ignored_files(self):
        with tempfile.TemporaryDirectory(prefix="rustpalm-public-source-") as directory:
            root = Path(directory)

            def git(*args):
                subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True)

            git("init", "--quiet")
            (root / ".gitignore").write_text(".local/\n", encoding="utf-8")
            (root / "config.json5").write_text(signing("synthetic-" + "credential"), encoding="utf-8")
            git("add", ".gitignore", "config.json5")
            (root / "config.json5").write_text(signing("${SIGNING_PASSWORD}"), encoding="utf-8")
            (root / ".local").mkdir()
            (root / ".local" / "private.txt").write_text("fixture", encoding="utf-8")
            self.assertFalse(CHECK.scan_repository(root)[1])
            self.assertEqual(CHECK.scan_repository(root, staged=True)[1], [
                CHECK.Finding("config.json5", 1, "signing_password"),
            ])
            git("add", "-f", ".local/private.txt")
            self.assertIn(
                CHECK.Finding(".local/private.txt", 1, "private_or_generated_path"),
                CHECK.scan_repository(root)[1],
            )
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--staged"], cwd=root,
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 1)
            self.assertFalse(json.loads(result.stdout)["ok"])
            self.assertNotIn("synthetic-" + "credential", result.stdout + result.stderr)

    def test_invalid_denylist_error_does_not_echo_contents(self):
        with tempfile.TemporaryDirectory(prefix="rustpalm-public-source-") as directory:
            denylist = Path(directory) / "private.json"
            value = "synthetic-" + "private-text"
            denylist.write_text(value, encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--denylist", str(denylist)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 2)
            self.assertEqual(json.loads(result.stdout)["category"], "invalid_denylist")
            self.assertNotIn(value, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
