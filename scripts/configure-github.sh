#!/usr/bin/env bash
set -euo pipefail
: "${GITHUB_REPOSITORY:?owner/repository required}"
if ! [[ "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
  printf 'GITHUB_REPOSITORY は owner/repository の形で指定してください（例: octocat/Hello-World）。\n' >&2
  exit 2
fi
for spec in 'user-report:5319e7' 'triage:fbca04' 'agent-ready:0e8a16' 'agent:codex:1d76db' 'agent:claude:d4c5f9' 'agent-running:0052cc' 'needs-info:d876e3' 'agent-failed:b60205' 'pr-opened:2da44e'; do
  name="${spec%:*}"; color="${spec##*:}"
  gh label create "$name" --repo "$GITHUB_REPOSITORY" --color "$color" --force
done
repo_info="$(gh repo view "$GITHUB_REPOSITORY" --json defaultBranchRef,visibility \
  --jq '[.defaultBranchRef.name, .visibility] | @tsv')"
IFS=$'\t' read -r default_branch visibility <<<"$repo_info"
protection_payload='{
  "required_status_checks": {"strict": true, "contexts": ["verify"]},
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}'
if ! printf '%s\n' "$protection_payload" | gh api --method PUT \
  "repos/$GITHUB_REPOSITORY/branches/$default_branch/protection" \
  -H 'Accept: application/vnd.github+json' --input - --silent
then
  printf '\nlabelは作成済みですが、default branch (%s) の保護は設定できませんでした。\n' \
    "$default_branch" >&2
  printf '%s\n' \
    '次に行うこと:' \
    '  1. GitHubのrepositoryを開き、Settings → Collaborators and teamsで自分のRoleがAdminか確認する。' >&2
  if [ "$visibility" = PRIVATE ]; then
    printf '%s\n' \
      '  2. private repositoryなので、Settings → Billing and plansでbranch protection対応プランか確認する。' \
      '     GitHub Freeのまま利用する場合は、公開して問題のないrepositoryだけpublicに変更する。' >&2
  else
    printf '%s\n' '  2. Settings → Branchesでbranch protectionを変更できるか確認する。' >&2
  fi
  printf '  3. 解消後、次を再実行する: GITHUB_REPOSITORY=%q scripts/configure-github.sh\n' \
    "$GITHUB_REPOSITORY" >&2
  printf '%s\n' \
    '再実行しても失敗する場合は、直前に表示されたGitHub APIのHTTP statusとmessageを確認してください。' >&2
  exit 1
fi
printf '✓ default branch "%s" protected in %s\n' "$default_branch" "$GITHUB_REPOSITORY"
