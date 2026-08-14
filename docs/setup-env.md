# 2. `.env.example` の使い方

## 2.1 最初に理解すべき3つのこと

**① `.env.example`は2つある。役割がまったく違う。**

| file | 誰の設定か | 置き場所 | 秘密度 |
| --- | --- | --- | --- |
| `.env.example`（ルート） | JavaFXアプリ と dispatcher（**client側**） | 利用者PC / dispatcherサーバ | publishable keyと専用tokenのみ |
| `supabase/.env.example` | Supabase Edge Functions（**server側**） | Supabaseのsecrets（またはlocal開発機） | service-role key、GitHub token。**外へ出さない** |

**② `.env`は誰も自動で読まない。**

このプロジェクトはdotenv系のlibraryに依存していません。値の読み取りは`System.getenv`（Java）と
`Deno.env.get`（Edge Functions）だけです。つまり`.env`を置いただけでは何も起きません。
**processの環境変数として渡す**必要があります。

| 対象 | 渡し方 |
| --- | --- |
| 手元のJavaFXアプリ | `set -a; source .env; set +a` の後に `./gradlew :app:run` |
| 本番のdispatcher | systemdの`EnvironmentFile=/etc/continuous-improvement/dispatcher.env` |
| Supabase（cloud） | `supabase secrets set --env-file supabase/.env` |
| Supabase（local） | `supabase functions serve --env-file supabase/.env` |

**③ `.env.example`はtemplate。実際の値を書き込んではいけない。**

`.gitignore`は次のようになっています。

```
.env
.env.*
!.env.example
```

`.env`や`.env.local`は無視されますが、**`.env.example`だけは追跡対象**です。
`cp .env.example .env`してから`.env`を編集する運用にしてください。
`.env.example`を直接書き換えると、実credentialがcommitされます。

---

## 2.2 ルート `.env.example` — 変数リファレンス

```
REPORT_API_URL=http://127.0.0.1:54321
SUPABASE_PUBLISHABLE_KEY=local-publishable-key
REPORT_OUTPUT_DIR=local-reports
DISPATCHER_ENDPOINT=http://127.0.0.1:54321/functions/v1/dispatcher-control
DISPATCHER_TOKEN=replace-with-dedicated-token
DISPATCHER_REPOSITORY=/absolute/path/to/private/repository
DISPATCHER_SCRATCH=
CODEX_BIN=codex
CLAUDE_BIN=claude
MAX_DIFF_LINES=2000
```

このtemplateは**アプリ用とdispatcher用が1ファイルに同居**しています。実運用では分けてください（2.4参照）。

### JavaFXアプリが読む変数

| 変数 | 必須 | 既定値 | 説明 |
| --- | --- | --- | --- |
| `REPORT_API_URL` | 送信時のみ | なし | Supabase **Project URL**。`https://<project-ref>.supabase.co`。localなら`http://127.0.0.1:54321`。`/functions/v1`は付けない（コード側で付与されます） |
| `SUPABASE_PUBLISHABLE_KEY` | 送信時のみ | なし | `sb_publishable_...`形式。HTTPの`apikey` headerとして送られます |
| `REPORT_OUTPUT_DIR` | 任意 | `local-reports` | bundleの出力先。**rawを含む**ので、共有されないpathにする |
| `APP_SMOKE_TEST` | 任意 | なし | `true`のとき起動直後にcaptureして終了（headless確認用） |

`REPORT_API_URL`と`SUPABASE_PUBLISHABLE_KEY`が**両方**空でなければ送信を試み、
片方でも欠ければlocal保存だけで終わります（`ContinuousImprovementApp.java:148`）。
「送信したはずなのにIssueができない」ときは、まずこの2つを疑ってください。

### dispatcherが読む変数

