# 継続的改善プラットフォーム PoC 実装計画

## 実装進捗

- [x] 実装環境とtoolchainの確認
- [x] Phase 0: repositoryとローカル縦切り（X11/HiDPI相当smokeを含む）
- [x] Phase 1: SupabaseとGitHub Issueの実装、schema、deploy/configuration手順
- [x] Phase 2: 機密データ対策とretention実装
- [x] Phase 3: DispatcherとCodex CLI adapter、fixture draft PR縦切り
- [x] Phase 4: Claude Code adapterとCI/human gate設定
- [x] Phase 5: 5件のsynthetic pilotと次段階の判断記録
- [x] 全test、build、Edge型検査、lint、security gate、GUI smokeの最終検証
- [ ] 外部live acceptance（Tokyo Supabase/private GitHub/実Agent各1件/Wayland実機。資格情報・project・Docker権限待ち）

## 1. 目的

JavaFXアプリの利用中に、ユーザーが「スクリーンショット × コメント × 直前ログ」を送信するとprivate GitHub repositoryにIssueが作成され、Ubuntu上のCodex CLIまたはClaude Codeが修正・テスト・draft PR作成まで進める改善サイクルを構築する。

このPoCの目的はAgent間の性能比較ではない。次の一連の流れが実際に回ることを確認し、人が介入すべき箇所と仕組みで補強すべき箇所を把握する。

```text
報告 → private Storage/Database → GitHub Issue → 人によるagent-ready判定
     → local Agent → test → draft PR → CI → 人によるreview/merge
```

## 2. PoCの完了条件

以下をすべて満たした時点でPoCを完了とする。

1. Ubuntu上のJavaFXアプリから、任意のユーザー名、コメント、期待結果、スクリーンショット、直前ログを送信できる。
2. raw artifactとマスク済みartifactがSupabaseのprivate Storageへ分離保存され、Databaseから`reportId`で追跡できる。
3. private GitHub repositoryに、raw artifactやsigned URLを含まないIssueが重複なく作成される。
4. 人がIssueへ`agent-ready`を付けるまでAgentは起動しない。
5. Ubuntu dispatcherがCodex CLIとClaude Codeのいずれかを選択して、使い捨てworktree内で修正とテストを実行できる。
6. Agentへ渡るのはマスク済みartifactだけであり、GitHub/Supabase資格情報はAgent processへ渡らない。
7. dispatcherが変更を検査し、条件を満たす場合だけbranchをpushしてdraft PRを作成する。
8. PRはCIと人間のreviewを経なければmergeできず、Agentはmerge/deployできない。
9. Codex CLIとClaude Codeの両方で少なくとも1件ずつ、Issueからdraft PRまたは明示的な`needs-info`まで到達する。
10. すべての処理を`reportId`、Issue番号、agent run ID、PR番号で追跡できる。

## 3. スコープ

### 対象

- Ubuntu上で動くJavaFXデモアプリと報告UI
- JDK 25.0.4、JavaFX 25.0.4、Gradle 9.6.1 Wrapper
- Supabase Tokyo region（`ap-northeast-1`）
- Supabase Database、private Storage、Edge Functions
- private GitHub repositoryへのIssue、label、draft PR作成
- Ubuntu上の1並列dispatcher
- Codex CLIとClaude Codeの非対話実行
- ログの規則ベースマスク、画面の既知領域マスク、送信前preview
- CI、監査ログ、PoC評価値の記録

### 対象外

- 利用者向けログイン、本人確認、厳密な報告者識別
- Windows/macOS対応
- GitHub cloud agentの実行
- 複数Agentの同時実行
- Agentによる自動merge、自動deploy
- Agent間の順位付けや統計的A/B test
- OCRだけに依存した完全自動の個人情報検出
- 広く一般公開するためのabuse対策

## 4. 確定事項と未決事項

### 確定事項

| 項目 | 決定 |
| --- | --- |
| OS | Ubuntu |
| Java | JDK 25.0.4、JavaFX 25.0.4 |
| build | Gradle 9.6.1 Wrapper、Java toolchain 25 |
| 利用者認証 | なし。任意の未検証ユーザー名のみ |
| Supabase | Tokyo `ap-northeast-1` |
| GitHub | private repository |
| local Agent | Codex CLIとClaude Codeの両方 |
| Agent起動 | 人が`agent-ready` labelを付けた後 |
| artifact | rawは常に機密。Agentにはマスク済み派生物だけを渡す |
| merge | CIと人間のreviewが必須 |

