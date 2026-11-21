import io
from pathlib import Path
import re
import subprocess
import sys
import tokenize
from typing import Callable
import tree_sitter_bash
from tree_sitter import Language, Parser

SHELL_DIRECTIVE = re.compile(r"^#\s*shellcheck\b")
PYTHON_DIRECTIVE = re.compile(r"^#\s*(?:noqa\b|type:\s*ignore\b|pragma:|pyright:|fmt:)")
SHELL_LANGUAGE = Language(tree_sitter_bash.language())
FULL_SCAN_TRIGGERS = ("tools/tree-sitter/requirements.txt", "scripts/check-comments.py")
UNCHECKED_SUFFIXES = frozenset({".jq"})

Checker = Callable[[bytes], list[tuple[int, str]]]


def is_allowed_shell_comment(text: str, row: int, col: int) -> bool:
    if row == 0 and col == 0 and text.startswith("#!"):
        return True
    return bool(SHELL_DIRECTIVE.match(text))


def is_allowed_python_comment(text: str, line: int, col: int) -> bool:
    if line == 1 and col == 0 and text.startswith("#!"):
        return True
    return bool(PYTHON_DIRECTIVE.match(text))


def first_error_line(node) -> int:
    stack = [node]
    while stack:
        current = stack.pop()
        if current.is_error or current.is_missing:
            return current.start_point[0] + 1
        stack.extend(reversed(current.children))
    return node.start_point[0] + 1


def check_shell_bytes(source: bytes) -> list[tuple[int, str]]:
    parser = Parser(SHELL_LANGUAGE)
    tree = parser.parse(source)
    findings: list[tuple[int, str]] = []
    if tree.root_node.has_error:
        findings.append((first_error_line(tree.root_node), "parse error: unable to parse shell file"))
    stack = [tree.root_node]
    while stack:
        node = stack.pop()
        if node.type == "comment":
            text = source[node.start_byte:node.end_byte].decode("utf-8", errors="replace")
            row, col = node.start_point
            if not is_allowed_shell_comment(text, row, col):
                findings.append((row + 1, f"disallowed comment: {text}"))
        else:
            stack.extend(reversed(node.children))
    return findings


def check_python_bytes(source: bytes) -> list[tuple[int, str]]:
    findings: list[tuple[int, str]] = []
    try:
        for tok in tokenize.tokenize(io.BytesIO(source).readline):
            if tok.type == tokenize.COMMENT:
                line, col = tok.start
                if not is_allowed_python_comment(tok.string, line, col):
                    findings.append((line, f"disallowed comment: {tok.string}"))
    except tokenize.TokenError as exc:
        line = exc.args[1][0] if len(exc.args) > 1 and isinstance(exc.args[1], tuple) else 1
        findings.append((line, f"parse error: {exc.args[0]}"))
    except (IndentationError, SyntaxError) as exc:
        findings.append((exc.lineno or 1, f"parse error: {exc.msg}"))
    return findings


def resolve_checker(path: Path, source: bytes) -> Checker | str | None:
    if path.suffix in UNCHECKED_SUFFIXES:
        return "unchecked"
    if path.suffix == ".py":
        return check_python_bytes
    if path.suffix in {".sh", ".bash"} or ".githooks" in path.parts:
        return check_shell_bytes
    first_line = source.splitlines()[:1]
    if first_line and first_line[0].startswith(b"#!"):
        if b"python" in first_line[0]:
            return check_python_bytes
        if b"sh" in first_line[0]:
            return check_shell_bytes
    return None


def run_git(args: list[str], cwd: Path) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, check=False)


def git_root(cwd: Path) -> Path | None:
    top = run_git(["rev-parse", "--show-toplevel"], cwd)
    if top.returncode != 0:
        return None
    return Path(top.stdout.decode("utf-8").strip())


def report(display: str, path: Path, source: bytes) -> tuple[int, int]:
    checker = resolve_checker(path, source)
    if checker == "unchecked":
        print(f"check-comments: skipping unchecked {path.suffix} file: {display}")
        return (0, 0)
    if checker is None:
        print(f"{display}:1: unclassified file (cannot determine language)", file=sys.stderr)
        return (0, 1)
    findings = checker(source)
    for line, message in findings:
        print(f"{display}:{line}: {message}", file=sys.stderr)
    return (1, len(findings))


def check_staged(cwd: Path) -> int:
    repo = git_root(cwd)
    if repo is None:
        print("check-comments: not inside a git repository", file=sys.stderr)
        return 2
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
    checked = 0
    failures = 0
    for rel in relpaths:
        blob = run_git(["show", f":{rel}"], repo)
        if blob.returncode != 0:
            continue
        c, f = report(rel, Path(rel), blob.stdout)
        checked += c
        failures += f
    if failures:
        print(f"check-comments: {failures} issue(s) found", file=sys.stderr)
        return 1
    print(f"check-comments: {checked} staged file(s) clean")
    return 0


def default_targets(cwd: Path) -> tuple[Path, list[Path]]:
    repo = git_root(cwd)
    if repo is not None:
        listed = run_git(
            [
                "-c",
                "core.quotePath=false",
                "ls-files",
                "--cached",
                "--others",
                "--exclude-standard",
                "--",
                "scripts/",
                ".githooks/",
            ],
            repo,
        )
        if listed.returncode == 0:
            paths = [repo / line for line in sorted(set(listed.stdout.decode("utf-8").splitlines())) if line]
            return repo, [path for path in paths if path.is_file()]
    root = Path(__file__).resolve().parent.parent
    targets: list[Path] = []
    for folder in (root / "scripts", root / ".githooks"):
        if folder.is_dir():
            targets.extend(sorted(path for path in folder.rglob("*") if path.is_file()))
    return root, targets


def main(argv: list[str]) -> int:
    if argv == ["--staged"]:
        return check_staged(Path.cwd())
    if any(arg.startswith("-") for arg in argv):
        print("usage: check-comments.py [--staged | <file>...]", file=sys.stderr)
        return 2
    if argv:
        root = git_root(Path.cwd()) or Path(__file__).resolve().parent.parent
        paths = [Path(arg) for arg in argv]
    else:
        root, paths = default_targets(Path.cwd())
    checked = 0
    failures = 0
    for path in paths:
        if not path.is_file():
            print(f"check-comments: file not found: {path}", file=sys.stderr)
            return 2
        try:
            display = str(path.resolve().relative_to(root.resolve()))
        except ValueError:
            display = str(path)
        c, f = report(display, path, path.read_bytes())
        checked += c
        failures += f
    if failures:
        print(f"check-comments: {failures} issue(s) found", file=sys.stderr)
        return 1
    print(f"check-comments: {checked} file(s) clean")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
