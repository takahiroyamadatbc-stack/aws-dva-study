# 指数バックオフ (Exponential Backoff) が絡むサービス別エラーまとめ

「スロットリングされたら指数バックオフで再試行する」という基本パターンは全AWSサービス共通だが、**サービスごとに投げてくるエラー名/ステータスコードが異なる**ため、設問文からどのサービスの話をしているか逆引きできるようにしておく。

## 指数バックオフの基本

- クライアントがリクエストを送り、スロットリング(レート制限超過)されたら、即座にリトライせず**試行のたびに待機時間を指数関数的に伸ばしながら**再送する(例: 1s → 2s → 4s → 8s...)
- 待機時間に**ジッター(ランダムな揺らぎ)**を加える(Full Jitter/Equal Jitterなど)ことで、同時に失敗した多数のクライアントが同じタイミングで再試行し、再度スロットリングを誘発する「再試行の同期化」を防ぐ
- AWS SDK(boto3, AWS SDK for Java/JS等)は多くのAPI呼び出しで**デフォルトでリトライ+指数バックオフを内蔵**している。したがって「自前でtry/exceptとsleepを書く」ではなく「SDKのリトライ設定(最大試行回数・retry mode)を使う」が模範解答になりやすい

## サービス別のスロットリングエラー対応表

| サービス | エラー/ステータスコード | 意味 | 補足 |
|---|---|---|---|
| API Gateway | `429 Too Many Requests` | APIのスロットリング上限(アカウント/メソッド単位のレート・バースト制限)を超過 | クライアント側で指数バックオフ。API Gateway側ではUsage Planでレート/バースト値そのものを調整できる |
| DynamoDB | `ProvisionedThroughputExceededException` | プロビジョニングされたRCU/WCUを超過 | オンデマンドモードでも急激なスパイクでは`ThrottlingException`が出ることがある。AWS SDKが自動的に指数バックオフでリトライする |
| Kinesis Data Streams | `ProvisionedThroughputExceededException` | シャードごとの書き込み(1,000 records/sまたは1MB/s)・読み込み上限を超過 | シャード数を増やす(リシャーディング)、もしくは書き込み側でバックオフ。パーティションキーの偏りによるホットシャードが根本原因であることが多い |
| Lambda(AWS SDK経由のAPI呼び出し) | 呼び出し先サービスの`ThrottlingException`等 | Lambda関数内でSDKを使って他サービスを呼んだ際、呼び出し先でスロットリングされる | Lambdaの同時実行数増加に伴い、呼び出し先(DynamoDB/KMS等)への呼び出しが集中してスロットリングされる構図が典型。SDKの自動リトライに任せるのが基本 |
| EC2 / Auto Scaling / ELB(Describe系などQuery形式API) | `RequestLimitExceeded` | EC2系(Query形式)APIへのリクエスト頻度がアカウント単位の上限を超過 | `DescribeInstances`等を高頻度でポーリングする実装で発生しやすい。`ThrottlingException`ではなくこの名称である点が試験のひっかけになりやすい |
| Amazon S3 | `503 Slow Down` | 特定プレフィックスへのリクエストレートが急上昇した際のスロットリング | 現在はプレフィックスごとに非常に高いレート上限を持つが、急激なスパイクでは依然発生しうる。指数バックオフに加え、プレフィックス設計でリクエストを分散させるのも有効 |
| AWS KMS | `ThrottlingException` | CMK(KMSキー)ごとに設定されたリクエストクォータ(呼び出し回数/秒)を超過 | Lambdaが呼び出しのたびに`Decrypt`/`GenerateDataKey`を呼ぶ設計で高負荷時に発生しやすい典型パターン。データキーのキャッシュ(AWS Encryption SDKのキャッシュ機構等)で呼び出し回数自体を減らすのが根本対策で、指数バックオフは対症療法にとどまる |
| Amazon CloudWatch | `ThrottlingException`(旧: `Throttling: Rate exceeded`) | `PutMetricData`等のAPIコール頻度がアカウント/API単位の上限を超過 | カスタムメトリクスを高頻度で送信する実装で発生しやすい。1回のAPI呼び出しに複数メトリクスをまとめる(バッチ化)ことでも呼び出し回数自体を削減できる |
| AWS STS | `ThrottlingException` | `AssumeRole`等の呼び出し頻度が上限を超過 | Lambda呼び出しごとに毎回`AssumeRole`する設計で発生しやすい。認証情報のキャッシュ・再利用が根本対策 |

## 見分け方のコツ

- エラー名が`ThrottlingException`なら比較的新しい形式のAPI(DynamoDBオンデマンド、KMS、CloudWatch、STSなど多数)、`RequestLimitExceeded`ならEC2系(Query形式)API、`ProvisionedThroughputExceededException`ならDynamoDB/Kinesisのプロビジョンドスループット、`503 Slow Down`ならS3、`429`ならAPI Gateway、と覚えておくと設問文のエラー名からサービスを逆引きしやすい
- 「根本原因への対処」を問う設問では、指数バックオフは**症状を緩和する対症療法**であり、根本対策(シャード数増加、CMKへの呼び出し削減、認証情報キャッシュ、Usage Plan調整等)とセットで問われることが多い点に注意

## その他

- （ここに追記していく）