### 実装着手前または該当Phase開始前に決めること

| ID | 未決事項 | 決定期限 | 暫定値 |
| --- | --- | --- | --- |
| D-01 | raw screenshot/logの保持期間と削除方法 | Phase 1開始前 | rawは30日後に自動削除 |
| D-02 | マスク済みartifactと計測metadataの保持期間 | Phase 1開始前 | 実験終了まで |
| D-03 | dispatcherがprivate artifactを取得する資格情報 | Phase 3開始前 | 専用read-only endpointとrunごとの短命credential |
| D-04 | 画面ごとの撮影禁止領域とマスク領域 | Phase 2開始前 | 対象デモ画面で明示定義 |
| D-05 | GitHub資格情報の形態 | Phase 1開始前 | Edge用とdispatcher用のGitHub Appを分離 |
| D-06 | JDK distributionとGradle DSL | Phase 0開始前 | maintained OpenJDK distribution、Kotlin DSL |
| D-07 | 目標試行件数 | Phase 5開始前 | まず5件、その後20件を再判断 |

暫定値は実装上の仮定であり、利用者の決定として扱わない。未決事項が安全性またはデータ削除に関係する場合、該当機能を本番Supabaseへdeployする前に確定する。

## 5. システム構成

```text
┌──────────────────── Ubuntu ────────────────────┐
│ JavaFX app                                     │
│  ├─ report dialog / preview                    │
│  ├─ Node.snapshot                              │
│  ├─ log ring buffer                            │
│  └─ redaction + HTTP client                    │
│                       │ HTTPS                  │
│                       ▼                        │
│                 Supabase Edge                  │
│                                                │
│ Dispatcher                                     │
│  ├─ GitHub poll / claim                        │
│  ├─ Supabase artifact fetch                    │
│  ├─ disposable git worktree                    │
│  ├─ CodexAdapter / ClaudeAdapter               │
│  ├─ verification gate                          │
│  └─ push + draft PR                            │
└────────────────────────────────────────────────┘
              │                    │
              ▼                    ▼
┌──────── Supabase Tokyo ──────┐  ┌── private GitHub repository ──┐
│ Database: metadata/state     │  │ Issue / labels / draft PR     │
│ Storage: raw/redacted files  │  │ CI / human review             │
│ Edge: validation/orchestration│  └───────────────────────────────┘
└──────────────────────────────┘
```

## 6. 想定するrepository構成

```text
.
├── settings.gradle.kts
├── build.gradle.kts
├── gradle.properties
├── gradlew
├── gradlew.bat
├── gradle/wrapper/
├── app/                         # JavaFXデモアプリとreport client
│   ├── build.gradle.kts
│   └── src/{main,test}/java/
├── dispatcher/                  # Ubuntu local agent dispatcher
│   ├── build.gradle.kts
│   └── src/{main,test}/java/
├── supabase/
│   ├── config.toml
│   ├── migrations/
│   ├── functions/create-report/
│   ├── functions/finalize-report/
│   ├── functions/get-redacted-artifacts/
│   └── functions/purge-expired-artifacts/
├── schemas/
│   ├── report-create.schema.json
│   ├── report-finalize.schema.json
│   └── agent-result.schema.json
├── scripts/
│   ├── run-dispatcher.sh
│   └── smoke-test-report.sh
├── .github/
│   ├── workflows/ci.yml
│   ├── pull_request_template.md
│   └── ISSUE_TEMPLATE/
├── AGENTS.md
├── CLAUDE.md
└── dev-notes/
    ├── research.md
    └── plan.md
```

JavaFXアプリとdispatcherは同じGradle multi-project buildに置く。Edge FunctionsだけはSupabaseのDeno/TypeScript runtimeに合わせる。

## 7. データ設計

### 7.1 Database

`reports`を処理全体のsource of truthとする。

