#!/bin/bash
set -e

FUNCTION_NAME="dva-007-kinesis-lambda-iteratorage"
END=$(date -u +%Y-%m-%dT%H:%M:%S)
START=$(date -u -d '-15 minutes' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-15M +%Y-%m-%dT%H:%M:%S)

echo "=== IteratorAge (ms, Maximum) : レコードがストリームに書き込まれてからLambdaが読むまでの滞留時間 ==="
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name IteratorAge \
  --dimensions Name=FunctionName,Value="$FUNCTION_NAME" \
  --start-time "$START" --end-time "$END" \
  --period 60 --statistics Maximum \
  --query "Datapoints | sort_by(@, &Timestamp)" --output table

echo "=== Duration (ms, Average) : 1回のLambda実行(1バッチ)にかかった時間 ==="
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value="$FUNCTION_NAME" \
  --start-time "$START" --end-time "$END" \
  --period 60 --statistics Average \
  --query "Datapoints | sort_by(@, &Timestamp)" --output table
