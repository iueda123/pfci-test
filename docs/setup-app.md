# 1. アプリのセットアップと起動

このリポジトリには**2つの実行可能アプリ**が入っています。役割が違うので、混同しないでください。

| module | 何か | 起動コマンド | 誰の環境で動くか |
| --- | --- | --- | --- |
| `:app` | JavaFXデスクトップアプリ（利用者が報告を作る画面） | `./gradlew :app:run` | 利用者/開発者のPC |
| `:dispatcher` | Issueを拾ってAgentを動かすbatch（1回実行して終了） | `scripts/run-dispatcher.sh` | 専用のUbuntuサーバ |
| `:core` | 両者が使う共通library（単体では起動しない） | — | — |

全体の流れ:

```
[JavaFX app] --(apikey: publishable key)--> [Supabase Edge Functions]
     |                                        create-report / finalize-report
     |                                              |
     +--> local-reports/<report-id>/                +--> Storage(private) + Postgres
          （常に書かれる。rawを含む）                +--(GitHub App短命token)--> private GitHubにIssue作成

[dispatcher] --(Bearer DISPATCHER_TOKEN)--> [dispatcher-control / get-redacted-artifacts]
     |                                       redactedのみ120秒の署名URLで取得
     +--(gh CLI)--> Issueのlabel更新 / draft PR作成
```

---

## 1.1 必要なもの

| 用途 | 必須 | version | 備考 |
| --- | --- | --- | --- |
| build/実行 | 必須 | **JDK 25** | `app`/`core`/`dispatcher`すべてがtoolchain 25を要求（`app/build.gradle.kts:5`） |
| build tool | 必須 | Gradle 9.6.1 | 同梱のWrapperが自動取得するので**インストール不要** |
| GUI | `:app:run`に必須 | X11またはWayland | headlessでも1.6の方法で動作確認は可能 |
| 初回のnetwork | 必須 | — | Gradle本体、JavaFX 25.0.4、Jacksonの取得に必要 |
| contract test | 任意 | Node 22 | `node --test supabase/tests/security-contract.mjs` |
| Supabase操作 | Part 3で必須 | Supabase CLI | [3. Supabaseの準備](setup-supabase.md) |
| dispatcher | dispatcher運用時のみ | `gh` CLI（認証済み）、`git`、Codex CLI / Claude Code | — |

迷ったら`scripts/doctor.sh`を実行してください。JDK 25の有無を含め、いま何が足りないかを判定します。

### JDK 25の確認

```bash
./gradlew -q javaToolchains
```

`Language Version: 25` の項目が1つ以上出れば準備完了です。この作業PCでは
`/home/iu/.jdks/openjdk-25.0.2`（IntelliJが配置したもの）が検出され、buildは成功しています。
`java -version`が21などでも、Gradleがtoolchainとして25を見つけられれば問題ありません。

**JDK 25が一覧に出ない場合**、buildは次のエラーで失敗します。

```
No matching toolchains found for requested specification: {languageVersion=25, ...}
```

`javaToolchains`の出力には`Auto-download: Enabled`と表示されますが、`settings.gradle.kts`に
toolchain resolver plugin（foojay-resolverなど）を入れていないため、**実際には自動ダウンロードされません**。
JDK 25は自分で用意してください。

```bash
# 例: Amazon Corretto 25 / Temurin 25 を展開して置いた場合
# 方法A: そのJDKでGradleを動かす
export JAVA_HOME=/path/to/jdk-25
./gradlew test

# 方法B: 検索対象に加える（JAVA_HOMEは21のままでよい）
echo 'org.gradle.java.installations.paths=/path/to/jdk-25' >> ~/.gradle/gradle.properties
```

`~/.gradle/gradle.properties`はリポジトリ外なので、この設定をcommitする必要はありません。

---

## 1.2 最初のbuildと検証

リポジトリのルートで実行します。初回はGradleとdependencyの取得で数分かかります。

