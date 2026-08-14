# PoC deployment and operation

## Provisioning gates

1. Create a Supabase project in Tokyo (`ap-northeast-1`) and run `scripts/deploy-supabase.sh`.
2. Create two GitHub App installations for the private repository. The Edge app may create/read Issues and metadata only. The dispatcher app may read Issues, write labels/comments, push branches, and create draft PRs; neither app gets merge, administration, Actions-write, environments, or deployment permission.
3. Set Edge secrets from `supabase/.env.example`; distribute only the publishable key to the JavaFX app.
4. Run `scripts/configure-github.sh` as a repository administrator. Verify branch protection in the GitHub UI, including required `verify` CI and one human approval.
5. Install the systemd unit/timer as the unprivileged `improvement-dispatcher` user. Keep its repository and scratch directory private.
6. Schedule one authenticated daily invocation of `purge-expired-artifacts` with Supabase Cron. Store `DISPATCHER_TOKEN` in Vault/Edge secrets, not in the SQL migration.

## Acceptance checks

- An unauthenticated Storage GET and all anon DB table reads return 401/403 or no rows.
- Repeating one `idempotencyKey` returns the same report and Issue.
- Break one upload and retry; finalization remains blocked until every declared hash matches.
- Inspect the generated Issue/PR for raw paths, signed URLs, and secrets before applying `agent-ready`.
- Run one `agent:codex` and one `agent:claude` Issue. Confirm neither child process environment contains GitHub/Supabase credentials.
- Confirm a failing CI and a PR with zero approvals cannot merge.
- Invoke `purge-expired-artifacts` against an intentionally expired fixture and confirm only raw files disappear and `raw_artifacts_purged` is appended.
- On an Ubuntu Wayland session, run the interactive app and inspect one normal-DPI and one scaled-display preview; X11/HiDPI are already covered by the headless smoke path.

## Recovery

Failed/timeout runs receive `agent-failed`; fix the cause and re-apply `agent-ready`. `needs-info` requires a human clarification. Worktrees are always removed in a `finally` block; `git worktree prune` is also run. Query `reports`, `agent_runs`, and `report_events` by `reportId` for the complete audit chain.
