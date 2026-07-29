#!/bin/bash
set -e

PRIMARY_REGION="us-west-1"
REPLICA_REGION="us-east-1"
SECRET_NAME="dva-012-secretsmanager-replication"

echo "=== プライマリ側のレプリケーションステータス(us-west-1) ==="
aws secretsmanager describe-secret \
  --region "$PRIMARY_REGION" \
  --secret-id "$SECRET_NAME" \
  --query "{ARN:ARN,ReplicationStatus:ReplicationStatus}"

echo
echo "=== レプリカ側から値を読み取れることを確認(us-east-1) ==="
aws secretsmanager get-secret-value \
  --region "$REPLICA_REGION" \
  --secret-id "$SECRET_NAME" \
  --query "SecretString" --output text

echo
echo "=== レプリカは読み取り専用であることを確認(us-east-1への直接書き込みは失敗するはず) ==="
aws secretsmanager put-secret-value \
  --region "$REPLICA_REGION" \
  --secret-id "$SECRET_NAME" \
  --secret-string '{"username":"app_user","password":"ShouldFail123!"}' \
  && echo "想定外: レプリカへの直接書き込みが成功してしまった" \
  || echo "想定通り: レプリカへの直接書き込みは失敗する(更新はプライマリ側でのみ可能)"

echo
echo "=== プライマリを更新するとレプリカへ自動同期されることを確認(us-west-1) ==="
aws secretsmanager put-secret-value \
  --region "$PRIMARY_REGION" \
  --secret-id "$SECRET_NAME" \
  --secret-string '{"username":"app_user","password":"Rotated456!"}' > /dev/null
echo "プライマリを更新。数秒〜数十秒待って、レプリカ側(${REPLICA_REGION})の値が" \
     "'Rotated456!' に自動同期されることを get-secret-value で再確認する"
