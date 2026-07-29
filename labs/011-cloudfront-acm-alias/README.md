# 011 CloudFront + カスタムドメインのACM証明書リージョンとRoute 53エイリアス

## 問題

開発者は us-east-2 リージョンで Amazon API Gateway REST API を構築し、Amazon CloudFront とカスタムドメイン名を組み合わせて公開したいと考えている。カスタムドメイン用の SSL/TLS 証明書はサードパーティの認証局から取得済み。

最小限の手順で HTTPS を有効化し、CloudFront 経由でカスタムドメインを利用できる構成を選ぶ問題。

選択肢:
- 証明書を us-east-1 リージョンの AWS Certificate Manager (ACM) にインポートし、CloudFront ディストリビューションで証明書を関連付ける。そのうえで Route 53 で A (エイリアス) レコードを作成して CloudFront ドメインに向ける
- 証明書を API Gateway と同じリージョンの ACM にインポートし、Route 53 で通常の A レコードを作成して CloudFront ディストリビューションに向ける
- 証明書を CloudFront に直接アップロードし、カスタムドメイン用の DNS CNAME レコードを作成する
- 証明書を us-east-2 リージョンの ACM にインポートし、カスタムドメイン用の DNS CNAME レコードを作成する

正解: 「証明書を us-east-1 リージョンの ACM にインポートし、CloudFront ディストリビューションで証明書を関連付ける。そのうえで Route 53 で A (エイリアス) レコードを作成して CloudFront ドメインに向ける」

## 選んだ答えと理由

選んだ: 「証明書を us-east-2 リージョンの ACM にインポートし、カスタムドメイン用の DNS CNAME レコードを作成する」(不正解)

理由:
- 証明書は「利用するサービス(API Gateway)と同じリージョンに置くもの」だと判断し、問題文で明示されている us-east-2 を選んでしまった
- Aレコード(エイリアス)とCNAMEレコードの違いを意識できておらず、「カスタムドメインをCloudFrontに向ける = CNAMEを張る」という一般的なDNSの知識だけで選択肢を判断していた

## 誤答の型

1. **ACM証明書のリージョン要件の誤解**: 「証明書はサービスと同じリージョンに置く」という思い込みが先行し、CloudFrontが常にus-east-1のACM証明書しか参照できないというCloudFront固有のグローバル要件を見落とした。API Gatewayのリージョナルカスタムドメイン(CloudFrontを挟まない場合)であれば「同一リージョン」が正しいルールなので、このルールを別の文脈(CloudFront経由)にそのまま持ち込んでしまった
2. **AレコードとCNAMEレコードの用語の理解不足**: DNS標準のCNAME(ホスト名→ホスト名)と、Route 53独自拡張のAレコード(エイリアス)(AWSリソースへの論理参照)を区別できておらず、「CloudFrontへの誘導 = CNAME」という短絡的な連想で選択肢を評価した

## 仮説

- CloudFrontはグローバルサービスであり、エッジロケーションでTLS終端を行う都合上、証明書は常に単一のリージョン(us-east-1)のACMからのみ参照できるはず。API Gateway/S3オリジンなど背後のリソースがどのリージョンにあっても、この制約は変わらないはず
- Route 53のAレコード(エイリアス)は、IPアドレスではなくAWSリソース(CloudFrontディストリビューション、ALB、S3ウェブサイトなど)を直接指すRoute 53独自の仕組みで、名前解決時にRoute 53内部でCloudFrontのドメインを直接IPに解決する(CNAMEのような追加のDNSルックアップを挟まない)ため、zone apexにも使え追加料金もかからないはず
- 通常のCNAMEでCloudFrontドメインを指すこと自体は技術的に可能だが、CloudFrontのエッジIPが動的に変わる前提だと、CNAME自体は「名前解決の連鎖」でしかないため実害はない一方、zone apex(ルートドメイン)には使えないという制約がある

## 検証

> 実機デプロイは行っていない(標準ではコード整備までを完了条件とする方針。[CLAUDE.md](../../CLAUDE.md)「AWS実行について」参照)。以下はユーザーが実行を希望した場合の検証手順として設計したもの。実行には、自分のAWSアカウントにRoute 53のパブリックホストゾーン(`ROOT_DOMAIN`)を保有している必要がある。

1. [`01_request_certificate.sh`](01_request_certificate.sh): `us-east-1` のACMで `${SUBDOMAIN}.${ROOT_DOMAIN}` 宛の証明書をDNS検証方式でリクエストする(API Gatewayの構築先である`us-east-2`ではなく、常に`us-east-1`固定であることを確認するのが狙い)
2. [`02_validate_certificate.sh`](02_validate_certificate.sh): ACMが要求するDNS検証用CNAMEをRoute 53にUPSERTし、証明書が`ISSUED`になるまで待機する
3. [`03_create_api.sh`](03_create_api.sh): `us-east-2`にREGIONALエンドポイントのREST API(モック統合でGET 200を返すだけ)を作成し`prod`ステージにデプロイする。エッジ最適化(EDGE)ではなくREGIONALを選ぶ理由は、EDGEだとAPI Gateway自体が内部にCloudFrontを持ち、前段に置く自前のCloudFrontと二重構成になってしまうため
4. [`04_create_distribution.sh`](04_create_distribution.sh): API Gatewayのリージョナルドメインをオリジンに、`us-east-1`で発行した証明書をViewerCertificateに指定してCloudFrontディストリビューションを作成する(Aliasesに`${SUBDOMAIN}.${ROOT_DOMAIN}`を設定)
5. [`05_create_alias_record.sh`](05_create_alias_record.sh): Route 53に**Aレコード(エイリアス)**を作成し、CloudFrontディストリビューションのドメイン(固定のHostedZoneId `Z2FDTNDATAQYW2`)を直接指す。ディストリビューションのデプロイ完了(`Deployed`)まで待機する
6. [`06_check_https.sh`](06_check_https.sh): `dig`でAレコードの解決結果(CNAMEチェーンを挟まないこと)、`curl -v`でHTTPS接続時の証明書のsubject/issuerとHTTPステータスを確認する

期待する結果:
- `dig`の結果、`${SUBDOMAIN}.${ROOT_DOMAIN}`はCNAMEを経由せず直接IPアドレス(CloudFrontエッジのIP)が返る
- `curl -v`で、`us-east-1`で発行した証明書のsubject(`CN=${SUBDOMAIN}.${ROOT_DOMAIN}`)が提示され、HTTP 200が返る
- もし証明書を`us-east-2`のACMで作成しようとした場合、CloudFrontディストリビューション作成時(`ViewerCertificate`の関連付け)でエラーになり、そもそも構成が成立しない

## 結論(1行)

> CloudFrontに関連付けるACM証明書は、背後のAPI Gateway/オリジンのリージョンに関係なく常にus-east-1固定。Route 53でカスタムドメインをCloudFrontに向ける際は、IPを固定管理する通常のAレコードやDNS標準のCNAMEではなく、CloudFront側のIP変更に自動追従し追加料金もかからないAレコード(エイリアス)を使うのがベストプラクティス。

## 片付け

[`07_delete.sh`](07_delete.sh)で Route 53のAレコード(エイリアス) → CloudFrontディストリビューション(無効化→デプロイ待ち→削除) → API Gateway → Route 53の検証用CNAME → ACM証明書、の順に削除する。
