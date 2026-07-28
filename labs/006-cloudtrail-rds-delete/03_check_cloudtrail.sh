#!/bin/bash
set -e

DB_INSTANCE_ID="dva-006-cloudtrail-rds-delete"

echo "CloudTrailへの反映には数分のラグがあります。DeleteDBInstanceイベントが見つかるまでリトライします。"

for i in $(seq 1 10); do
  COUNT=$(aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=ResourceName,AttributeValue="$DB_INSTANCE_ID" \
    --query "length(Events[?EventName=='DeleteDBInstance'])" \
    --output text)

  if [ "$COUNT" != "0" ]; then
    echo "イベントが見つかりました。"
    break
  fi

  echo "($i/10) まだ見つかりません。30秒待って再試行します..."
  sleep 30
done

echo ""
echo "=== 実行者サマリ(EventTime / Username / EventName) ==="
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue="$DB_INSTANCE_ID" \
  --query "Events[?EventName=='DeleteDBInstance'].[EventTime,Username,EventName]" \
  --output table

echo ""
echo "=== イベント詳細(CloudTrailEvent全文。userIdentity/sourceIPAddress/accessKeyIdなどを含む) ==="
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue="$DB_INSTANCE_ID" \
  --query "Events[?EventName=='DeleteDBInstance']" \
  --output json
