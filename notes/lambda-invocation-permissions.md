# Lambda関数まわりの権限4種の切り分け（誰が呼べるか／呼ばれた後に何ができるか）

「S3イベント→Lambda」のようなイベント駆動構成で毎回混同しやすい、Lambda関連の権限の種類を整理する。ポイントは**「呼び出しの許可」と「呼び出された後のリソースアクセス許可」は完全に別のポリシーが担当している**こと。

## 一行結論

> 「意図しない相手がLambda関数を**起動できてしまう**」を防ぎたい → **Lambdaのリソースベースポリシー**（誰がInvokeできるか）。
> 「Lambda関数の**中の処理**が意図しないリソースにアクセスしてしまう／できない」→ **実行ロールの許可ポリシー**（起動後に何ができるか）。

この2つを取り違えると、「実行ロールを絞ったのに関数が呼ばれ続ける（無駄な起動・課金・エラーログ）」というハマり方をする。

## 権限の種類一覧

| # | 名称 | どこに付く | 制御する内容 | 評価タイミング |
|---|------|-----------|--------------|----------------|
| 1 | **Lambdaリソースベースポリシー**（関数ポリシー） | Lambda関数自体 | 「誰（どのプリンシパル／サービス／アカウント）が`lambda:InvokeFunction`できるか」 | 呼び出し**前**（起動の可否を決める） |
| 2 | **実行ロールの許可ポリシー**（Execution Role） | 実行ロール（IAM Role） | 「起動した関数のコードが、他のAWSリソースに対して何をできるか」（S3読み取り、DynamoDB書き込み等） | 呼び出され起動した**後** |
| 3 | **実行ロールの信頼ポリシー**（Trust Policy） | 実行ロール（IAM Role） | 「そもそもLambdaサービス（`lambda.amazonaws.com`）がこのロールをAssumeしてよいか」 | 関数の実行環境が起動する時 |
| 4 | **呼び出し元のIDベースポリシー** | 呼び出す側のIAMユーザー/ロール | 人やCLI/SDK、あるいはEventBridgeルールのIAMロールが`lambda:InvokeFunction`を明示的に呼ぶ場合、呼び出し元にもその権限が必要 | 呼び出し**前**（1と両方揃って初めて成立） |
| 5 | **S3バケットポリシー** | S3バケット | 「誰がそのバケットに`GetObject`/`PutObject`等できるか」。Lambda呼び出しの可否とは無関係 | S3オブジェクトへのアクセス時 |
| 6 | **S3イベント通知設定** | S3バケット（ポリシーではなく設定） | 「どのイベント（ObjectCreated等）をどの送信先（Lambda/SNS/SQS/EventBridge）に通知するか」の**配線設定**。権限ではない | イベント発生時にS3が送信先を決める |
| （参考）SCP | Organizations | アカウントに対する許可の上限（ガードレール）。1〜5がAllowしていてもSCPがDenyなら実行不可 | 常に最優先で評価 |

## push型（S3イベント通知）とpull型（Event Source Mapping）の違い

- **push型**（S3イベント通知、SNS、EventBridge等）: サービス側がLambdaの`Invoke`を能動的に呼ぶ。だから**1のリソースベースポリシー**でその呼び出し元を許可しておく必要がある（通常は`aws lambda add-permission`で設定、コンソールでトリガー追加すると自動生成される）
- **pull型**（Event Source Mapping: SQS、Kinesis、DynamoDB Streams）: Lambda側（正確にはLambdaサービスの内部ポーラー）が**実行ロール**を使ってキュー/ストリームをポーリングしにいく。呼び出しの許可という概念がなく、実行ロールに`sqs:ReceiveMessage`等があれば足りる。つまりpull型では「1のリソースベースポリシー」は登場しない

この違いを知っていると、「SQSトリガーのLambdaが動かない」系の設問では実行ロールを、「S3/SNSトリガーのLambdaが意図しない相手から呼ばれる／呼ばれない」系の設問ではリソースベースポリシーを疑う、と機械的に切り分けられる。

## コード例

### 1. Lambdaリソースベースポリシー（同一アカウントの特定バケットからのみ許可）

```bash
aws lambda add-permission \
  --function-name prod-image-processor \
  --statement-id AllowS3ProdBucketOnly \
  --action lambda:InvokeFunction \
  --principal s3.amazonaws.com \
  --source-arn arn:aws:s3:::prod-image-bucket \
  --source-account 111111111111
```

`--source-arn`（対象バケットの固定）と`--source-account`（呼び出し元アカウントの固定）の両方を付けるのが安全。片方だけだと想定外のバケット/アカウントからの呼び出しを許してしまう場合がある。

### 2. 実行ロールの許可ポリシー（起動後にできることを絞る）

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::prod-image-bucket/*"
    }
  ]
}
```

これはあくまで「コードの中で`s3.getObject()`を呼んだ時に成功するか」の話であり、この関数がいつ・誰から起動されるかには一切関与しない。

### 3. 実行ロールの信頼ポリシー（誰がこのロールをAssumeできるか）

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Lambda関数を作る時にほぼ自動生成される部分で、意識することは少ないが、「実行ロール」と一口に言っても許可ポリシーと信頼ポリシーは別物という点は覚えておく。

## 典型的な誤答パターン

| 設問の記述 | 誤って疑いがちな対象 | 本来疑うべき対象 |
|---|---|---|
| 「意図しないS3バケットがLambdaを呼び出してしまう」 | 実行ロール、S3バケットポリシー | Lambdaリソースベースポリシー（`SourceArn`/`SourceAccount`条件） |
| 「Lambdaがトリガーはされるが、S3から読み取れずエラーになる」 | リソースベースポリシー | 実行ロールの許可ポリシー |
| 「SQSキューのメッセージがLambdaで処理されない」 | リソースベースポリシー | 実行ロールの許可ポリシー（Event Source MappingはPull型） |
| 「クロスアカウントで他アカウントのLambdaを呼びたい」 | 呼び出し先の実行ロール | 呼び出し先のリソースベースポリシー＋呼び出し元のIDベースポリシー（両方必要） |

## 関連

- [networking-access-control.md](networking-access-control.md) — OAC（CloudFront→S3のリソースベースポリシー活用）とCORSの切り分け。「サーバー間のアクセス制御はリソースベースポリシー／IAM、ブラウザ制約はCORS」という構図はここでの整理と同じ発想
- [async-integration-patterns.md](async-integration-patterns.md) — Lambda Destinations等、Lambdaの呼び出し後の連携パターン比較
