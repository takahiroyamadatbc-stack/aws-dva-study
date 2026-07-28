# DEK（データキー）とエンベロープ暗号化

## 1. なぜDEKが必要か

KMSには2つの制約がある。

- `kms:Encrypt` / `kms:Decrypt` で直接暗号化できるのは **最大4KB** まで
- 大量データを毎回KMSに送るのは性能・コストの面で非現実的

そこで、鍵の管理はKMSに任せ、実際のデータ暗号化はローカルで行う。この分担方式を **エンベロープ暗号化** と呼び、ローカル暗号化に使う鍵が **DEK（Data Encryption Key）**。

```
KMSキー（CMK）  ─ 外に出ない。ARNで参照するのみ
     │
     │ GenerateDataKey
     ▼
DEK（平文）───────→ ローカルでデータを暗号化 → 使用後ただちに破棄
DEK（暗号化済み）──→ 暗号化データと一緒に保存
```

## 2. DEKを自分で扱う場面 / 扱わない場面

| 対象 | 使うAPI | DEKを意識するか |
|---|---|---|
| 4KB以下（パスワード、トークン、設定値） | `Encrypt` / `Decrypt` を直接 | 不要 |
| 4KB超（ファイル、DBレコード群、ログ） | `GenerateDataKey` → ローカル暗号化 | 必要 |
| S3 / DynamoDB / EBS / RDS のSSE | 自分では何も呼ばない | 不要（AWSが内部で実施） |

マネージドサービスのSSEは内部でエンベロープ暗号化をしているが、DEKの生成・破棄・保存はサービス側が行うため、利用者からは見えない。

### 自分でDEKを扱う代表的なケース

- **クライアントサイド暗号化**：AWSに渡す前に自分で暗号化する（AWS Encryption SDK等）
- **フィールドレベル暗号化**：テーブル全体のSSEとは別に、特定の属性だけ追加で暗号化する
- **AWS外への持ち出し**：暗号化データをオンプレ等に置く。復号にはKMSアクセスが必要
- **自前のバックアップ・アーカイブ処理**

## 3. API 3種

| API | 返るもの | 用途 |
|---|---|---|
| `GenerateDataKey` | 平文DEK + 暗号化DEK | 今すぐ暗号化する |
| `GenerateDataKeyWithoutPlaintext` | 暗号化DEKのみ | 後で使う／呼び出し側が平文を持ちたくない |
| `Decrypt` | 平文DEK | 復号時（暗号化DEKを渡す） |

- 対称鍵の場合、`Decrypt` に `--key-id` は不要（暗号文のブロブ内に鍵情報が含まれる）

## 4. 実装の鉄則

- **平文DEKは保存しない**。使用後は即座にメモリ・ディスクから消す
- **暗号化DEKは暗号化データの隣に保存してよい**（KMSキーへのアクセス権がなければ復号不可のため）
- **暗号化コンテキスト（Encryption Context）を付ける**

## 5. 暗号化コンテキスト（Encryption Context）

暗号化時に添えるキーと値のペア。

```bash
--encryption-context tenant=acme,table=users
```

### 性質

- 暗号化されない（平文のままメタデータとして保持される）
- AES-256-GCMのAAD（Additional Authenticated Data）として使われ、改ざん検知の対象になる
- 復号時は暗号化時と**完全に同じ**キー・値を渡す必要がある（過不足・変更があれば `InvalidCiphertextException`）
- 対称鍵では任意（付けるのがベストプラクティス）、**非対称鍵では概念自体が存在しない**（試験のひっかけ対象）

### 何のためにあるか

| 目的 | 内容 |
|---|---|
| 取り違え事故の防止 | 別テナント／別リソース用のDEKを誤って復号しようとした場合に失敗させる |
| 改ざん検知 | 暗号文とコンテキストの組み合わせが変えられていないかをGCMのAADで保証 |
| 監査証跡 | CloudTrailの`Encrypt`/`Decrypt`/`GenerateDataKey`イベントに平文で記録される |
| ポリシーの条件句 | `kms:EncryptionContext:<key>` でIAM/キーポリシーから制御できる |

### 誤解しやすい点

- 鍵導出には使われない（パスワードのソルトとは役割が異なる）
- 秘密情報を値に入れてはいけない（CloudTrailに平文で残る）
- 省略しても失敗する＝暗号文に埋め込まれているのではなく、呼び出し側が毎回正しく提示する必要がある

## 6. データキーキャッシング

同じDEKを一定回数・一定時間だけ再利用する仕組み（AWS Encryption SDK）。

- メリット：KMS呼び出し回数減 → コスト・レイテンシ改善
- トレードオフ：1つのDEKが守るデータ量が増える → 漏洩時の影響範囲が拡大

高スループット用途で検討する。

## 7. 試験でのキーワード対応

| 設問の語 | 対応する答え |
|---|---|
| 4KBを超えるデータを暗号化 | `GenerateDataKey` によるエンベロープ暗号化 |
| KMS呼び出し回数・コストを削減 | データキーキャッシング |
| 暗号化を後で行う／平文鍵を持ちたくない | `GenerateDataKeyWithoutPlaintext` |
| 復号時の意図しない取り違えを防ぐ | 暗号化コンテキスト |
| AWSにも平文を見せたくない | クライアントサイド暗号化 |
| 非対称鍵 + 暗号化コンテキスト | 誤り（非対称鍵では使えない） |

## 8. ハンズオン記録（labs/003-envelope-encryption/）

```bash
KEY_ID=$(aws kms create-key --description "dva-003 envelope" \
  --tags TagKey=Project,TagValue=dva-study \
  --query KeyMetadata.KeyId --output text)

# 4KB制限の確認（失敗することを確認）
dd if=/dev/urandom of=big.bin bs=1024 count=5
aws kms encrypt --key-id $KEY_ID --plaintext fileb://big.bin

# DEK生成
aws kms generate-data-key --key-id $KEY_ID --key-spec AES_256 \
  --encryption-context purpose=dva-lab > dek.json

jq -r .Plaintext      dek.json | base64 -d > dek.bin
jq -r .CiphertextBlob dek.json | base64 -d > dek.enc

# ローカル暗号化
dd if=/dev/urandom of=data.bin bs=1M count=10
openssl enc -aes-256-cbc -pbkdf2 -in data.bin -out data.enc -pass file:dek.bin

# 平文DEKを破棄
shred -u dek.bin dek.json

# 復号
aws kms decrypt --ciphertext-blob fileb://dek.enc \
  --encryption-context purpose=dva-lab \
  --query Plaintext --output text | base64 -d > dek2.bin
openssl enc -d -aes-256-cbc -pbkdf2 -in data.enc -out data2.bin -pass file:dek2.bin

cmp data.bin data2.bin && echo "一致：復元成功"
```

暗号化コンテキストを変えて復号を試すと `InvalidCiphertextException` になることを確認。

### 片付け

```bash
aws kms schedule-key-deletion --key-id $KEY_ID --pending-window-in-days 7
rm -f data.bin data.enc data2.bin dek.enc big.bin
```

## 一行結論

> KMSは4KB制限があるため、それを超えるデータはGenerateDataKeyでDEKを取得しローカルで暗号化する。平文DEKは即破棄し、暗号化DEKをデータと共に保存する。暗号化コンテキストは平文のAADで、取り違え防止・改ざん検知・監査証跡・ポリシー制御に使う（非対称鍵では使えない）。
