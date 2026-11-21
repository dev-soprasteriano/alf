from pathlib import Path
import re
import sys
import tokenize
import tree_sitter_bash
from tree_sitter import Language, Parser

SHELL_DIRECTIVE = re.compile(r"^#\s*shellcheck\b")
PYTHON_DIRECTIVE = re.compile(r"^#\s*(?:noqa\b|type:\s*ignore\b|pragma:|pyright:|fmt:)")
SHELL_LANGUAGE = Language(tree_sitter_bash.language())


def is_allowed_shell_comment(text: str, row: int, col: int) -> bool:
    if row == 0 and col == 0 and text.startswith("#!"):
        return True
    return bool(SHELL_DIRECTIVE.match(text))


def is_allowed_python_comment(text: str, line: int, col: int) -> bool:
    if line == 1 and col == 0 and text.startswith("#!"):
        return True
    return bool(PYTHON_DIRECTIVE.match(text))


def check_shell(path: Path) -> list[tuple[int, str]]:
    source = path.read_bytes()
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


def check_python(path: Path) -> list[tuple[int, str]]:
    findings: list[tuple[int, str]] = []
    with path.open("r", encoding="utf-8") as handle:
        for tok in tokenize.generate_tokens(handle.readline):
            if tok.type == tokenize.COMMENT:
                line, col = tok.start
                if not is_allowed_python_comment(tok.string, line, col):
                    findings.append((line, tok.string))
    return findings


def file_kind(path: Path) -> str | None:
    if path.suffix == ".py":
        return "python"
    if path.suffix in {".sh", ".bash"} or path.parent.name == ".githooks":
        return "shell"
    with path.open("rb") as handle:
        first_line = handle.readline(256)
    if first_line.startswith(b"#!"):
        if b"python" in first_line:
            return "python"
        if b"sh" in first_line:
            return "shell"
    return None


def default_targets(root: Path) -> list[Path]:
    targets: list[Path] = []
    for folder in (root / "scripts", root / ".githooks"):
        if not folder.is_dir():
            continue
        for path in sorted(folder.iterdir()):
            if path.is_file() and file_kind(path) is not None:
                targets.append(path)
    return targets


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent
    paths = [Path(arg) for arg in argv] if argv else default_targets(root)
    failures = 0
    for path in paths:
        if not path.is_file():
            print(f"check-comments: file not found: {path}", file=sys.stderr)
            return 2
        kind = file_kind(path)
        if kind is None:
            continue
        findings = check_python(path) if kind == "python" else check_shell(path)
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
    print(f"check-comments: {len(paths)} file(s) clean")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