```text
reports
  id uuid primary key
  created_at timestamptz not null
  updated_at timestamptz not null
  status report_status not null
  reporter_name text null
  category text not null
  comment text not null
  expected text null
  app_version text not null
  build_sha text null
  environment jsonb not null
  raw_screenshot_path text null
  raw_log_path text null
  redacted_screenshot_path text null
  redacted_log_path text null
  redaction_status text not null
  redaction_version text not null
  consented_at timestamptz not null
  github_issue_number bigint null unique
  github_issue_url text null
  expires_at timestamptz null
```

Agent実行は`agent_runs`へ分離する。

```text
agent_runs
  id uuid primary key
  report_id uuid references reports(id)
  github_issue_number bigint not null
  agent text not null             -- codex | claude
  status agent_run_status not null
  claimed_at timestamptz not null
  started_at timestamptz null
  finished_at timestamptz null
  branch_name text null
  github_pr_number bigint null
  result_summary jsonb null
  intervention_count integer not null default 0
  failure_code text null
```

`report_events`へ状態遷移をappend-onlyで記録する。

```text
report_events
  id bigint generated always as identity primary key
  report_id uuid not null
  agent_run_id uuid null
  occurred_at timestamptz not null
  event_type text not null
  actor text not null
  details jsonb not null
```

### 7.2 状態遷移

```text
uploading
  ├─ submitted → issue_created → agent_ready → agent_running → pr_opened → completed
  │                                               ├─ needs_info
  │                                               └─ agent_failed
  ├─ rejected
  └─ upload_failed
```

- すべての遷移をserver/dispatcher側で検証する。
- 同じ`reportId`の`github_issue_number`は1つだけ許可する。
- `agent_running`のrunは1件だけ許可する部分unique constraintまたはtransactional claimを設ける。
- GitHub labelは表示・操作用、Database stateは排他と監査用とする。

### 7.3 Storage

bucket名は`user-reports`とし、privateにする。

```text
reports/<reportId>/raw/screenshot.png
reports/<reportId>/raw/logs.jsonl
reports/<reportId>/redacted/screenshot.png
reports/<reportId>/redacted/logs.jsonl
reports/<reportId>/manifest.json
```

`manifest.json`には各fileのMIME type、byte数、SHA-256、redaction versionを記録する。dispatcherはhashを検証してからAgent用read-only directoryへ展開する。

## 8. API設計

### 8.1 `POST /functions/v1/create-report`

役割:

- requestのschema、文字数、category、rate limitを検証
- `reportId`と`reports` rowを作成
- upload対象ごとの短命なsigned upload tokenを発行
- 再送時はidempotency keyから既存reportを返す

主な入力:

```json
{
  "idempotencyKey": "uuid",
  "reporterName": "optional",
  "category": "bug",
  "comment": "...",
  "expected": "...",
  "consentedAt": "RFC3339",
  "app": {"version": "...", "buildSha": "..."},
  "environment": {"os": "...", "jdk": "...", "javafx": "...", "screenId": "..."},
  "artifacts": [{"kind": "rawScreenshot", "contentType": "image/png", "bytes": 1234}]
}
```

主な出力:

```json
{
  "reportId": "uuid",
  "status": "uploading",
  "uploads": [{"kind": "rawScreenshot", "path": "...", "token": "..."}],
  "expiresAt": "RFC3339"
}
```

### 8.2 `POST /functions/v1/finalize-report`

役割:

- upload済みobjectの存在、path、MIME type、byte数、hashを確認
- redaction結果が`approved`であることを確認
- metadataとマスク済み要約だけでGitHub Issueを作成
- Issue番号とURLをDatabaseへ保存
- 同じreportの再実行では既存Issueを返す

redactionが未完了または検証不能なら`409 redaction_review_required`とし、Issue作成とAgent起動を止める。

### 8.3 dispatcher用artifact取得

dispatcherは利用者向けendpointを使わず、専用のread-only routeまたはStorage APIで`redacted/`配下だけを取得する。raw pathの取得権限は通常runから分離する。

## 9. マスク処理

### 9.1 スクリーンショット

1. `Node.snapshot`でアプリscene rootだけを撮影する。
2. 画面ごとの`ScreenMaskPolicy`が、機密Nodeまたは矩形領域を黒塗りする。
3. ユーザーがpreviewで追加の黒塗り領域を指定できるようにする。
4. raw画像とredacted画像を別byte列として生成する。
5. mask policyが未登録の画面、座標変換失敗、画像生成失敗は`review_required`とする。