| 変数 | 必須 | 既定値 | 説明 |
| --- | --- | --- | --- |
| `DISPATCHER_TOKEN` | **必須** | なし | Edge Functionの同名secretと**完全一致**が必要。`Authorization: Bearer <token>`で送られます |
| `DISPATCHER_REPOSITORY` | **必須** | なし | private repositoryのclone先**絶対path**。worktreeの親になります |
| `DISPATCHER_ENDPOINT` | **必須** | なし | `.../functions/v1/dispatcher-control` まで含めた完全なURL |
| `DISPATCHER_SCRATCH` | 任意 | `$HOME/Documents/continuous-improvement` | run毎の作業領域とaudit logの置き場所。実行ユーザーのhome配下へ絶対pathで配置する |
| `CODEX_BIN` | 任意 | `codex` | Codex CLIのpath |
| `CLAUDE_BIN` | 任意 | `claude` | Claude Codeのpath |
| `MAX_DIFF_LINES` | 任意 | `2000` | これを超える変更はverification gateで不合格 |

必須3つが未設定の場合、dispatcherは起動時点でエラーになります（`scripts/run-dispatcher.sh`と
`DispatcherMain.java`の両方でチェック）。

`DISPATCHER_SCRATCH`を明示するときは、`$HOME`や`~`ではなく
`/home/<user>/Documents/continuous-improvement`のような展開済みの絶対pathを設定してください。

> Agentの子processには、これらのcredentialは**継承されません**。`ProcessRunner`が環境変数を一度クリアし、
> 許可listのみを復元します。`gh`とgit push はdispatcher親processのcontrol経路だけが実行します（`I-009`/`I-011`）。

---

## 2.3 `supabase/.env.example` — 変数リファレンス

```
SUPABASE_URL=https://PROJECT_REF.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<deploy時に設定>
GITHUB_APP_ID=123456
GITHUB_APP_PRIVATE_KEY_BASE64=<deploy時に設定>
GITHUB_REPOSITORY=owner/private-repository
DISPATCHER_TOKEN=<専用のrandom secretを生成して設定>
```

（実ファイルのplaceholderは`replace-at-deploy-time`等の文字列です。上記は`scripts/security-gate.sh`の
secret patternに引っかからないよう、この資料上で書き換えています。）

| 変数 | 使う場所 | 説明 |
| --- | --- | --- |
| `SUPABASE_URL` | 全function（`_shared/config.ts`） | service-role clientの接続先 |
| `SUPABASE_SERVICE_ROLE_KEY` | 全function | RLSを迂回する管理者鍵。**絶対にclientへ配らない** |
| `GITHUB_APP_ID` | `finalize-report` | Edge用GitHub Appの数値ID |
| `GITHUB_APP_PRIVATE_KEY_BASE64` | `finalize-report` | 実行時に短命installation tokenを発行するprivate key。server側のみ |
| `GITHUB_APP_TOKEN` | `finalize-report` | 旧方式の移行用。1時間で失効するため通常は使わない |
| `GITHUB_REPOSITORY` | `finalize-report` | `owner/repo`形式 |
| `DISPATCHER_TOKEN` | `dispatcher-control`, `get-redacted-artifacts`, `purge-expired-artifacts` | dispatcher専用のBearer token。ルート`.env`と同じ値 |

