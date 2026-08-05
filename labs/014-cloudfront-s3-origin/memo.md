# CloudFront + S3オリジンのバケットポリシーと接続手順

誤答検証ではなく、CloudFrontがS3をオリジンにする際の定番構成(OAC + バケットポリシー)を横断的に整理しておくためのメモ。

## OAC(Origin Access Control) vs 旧OAI(Origin Access Identity)

| | OAC(現行推奨) | OAI(レガシー) |
| --- | --- | --- |
| 対応リージョン | 全リージョン(S3のリージョンに依存しない) | 一部制約あり |
| SSE-KMS暗号化されたオブジェクト | 対応 | 非対応 |
| 署名方式 | SigV4(常に) | 独自の署名方式 |
| AWSの位置づけ | 現在の推奨(新規はOAC一択) | 非推奨(既存構成の互換維持用) |

新規に組むなら常にOACを使う。DVA試験でOAIの選択肢が出てきたら「動くには動くが非推奨」という文脈で登場することが多い。

## バケットポリシーのサンプル

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowCloudFrontServicePrincipal",
    "Effect": "Allow",
    "Principal": { "Service": "cloudfront.amazonaws.com" },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::<bucket>/*",
    "Condition": {
      "StringEquals": { "AWS:SourceArn": "arn:aws:cloudfront::<account-id>:distribution/<distribution-id>" }
    }
  }]
}
```

- `Principal: cloudfront.amazonaws.com` **単体**では「同じAWSアカウント内の任意のCloudFrontディストリビューション」からの読み取りを許可してしまう(サービスプリンシパルはアカウント境界でしか絞れない)
- `Condition: AWS:SourceArn` で対象ディストリビューションのARNまで絞り込むことで、同一アカウント内の別ディストリビューション経由で読まれる「confused deputy」問題を防ぐ。**この2つはセットで使うのが正解**
- S3のBlock Public Accessは4項目すべてONのままでよい。OACはS3を公開せず、CloudFront(サービスプリンシパル)だけに許可する仕組みなので、バケットを公開する必要が一切ない

## 接続手順(このLabのスクリプトの流れ)

```
① S3バケット作成(Private, Block Public Access全ON)
        ↓
② OAC作成 → CloudFrontディストリビューション作成(オリジンにOACを紐付け)
        ↓         ※この時点でディストリビューションARNが確定する
③ バケットポリシー適用(②で確定したARNをConditionに指定)
        ↓
④ 動作確認(CloudFront経由=200 / S3直URL=403)
```

**順序に依存がある点が重要**: バケットポリシーのConditionにはディストリビューションARNが必要なため、③は②より後でないと組めない。IaC(CDK/CloudFormation)で組む場合はこの前後関係をフレームワーク側が解決してくれるが、CLIで手組みする場合は明示的に「ディストリビューション作成→ARN取得→ポリシー適用」の順で実行する必要がある。

## 試験で狙われやすい落とし穴

1. **OAC/OAIが使えるのはS3の「RESTエンドポイント」だけ**
   - `<bucket>.s3.<region>.amazonaws.com` (REST) → OAC/OAI対応
   - `<bucket>.s3-website-<region>.amazonaws.com` (静的website hosting) → OAC/OAI**非対応**。バケットを丸ごとパブリック読み取りにするしかない
   - 静的website hostingの機能(index/errorドキュメントのルーティング、リダイレクトルール)を使いたい場合は、OAC + REST originを諦めてバケットをpublicにするか、CloudFront Functions/Lambda@Edgeでルーティングを肩代わりしてREST originのままにするか、のトレードオフになる
2. **バケットポリシーは「後付け」になる**: ディストリビューション作成前にはARNが存在しないため、OAC作成→ディストリビューション作成→バケットポリシー適用、の順序を崩せない
3. **Principal単体では絞り込みが甘い**: `cloudfront.amazonaws.com`だけだと同一アカウント内の任意のディストリビューションから読める。`AWS:SourceArn`条件との併用が前提

## 結論

CloudFront+S3の定番構成は「OAC作成→ディストリビューション作成(ARN確定)→そのARNを`AWS:SourceArn`条件に指定したバケットポリシーを適用」という順序依存の3ステップ。OAI/パブリックバケットは非推奨で、S3側はBlock Public Accessを全ONにしたままCloudFrontサービスプリンシパル+ディストリビューションARN限定で許可するのが現行のベストプラクティス。ただしOAC/OAIはS3のRESTエンドポイントのみ対応で、静的website hostingエンドポイントをオリジンにする場合はそもそも使えない点は要注意。
