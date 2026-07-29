#!/bin/bash
set -e

PRIMARY_REGION="us-west-1"
REPLICA_REGION="us-east-1"
SECRET_NAME="dva-012-secretsmanager-replication"

echo "レプリカリージョンを削除(${REPLICA_REGION})..."
aws secretsmanager remove-region-from-replication \
  --region "$PRIMARY_REGION" \
  --secret-id "$SECRET_NAME" \
  --region-list "$REPLICA_REGION" || true

echo "プライマリシークレットを削除(即時・復旧不可)..."
aws secretsmanager delete-secret \
  --region "$PRIMARY_REGION" \
  --secret-id "$SECRET_NAME" \
  --force-delete-without-recovery || true

echo "KMSキーの削除をスケジュール(${REPLICA_REGION}、最短7日後)..."
KEY_ID=$(aws kms describe-key \
  --region "$REPLICA_REGION" \
  --key-id "alias/${SECRET_NAME}" \
  --query "KeyMetadata.KeyId" --output text 2>/dev/null || echo "")

if [ -n "$KEY_ID" ] && [ "$KEY_ID" != "None" ]; then
  aws kms delete-alias --region "$REPLICA_REGION" --alias-name "alias/${SECRET_NAME}" || true
  aws kms schedule-key-deletion \
    --region "$REPLICA_REGION" \
    --key-id "$KEY_ID" \
    --pending-window-in-days 7 || true
  echo "KMSキー削除スケジュール完了: $KEY_ID (7日後に削除。KMSキーは即時削除不可)"
fi

echo "片付け完了"
