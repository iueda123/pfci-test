# セットアップ資料

初めてこのリポジトリを触る人向けの手順書です。**上から順に**読むことを想定しています。

| # | 資料 | 内容 | 所要時間の目安 |
| --- | --- | --- | --- |
| 1 | [アプリのセットアップと起動](setup-app.md) | JDK/Gradle、JavaFX操作、Issue作成後からAI draft PRまでの統合runbook | 30分 |
| 2 | [`.env.example` の使い方](setup-env.md) | 2つの`.env.example`の役割、全環境変数リファレンス、値の渡し方と置き場所 | 20分 |
| 3 | [Supabaseの準備](setup-supabase.md) | localスタック、cloud project作成、migration/Edge Functions配置、secrets、疎通確認 | 60分〜 |

## いま自分がどこまで進んでいるか

`scripts/doctor.sh`が、環境を毎回実測して到達済みの段階と**次の1手**だけを表示します。
進捗を記録するのではなく都度測るので、途中で中断しても、別の日に再開しても、
「どこから読み直せばよいか」がこの1コマンドでわかります。

```bash
scripts/doctor.sh            # 手早く判定（既定）
scripts/doctor.sh --full     # build/test、headless capture、DB到達確認まで実走
scripts/doctor.sh --offline  # network到達確認を行わない
```

未到達のstageには、この資料の該当箇所へのリンクが出ます。読み進める前と、
手順を1つ終えるたびに実行してください。値（鍵やtoken）は決して表示しません。

## 対話で進める

`scripts/setup.sh`は、同じ判定を使って**未到達のstageを1つだけ**進めます。

```bash
scripts/setup.sh          # 1段階だけ進める
scripts/setup.sh --all    # 進められなくなるまで繰り返す
scripts/setup.sh --route cloud --github-app  # GitHub Appの生成・install案内を再表示
```

- 最初に**route**（`app` / `local` / `cloud`）を尋ねます。以降の手順はここで分岐します
- cloudのEdge secrets段階では、Edge用GitHub AppのApp IDとprivate key PEMのpathを尋ね、
  GitHub画面でのPEM取得方法を案内したうえで、base64変換・secret登録・
  `finalize-report`のdeployを自動実行します
- 設定が要るstageでは`.env`を`0600`で作り、変数ごとに値を尋ねます。`@secret`の値は入力中も画面に出ません
- `SUPABASE_PUBLISHABLE_KEY`にsecret/service-role鍵を入れようとすると拒否します
- `DISPATCHER_ENDPOINT`のように他の変数から決まる値は、推奨値を提示します
- **コマンドは必ず確認してから実行します**（既定は「実行しない」）。値を埋める必要のある雛形は表示するだけです

書き込むのは`.env`と`supabase/.env`だけです。`.env.example`やリポジトリのファイルは変更しません。

## 最短ルート

Supabaseを用意せず、まずアプリだけ動かして仕組みを見たい場合は
[1. アプリのセットアップと起動](setup-app.md)だけで完結します。この場合、報告bundleは
`local-reports/<report-id>/`へ保存されるだけで、外部へは何も送信されません。

## 関連ドキュメント

- [../README.md](../README.md) — プロジェクト概要
- [../AGENTS.md](../AGENTS.md) — Agent向けの禁止事項（人間も読んでください）
- [../dev-notes/operations.md](../dev-notes/operations.md) — 本番相当の運用gateとacceptance checks
- [../dev-notes/implementation-notes.md](../dev-notes/implementation-notes.md) — 実装上の判断と既知の妥協点（本資料の`I-0xx`参照はこの文書のID）
