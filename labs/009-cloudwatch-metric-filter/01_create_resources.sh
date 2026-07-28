#!/bin/bash
set -e

# 使い方: NOTIFY_EMAIL=you@example.com ./01_create_resources.sh
: "${NOTIFY_EMAIL:?環境変数 NOTIFY_EMAIL に通知先メールアドレスを設定してください}"

LOG_GROUP="/dva-009/cloudwatch-metric-filter"
LOG_STREAM="app-log-stream"
FILTER_NAME="dva-009-cloudwatch-metric-filter-error"
NAMESPACE="DvaStudy/009"
METRIC_NAME="ErrorCount"
TOPIC_NAME="dva-009-cloudwatch-metric-filter"
ALARM_NAME="dva-009-cloudwatch-metric-filter-alarm"

# 1. ロググループ・ログストリーム作成
aws logs create-log-group \
  --log-group-name "$LOG_GROUP" \
  --tags Project=dva-study

aws logs create-log-stream \
  --log-group-name "$LOG_GROUP" \
  --log-stream-name "$LOG_STREAM"

# 2. SNSトピック作成 + メール購読(確認メールのリンクをクリックするまでPendingのまま)
TOPIC_ARN=$(aws sns create-topic \
  --name "$TOPIC_NAME" \
  --tags Key=Project,Value=dva-study \
  --query 'TopicArn' --output text)

aws sns subscribe \
  --topic-arn "$TOPIC_ARN" \
  --protocol email \
  --notification-endpoint "$NOTIFY_EMAIL"

echo "SNS購読確認メールを $NOTIFY_EMAIL に送信しました。リンクをクリックして購読を確定してください。"

# 3. メトリクスフィルター作成(ログ内の"ERROR"文字列の出現回数を$METRIC_NAMEとして記録)
aws logs put-metric-filter \
  --log-group-name "$LOG_GROUP" \
  --filter-name "$FILTER_NAME" \
  --filter-pattern "ERROR" \
  --metric-transformations \
      metricName="$METRIC_NAME",metricNamespace="$NAMESPACE",metricValue=1,defaultValue=0

# 4. アラーム作成($METRIC_NAMEの合計が1以上になったらSNSトピックへ通知)
aws cloudwatch put-metric-alarm \
  --alarm-name "$ALARM_NAME" \
  --namespace "$NAMESPACE" \
  --metric-name "$METRIC_NAME" \
  --statistic Sum \
  --period 60 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$TOPIC_ARN" \
  --tags Key=Project,Value=dva-study

echo "作成完了: LogGroup=$LOG_GROUP, MetricFilter=$FILTER_NAME, Topic=$TOPIC_ARN, Alarm=$ALARM_NAME"
