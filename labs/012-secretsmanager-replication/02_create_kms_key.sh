#!/bin/bash
set -e

REPLICA_REGION="us-east-1"
NAME="dva-012-secretsmanager-replication"

# レプリカ先(us-east-1)専用のカスタマー管理KMSキーを作成する。
# ソースリージョン(us-west-1)のキーを流用しない点がこのLabの検証ポイント。
KEY_ID=$(aws kms create-key \
  --region "$REPLICA_REGION" \
  --description "dva-study Lab012: ${REPLICA_REGION}でのSecrets Managerレプリカ暗号化用" \
  --tags TagKey=Project,TagValue=dva-study TagKey=Name,TagValue="$NAME" \
  --query "KeyMetadata.KeyId" --output text)

aws kms create-alias \
  --region "$REPLICA_REGION" \
  --alias-name "alias/${NAME}" \
  --target-key-id "$KEY_ID"

echo "KMSキー作成完了(${REPLICA_REGION}): $KEY_ID"
echo "エイリアス: alias/${NAME}"
echo "続けて 03_add_replica.sh を実行してください"