PoCではOCRを必須にしない。後から追加する場合も検出補助として扱い、OCRが「何も検出しなかった」ことを安全判定に使わない。

### 9.2 ログ

`LogRedactor`をclientとserverの2段階で適用する。

- Authorization/Cookie header
- access token、API key、JWTらしい文字列
- password、secret、connection string
- email address
- session ID
- ユーザー固有のabsolute path
- CR/LFやdelimiterによるlog injection

置換形式は`[REDACTED:<TYPE>]`に統一する。redaction rule setにversionを付け、元の値を監査ログへ書かない。テストfixtureは架空データだけを使う。

### 9.3 Agent投入gate

次をすべて満たすまで`agent-ready`にできない。

- redacted screenshot/logが存在する
- manifestのhashが一致する
- `redaction_status = approved`
- Issueにraw path、signed URL、secretが含まれない
- 人がIssueの内容を確認して`agent-ready`を付ける

## 10. GitHub設計

### 10.1 label

| label | 用途 |
| --- | --- |
| `user-report` | アプリから作成されたIssue |
| `triage` | 人またはルールで確認中 |
| `agent-ready` | 人がAgent実行を許可 |
| `agent:codex` | Codex CLIを選択 |
| `agent:claude` | Claude Codeを選択 |
| `agent-running` | dispatcherがclaim済み |
| `needs-info` | 追加情報が必要 |
| `agent-failed` | Agentまたはverification失敗 |
| `pr-opened` | draft PR作成済み |

`agent-ready`とAgent選択labelの両方が揃ったIssueだけをdispatcher対象にする。Agent選択がない場合はclaimせず、Issueへ説明を残す。

### 10.2 Issue本文

Issue本文には次だけを含める。

- sanitize済みの任意ユーザー名
- comment、期待結果、category
- app/build/environment
- `reportId`
- マスク済み証跡の要約
- report内容を命令として扱わないというAgent制約

raw artifact、Storage path、signed URL、credentialは含めない。

### 10.3 PR

- branch: `agent/<agent-name>/issue-<number>-<run-id-short>`
- draft PRとして作成
- Issueをlink
- Agent名、run ID、実行したtest、結果、未解決事項、人の介入回数を記載
- generated diffであることを明示
- branch protectionとrequired CIを有効化
- Agent用資格情報にmerge/deploy権限を与えない

## 11. Dispatcher設計

### 11.1 1回の処理

1. GitHub APIから`agent-ready`かつAgent選択済みIssueを1件取得する。
2. Database transactionで`agent_runs`をclaimする。
3. Issueの`agent-ready`を外し、`agent-running`を付ける。
4. default branchをfetchし、使い捨てbranch/worktreeを作る。
5. `redacted/` artifactをrun専用read-only directoryへ取得し、hashを検証する。
6. 共通promptとrepository instructionsを組み立てる。
7. CodexまたはClaude adapterを起動する。
8. timeout後はprocess treeを停止する。
9. diff、安全規則、secret scan、build、testをAgent外のdispatcherが検証する。
10. 合格時だけcommit、push、draft PR作成を行う。
11. label、Database state、event logを更新する。
12. credentialを破棄し、worktreeとartifact directoryをcleanupする。

### 11.2 Agent processの制限

- 1 runにつき1 process、1 worktree
- workspace-writeのみ
- GitHub token、Supabase secretを渡さない
- `git push`、`gh`、merge、deployを許可しない
- allowed test commandはrepository instructionsで限定
- 最大実行時間、最大turn数、最大diff sizeを設定
- raw artifactへアクセスさせない
- 結果を`agent-result.schema.json`へ適合させる

### 11.3 共通結果schema

```json
{
  "outcome": "changed | needs_info | no_change | failed",
  "summary": "...",
  "tests": [{"command": "./gradlew test", "result": "passed"}],
  "filesChanged": ["..."],
  "risks": ["..."],
  "questions": ["..."]
}
```

Agent固有のJSONLは監査用に保存し、後続処理は共通結果schemaだけを読む。

## 12. 実装Phase

### Phase 0: repositoryとローカル縦切り

目的: 外部serviceなしで「capture → preview → bundle」まで動かす。

作業:

