#!/bin/sh
# Prints the skill folders to scan. Reads changed paths on stdin, one per line, repo-relative.
# With --all, prints every skill folder. Run from the repo root.
set -eu

# Succeeds when the folder $1 is a skill: it has a SKILL.md.
has_skill() {  # folder
  [ -f "$1/SKILL.md" ]
}

# Prints the folder a path belongs to: src/skills/<name>/ or src/upstream/<upstream>/<skill>/.
# Prints nothing for any other path.
skill_folder_of() {  # path
  case "$1" in
    src/skills/*/*) printf '%s\n' "$1" | cut -d/ -f1-3 ;;
    src/upstream/*/*/*) printf '%s\n' "$1" | cut -d/ -f1-4 ;;
  esac
}

# Prints every skill folder: src/skills/<name>/ and src/upstream/<upstream>/<skill>/.
list_all() {
  for d in src/skills/*/ src/upstream/*/*/; do
    d=${d%/}
    if has_skill "$d"; then
      echo "$d"
    fi
  done
}

# Succeeds when a changed path on stdin needs every skill scanned.
full_scan_needed() {
  while IFS= read -r p; do
    case "$p" in
      .skillspector-baseline.yaml|Taskfile.yml|scripts/skillspector-ci.sh|scripts/changed-skills.sh)
        return 0
        ;;
    esac
  done
  return 1
}

# Prints every wrapper under src/skills/ whose SKILL.md links into the upstream skill $1.
wrappers_linking() {  # e.g. src/upstream/mattpocock/to-spec
  for w in src/skills/*/; do
    w=${w%/}
    if grep -qF "../../${1#src/}/" "$w/SKILL.md" 2>/dev/null; then
      echo "$w"
    fi
  done
}

# Prints the skill folders to scan for the changed paths on stdin: each path's own skill folder,
# and the wrappers that link to a changed upstream skill.
folders_to_scan() {
  while IFS= read -r p; do
    f=$(skill_folder_of "$p")
    if [ -z "$f" ]; then
      continue
    fi
    if has_skill "$f"; then
      echo "$f"
    fi
    case "$f" in
      src/upstream/*) wrappers_linking "$f" ;;
    esac
  done
}

main() {
  if [ "${1:-}" = "--all" ]; then
    list_all
    return 0
  fi
  changed=$(cat)
  if printf '%s\n' "$changed" | full_scan_needed; then
    list_all
  else
    printf '%s\n' "$changed" | folders_to_scan | sort -u
  fi
}

main "$@"