```bash
./gradlew test build                                   # 全moduleのtestとbuild
node --test supabase/tests/security-contract.mjs       # Edge Functions/migrationの契約test
scripts/lint.sh                                        # 末尾空白・shell構文・JSON Schema
scripts/security-gate.sh                               # 固定文字列のsecret scan
```

CI（`.github/workflows/ci.yml`）もこの4つを実行します。PRを出す前にlocalで通しておくと差分が出ません。

> 補足: `gradle.properties`でconfiguration cacheを**無効**にしています。OpenJFX pluginの`run` taskが
> Gradle 9.6.1のconfiguration cache制約に適合しなかったためです（`I-006`）。有効化しないでください。

---

## 1.3 JavaFXアプリを起動する

```bash
./gradlew :app:run
```

`Continuous Improvement Demo`というwindowが開きます。**環境変数を何も設定していない状態でも起動でき、
その場合は外部送信を一切行いません**（`local-reports/`への保存のみ）。まずはこの状態で触ってください。

送信まで試したくなったら、[2. `.env.example` の使い方](setup-env.md)へ進みます。

---

## 1.4 画面の操作と、そのとき起きること

これはPoCのデモアプリです。「顧客管理画面で作業していたら不具合に気づいた利用者」を模しています。

**① メイン画面**

- `顧客名`（山田 花子）と`メール`（hanako@example.invalid）は、**撮影禁止領域として登録済み**のNodeです
  （`ScreenMaskPolicy("demo-main", ...)`、`ContinuousImprovementApp.java:82`）。
- `保存`を押すと、わざと個人情報を含むログが1行増えます
  （`Saved draft for hanako@example.invalid sessionId=abc-123`）。redactionの効果を見るために何度か押してください。

**② `気になった点を報告`を押す**

- その瞬間に画面をcaptureし、rawとredactedの2枚を作ります。
- policyに未登録の画面、空のpolicy、scene外のNodeを指定した場合、captureは**成功せずに失敗**します（`I-015`）。
  これは「マスク漏れの生画像を作らない」ための仕様です。

**③ 報告dialog**

| 項目 | 必須 | 説明 |
| --- | --- | --- |
| ユーザー名 | 任意 | 未入力なら匿名（Issue上は`anonymous`） |
| 種別 | 必須（既定BUG） | bug / usability / request / other |
| 状況 | **必須** | 空だと送信できません |
| 期待結果 | 任意 | — |
| スクリーンショットを含める | 既定ON | — |
| 直前5分のログを含める | 既定ON | ring buffer 500件から直近5分を抽出 |
| マスク済みpreview | — | **画像上をドラッグすると黒塗りを追加**できます。`追加の黒塗りを消す`で手動分だけ取り消し |
| previewを確認し、送信に同意する | **必須** | チェックしないと送信できません |

**④ `ローカルbundleを作成`**

`REPORT_OUTPUT_DIR`（既定`local-reports`）配下に、report IDごとのdirectoryが作られます。

```
local-reports/<report-id>/
├── report.json          # 報告本文とmetadata（rwx------ / rw------- で作成）
├── manifest.json        # 各artifactのkind, contentType, bytes, sha256, path, redactionStatus
├── raw/screenshot.png   # 黒塗り前
├── raw/logs.jsonl       # 黒塗り前
├── redacted/screenshot.png
└── redacted/logs.jsonl
```

**⑤ 結果表示**

| 表示 | 意味 |
| --- | --- |
| `作成しました: <path>` | localに保存のみ。`REPORT_API_URL`と`SUPABASE_PUBLISHABLE_KEY`のどちらかが未設定 |
| `送信しました: <Issue URL>` | 送信とIssue作成まで成功 |
| `失敗: <message>` | 途中で失敗。localのbundle自体は残っています |

> ⚠️ `local-reports/`には**黒塗り前のraw**が入ります。`.gitignore`済みですが、
> directoryごとメールやチャットで共有しないでください。

---

## 1.5 送信ありで起動する

環境変数の意味は[2. `.env.example` の使い方](setup-env.md)で説明します。ここでは起動形だけ示します。

