# Step Functions 入門

誤答検証ではなく、「使ったことがなく機能のイメージが湧かない」ため、
実際に動くステートマシンをCDKで組んで理解するためのLab。

## 1. 何が嬉しいのか(Lambda単体との違い)

Lambda単体で複数処理を繋げようとすると、次のような課題が出る。

| 課題 | Lambda単体でやると | Step Functionsだと |
|---|---|---|
| 処理の順序・分岐 | コード内にif/elseとLambda呼び出しを埋め込む | ASL(Amazon States Language)でワークフローとして宣言 |
| リトライ | 自前でtry/exceptとsleepを書く | `Retry` を宣言するだけ(間隔・回数・backoff倍率を指定) |
| エラー時の代替処理 | 自前でtry/exceptして呼び分け | `Catch` で別ステートへ自動遷移 |
| 実行状況の可視化 | CloudWatch Logsを自分で読む | コンソールでVisual Workflow＋各ステートの入出力がそのまま見える |
| 長時間待機 | Lambdaのタイムアウト(最大15分)に縛られる | `Wait`や`.waitForTaskToken`で日単位の待機も可能 |
| 状態の受け渡し | 自分でDB/S3に保存 | 実行コンテキストとして自動的に前段の出力が次段の入力になる |

一言で言うと、**「複数のLambda(やAPI)を順序・分岐・リトライ込みでオーケストレーションし、
かつその実行過程を丸ごと可視化・保持してくれるサービス」**。

## 2. Standard vs Express

試験で必ず比較が問われる。

| 項目 | Standard | Express |
|---|---|---|
| 実行時間 | 最大1年 | 最大5分 |
| 実行モデル | exactly-once | at-least-once(重複実行の可能性あり) |
| 料金 | 状態遷移(state transition)ごとの課金 | 実行回数・実行時間・メモリで課金(Lambdaに近い課金体系) |
| 実行履歴 | コンソールで実行ごとに90日間無料保持、詳細に確認可能 | CloudWatch Logsに出力(自分で有効化が必要)、コンソール上の詳細度は低い |
| 想定用途 | 人が承認するワークフロー、長時間の非同期処理、監査証跡が欲しい処理 | 高頻度・大量のイベント処理(IoT、ストリーミング処理) |

本Labは学習用に実行履歴が見やすい **Standard** を使っている。

## 3. 主要なState型

| State | 役割 | 本Labでの使用箇所 |
|---|---|---|
| `Task` | Lambda呼び出しなど実処理を1つ実行 | CheckStock, ProcessPayment, 各種Notify |
| `Choice` | 条件分岐(if/elseの集合) | InStock?(在庫の有無で分岐) |
| `Wait` | 指定秒数 or 指定時刻まで待機 | WaitBeforePayment |
| `Parallel` | 複数ブランチを並列実行(ブランチ数は定義時に固定) | 未使用(応用) |
| `Map` | 配列の各要素に同じ処理を繰り返す(件数は実行時に可変) | 未使用(応用) |
| `Pass` | 何もせず入出力を加工するだけ | 未使用 |
| `Succeed` / `Fail` | 正常/異常終了を明示 | 未使用(暗黙に最終Taskの出力で終了) |

`Parallel`は「固定本数のブランチを並列に」、`Map`は「可変件数の配列要素を並列(または直列)に処理」という違いが試験のひっかけになりやすい。

## 4. Retry / Catch の仕組み

`Task`(や`Parallel`/`Map`)に対して個別に設定できる、State単位のエラーハンドリング。

```python
process_payment.add_retry(
    errors=["States.ALL"],
    interval=Duration.seconds(1),
    max_attempts=3,
    backoff_rate=2.0,
)
process_payment.add_catch(
    payment_failed_notify,
    errors=["States.ALL"],
    result_path="$.error",
)
```

- `Retry`は同じStateを指数バックオフで再試行する。`errors`にエラー種別(`States.ALL`や`States.TaskFailed`、Lambdaの例外クラス名など)を指定して、リトライ対象を絞れる
- `Retry`を使い切ってもなお失敗した場合に初めて`Catch`が発動し、指定した別Stateへ遷移する
- `result_path`でエラー情報を入力データに追記できる(元の入力を潰さずにエラー内容を持ち回れる)
- **LambdaのInvoke自体のリトライ(サービス側のスロットリング等)とは別物**。Step FunctionsのRetry/Catchはステートマシンの制御であり、Lambda側のリトライ設定(非同期呼び出し時のRetry Attempts等)とは独立している

## 5. コンテキストオブジェクト(`$$`)

`$`は「現在のStateへの入力」、`$$`は「Step Functionsが管理する実行メタデータ」を指す。

本Labでは `$$.State.RetryCount` を使い、ステートレスなLambdaに「今何回目の試行か」を知らせている。

```python
payload=sfn.TaskInput.from_object({
    "item_id.$": "$.item_id",
    "payment_behavior.$": "$.payment_behavior",
    "retryCount.$": "$$.State.RetryCount",
}),
```

他にも `$$.Execution.Id`(実行ARN)、`$$.State.EnteredTime`などが取れる。
Lambda単体では「これは何回目の呼び出しか」を知る手段がない(呼び出し側が渡さない限り)ため、
Step Functions特有の便利ポイント。

