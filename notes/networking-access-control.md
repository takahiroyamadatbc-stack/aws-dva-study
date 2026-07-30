# S3公開アクセス周り: OAC(CloudFront)とCORS(ブラウザ)の切り分け

「S3/CloudFront/API Gatewayが絡む配信・アクセス制御」の設問で毎回迷いやすいOACとCORSを、**エラーの発生元（AWS側の権限 or ブラウザ側の制約）**で切り分けるためのメモ。

## 一行結論

> 「S3 + CloudFront + 非公開バケット」を公開したい → **OAC**（サーバー間＝CloudFront→S3のアクセス制御）。
> 「JavaScriptからS3/APIを直接呼んだらブラウザにエラーが出た」→ **CORS**（クライアント＝ブラウザ側の制約）。

両者は問題領域が別（前者はAWSのリソースアクセス許可、後者はブラウザの同一オリジンポリシー）なので、設問中に「非公開バケットを公開したい」と「ブラウザでエラーが出る」のどちらが書かれているかを見れば機械的に判別できる。

## 1. OAC（Origin Access Control）: CloudFrontからS3への正規アクセス

| 項目 | 内容 |
|---|---|
| 何が困る場面か | S3バケットを非公開（パブリックアクセスブロック有効）のままCloudFront経由でのみ配信したい |
| 解決する層 | **AWSリソース間**（CloudFrontというプリンシパルがS3オブジェクトを取得できるか）のアクセス制御。ブラウザは関与しない |
| 仕組み | CloudFrontディストリビューションにOACを設定し、S3バケットポリシーで `Principal: cloudfront.amazonaws.com` ＋ `Condition: AWS:SourceArn`（対象ディストリビューションのARN）のみを許可する。ユーザーがS3のURLに直接アクセスしても403になり、CloudFront経由のみ200が返る |
| 旧方式との違い | OAI（Origin Access Identity）はレガシー。SSE-KMSで暗号化されたオブジェクトに非対応、S3のダイナミックオリジン（Lambda@Edge併用など）に非対応、といった制約があった。OACは全リージョン・全暗号化方式に対応する後継で、**現在はOACが推奨** |
| 典型的な誤答パターン | バケットポリシーで特定IPレンジやVPCエンドポイントを許可しようとする、あるいはバケットをパブリック読み取り可にしてしまう（非公開要件に反する） |

### バケットポリシー例（OAC用）

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::dva-example-bucket/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::123456789012:distribution/EXXXXXXXXXXXXX"
        }
      }
    }
  ]
}
```

## 2. CORS（Cross-Origin Resource Sharing）: ブラウザからの直接呼び出し

| 項目 | 内容 |
|---|---|
| 何が困る場面か | ブラウザ上のJavaScript（`fetch`/`XMLHttpRequest`）が、ページを配信しているオリジンとは異なるオリジンのS3/API Gateway/独自ドメインを呼び出し、コンソールに `blocked by CORS policy` 系のエラーが出る |
| 解決する層 | **ブラウザの同一オリジンポリシー**。サーバー側の権限（IAM/バケットポリシー）が正しくてもCORS設定が無ければブラウザ側で弾かれる。逆にIAM権限が無ければCORSを設定してもリクエスト自体は失敗する（両方揃って初めて成功） |
| 仕組み | リクエスト先（S3バケット／API Gateway）側で「どのオリジンからの、どのメソッド・ヘッダーのリクエストを許可するか」を設定する。ブラウザは実リクエストの前に `OPTIONS` メソッドでプリフライトリクエストを送り、許可レスポンスヘッダー（`Access-Control-Allow-Origin`等）を確認してから本リクエストを送る |
| S3の場合 | バケットに「CORS設定（CORSルール）」をJSON/XMLで追加。`AllowedOrigins` / `AllowedMethods` / `AllowedHeaders` 等を指定 |
| API Gatewayの場合 | REST APIは各リソースに `OPTIONS` メソッドを追加し `Access-Control-Allow-*` ヘッダーを返す（コンソールの「CORSの有効化」で自動生成可）。HTTP APIはCORS設定をAPIレベルで一括指定できる |
| 典型的な誤答パターン | 「ブラウザコンソールにCORSエラー」という記述を見て、IAMポリシーやバケットポリシー（OAC含む）を疑ってしまう。CORSエラーは**リクエストがサーバーに届く前にブラウザが止めている**ケースが多く、サーバー側の権限設定を直しても解決しない |

### S3バケットCORS設定例

```json
[
  {
    "AllowedOrigins": ["https://app.example.com"],
    "AllowedMethods": ["GET", "PUT"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3000
  }
]
```

## 3. 見分け方チェックリスト

| 設問の記述 | 疑うべき機能 |
|---|---|
| 「S3バケットを非公開にしたままCloudFrontだけからアクセスさせたい」 | OAC |
| 「S3の直接URLへのアクセスを403にしたい／CloudFront経由を強制したい」 | OAC |
| 「ブラウザの開発者ツールに `No 'Access-Control-Allow-Origin' header` と出る」 | CORS |
| 「SPA（シングルページアプリ）からS3/API Gatewayを直接fetchしている」 | CORS |
| 「サーバー間（Lambda→S3、EC2→S3等）でのアクセスエラー」 | CORS **ではない**（CORSはブラウザのみの制約。サーバー間通信ならIAM権限を疑う） |

## その他

- OACとCORSは併用されることもある（例: 非公開バケット＋CloudFront配信で、かつフロントエンドJSからCloudFront経由でAPIを叩く場合、CloudFront側のオリジンやAPI Gateway側にもCORS設定が要る）。「片方を設定すればもう片方は不要」ではない点に注意。
