#!/usr/bin/env bash
# setup-github
#
# Applies trunk-based GitHub settings to the repository in the current directory.
#
# Usage: setup-github.sh [--discover-checks] [--dry-run] [--check NAME]...
#   --discover-checks  print the check names reported on the default branch, then exit
#   --dry-run          print what would change, then exit without changing anything
#   --check NAME       require the CI check NAME to pass before merge (repeatable)
set -euo pipefail

RULESET_NAME="trunk-based"
dry_run=false
discover=false
checks=()

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=true ;;
    --discover-checks) discover=true ;;
    --check)
      [ $# -ge 2 ] || { echo "error: --check needs a name" >&2; exit 2; }
      checks+=("$2")
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: setup-github.sh [--discover-checks] [--dry-run] [--check NAME]...
  --discover-checks  print the check names reported on the default branch, then exit
  --dry-run          print what would change, then exit without changing anything
  --check NAME       require the CI check NAME to pass before merge (repeatable)
EOF
      exit 0
      ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

for tool in gh jq; do
  command -v "$tool" >/dev/null || { echo "error: $tool is not installed" >&2; exit 1; }
done

# Test the active account directly. `gh auth status` exits non-zero when any
# stored account is broken, even if the active one works.
viewer=$(gh api user --jq .login 2>/dev/null) \
  || { echo "error: gh has no working login (run: gh auth login)" >&2; exit 1; }

repo_info=$(gh repo view --json nameWithOwner,defaultBranchRef,viewerPermission \
  --jq '[.nameWithOwner, .defaultBranchRef.name, .viewerPermission] | @tsv') \
  || { echo "error: not inside a GitHub repository" >&2; exit 1; }
IFS=$'\t' read -r repo branch perm <<<"$repo_info"

if [ "$discover" = true ]; then
  sha=$(gh api "repos/$repo/branches/$branch" --jq '.commit.sha')
  names=$(gh api --paginate "repos/$repo/commits/$sha/check-runs" --jq '.check_runs[].name' | sort -u)
  if [ -z "$names" ]; then
    echo "no check runs reported on $branch yet"
  else
    printf '%s\n' "$names"
  fi
  exit 0
fi

if [ "$perm" != "ADMIN" ]; then
  echo "error: you need admin rights on $repo (you have $perm)" >&2
  exit 1
fi

# The approval rule needs an approver other than the last pusher. Count direct
# collaborators with write access, leaving out the person running the script.
# Team members with write access are not counted.
writers=$(gh api --paginate "repos/$repo/collaborators" \
  --jq '.[] | select(.permissions.push or .permissions.maintain or .permissions.admin) | .login') \
  || { echo "error: could not list collaborators on $repo" >&2; exit 1; }
approvers=$(printf '%s\n' "$writers" | grep -v -x -e "$viewer" -e '' || true)
if [ -z "$approvers" ]; then
  approver_status="warning: no other collaborator with write access can approve. No pull request can merge until one is added."
else
  approver_names=$(printf '%s\n' "$approvers" | paste -sd, -)
  approver_status="1 approval from someone other than the last pusher. Other writers: $approver_names"
fi

# Repository settings: squash only, PR title as the squash title, blank body,
# head branches deleted on merge. Everything else is left as it is.
settings=$(jq -n '{
  allow_squash_merge: true,
  allow_merge_commit: false,
  allow_rebase_merge: false,
  delete_branch_on_merge: true,
  squash_merge_commit_title: "PR_TITLE",
  squash_merge_commit_message: "BLANK"
}')

# Ruleset on the default branch: changes go through a pull request, one approval
# from someone other than the last pusher, squash only.
rules=$(jq -n '[{
  type: "pull_request",
  parameters: {
    allowed_merge_methods: ["squash"],
    dismiss_stale_reviews_on_push: false,
    require_code_owner_review: false,
    require_last_push_approval: true,
    required_approving_review_count: 1,
    required_review_thread_resolution: false
  }
}]')

