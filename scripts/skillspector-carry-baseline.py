"""Carries accepted findings in .skillspector-baseline.yaml over to the installed SkillSpector version.

Usage, from the repo root, after installing the new version:
    .tools/skillspector/bin/python -I scripts/skillspector-carry-baseline.py <skill-dir>...

Run by scripts/update-skillspector.sh. Scans each skill folder once, static only, as
scripts/skillspector-ci.sh does. SkillSpector fingerprints a finding over the scanner version,
the complete file text and every evidence field. So each finding is fingerprinted twice: as
the baseline's scanner_version and as the installed version. When the first fingerprint is
accepted in the baseline, the installed version reports the same finding on the same text.
That entry is rewritten with the second fingerprint, and keeps its reason.

Accepted entries that no finding reproduces are dropped, and printed as "rule_id<TAB>file".
A dropped finding that the new version still reports is active again, for a reviewer.
Exits non-zero, leaving the baseline unchanged, if a scan fails or SkillSpector changed the
internals used here.
"""

import contextlib
import io
import sys

import yaml
from skillspector import __version__, cli, suppression

BASELINE = ".skillspector-baseline.yaml"


def main(skills: list[str]) -> int:
    if not skills:
        print("usage: skillspector-carry-baseline.py <skill-dir>...", file=sys.stderr)
        return 2
    with open(BASELINE, encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    old_version = data.get("scanner_version")
    accepted = data.get("fingerprints") or []
    if not isinstance(old_version, str) or not old_version.strip():
        print(f"skillspector-carry-baseline: {BASELINE} has no scanner_version", file=sys.stderr)
        return 1
    if old_version == __version__ or not accepted:
        return 0

    # Pairs of (entry as old_version, entry as installed version) for every finding.
    # One scan feeds both, so the pairs line up: the version is the only input that differs.
    pairs: list[tuple[dict, dict]] = []
    build = cli.build_baseline_dict

    def build_and_record(findings, *args, file_cache=None, **kwargs):
        as_old = build(findings, file_cache=file_cache, scanner_version=old_version)["fingerprints"]
        as_new = build(findings, file_cache=file_cache, scanner_version=__version__)["fingerprints"]
        if len(as_old) != len(as_new):
            raise RuntimeError("fingerprints do not pair up")
        pairs.extend(zip(as_old, as_new))
        return build(findings, *args, file_cache=file_cache, **kwargs)

    cli.build_baseline_dict = build_and_record
    for skill in skills:
        # The command prints a baseline for the folder on stdout. Only its findings are needed.
        with contextlib.redirect_stdout(io.StringIO()):
            code = cli.app(["baseline", skill, "--no-llm", "--output", "-"], standalone_mode=False)
        if code:
            print(f"skillspector-carry-baseline: scan failed: {skill}", file=sys.stderr)
            return 1

    renewed = {old["hash"]: new for old, new in pairs}
    carried = []
    for entry in accepted:
        new = renewed.get(entry["hash"])
        if new is None:
            print(f"{entry.get('rule_id', '')}\t{entry.get('file', '')}")
        elif all(new["hash"] != kept["hash"] for kept in carried):
            carried.append({**new, "reason": entry["reason"]})

    suppression.dump_baseline(
        {
            "version": data["version"],
            "scanner_version": __version__,
            "rules": data.get("rules") or [],
            "fingerprints": carried,
        },
        BASELINE,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
