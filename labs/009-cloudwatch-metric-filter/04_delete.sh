#!/bin/bash
set -e

LOG_GROUP="/dva-009/cloudwatch-metric-filter"
FILTER_NAME="dva-009-cloudwatch-metric-filter-error"
TOPIC_NAME="dva-009-cloudwatch-metric-filter"
ALARM_NAME="dva-009-cloudwatch-metric-filter-alarm"

aws cloudwatch delete-alarms --alarm-names "$ALARM_NAME"

TOPIC_ARN=$(aws sns list-topics \
  --query "Topics[?ends_with(TopicArn, ':${TOPIC_NAME}')].TopicArn | [0]" --output text)
if [ "$TOPIC_ARN" != "None" ] && [ -n "$TOPIC_ARN" ]; then
  aws sns delete-topic --topic-arn "$TOPIC_ARN"
fi

aws logs delete-metric-filter \
  --log-group-name "$LOG_GROUP" \
  --filter-name "$FILTER_NAME"

aws logs delete-log-group --log-group-name "$LOG_GROUP"

echo "削除完了: $ALARM_NAME / $TOPIC_NAME / $FILTER_NAME / $LOG_GROUP"
