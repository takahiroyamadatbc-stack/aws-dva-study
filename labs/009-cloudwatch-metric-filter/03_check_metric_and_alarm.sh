#!/bin/bash
set -e

NAMESPACE="DvaStudy/009"
METRIC_NAME="ErrorCount"
ALARM_NAME="dva-009-cloudwatch-metric-filter-alarm"

START_TIME=$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-10M +%Y-%m-%dT%H:%M:%S)
END_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)

echo "=== ErrorCount メトリクス(直近10分, 60秒粒度, Sum) ==="
aws cloudwatch get-metric-statistics \
  --namespace "$NAMESPACE" \
  --metric-name "$METRIC_NAME" \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --period 60 \
  --statistics Sum \
  --query "sort_by(Datapoints, &Timestamp)"

echo "=== アラーム状態 ==="
aws cloudwatch describe-alarms \
  --alarm-names "$ALARM_NAME" \
  --query "MetricAlarms[0].{State:StateValue,Reason:StateReason}"
