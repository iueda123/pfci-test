# Fixture pilot — 2026-08-11

The first five safe trials used synthetic reports, a disposable local Git repository, fake agent adapters, and a fake draft-PR gateway. This validates orchestration without sending data or consuming model/API credentials.

| Trial | Agent route | Result | Human interventions | Cost |
| --- | --- | --- | ---: | ---: |
| 1 | Codex | draft PR fixture opened | 0 | 0 |
| 2 | Claude | draft PR fixture opened | 0 | 0 |
| 3 | Codex | draft PR fixture opened | 0 | 0 |
| 4 | Claude | draft PR fixture opened | 0 | 0 |
| 5 | Codex | draft PR fixture opened | 0 | 0 |

Automated assertions covered exclusive claim behavior at the SQL/schema level, credential removal, disposable worktree cleanup, external test/build gates, secret detection, branch push to a local bare remote, and the draft-PR transition. Codex CLI 0.145.0 and Claude Code 2.1.227 were present; live model execution was deliberately not used without explicit credentials/cost authorization.

Decision: retain the architecture and proceed to a live five-report pilot only after a private GitHub repository, Tokyo Supabase project, two scoped GitHub Apps, retention approval, and branch protection are configured. Do not advance to 20 reports until the live five are reviewed. No leakage or review-bypass occurred in the synthetic pilot.
