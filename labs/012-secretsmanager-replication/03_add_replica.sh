#!/bin/bash
set -e

PRIMARY_REGION="us-west-1"
REPLICA_REGION="us-east-1"
SECRET_NAME="dva-012-secretsmanager-replication"

KEY_ID=$(aws kms describe-key \
  --region "$REPLICA_REGION" \
  --key-id "alias/${SECRET_NAME}" \
  --query "KeyMetadata.KeyId" --output text)

# 正解の選択肢どおり、既存シークレットに「レプリカリージョンを追加する」だけでよい。
# 新規シークレットの手動作成や、ローテーションルールとの関連付けは不要。
aws secretsmanager replicate-secret-to-regions \
  --region "$PRIMARY_REGION" \
  --secret-id "$SECRET_NAME" \
  --add-replica-regions "Region=${REPLICA_REGION},KmsKeyId=${KEY_ID}"

echo "レプリケーション設定完了: ${PRIMARY_REGION} -> ${REPLICA_REGION}"
echo "続けて 04_check_replication.sh を実行してください"
