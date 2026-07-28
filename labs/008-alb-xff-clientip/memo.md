# ALB配下でクライアントの実IPを扱う

## 1. なぜバックエンドからALBのIPしか見えないのか

ALBはL7で動作するリバースプロキシ。クライアント⇔ALB、ALB⇔ターゲット(EC2)は別々のTCPコネクションであり、EC2から見ると新規に接続してきたALBノードのIPしか送信元として見えない。クライアントの情報を失わないために、ALBはHTTPヘッダーに情報を積んで転送する。

```
クライアント ──TCP接続1─→ ALB ──TCP接続2─→ EC2(ターゲット)
  実IP: 203.0.113.10          EC2からのremote_addrは常にALBノードのIP
```

## 2. ALBが自動付与する主なヘッダー

| ヘッダー | 内容 |
|---|---|
| `X-Forwarded-For` | クライアントの実IP。複数プロキシを経由する場合はカンマ区切りで連結され、**先頭**が最初のクライアントIP |
| `X-Forwarded-Proto` | クライアントが実際に使ったプロトコル(`http`/`https`)。ALBでTLS終端している場合、バックエンドとの通信がHTTPでもこのヘッダーで元がHTTPSだったと分かる |
| `X-Forwarded-Port` | クライアントが接続してきた元のポート番号 |
| `X-Amzn-Trace-Id` | リクエストトレーシング用ID(X-Rayと連携可能) |

これらは**ヘッダーに載って渡ってくる情報**であり、HTTPサーバー(nginx/Apache/IIS)側のログ設定でヘッダー値をログに出力するよう指定するだけで記録できる。

## 3. HTTPサーバー側の設定例

| サーバー | 設定ファイル/ディレクティブ | 変数 |
|---|---|---|
| nginx | `log_format` + `access_log` | `$http_x_forwarded_for` |
| Apache | `LogFormat` | `%{X-Forwarded-For}i` |
| IIS | ログ記録のカスタムフィールド | `X-Forwarded-For` |

nginxの例(このLabの[`src/user_data.sh`](src/user_data.sh)で使用):

```nginx
log_format xff_log '$time_local remote_addr=$remote_addr x_forwarded_for=$http_x_forwarded_for request="$request"';
access_log /var/log/nginx/xff-access.log xff_log;
```

## 4. セキュリティ上の注意

- `X-Forwarded-For`はクライアントが任意の値を送りつけて偽装できる。ALB経由のリクエストであれば、ALBが受け取った時点のクライアントIPを**先頭に追加**した上で転送するが、クライアントが最初から偽の値をカンマ区切りで送っていた場合、ヘッダー全体を鵜呑みにすると偽装を許してしまう
- 対策としては、EC2側のセキュリティグループでALBのSGからの通信のみ許可する(このLabの`ec2-sg`のように)ことで「ALBを経由しない直接アクセス」自体を遮断し、ヘッダーの最後尾(=ALBが直接見た送信元IP)を信頼するのが基本

## 5. 誤答の選択肢が的外れな理由(整理)

| 選択肢 | 守備範囲 | なぜ的外れか |
|---|---|---|
| AWS X-Rayデーモン | 分散トレーシング(リクエストの経路・所要時間の可視化) | 任意のHTTPサーバーのログファイルに書き込む機能を持たない |
| CloudWatch Logsエージェント | 既存ログファイルをCloudWatch Logsへ収集・転送 | ログの内容を変更/追加する機能はなく、あくまで転送専用 |
| `Host`ヘッダー | リクエスト**先**(ドメイン名・ポート)を示す | 送信元(クライアント)の情報とは無関係 |

いずれも「ログの中身(どのフィールドを記録するか)を決めるのはHTTPサーバー自身の設定」という基本構造を無視した選択肢になっている。

## 6. 試験でのキーワード対応

| 設問の語 | 対応する答え |
|---|---|
| ALB配下でクライアントの実IPをログに残したい | HTTPサーバーの`log_format`/`LogFormat`に`X-Forwarded-For`を追加 |
| ALBでTLS終端後、元のプロトコルを知りたい | `X-Forwarded-Proto` |
| 複数プロキシ経由でクライアントIPを特定したい | `X-Forwarded-For`の**先頭**の値 |
| 「トラフィックを分析する」→ X-Rayを連想させるひっかけ | X-Rayはトレーシング専用でログ書き込み機能はない |
| ログ収集/転送サービスをログ加工に使おうとする選択肢 | 誤り(CloudWatch Logsエージェント等は転送専用) |

## 一行結論

> ALBはプロキシとして動作するため、バックエンドから見た送信元IPは常にALBのもの。クライアントの実IPは`X-Forwarded-For`ヘッダーに載って渡ってくるので、HTTPサーバー側のログ設定(`log_format`/`LogFormat`)でこのヘッダーを出力すればよい。X-RayやCloudWatch Logsエージェントはログの中身を追加・加工する機能を持たないため的外れ。