## 6. サービス統合パターン(呼び出し方の3種類)

Lambdaに限らず、Step Functionsが他サービスを呼ぶときの統合パターンが3つある。試験頻出。

| パターン | 挙動 | 例 |
|---|---|---|
| Request Response | APIを1回呼んでレスポンスが返ったら次へ進む(デフォルト) | 本Labの`LambdaInvoke`はこれ |
| Run a Job(`.sync`) | ジョブを開始し、完了(成功/失敗)まで待ってから次へ進む | Batch/ECS/Glueジョブの実行完了待ち |
| Wait for Callback(`.waitForTaskToken`) | タスクトークンを発行し、外部から`SendTaskSuccess`/`SendTaskFailure`が呼ばれるまで待つ | 人間の承認待ち、外部システムからのコールバック待ち(最大1年、Standardのみ) |

`.waitForTaskToken`は「人が承認ボタンを押すまで待つ」ような長時間非同期処理の定番。EXPRESSでは使えない(実行時間上限5分のため)点がひっかけになりやすい。

## 7. IAM

- ステートマシンには**実行ロール(IAM Role)**が必要で、呼び出す先(Lambda等)へのInvoke権限を持つ
- CDKの`LambdaInvoke`を使うと、対象Lambdaへの`lambda:InvokeFunction`権限が実行ロールに自動付与される(明示的なポリシー記述は不要)
- Lambda側にStep Functionsを信頼するようなリソースポリシーは不要(呼び出し元はIAM Roleの権限で制御されるため、Lambda関数ポリシーの追加は発生しない)

## 8. 試験でのキーワード対応

| 設問の語 | 対応する答え |
|---|---|
| 複数Lambdaを順序・条件分岐付きでオーケストレーション | Step Functions |
| ワークフローの実行状況を可視化・監査したい | Step Functions Standard(実行履歴が90日保持) |
| 大量・高頻度・短時間のイベント処理 | Step Functions Express |
| 人の承認を挟む/外部コールバックを待つ長時間処理 | `.waitForTaskToken`(Standardのみ) |
| 特定のジョブの完了を待ってから次に進みたい | `.sync`統合パターン |
| 配列の各要素に同じ処理をかけたい(件数は可変) | `Map` state |
| 固定本数の処理を同時に流したい | `Parallel` state |
| Task失敗時に自動で再試行したい | `Retry` |
| Task失敗時に別処理へフォールバックしたい | `Catch` |

## 9. ハンズオン(このLabの使い方)

**未デプロイ。実行する場合は以下の手順。**

```bash
cd labs/013-step-functions
cdk synth
cdk deploy --tags Project=dva-study
```

デプロイ後、State Machine ARNを控えて複数パターンで実行し、コンソールのVisual Workflowで
どのブランチを通ったか・Retryが何回発生したかを確認する。

```bash
# 1. 在庫あり、決済も1発成功 -> WaitBeforePayment -> ProcessPayment -> SendConfirmation
aws stepfunctions start-execution --state-machine-arn <ARN> \
  --input '{"item_id":"item-001","in_stock":true,"payment_behavior":"success"}'

# 2. 在庫なし -> Choiceで即OutOfStockNotifyへ(ProcessPaymentには到達しない)
aws stepfunctions start-execution --state-machine-arn <ARN> \
  --input '{"item_id":"item-002","in_stock":false}'

# 3. 決済が2回失敗して3回目で成功 -> Retryが2回発生する様子が実行履歴に残る
aws stepfunctions start-execution --state-machine-arn <ARN> \
  --input '{"item_id":"item-003","in_stock":true,"payment_behavior":"fail_then_success"}'

# 4. 決済が常に失敗 -> Retryを3回使い切ってCatchが発動し、PaymentFailedNotifyへ
aws stepfunctions start-execution --state-machine-arn <ARN> \
  --input '{"item_id":"item-004","in_stock":true,"payment_behavior":"always_fail"}'
```

実行結果は以下でも確認できる。

```bash
aws stepfunctions describe-execution --execution-arn <実行ARN>
aws stepfunctions get-execution-history --execution-arn <実行ARN>
```

期待される挙動:

- パターン3では`ProcessPayment`のイベント履歴に`TaskFailed`→(interval後)`TaskStateEntered`が2回並び、3回目の`TaskSucceeded`で`SendConfirmation`に進む
- パターン4では`TaskFailed`が3回(初回+Retry2回)続いた後、Retryを使い切って`Catch`が発動し`PaymentFailedNotify`が実行される

### 片付け

```bash
cd labs/013-step-functions
cdk destroy --force
```

## 一行結論

> Step Functionsは複数Lambda等を順序・分岐・Retry/Catch込みでオーケストレーションし、実行過程を可視化・保持できるサービス。Standard(最大1年、exactly-once、履歴90日保持)とExpress(最大5分、at-least-once、高頻度向け)は用途で使い分け、Retryは同一Stateの自動再試行、Catchはリトライを使い切った後の代替ルート、`.waitForTaskToken`は外部コールバック待ちの長時間処理(Standardのみ)に使う。