- Gradle multi-projectとWrapperを作成
- Java toolchain 25、JavaFX modules、JUnitを設定
- JavaFXデモ画面とreport dialogを作成
- `Node.snapshot`、PNG encode、固定サンプルログを実装
- report DTOとJSON schemaを作成
- preview、cancel、ローカルdirectoryへのbundle出力を実装
- UbuntuのWayland/X11、HiDPIで基本captureを手動確認

完了条件:

- `./gradlew test`が成功する
- `./gradlew :app:run`でデモアプリが起動する
- UIをblockせずPNGとJSONLを生成できる
- 送信前previewとcancelが動く

### Phase 1: SupabaseとGitHub Issueの縦切り

目的: 1件の報告をprivate Storage/Databaseへ保存し、Issueを1件作る。

作業:

- Supabase projectをTokyo regionに作成
- migration、private bucket、RLS、size/MIME制限を定義
- `create-report`と`finalize-report`を実装
- idempotency、rate limit、入力sanitizeを実装
- GitHub Appまたは承認されたPoC credentialを設定
- Issue template、labelを作成
- JavaFX HTTP clientをEdge Functionへ接続
- 失敗時のretryとIssue URL表示を実装

完了条件:

- 同じidempotency keyを再送してもreport/Issueが増えない
- clientからDatabase/Storageを直接操作できない
- private bucketのobjectを未認証で取得できない
- Issueにraw data、signed URL、secretが含まれない
- upload途中失敗とGitHub API失敗から再試行できる

### Phase 2: 機密データ対策

目的: Agentへ渡せるマスク済みartifactを安全に生成する。

作業:

- log ring bufferとJSONL serializerを実装
- client/server `LogRedactor`とrule versionを実装
- `ScreenMaskPolicy`と手動黒塗りUIを実装
- raw/redacted pathを分離
- manifestとSHA-256検証を実装
- `review_required` gateを実装
- retention cleanup functionと監査eventを実装

完了条件:

- fixtureに含めたtoken、email、session IDがredacted artifactへ残らない
- rawとredactedのStorage pathが混同されない
- mask policy未登録または失敗時にIssue/Agent処理が停止する
- previewでartifact単位に送信除外できる
- purge対象だけが削除され、削除eventが残る

### Phase 3: DispatcherとCodex CLI

目的: `agent-ready` IssueからCodexによるdraft PRまで通す。

作業:

- polling、transactional claim、label更新を実装
- worktree lifecycleとcleanupを実装
- read-only artifact取得とhash検証を実装
- `CodexAdapter`を`codex exec`で実装
- timeout、JSONL capture、result schemaを実装
- dispatcher側verificationとsecret scanを実装
- commit、push、draft PR作成を実装

完了条件:

- `agent-ready`前に実行されない
- 二重起動しても同一Issueを二重claimしない
- Agent processからGitHub/Supabase資格情報を読めない
- failure時にbranch/PRを作らず、再試行可能なstateになる
- 成功時にtest結果付きdraft PRが作成される

### Phase 4: Claude CodeとCI/human gate

目的: 同じ改善サイクルをClaude Codeでも回し、PRの安全gateを完成させる。

作業:

- `ClaudeAdapter`を`claude -p`で実装
- allowed/disallowed tools、max turns、timeoutを設定
- Codex/Claude共通promptとresult schemaを調整
- `AGENTS.md`、`CLAUDE.md`へ同等のbuild/test/禁止事項を記述
- CIにbuild、test、format/lint、secret scanを追加
- branch protectionとhuman reviewを設定

完了条件:

- Agent labelだけでCodex/Claudeを切り替えられる
- 両Agentが同じverification gateを通る
- CI失敗時はmergeできない
- Agentまたはdispatcherがmerge/deployできない
- CodexとClaudeで各1件以上のrun記録が残る

### Phase 5: Pilotと改善

目的: 実際の報告でサイクルを繰り返し、運用上の詰まりを改善する。

作業:

- まず5件のreportを処理
- 各runの時刻、介入、failure、採否、費用を記録
- 同種failureをIssue template、redaction、instructions、test、dispatcherへ反映
- 成功条件と20件pilotへ進むかをreview

完了条件:

