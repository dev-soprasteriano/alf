#!/bin/sh
set -eu

has_skill() {
  [ -f "$1/SKILL.md" ]
}

skill_folder_of() {
  case "$1" in
    src/skills/*/*) printf '%s\n' "$1" | cut -d/ -f1-3 ;;
    src/upstream/*/*/*) printf '%s\n' "$1" | cut -d/ -f1-4 ;;
  esac
}

list_all() {
  for d in src/skills/*/ src/upstream/*/*/; do
    d=${d%/}
    if has_skill "$d"; then
      echo "$d"
    fi
  done
}

scan_all_changed() {
  while IFS= read -r p; do
    case "$p" in
      .skillspector-baseline.yaml | tools/skillspector/requirements.txt) return 0 ;;
    esac
  done
  return 1
}

wrappers_linking() {
  for w in src/skills/*/; do
    w=${w%/}
    if grep -qF "../../${1#src/}/" "$w/SKILL.md" 2>/dev/null; then
      echo "$w"
    fi
  done
}

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

targets_for() {
  if printf '%s\n' "$1" | scan_all_changed; then
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
      targets_for "$(git diff --cached --no-renames --name-only)"
      ;;
    *)
      targets_for "$(cat)"
      ;;
  esac
}

main "$@"
