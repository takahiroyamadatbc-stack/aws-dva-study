# デプロイ戦略メモ

CodeDeploy / SAM のデプロイタイプに関する暗記事項。
Labで検証した内容があれば該当Labへのリンクを添える。

## CodeDeploy デプロイタイプ

| 対象 | デプロイタイプ | 説明 | 主なユースケース／注意点 | 検証Lab |
|------|----------------|------|--------------------------|---------|
| Lambda | Canary | 一定割合を先行公開し、時間経過後に残りを切替 | 例: Canary10Percent5Minutes | |
| Lambda | Linear | 一定割合ずつ段階的に切替 | 例: Linear10PercentEvery1Minute | |
| Lambda | AllAtOnce | 即時全量切替 | ロールバック猶予なし | |
| EC2/オンプレミス | In-place | 既存インスタンス上でアプリを更新 | ダウンタイムあり得る | |
| EC2/オンプレミス | Blue/Green | 新インスタンス群を作成して切替 | ロールバックが容易 | |
| ECS | Blue/Green | 新タスクセットを作成して切替 | CodeDeployがALB経由でトラフィック制御 | |

## SAM `AutoPublishAlias` / `DeploymentPreference`

| 項目 | 役割 | メモ | 検証Lab |
|------|------|------|---------|
| `AutoPublishAlias` | デプロイの度にLambdaバージョンを発行し、指定名のエイリアスを自動で新バージョンに向ける | これを設定しないと段階的デプロイ（Canary/Linear）は使えない | |
| `DeploymentPreference.Type` | Canary/Linear/AllAtOnceを指定 | CodeDeployのLambdaデプロイタイプ名をそのまま使う | |
| `DeploymentPreference.Alarms` | デプロイ監視用CloudWatchアラーム | しきい値超過で自動ロールバック | |
| `DeploymentPreference.Hooks` | Pre/PostTrafficフックのLambda関数 | トラフィック切替前後の検証処理を挟める | |

## その他

- （ここに追記していく）