# CI gate and up-to-date rule. "Up to date" only takes effect with at least one
# required check, so the rule is added only when check names are given.
if [ ${#checks[@]} -gt 0 ]; then
  contexts=$(printf '%s\n' "${checks[@]}" | jq -Rn '[inputs | {context: .}]')
  rules=$(jq --argjson contexts "$contexts" '. + [{
    type: "required_status_checks",
    parameters: {
      strict_required_status_checks_policy: true,
      required_status_checks: $contexts
    }
  }]' <<<"$rules")
  up_to_date="enforced"
else
  up_to_date="skipped (no CI checks given)"
fi

ruleset=$(jq -n --arg name "$RULESET_NAME" --argjson rules "$rules" '{
  name: $name,
  target: "branch",
  enforcement: "active",
  conditions: {ref_name: {include: ["~DEFAULT_BRANCH"], exclude: []}},
  bypass_actors: [],
  rules: $rules
}')

existing_id=$(gh api "repos/$repo/rulesets" \
  --jq ".[] | select(.name == \"$RULESET_NAME\") | .id" | sed -n '1p')

echo "Approval: $approver_status"

if [ "$dry_run" = true ]; then
  echo "Repository: $repo (default branch: $branch)"
  echo
  echo "Repository settings (PATCH):"
  jq . <<<"$settings"
  echo
  if [ -n "$existing_id" ]; then
    echo "Ruleset '$RULESET_NAME': update existing id $existing_id"
  else
    echo "Ruleset '$RULESET_NAME': create"
  fi
  jq . <<<"$ruleset"
  echo
  echo "Up-to-date rule: $up_to_date"
  exit 0
fi

gh api -X PATCH "repos/$repo" --input - <<<"$settings" >/dev/null
echo "Repository settings updated."

if [ -n "$existing_id" ]; then
  gh api -X PUT "repos/$repo/rulesets/$existing_id" --input - <<<"$ruleset" >/dev/null
  echo "Ruleset '$RULESET_NAME' updated (id $existing_id)."
  ruleset_id="$existing_id"
else
  ruleset_id=$(gh api -X POST "repos/$repo/rulesets" --input - <<<"$ruleset" --jq '.id')
  echo "Ruleset '$RULESET_NAME' created (id $ruleset_id)."
fi

# Read back and compare, so a silently ignored field shows up as an error.
want=$(jq -S . <<<"$settings")
got=$(gh api "repos/$repo" --jq '{
  allow_squash_merge, allow_merge_commit, allow_rebase_merge,
  delete_branch_on_merge, squash_merge_commit_title, squash_merge_commit_message
}' | jq -S .)
if [ "$want" != "$got" ]; then
  echo "error: repository settings differ from what was requested" >&2
  diff <(echo "$want") <(echo "$got") >&2 || true
  exit 1
fi
echo "Verified: repository settings match."

# Read back the ruleset: approval rule, merge method, bypass list, and checks.
got_ruleset=$(gh api "repos/$repo/rulesets/$ruleset_id")
ruleset_ok=$(jq -r '
  ([.rules[] | select(.type == "pull_request") | .parameters] | .[0]) as $pr
  | ($pr.required_approving_review_count == 1)
    and ($pr.require_last_push_approval == true)
    and ($pr.allowed_merge_methods == ["squash"])
    and (((.bypass_actors // []) | length) == 0)
  ' <<<"$got_ruleset")
if [ "$ruleset_ok" != "true" ]; then
  echo "error: ruleset approval, merge method or bypass settings differ from what was requested" >&2
  exit 1
fi
if [ ${#checks[@]} -gt 0 ]; then
  want_checks=$(printf '%s\n' "${checks[@]}" | jq -R . | jq -s -c 'sort')
  checks_ok=$(jq -r --argjson want "$want_checks" '
    ([.rules[] | select(.type == "required_status_checks") | .parameters] | .[0]) as $sc
    | ($sc.strict_required_status_checks_policy == true)
      and ([$sc.required_status_checks[].context] | sort == $want)
    ' <<<"$got_ruleset")
  if [ "$checks_ok" != "true" ]; then
    echo "error: required checks differ from what was requested" >&2
    exit 1
  fi
fi
echo "Verified: ruleset approval, merge method and bypass settings match."
enforcement=$(jq -r '.enforcement' <<<"$got_ruleset")
rule_types=$(jq -r '[.rules[].type] | join(", ")' <<<"$got_ruleset")
echo "Verified: ruleset enforcement=$enforcement, rules=$rule_types"
echo "Up-to-date rule: $up_to_date"
echo "Done for $repo."
