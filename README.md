# pfci-test

継続的改善サイクルの**改善対象アプリ**です。改善の機構そのもの（報告 SDK、Supabase Edge
Functions、dispatcher）は別リポジトリ `platform-for-continuous-improvement` にあり、
このリポジトリはそれを Maven artifact として参照するだけです。

- 業務アプリ本体 — `app/src/main/java/dev/pfcitest/app/`
- 報告クライアント SDK — `dev.continuousimprovement:reporting`（`app/build.gradle.kts`）
- `AGENTS.md` / `CLAUDE.md` / `.github/` — platform の `templates/` から配布されたもの。
  **このリポジトリで直接編集しないでください。** 変更は platform 側の `templates/` に対して行い、
  `scripts/sync-templates.sh` で再配布します。

## build と実行

JDK 25 が必要です。Gradle は同梱の Wrapper が取得します。

```bash
./gradlew test build
./gradlew :app:run
```

`reporting` は private な GitHub Packages にあるため、取得には資格情報が要ります。

| 実行場所 | 解決経路 |
| --- | --- |
| CI | GitHub Packages（`GPR_USER` / `GPR_TOKEN`。workflow が `GITHUB_TOKEN` を渡します） |
| ローカル開発 | 同上、または platform 側で `./gradlew publishToMavenLocal` を実行して `mavenLocal()` から |
| dispatcher 配下の agent | dispatcher が事前に依存を解決した Gradle home を渡し、agent は `--offline` で解決 |

資格情報を `.env` やこのリポジトリへ書かないでください。

## 報告の送信

`REPORT_API_URL` と `SUPABASE_PUBLISHABLE_KEY` の両方が設定されている場合だけ、報告は
Supabase Edge Functions へ送信されます。未設定なら `local-reports/<report-id>/` への
ローカル保存だけを行います。このディレクトリには raw データが含まれる可能性があるため、
ディレクトリ全体を共有しないでください。

どちらの動作になるかは、報告 dialog の「アプリの送信設定」（SDK の `SettingsStatusPane`）が
**値を表示せずに**示します。送信できる設定ならボタンは `送信する`、できなければ
`ローカルbundleを作成` になります。`SUPABASE_PUBLISHABLE_KEY` に secret / service-role 相当の
鍵が設定されている場合は警告し、ローカル保存だけを行って送信しません。

```bash
export REPORT_API_URL='https://<project-ref>.supabase.co'
export SUPABASE_PUBLISHABLE_KEY='<publishable-key>'
./gradlew :app:run
```
