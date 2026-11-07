#!/bin/sh
# Prints the skill folders to scan. Run from the repo root.
#   --all: every skill folder.
#   --staged: the skill folders of the staged files. Every skill folder when the staged files change the
#     baseline, or the SkillSpector pin in Taskfile.yml or scripts/skillspector-ci.sh.
#   no argument: the skill folders of the changed paths read from stdin, one per line, repo-relative.
#     Every skill folder when the baseline is among them.
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

# Succeeds when a changed path on stdin is the baseline.
baseline_changed() {
  while IFS= read -r p; do
    if [ "$p" = ".skillspector-baseline.yaml" ]; then
      return 0
    fi
  done
  return 1
}

# Prints the SkillSpector source pin in a file revision, such as HEAD:Taskfile.yml or :Taskfile.yml for the index.
pin_at() {  # revision:path
  git show "$1" 2>/dev/null | grep -o 'skillspector\.git@[^"[:space:]]*' | head -n 1 || true
}

# Succeeds when the pin in Taskfile.yml or scripts/skillspector-ci.sh differs between the index and HEAD.
pin_changed() {
  for f in Taskfile.yml scripts/skillspector-ci.sh; do
    if [ "$(pin_at ":$f")" != "$(pin_at "HEAD:$f")" ]; then
      return 0
    fi
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

# Prints the scan targets for the changed paths in $1: every skill when the baseline is among them, else their folders.
targets_for() {  # changed paths, newline-separated
  if printf '%s\n' "$1" | baseline_changed; then
    list_all
  else
    printf '%s\n' "$1" | folders_to_scan | sort -u
  fi
}

main() {
  case "${1:-}" in
    --all)
      list_all
      ;;
    --staged)
      changed=$(git diff --cached --no-renames --name-only)
      if pin_changed; then
        list_all
      else
        targets_for "$changed"
      fi
      ;;
    *)
      targets_for "$(cat)"
      ;;
  esac
}

main "$@"
