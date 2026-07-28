# API Gateway APIキー + 使用量プラン 試験の判断基準

## APIキーの用途

APIキーは認証・認可の手段ではなく、識別・管理のための仕組み。実務では以下の4用途で使われる。

| 用途 | 内容 |
| --- | --- |
| クライアント識別 | パートナー/取引先ごとにキーを分けて呼び出し元を区別する(B2B API) |
| クライアント単位のスロットリング・クォータ制御 | Usage Planと組み合わせ、キーごとに流量制限を変える(無料プラン/有料プランなど)。ステージ全体のスロットリングとは別軸で制御できる |
| SaaS課金メータリング | AWS Marketplaceのメータリング型SaaS商品で、購入者ごとにキーを発行し呼び出し回数を従量課金の根拠にする |
| 利用状況の可視化 | CloudWatchでAPIキー単位(`ApiKeyId`ディメンション)にメトリクス/アクセスログを分離して監視できる |

APIキーは`x-api-key`ヘッダーに平文で載るだけの文字列で、盗聴・使い回しに弱い。そのため実務ではIAM/Cognito/Lambdaオーソライザーによる認証と役割分担して併用するのが前提で、APIキー単体を機密データの保護手段として使う選択肢は基本的に誤り。

## 誤答の判断基準

| 設問のキーワード | 答え |
| --- | --- |
| APIキーを認証・認可の手段だと誤解させる選択肢 | 誤り。APIキーは識別・スロットリング・課金のためのものであり、認証はIAM/Cognito/Lambdaオーソライザーの役割 |
| `CreateApiKey`直後に403が出る | 使用量プラン(Usage Plan)にキーが紐付いていない。`CreateUsagePlanKey`で紐付ける |
| キーごとに流量制限を変えたい | Usage Planを分ける(例: 無料プラン/有料プラン)。ステージ全体のスロットリングとは別軸 |
| SaaSの従量課金をAPI呼び出し回数で行いたい | Usage Plan + APIキーの組み合わせ(AWS Marketplaceのメータリング型SaaSで使う構成) |
| オーソライザーの更新(`UpdateAuthorizer`)で403を直そうとする選択肢 | 誤り。オーソライザーはLambda/Cognito認可の設定であり、APIキー検証とは別レイヤー |
| 再デプロイ(`CreateDeployment`)で403を直そうとする選択肢 | 誤り。APIキー作成やUsage Plan紐付けはAPI定義の変更を伴わないため再デプロイ不要 |

## リソースの関係

```
API Key ──(CreateUsagePlanKey)──> Usage Plan ──(api-stages)──> Stage / REST API
```

- APIキー単体では何の権限も持たない、ただの識別子
- メソッド側で `apiKeyRequired: true` になっている場合、有効なUsage Plan紐付けのないキーで呼ぶと403
- Usage Planはスロットリング(`--throttle`)とクォータ(`--quota`)をキー単位で設定する

## 403の原因切り分け順序

1. メソッドで `api-key-required` が有効か
2. キー自体が `enabled: true` か
3. キーがUsage Planに紐付いているか(`CreateUsagePlanKey`)
4. Usage PlanがそのAPI/Stageに紐付いているか(`--api-stages`)
5. クォータを使い切っていないか(`GetUsage`で確認)

## 検証の流れ(このLabのスクリプト)

1. `01_create_api.sh`: `apiKeyRequired=true`のGETメソッドを持つREST APIを作成しprodへデプロイ
2. `02_create_key_and_call_before_link.sh`: APIキーを作成し、Usage Plan未紐付けの状態で呼び出す → **403を期待**
3. `03_create_usageplan_and_link.sh`: Usage Planを作成しStageに紐付け、`CreateUsagePlanKey`でキーを紐付ける
4. `04_verify_after_link.sh`: 再度呼び出す → **200を期待**。`GetUsage`でクォータ消費も確認
5. `05_delete_all.sh`: Usage Plan Key → Usage Plan → APIキー → REST APIの順で削除

> 実行環境にAWS認証情報が未設定のため、上記スクリプトは未実行(2026-07-28時点)。認証情報設定後に01→04の順で実行し、期待通りの403→200の遷移とGetUsageの結果を確認すること。
