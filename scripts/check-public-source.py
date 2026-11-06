"""Check Git publication candidates without printing matching secret values.

Run from the repository root. By default, inspect tracked and nonignored
untracked files in the working tree; --staged inspects the complete index.
--denylist accepts a private JSON array of strings, kept outside public source.
This is a publication guard, not a replacement for reviewing code and images.
"""
import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys


@dataclass(frozen=True, order=True)
class Finding:
    file: str
    line: int
    category: str


PRIVATE_ROOTS = {".local", "dist", "third_party", "src"}
PRIVATE_DIRECTORIES = {
    ".git", ".idea", ".hvigor", ".cxx", ".cache", "cache", "build",
    "target", "node_modules", "oh_modules", "__pycache__",
}
PRIVATE_SUFFIXES = {
    ".p12", ".p7b", ".cer", ".csr", ".pem", ".key", ".pfx", ".jks",
    ".keystore", ".hap", ".hsp", ".har", ".app", ".log", ".pyc",
}
SECRET_PATTERNS = {
    "private_key": re.compile(
        r"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----"
    ),
    "github_token": re.compile(
        r"\b(?:gh[pousr]_[A-Za-z0-9]{36,255}|github_pat_[A-Za-z0-9_]{40,255})\b"
    ),
    "aws_access_key": re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    "google_api_key": re.compile(r"\bAIza[A-Za-z0-9_-]{35}\b"),
    "slack_token": re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{20,255}\b"),
    "api_token": re.compile(r"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{32,255}\b"),
}
SIGNING_PASSWORD = re.compile(
    r"\b(?:storePassword|keyPassword)\b['\"]?\s*[:=]\s*"
    r"(?P<quote>['\"])(?P<value>(?:\\.|(?!(?P=quote))[^\\])*)(?P=quote)",
    re.IGNORECASE,
)


def is_placeholder(value: str) -> bool:
    """Allow deliberate example values, never an arbitrary comment on a line."""
    value = value.strip()
    if not value:
        return True
    if re.fullmatch(r"\$\{[^{}]+\}|<[^<>]+>|%[A-Z_][A-Z0-9_]*%", value):
        return True
    return bool(re.fullmatch(
        r"(?:TEST_ONLY|EXAMPLE|YOUR|PLACEHOLDER)(?:[_ -][A-Z0-9_ -]+)?"
        r"|CHANGE[_ -]?ME|REPLACE[_ -]?ME",
        value, re.IGNORECASE,
    ))


def scan_path(path: str) -> list[Finding]:
    normalized = PurePosixPath(path.replace("\\", "/"))
    parts = tuple(part.lower() for part in normalized.parts)
    if not parts:
        return []
    name = parts[-1]
    forbidden = (
        normalized.is_absolute()
        or ".." in parts
        or parts[0] in PRIVATE_ROOTS
        or any(part in PRIVATE_DIRECTORIES for part in parts[:-1])
        or parts[:3] == ("app", "entry", "libs")
        or normalized.suffix.lower() in PRIVATE_SUFFIXES
        or name == "local.properties"
        or (name.startswith(".env") and name not in {".env.example", ".env.sample"})
        or ("signing" in name and ".local." in name)
    )
    return [Finding(path, 1, "private_or_generated_path")] if forbidden else []


def scan_content(path: str, content: str, denylist=()) -> list[Finding]:
    findings: set[Finding] = set()

    def record(offset: int, category: str) -> None:
        findings.add(Finding(path, content.count("\n", 0, offset) + 1, category))

    for category, pattern in SECRET_PATTERNS.items():
        for match in pattern.finditer(content):
            if not is_placeholder(match.group()):
                record(match.start(), category)
    for match in SIGNING_PASSWORD.finditer(content):
        if not is_placeholder(match.group("value")):
            record(match.start(), "signing_password")
    for private_value in denylist:
        if not private_value:
            continue
        start = 0
        while (offset := content.find(private_value, start)) != -1:
            record(offset, "private_literal")
            start = offset + len(private_value)
    return sorted(findings)


def git(root: Path, *arguments: str) -> bytes:
    result = subprocess.run(
        ["git", "-C", str(root), *arguments], capture_output=True, check=False,
    )
    if result.returncode:
        # Git errors can include paths or contents supplied by local configuration.
        raise RuntimeError("git_operation_failed")
    return result.stdout


def decode_content(content: bytes) -> str:
    if content.startswith((b"\xff\xfe", b"\xfe\xff")):
        return content.decode("utf-16", errors="replace")
    return content.decode("utf-8-sig", errors="replace")


def scan_repository(root: Path, *, staged=False, denylist=()) -> tuple[int, list[Finding]]:
    arguments = ["ls-files", "--cached", "-z"]
    if not staged:
        arguments.extend(["--others", "--exclude-standard"])
    paths = sorted(set(
        path.decode("utf-8", errors="surrogateescape")
        for path in git(root, *arguments).split(b"\0") if path
    ))
    findings = []
    scanned = 0
    root = root.resolve()
    for path in paths:
        unsafe = scan_path(path)
        findings.extend(unsafe)
        if unsafe:
            # A path violation is sufficient; do not open private files or packages.
            continue
        try:
            if staged:
                content = git(root, "show", f":{path}")
            else:
                candidate = root / path
                if candidate.is_symlink() or not candidate.resolve().is_relative_to(root):
                    findings.append(Finding(path, 1, "symlink_or_external_path"))
                    continue
                if not candidate.exists():
                    # A tracked deletion will disappear from the index after staging.
                    continue
                content = candidate.read_bytes()
            scanned += 1
            findings.extend(scan_content(path, decode_content(content), denylist))
        except (OSError, RuntimeError):
            findings.append(Finding(path, 1, "unreadable_candidate"))
    return scanned, sorted(set(findings))


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true", help="inspect all Git index contents")
    parser.add_argument("--denylist", type=Path, help="private JSON array of exact strings")
    options = parser.parse_args(argv)
    try:
        denylist = []
        if options.denylist:
            try:
                denylist = json.loads(options.denylist.read_text(encoding="utf-8-sig"))
            except (OSError, UnicodeError, ValueError):
                raise ValueError("invalid_denylist") from None
            if not isinstance(denylist, list) or any(
                not isinstance(value, str) or not value for value in denylist
            ):
                raise ValueError("invalid_denylist")
        root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel").decode("utf-8").strip())
        scanned, findings = scan_repository(root, staged=options.staged, denylist=denylist)
    except (OSError, RuntimeError, UnicodeError, ValueError) as error:
        category = "invalid_denylist" if str(error) == "invalid_denylist" else "scan_setup_failed"
        print(json.dumps({"ok": False, "category": category}))
        return 2
    print(json.dumps({
        "ok": not findings,
        "mode": "staged" if options.staged else "worktree",
        "files_scanned": scanned,
        "findings": [asdict(finding) for finding in findings],
    }, ensure_ascii=True, indent=2))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