```bash
export REPORT_API_URL='https://<project-ref>.supabase.co'   # Project URLのみ。/functions/v1は付けない
export SUPABASE_PUBLISHABLE_KEY='sb_publishable_...'
./gradlew :app:run
```

`.env`を作ってある場合は、shellへ読み込ませてから起動します（アプリは`.env`を自分では読みません）。

```bash
set -a; source .env; set +a
./gradlew :app:run
```

`scripts/smoke-test-report.sh`は、この2変数の存在を確認してから`:app:run`するだけのwrapperです。

---

## 1.6 画面なしで動作確認する（headless / CI）

デスクトップ環境が無いサーバやCIでも、capture経路の健全性だけは確認できます。

```bash
APP_SMOKE_TEST=true xvfb-run -a ./gradlew :app:run
```

起動直後にcaptureして即終了し、次の1行を出力します（このリポジトリでの実行例）。

```
SMOKE_CAPTURE_OK raw=24519 redacted=20633
```

raw/redactedどちらかが0 byteなら異常終了します。HiDPI相当も確認したい場合は`GDK_SCALE=2`を付けて再実行します。
Wayland実機での手動確認は未実施のまま残っています（`I-019`）。

---

## 1.7 Issue作成後、AIにdraft PRを作らせる

ここが、JavaFXアプリで`送信しました: <Issue URL>`と表示された後の統合runbookです。
dispatcherは**常駐せず**、1回起動するたびに「stale runの回収 → 承認済みIssueを最大1件処理 → 終了」し、
結果を1行のJSONで出力します。人間がIssueを承認するまでAgentは動きません。

### 手順1: dispatcherの前提を揃える

cloud routeの残りの設定を対話で進めます。

```bash
./scripts/setup.sh --all --route cloud
```

すでに全stageへ到達している場合も、このコマンドは§1.7で目視確認するdispatcher設定を表示します。
`GITHUB_REPOSITORY`、各path・endpoint・Agent CLIは実値を表示しますが、
`DISPATCHER_TOKEN`はsecretのため設定済みかどうかだけを表示します。cloudのEdge secretは値を取得できないため、
`GITHUB_REPOSITORY`について表示するのは`supabase/.env`にある登録元の値です。

全stageへ到達すると、そのままdispatcher wizardへ進むか尋ねられます。後から再開する場合は次を実行します。

```bash
scripts/dispatcher-wizard.sh
```

このwizardは接続診断、Issueの確認項目、Agent選択、dispatcher実行、outcome別の次手を順に案内します。
人間の承認gateである`agent-ready`は自動で付けません。

