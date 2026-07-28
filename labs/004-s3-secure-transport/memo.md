# S3の転送中/保管時暗号化 試験の判断基準

| 設問のキーワード | 答え |
| --- | --- |
| 転送中の暗号化を強制 | `aws:SecureTransport` 条件を使ったDenyポリシー（リソースベース） |
| 複数アカウント/複数プリンシパルに一律強制したい | リソースベースのポリシー（バケットポリシー等）。IAM側の個別設定ではない |
| 保管時の暗号化を強制 | `s3:x-amz-server-side-encryption` 条件でのDeny、またはバケットのデフォルト暗号化設定 |
| KMSキーポリシーの管轄 | そのキーでの暗号化/復号操作の可否。ネットワーク層は管轄外 |

## 転送中 vs 保管時で使う条件キーが違う

「転送中」と「保管時」で使う条件キーが違う点もセットで覚えておくと、類題に強くなる。

- 転送中: `aws:SecureTransport`
- 保管時: `s3:x-amz-server-side-encryption` / `s3:x-amz-server-side-encryption-aws-kms-key-id`
