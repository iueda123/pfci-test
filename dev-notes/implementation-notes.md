# Implementation Notes

`dev-notes/plan.md`に明記されていなかった判断、変更、妥協点を時系列で記録する。

## 2026-08-11

### I-001: 実行toolchainをworkspace外へ展開

- 環境の既定JDKは21.0.9、Gradleは8.7で、計画のversionと一致しなかった。
- Amazon Corretto JDK 25.0.4とGradle 9.6.1を`/tmp/pci-toolchain`へ展開し、実装検証に使用する。
- system環境やuser homeは変更しない。
- 既定のGradle user homeではnative libraryをloadできなかったため、`GRADLE_USER_HOME=/tmp/pci-gradle-home`を使用する。

### I-002: workspaceの`.git`をrepositoryとして利用できない

- workspace直下の`.git`は空かつread-onlyで、`git status`はrepositoryでないと判定する。
- source fileの実装は継続する。
- dispatcherのgit/worktree integration testは`/tmp`に作る使い捨てGit repositoryで行う。
- 実repositoryへのbranch push、Issue、PR作成は外部資格情報と有効なGit repositoryが用意された後にsmoke testする。

### I-003: `core` Gradle moduleを追加

- 計画書の構成は`app`と`dispatcher`だけだったが、report model、validation、redaction、manifest、hash処理を重複させないため`core` moduleを追加する。
- `app`と`dispatcher`は`core`へ依存する。
- Supabase Edge FunctionsはruntimeがDeno/TypeScriptのため、JSON Schemaを契約のsourceとしてJava側との整合をtestする。

### I-004: D-06の実装時選択

- JDK distributionはAmazon Corretto 25.0.4を使用する。
- Gradle DSLはKotlin DSLを使用する。
- これは実装を進めるための選択であり、アプリを特定vendorのJDK APIへ依存させない。

### I-005: Gradle 9.6.1ではJUnit Platform launcherを明示

- Gradle 9.6.1のtest実行はJUnit Platform launcherがruntime classpathにない場合に失敗した。
- 各Java moduleへ`testRuntimeOnly("org.junit.platform:junit-platform-launcher")`を追加した。

### I-006: Gradle configuration cacheを無効化

- OpenJFX Gradle plugin 0.1.0の`run` taskはGradle 9.6.1のconfiguration cache制約に適合せず、アプリ起動前に失敗した。
- build cacheとparallel実行は維持し、configuration cacheだけを無効化した。JavaFX起動を計画の完了条件として優先した。

### I-007: GUI自動smoke用の環境変数を追加

- CIやheadless Ubuntuで実画面captureを検証できるよう、`APP_SMOKE_TEST=true`のとき初期画面をcaptureして終了する経路を追加した。
- 通常起動のUIやreport操作には影響しない。XvfbでX11とHiDPI相当の2条件を検証するために使用する。

### I-008: D-01/D-02の実装値

- raw artifactは作成から30日でpurge対象とし、削除後はpathと`expires_at`をnullにしてappend-only eventを残す。
- redacted artifactと計測metadataは自動purge対象にせず、PoC終了時に運用者が削除する。
- 本番データ投入前に保持期間を利用者/管理者が承認する必要がある。

### I-009: dispatcher control planeを1つのEdge Functionへ集約

- 計画のread-only artifact endpointに加え、短命な専用tokenでclaimとrun状態更新も行う`dispatcher-control`を追加した。
- service-role keyをUbuntuへ配布せずに済み、Agent child processには専用tokenも継承しない。
- GitHub操作はdispatcher親processの`gh`に限定し、Agent用`ProcessRunner`とcredentialを使うcontrol process経路を分離した。

### I-010: live外部serviceの代替検証

- workspaceは有効なGit repositoryではなく、Supabase/GitHub project、App credential、課金許可も提供されていない。
- そのため外部へのproject作成、Issue/PR作成、branch protection変更、実Agentによる課金runは行わない。
- 5件pilotは使い捨てGit remoteとfake gateway/agentで実行し、live固有チェックは`dev-notes/operations.md`へ明示した。これはlive PoC完了の代替ではなく、安全に検証できる実装範囲の完了を示す。

### I-011: Agent CLIの権限制御

- Codexは`workspace-write`、Claudeは明示的allowed/disallowed toolsで起動する。共通してcredentialを除去した環境を使用する。
- Git fetch/pushと`gh`だけはdispatcher親processのcontrol経路で実行し、Agent adapterから呼べないようにした。

### I-012: Agent固有audit outputもlocalでredact

- CLIのstdoutにはreport由来文字列が含まれ得るため、そのまま永続化せずclientと同じ規則でredactし、dispatcher scratchの`audit/<runId>.jsonl`へ保存する。
- 共通結果JSONは別にparse・検証し、後続処理はそちらだけを利用する。

### I-013: secret scanの架空fixture除外

- redaction/verificationのfalse-negative testには明示的な架空tokenが必要なため、repository security gateは`src/test`を固定文字列scanから除外する。
- 実行時testでは逆にそれらが検出・除去されることをassertする。CI用の一般的なsecret scannerを導入する際はtest allowlistで同じfixtureだけを明示除外する。

### I-014: Supabase local統合testの環境制約

- Supabase CLI 2.113.0は取得できたが、現在の利用者はDocker socketへアクセスできず、`sudo`もpassword必須だったためlocal stackは起動できなかった。
- 代わりにDeno 2.9.5による全Edge Functionの依存解決・型検査、Node contract test、migrationの静的security contractを実行した。
- 実DBでのmigration/RLS/Storage検証はDocker権限または接続先projectが提供された時点で`dev-notes/operations.md`のacceptance checksを実行する。

### I-015: D-03 credentialとD-04 mask policy

- dispatcherは長命の専用control tokenを親processだけが保持し、artifactごとに120秒のsigned read URLを受け取る。計画の「runごとの短命credential」そのものではなく、data accessだけを短命化したPoC上の妥協である。
- `demo-main` screenには顧客名とemail Nodeを撮影禁止領域として登録した。未登録policy、空policy、scene外Nodeはcaptureを失敗させる。

### I-016: public Edge Functionの認証方式

- 利用者loginを設けない要件のためcreate/finalizeはpublishable key、rate limit、schema、size/hash検査で守る。
- dispatcher/purge/redacted取得はSupabase JWT検証を無効にし、専用Bearer tokenをfunction内で定数時間比較相当の完全一致により検査する。Supabase JWTを有効にするとこの専用tokenがgatewayで拒否されるためである。
- 一般公開はスコープ外であり、本番展開前にWAF/rate limit強化とtoken rotationを行う。

### I-017: 軽量lintをrepository内scriptで実装

- 計画は特定formatterを指定していないため、新しいformat依存を増やさず、末尾空白、shell構文、JSON schema parseを`scripts/lint.sh`で検査する。
- Javaのstyle強制はpilot後に必要性を評価する。

### I-018: root READMEと環境変数templateを追加

- 計画の構成にはなかったが、local検証とcredentialを含まない設定名を再現可能にするため`README.md`と`.env.example`を追加した。
- template値はplaceholder/local値だけで、実credentialはcommitしない。

### I-019: Wayland実機確認は未実施

- 現環境ではXvfb/X11だけが利用でき、通常DPIと`GDK_SCALE=2`のcaptureは成功した。
- Wayland compositor上の手動preview/cancel確認は実機sessionが必要なため、外部live acceptanceとして未完了のまま明示する。
