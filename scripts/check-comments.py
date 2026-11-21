import io
from pathlib import Path
import re
import subprocess
import sys
import tokenize
import tree_sitter_bash
from tree_sitter import Language, Parser

SHELL_DIRECTIVE = re.compile(r"^#\s*shellcheck\b")
PYTHON_DIRECTIVE = re.compile(r"^#\s*(?:noqa\b|type:\s*ignore\b|pragma:|pyright:|fmt:)")
SHELL_LANGUAGE = Language(tree_sitter_bash.language())
FULL_SCAN_TRIGGERS = ("tools/tree-sitter/requirements.txt", "scripts/check-comments.py")


def is_allowed_shell_comment(text: str, row: int, col: int) -> bool:
    if row == 0 and col == 0 and text.startswith("#!"):
        return True
    return bool(SHELL_DIRECTIVE.match(text))


def is_allowed_python_comment(text: str, line: int, col: int) -> bool:
    if line == 1 and col == 0 and text.startswith("#!"):
        return True
    return bool(PYTHON_DIRECTIVE.match(text))


def check_shell_bytes(source: bytes) -> list[tuple[int, str]]:
    parser = Parser(SHELL_LANGUAGE)
    tree = parser.parse(source)
    findings: list[tuple[int, str]] = []
    stack = [tree.root_node]
    while stack:
        node = stack.pop()
        if node.type == "comment":
            text = source[node.start_byte:node.end_byte].decode("utf-8", errors="replace")
            row, col = node.start_point
            if not is_allowed_shell_comment(text, row, col):
                findings.append((row + 1, text))
        else:
            stack.extend(reversed(node.children))
    return findings


def check_python_bytes(source: bytes) -> list[tuple[int, str]]:
    findings: list[tuple[int, str]] = []
    for tok in tokenize.tokenize(io.BytesIO(source).readline):
        if tok.type == tokenize.COMMENT:
            line, col = tok.start
            if not is_allowed_python_comment(tok.string, line, col):
                findings.append((line, tok.string))
    return findings


def file_kind(path: Path, source: bytes) -> str | None:
    if path.suffix == ".py":
        return "python"
    if path.suffix in {".sh", ".bash"} or path.parent.name == ".githooks":
        return "shell"
    first_line = source.splitlines()[:1]
    if first_line and first_line[0].startswith(b"#!"):
        if b"python" in first_line[0]:
            return "python"
        if b"sh" in first_line[0]:
            return "shell"
    return None


def default_targets(root: Path) -> list[Path]:
    targets: list[Path] = []
    for folder in (root / "scripts", root / ".githooks"):
        if not folder.is_dir():
            continue
        for path in sorted(folder.iterdir()):
            if path.is_file():
                targets.append(path)
    return targets


def run_git(args: list[str], cwd: Path) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, check=False)


def check_staged(cwd: Path) -> int:
    top = run_git(["rev-parse", "--show-toplevel"], cwd)
    if top.returncode != 0:
        print("check-comments: not inside a git repository", file=sys.stderr)
        return 2
    repo = Path(top.stdout.decode("utf-8").strip())
    trigger = run_git(["diff", "--cached", "--quiet", "--", *FULL_SCAN_TRIGGERS], repo)
    if trigger.returncode != 0:
        listed = run_git(["-c", "core.quotePath=false", "ls-files", "--", "scripts/", ".githooks/"], repo)
    else:
        listed = run_git(
            [
                "-c",
                "core.quotePath=false",
                "diff",
                "--cached",
                "--no-renames",
                "--name-only",
                "--diff-filter=d",
                "--",
                "scripts/",
                ".githooks/",
            ],
            repo,
        )
    if listed.returncode != 0:
        print(listed.stderr.decode("utf-8", errors="replace"), file=sys.stderr)
        return 2
    relpaths = [line for line in listed.stdout.decode("utf-8").splitlines() if line]
    if not relpaths:
        print("check-comments: no staged script changed. Nothing to check.")
        return 0
    failures = 0
    checked = 0
    for rel in relpaths:
        blob = run_git(["show", f":{rel}"], repo)
        if blob.returncode != 0:
            continue
        source = blob.stdout
        kind = file_kind(Path(rel), source)
        if kind is None:
            continue
        checked += 1
        findings = check_python_bytes(source) if kind == "python" else check_shell_bytes(source)
        for line, text in findings:
            print(f"{rel}:{line}: disallowed comment: {text}", file=sys.stderr)
            failures += 1
    if failures:
        print(f"check-comments: {failures} disallowed comment(s) found", file=sys.stderr)
        return 1
    print(f"check-comments: {checked} staged file(s) clean")
    return 0


def main(argv: list[str]) -> int:
    if argv == ["--staged"]:
        return check_staged(Path.cwd())
    if any(arg.startswith("-") for arg in argv):
        print("usage: check-comments.py [--staged | <file>...]", file=sys.stderr)
        return 2
    root = Path(__file__).resolve().parent.parent
    paths = [Path(arg) for arg in argv] if argv else default_targets(root)
    failures = 0
    checked = 0
    for path in paths:
        if not path.is_file():
            print(f"check-comments: file not found: {path}", file=sys.stderr)
            return 2
        source = path.read_bytes()
        kind = file_kind(path, source)
        if kind is None:
            continue
        checked += 1
        findings = check_python_bytes(source) if kind == "python" else check_shell_bytes(source)
        for line, text in findings:
            try:
                display = path.resolve().relative_to(root)
            except ValueError:
                display = path
            print(f"{display}:{line}: disallowed comment: {text}", file=sys.stderr)
            failures += 1
    if failures:
        print(f"check-comments: {failures} disallowed comment(s) found", file=sys.stderr)
        return 1
    print(f"check-comments: {checked} file(s) clean")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