- 機密情報漏えい0件
- 人のreviewなしのmerge 0件
- 各failureが分類され、再実行または`needs-info`で終了する
- 次段階へ進む／構成を見直す判断記録がある

## 13. テスト計画

### Unit test

- report validation、username sanitize、GitHub mention escape
- log redactionの各ruleとfalse negative fixture
- Storage path generationとpath traversal拒否
- state transitionとclaim排他
- Issue/PR Markdown生成とsecret/signed URL非混入
- Codex/Claude command builderと危険flag拒否
- agent result schema validation

### Integration test

- Supabase local環境でmigration、RLS、Edge Function、Storage
- GitHub APIはrecorded fixtureまたはtest repositoryで検証
- CLI adapterはfake executableでsuccess/timeout/malformed JSONを検証
- idempotent retry、upload欠損、hash不一致、GitHub 403/422/5xx
- dispatcher二重起動、stale claim、stale worktree recovery

### End-to-end test

1. JavaFXからfixture reportを送信する。
2. Database、raw/redacted Storage、Issueを確認する。
3. `agent-ready`とAgent labelを付ける。
4. dispatcherを起動する。
5. draft PR、CI、Database eventを確認する。
6. 人がreviewし、mergeまたは却下を記録する。

### 故障注入

- network offline、timeout、途中upload切断
- Supabase/GitHub rate limitと5xx
- Agent timeout、異常終了、schema不正
- build/test失敗
- disk不足、permission error、cleanup失敗
- credential欠落または期限切れ

## 14. セキュリティgate

deploy前に次を確認する。

- repositoryにsecret、`.env`、Supabase secret key、GitHub private keyがない
- JavaFX artifactにservice-role keyやGitHub tokenがない
- private bucketとRLSが有効
- Edge Functionのadmin操作が必要な処理だけに限定されている
- Issue/PR生成文字列がsanitizeされ、shellへ直接展開されない
- Agent process環境からGitHub/Supabase credentialが除去されている
- `danger-full-access`、Codexのsandbox bypass、Claudeのpermission bypassを使用していない
- Agentのnetwork、filesystem、command allowlistが最小
- raw artifactがAgent worktree、prompt、commit、PR、dispatcher logへ残らない
- branch protection、required CI、human reviewが有効
- retentionと削除jobが実データ投入前に確定・検証済み

## 15. 運用と可観測性

### 記録するevent

- report created/uploaded/finalized
- redaction approved/review required
- Issue created/triaged/agent ready
- run claimed/started/timed out/failed/completed
- branch pushed/PR opened
- human intervention/review/merge/reject
- raw/redacted artifact purged

### alert対象

- upload/Issue作成の連続失敗
- redaction review待ちの滞留
- `agent-running`のtimeout超過
- cleanup失敗またはdisk使用量上昇
- secret scan検出
- purge job失敗

PoCではdashboard構築を必須にせず、Database queryと構造化JSONLで確認する。必要性が判明した後に可視化する。

## 16. 実装順序と依存関係

```text
D-06 build選定
  ↓
Phase 0 local capture
  ↓
D-01/D-02 retention + D-05 GitHub credential
  ↓
Phase 1 Supabase/GitHub vertical slice
  ↓
D-04 mask policy
  ↓
Phase 2 redaction/security
  ↓
D-03 dispatcher credential
  ↓
Phase 3 Codex dispatcher
  ↓
Phase 4 Claude + CI gates
  ↓
D-07 trial count
  ↓
Phase 5 pilot/improvement
```

各Phaseは前Phaseの完了条件を満たしてから開始する。ただしSupabase migration、Java DTO、JSON schemaなどinterface設計は並行して準備できる。

## 17. 最初に着手する作業

1. Phase 0開始に必要なD-06を確定する。
2. Gradle multi-projectとWrapperを作る。
3. JavaFXデモ画面とreport DTOを作る。
4. `Node.snapshot`からpreviewまでの最小縦切りを作る。
5. fixtureだけを使ったredaction unit testを先に作る。
6. Phase 0と並行して、Phase 1のgateであるD-01、D-02、D-05を確定する。
7. Phase 0の完了条件を満たしてから、Supabase local migrationとEdge Function contract testへ進む。

実装開始時には、Phase 0の範囲を最初のIssueまたは作業単位として切り出し、完了条件をそのままacceptance criteriaとして使用する。
