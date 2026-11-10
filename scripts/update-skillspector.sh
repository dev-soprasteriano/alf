#!/bin/sh
# Moves SkillSpector to NVIDIA's latest GitHub release, and opens or updates a pull request for it.
# Dependabot cannot: SkillSpector is not on PyPI, and tools/skillspector/requirements.in pins a release wheel URL.
# Run daily by .github/workflows/update-skillspector.yml. Needs gh with a token, and Python 3.12 (see install-tools.sh).
# Usage: sh scripts/update-skillspector.sh
# Environment:
#   SKILLSPECTOR_BRANCH        branch for the update (default: tools/skillspector-update)
#   SKILLSPECTOR_LOCAL_ONLY=1  commit to the branch, but skip the push and the pull request
set -eu

cd "$(dirname "$0")/.."

REPO="NVIDIA/skillspector"
IN="tools/skillspector/requirements.in"
branch="${SKILLSPECTOR_BRANCH:-tools/skillspector-update}"

die() {
  echo "update-skillspector: $*" >&2
  exit 1
}

# Succeeds for a release tag such as v2.13.4, and nothing else. The tag goes into a URL, a file and a branch.
is_version() {
  expr "x$1" : 'xv[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' > /dev/null
}

BASELINE=".skillspector-baseline.yaml"
if [ -n "$(git status --porcelain -- tools/skillspector "$BASELINE")" ]; then
  die "tools/skillspector or $BASELINE has uncommitted changes"
fi

current="$(sed -n "s|^skillspector @ https://github.com/$REPO/releases/download/\([^/]*\)/skillspector-[^/]*\.whl\$|\1|p" "$IN")"
is_version "$current" || die "cannot read the pinned release tag from $IN"
latest="$(gh release view --repo "$REPO" --json tagName --jq .tagName)" || die "cannot read the latest release of $REPO"
is_version "$latest" || die "unexpected latest release tag of $REPO: $latest"

if [ "$latest" = "$current" ]; then
  echo "SkillSpector $current is the latest release."
  exit 0
fi
if [ "$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n 1)" != "$latest" ]; then
  echo "The latest release, $latest, is older than the pinned $current. Nothing to do."
  exit 0
fi
# A new commit on the branch would dismiss approvals and drop baseline changes pushed to it.
if git fetch --quiet --depth=1 origin "$branch" 2> /dev/null &&
  git show "FETCH_HEAD:$IN" 2> /dev/null | grep -qF "/download/$latest/"; then
  echo "$branch already pins $latest. Nothing to push."
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Both the tag and the wheel file name hold the version. Dots are escaped for sed.
old_tag="$(printf '%s' "$current" | sed 's/\./\\./g')"
old_ver="${old_tag#v}"
sed "s|/download/$old_tag/skillspector-$old_ver-|/download/$latest/skillspector-${latest#v}-|" "$IN" > "$work/requirements.in"
if cmp -s "$work/requirements.in" "$IN"; then
  die "cannot replace $current with $latest in $IN"
fi
cat "$work/requirements.in" > "$IN"
sh scripts/lock-tool.sh skillspector

# A new version makes every accepted finding active again. Carry over the ones it reports unchanged.
sh scripts/install-tools.sh skillspector
skills="$(sh scripts/changed-skills.sh --all)"
review="If the SkillSpector check fails, review its findings and accept them again as \`docs/skillspector.md\` describes. Push the baseline change to this branch."
# shellcheck disable=SC2086 # one word per skill folder, as in skillspector-ci.sh
if dropped="$(.tools/skillspector/bin/python -I scripts/skillspector-carry-baseline.py $skills)"; then
  if [ -z "$dropped" ]; then
    carry="SkillSpector $latest reports every accepted finding in \`$BASELINE\` unchanged, on unchanged text. This pull request carries them over with their reasons. $review"
  else
    carry="SkillSpector $latest reports some accepted findings in \`$BASELINE\` differently, or not at all. This pull request drops them:

$(printf '%s\n' "$dropped" | awk -F '\t' '{ printf "- `%s` in `%s`\n", $1, $2 }')

It carries the other accepted findings over with their reasons. $review"
  fi
else
  git checkout -- "$BASELINE"
  carry="Carrying the accepted findings in \`$BASELINE\` over to $latest failed, so they are all active again. $review"
fi

title="Update SkillSpector to $latest"
cat > "$work/body.md" << EOF
Moves SkillSpector from $current to $latest. [Release notes](https://github.com/$REPO/releases/tag/$latest).

$carry

A newer SkillSpector release replaces this branch. Opened by \`scripts/update-skillspector.sh\`.
EOF
{
  printf '%s\n\n' "$title"
  cat "$work/body.md"
} > "$work/commit.txt"

git checkout --quiet -B "$branch"
git add -- tools/skillspector "$BASELINE"
# The pre-commit scan fails by design while a finding needs review. CI scans the pull request.
git commit --quiet --no-verify -F "$work/commit.txt"
git checkout --quiet -
if [ "${SKILLSPECTOR_LOCAL_ONLY:-0}" = 1 ]; then
  echo "Committed to $branch. Push and pull request skipped (SKILLSPECTOR_LOCAL_ONLY=1)."
  exit 0
fi

git push --quiet --force origin "$branch"
if [ "$(gh pr list --head "$branch" --state open --json number --jq length)" -gt 0 ]; then
  gh pr edit "$branch" --title "$title" --body-file "$work/body.md"
else
  gh pr create --base main --head "$branch" --title "$title" --body-file "$work/body.md"
fi
# A push made with GITHUB_TOKEN does not start pull_request workflows, so the CI checks that
# main requires never run on this pull request. Start them here. workflow_dispatch is exempt.
gh workflow run ci.yml --ref "$branch"