> cloud（hosted）のEdge Functionsでは`SUPABASE_URL`と`SUPABASE_SERVICE_ROLE_KEY`は
> **自動で注入される予約変数**で、`SUPABASE_`で始まる名前はsecretsとして登録できません。
> 明示的に設定が必要なのはApp ID、private key、repository、dispatcher tokenです。詳細と確認方法は
> [3.3 手順5](setup-supabase.md#手順5-edge-secretsを設定する)を参照してください。
> このファイルの`SUPABASE_*`は主にlocal（`supabase functions serve --env-file`）で使います。

---

## 2.4 推奨するファイル配置

1ファイルに全部入れず、**渡す相手ごとに分ける**のが安全です。

| file | 置く場所 | 権限 | 入れる変数 |
| --- | --- | --- | --- |
| `.env` | 開発者PCのリポジトリ直下 | `600` | `REPORT_API_URL`, `SUPABASE_PUBLISHABLE_KEY`, `REPORT_OUTPUT_DIR` |
| `dispatcher.env` | `/etc/continuous-improvement/`（owner: `improvement-dispatcher`） | `600` | `DISPATCHER_*`, `CODEX_BIN`, `CLAUDE_BIN`, `MAX_DIFF_LINES` |
| `supabase/.env` | 運用担当者のPCのみ（local用途） | `600` | `supabase/.env.example`の5つ |
| （cloudのsecrets） | Supabase側に保存 | — | `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY_BASE64`, `GITHUB_REPOSITORY`, `DISPATCHER_TOKEN` |

```bash
cp .env.example .env && chmod 600 .env
cp supabase/.env.example supabase/.env && chmod 600 supabase/.env
```

**やってはいけないこと**

- service-role key / secret key（`sb_secret_...`）をデスクトップアプリへ配布する
- `.env.example`に実際の値を書く
- `DISPATCHER_TOKEN`をSQL migrationやIssue本文、PR本文に書く
- `echo $SUPABASE_SERVICE_ROLE_KEY`のように値を端末やログへ出す
- 同じtokenをdispatcherとGitHub Actionsなど複数用途で使い回す

---

## 2.5 設定できているかの確認方法

`scripts/doctor.sh`が、**値を表示せずに**全変数の状態をまとめて判定します。
`.env.example`の`# @`メタデータを読んでいるので、変数を増やしたときもこのscriptの修正は不要です。

```bash
scripts/doctor.sh
```

各変数は次の3状態のどれかとして表示されます。**2番目が最も多い誤り**です。

| 表示 | 意味 |
| --- | --- |
| `設定済み` | 起動するprocessの環境変数にある |
| `.env にはありますが、このシェルには未設定です` | `set -a; source .env; set +a`をしていない（2.1 ②） |
| `未設定` | どこにもない |

`@format`を持つ変数は形式まで検査されます（`REPORT_API_URL`に`/functions/v1`を付けてしまった、
`DISPATCHER_REPOSITORY`が相対pathになっている、`GITHUB_REPOSITORY`にcloneのURLを貼ってしまった、など）。
`SUPABASE_PUBLISHABLE_KEY`にsecret keyやservice-role keyを設定してしまった場合は、
値を表示せずに不合格として報告します（2.6）。

`@example`を持つ変数は、不合格のときに正規表現だけでなく実例も表示します。
例は`.env.example`側にあるので、値の形を変えたら`@format`と`@example`を一緒に更新してください。

値の入力まで対話で行う場合は`scripts/setup.sh`を使います。`.env`を`0600`で作り、
`@secret`の値は入力中も画面に出さず、`@format`に合わない値はその場で`例:`付きで拒否します。
`GITHUB_REPOSITORY`にcloneのURLを入れた場合は`owner/repo`へ直してから保存します。

手で確認する場合は次のとおりです。

```bash
for name in REPORT_API_URL SUPABASE_PUBLISHABLE_KEY DISPATCHER_TOKEN DISPATCHER_ENDPOINT DISPATCHER_REPOSITORY; do
  if [ -n "${!name-}" ]; then echo "$name: set"; else echo "$name: MISSING"; fi
done
```

Supabase側は、値ではなくhashの一覧が返ります。

```bash
supabase secrets list --project-ref "$SUPABASE_PROJECT_REF"
```

---

## 2.6 鍵の種類を見分ける

| 見た目 | 名称 | 置いてよい場所 | 権限 |
| --- | --- | --- | --- |
| `sb_publishable_...` | publishable key | **デスクトップアプリに配布可** | 公開前提。単体ではDB/Storageに触れない |
| `sb_secret_...` | secret key | server側のみ | 高権限 |
| `eyJ...`（長いJWT） | 旧anon / service_role key | anonはclient可、service_roleは**server側のみ** | service_roleはRLSを完全に迂回 |

**なぜpublishable keyを配ってよいのか**: `user-reports` bucketはprivateで、
`reports`等のtableには`anon`/`authenticated`向けのRLS policyを1つも作っていません
（`supabase/migrations/202608110001_initial.sql`の末尾コメント参照）。
データへのアクセスはすべてEdge Function経由で、functionがservice-role keyを使います。
したがってpublishable keyが漏れても、直接DBやStorageからデータを引き出すことはできません。

> PoCとしての制約: `create-report` / `finalize-report`は`verify_jwt = false`で公開されています（`I-016`）。
> 防御は入力schema検査、size/hash検査、rate limit（1時間あたり10回）です。
> 一般公開する前にWAFとrate limit強化、token rotationが必要です。

次: [3. Supabaseの準備](setup-supabase.md)