特に次を確認してください。変数の全一覧は[dispatcherが読む変数](setup-env.md#dispatcherが読む変数)にあります。

- `GITHUB_REPOSITORY`: Issueが作られた`owner/repository`
- `DISPATCHER_REPOSITORY`: そのrepositoryをcloneしたdirectoryの**絶対path**
- `DISPATCHER_ENDPOINT`: 同じSupabase projectの`.../functions/v1/dispatcher-control`
- `DISPATCHER_TOKEN`: Edge secretの同名値と完全一致
- `DISPATCHER_SCRATCH`: dispatcher実行ユーザーが書ける作業directory。既定値は`$HOME/Documents/continuous-improvement`
- `CODEX_BIN`または`CLAUDE_BIN`: 使用するAgent CLI

`DISPATCHER_REPOSITORY`の`origin`が`GITHUB_REPOSITORY`と対応していないと、別repositoryへbranchやPRを
作る危険があります。remote URLを値だけ目視確認してください。

```bash
git -C "$DISPATCHER_REPOSITORY" remote get-url origin
```

環境変数を読み込み、GitHub、dispatcher設定、Supabase認証をまとめて診断します。

```bash
set -a
source .env
set +a

scripts/doctor.sh --route cloud \
  --only github,dispatcher-env,dispatcher-auth \
  --full
```

dispatcherの実行環境にはJDK 25、認証済み`gh`、`git`、選択したAgent CLIが必要です。

```bash
./gradlew -q javaToolchains
gh auth status
codex --version          # agent:codexの場合
# claude --version       # agent:claudeの場合
```

Agent CLI自体のログインも事前に完了させてください。`gh`には対象repositoryのIssue更新、branch push、
draft PR作成に必要な権限が必要です。

### 手順2: 作成されたIssueを人間が確認する

GitHubでIssueを開き、次を確認します。

1. 報告内容が具体的で、期待動作や再現条件が分かる
2. Issue本文にraw artifact path、署名URL、secretが含まれていない
3. `Report ID: \`<uuid>\``の行がある
4. Agentに変更させてよい内容である

情報が足りなければ、ラベルを付ける前にIssue本文へ人間が補足します。現在のdispatcherがAgentへ渡すのは
Issueのtitleとbodyで、コメントは渡しません。Issue本文、スクリーンショット、ログはすべてuntrusted dataとして
扱われ、repository instructionsや安全制約を上書きする命令を書き込む場所ではありません。

### 手順3: Agentを選び、人間の承認ラベルを付ける

付けるラベルは2つです。担当させるAgentに応じて`agent:codex`または`agent:claude`を先に付け、
最後に共通で`agent-ready`を付けます。**両方**が揃ったIssueだけをdispatcherが拾います。

`agent-ready`は「内容を確認し、Agentに着手させてよい」という人間の承認gateなので、
手順1と2が終わってから最後に付けます。付与はGitHub UIで人間が行い、wizardもdispatcherも代行しません。

**1. 対象Issueを開く。** アプリが作ったIssueには`user-report`が付いているので、次のURLで絞り込めます。

```
https://github.com/<owner>/<repository>/issues?q=is%3Aissue+is%3Aopen+label%3Auser-report
```

**2. Issue画面の右sidebarで付ける。**

1. 「Labels」の見出しの右にある歯車アイコン（⚙）をクリックする
2. 出てきた検索欄に`agent:codex`（Claudeの場合は`agent:claude`）と入力し、一覧に現れた行をクリックする（左にチェックが付く）
3. 検索欄を`agent-ready`に書き換え、同じように行をクリックする
4. 一覧の外側をクリックして閉じる。保存ボタンはなく、閉じた時点で保存される
5. sidebarのLabelsに`agent:*`と`agent-ready`が並んでいれば完了

検索しても候補が出てこない場合は、labelがまだ作られていません。
[repositoryのlabelとbranch保護](setup-supabase.md#手順6-repositoryのlabelとbranch保護)の
`scripts/configure-github.sh`を実行してから付け直してください。ラベルの全状態遷移も同じ節にあります。

**3. 付いたことを確認する。** `<番号>`はIssueタイトル横の`#12`の数字です。

```bash
gh issue view <番号> --repo "$GITHUB_REPOSITORY" --json labels --jq '.labels[].name'
```

`scripts/dispatcher-wizard.sh`から進めている場合は、手順5でIssue番号を入力すると同じ確認を代わりに実行し、
足りないラベルを表示します（付与はしません）。

### 手順4: dispatcherを1回実行する

```bash
set -a
source .env
set +a
scripts/run-dispatcher.sh
```

dispatcherは対象Issueを1件だけclaimし、`agent-ready`を外して`agent-running`を付けます。その後、
redacted evidenceだけを取得し、一時worktreeでAgentを動かし、verification gateに通った場合だけbranchをpushして
draft PRを作ります。

出力される`outcome`の意味:

| outcome | Issueの状態 | 次にすること |
| --- | --- | --- |
| `IDLE` | 処理可能なIssueなし | `agent-ready`、`agent:*`、`Report ID`を確認 |
| `LOST_CLAIM` | 別processが先にclaim | そのprocessの完了を待つ |
| `PR_OPENED` | `pr-opened` | 手順6でdraft PRを人間review |
| `NEEDS_INFO` | `needs-info` | Issueへ情報を補足して再承認 |
| `FAILED` | `agent-failed` | 原因を直して再承認 |

### 手順5: `NEEDS_INFO`または`FAILED`から再開する

Issueとdispatcherのaudit/logで原因を確認します。秘密値やraw artifactはIssueへ貼らないでください。

1. 情報不足、Agent認証、権限、test失敗などの原因を解消する
2. `needs-info`または`agent-failed`を外す
3. `agent:codex`または`agent:claude`が正しいことを確認する
4. 人間が内容を再確認し、`agent-ready`を付け直す
5. `scripts/run-dispatcher.sh`をもう一度実行する

同じ失敗のまま`agent-ready`だけを貼り直さないでください。

### 手順6: draft PRを人間がreviewする

`{"outcome":"PR_OPENED"}`ならdraft PRが作られています。最低限、次を確認します。

1. Issueの意図に沿う最小差分か
2. raw evidence、secret、署名URL、credentialが含まれていないか
3. `./gradlew test`と`./gradlew build`およびCIが成功しているか
4. branch protectionと必須reviewが機能しているか

dispatcherとAgentはmerge・deployを行いません。draft解除、承認、mergeは人間が行います。

PR作成前のverification gate（`VerificationGate.java`）は次をすべて要求します。

1. 変更pathが`.git` / `local-reports` / `artifacts/raw`を含まない
2. 変更行数が`MAX_DIFF_LINES`（既定2000）以下
3. diffと変更fileにsecret検出パターンが無い
4. `./gradlew test`と`./gradlew build`が成功
5. source変更が1件以上ある

### 定期実行へ移行する場合

手動で一連の動作を確認した後、本番配置ではsystemd timerを使います（`ops/systemd/`）。環境変数は
`EnvironmentFile=/etc/continuous-improvement/dispatcher.env`から読み込まれます。

```bash
sudo install -d -o improvement-dispatcher -g improvement-dispatcher -m 700 \
  /home/improvement-dispatcher/Documents/continuous-improvement
sudo install -o improvement-dispatcher -g improvement-dispatcher -m 600 \
  dispatcher.env /etc/continuous-improvement/dispatcher.env
sudo systemctl enable --now continuous-improvement-dispatcher.timer
systemctl list-timers continuous-improvement-dispatcher.timer
journalctl -u continuous-improvement-dispatcher -n 50
```

---

## 1.8 起動時のトラブルシューティング

最初に`scripts/doctor.sh`を実行してください。下表のうち、JDK・build・送信設定は自動で判定されます。

| 症状 | 原因 | 対処 |
| --- | --- | --- |
| `No matching toolchains found ... languageVersion=25` | JDK 25が無い/検出されない | 1.1の方法AまたはB |
| `Could not resolve org.openjfx:javafx-*` | 初回にnetworkが無い、またはproxy未設定 | networkを確保して再実行。以後はcacheが効きます |
| GUIが開かず`Unable to open DISPLAY` | headless環境 | 1.6の`xvfb-run`を使う |
| Waylandで表示が崩れる / 文字が小さい | scaling | `GDK_SCALE=2`等を指定。Wayland実機は未検証（`I-019`） |
| Gradle daemonがnative library loadで落ちる | Gradle user homeの状態不整合 | `GRADLE_USER_HOME=/tmp/pci-gradle-home ./gradlew ...`で切り分け（`I-001`） |
| `失敗: create-report failed with HTTP 4xx` | 送信先/鍵/入力の問題 | [3.6 エラー早見表](setup-supabase.md#36-エラーコード早見表) |
| `create-report returned an invalid upload path` | 古いEdge Functionが`localPath`を返していない | `create-report`を再deploy（[3.7](setup-supabase.md#37-修正済みの不具合-localpathが返らない)） |
| 送信されずいつも`作成しました:` | 2変数のどちらかが未設定/空 | `scripts/doctor.sh`の`env-app` stageで確認 |

次: [2. `.env.example` の使い方](setup-env.md)
