#!/bin/bash
set -e

STREAM_NAME="dva-007-kinesis-lambda-iteratorage"
FUNCTION_NAME="dva-007-kinesis-lambda-iteratorage"
ROLE_NAME="dva-007-kinesis-lambda-iteratorage-role"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. Kinesis Data Stream(初期シャード数1。意図的に処理が追いつかない状態を作る)
aws kinesis create-stream \
  --stream-name "$STREAM_NAME" \
  --shard-count 1

aws kinesis wait stream-exists --stream-name "$STREAM_NAME"

aws kinesis add-tags-to-stream \
  --stream-name "$STREAM_NAME" \
  --tags Project=dva-study

# 2. Lambda実行ロール
TRUST_POLICY=$(cat <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF
)

aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document "$TRUST_POLICY" \
  --tags Key=Project,Value=dva-study

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole

echo "IAMロール伝播待ち..."
sleep 10

# 3. Lambda関数(0.2秒/レコードのsleepで処理が遅い状態を模擬、メモリは意図的に小さい128MB)
cd "$SCRIPT_DIR/src"
zip -q function.zip handler.py
cd - > /dev/null

aws lambda create-function \
  --function-name "$FUNCTION_NAME" \
  --runtime python3.12 \
  --role "arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}" \
  --handler handler.handler \
  --zip-file "fileb://${SCRIPT_DIR}/src/function.zip" \
  --memory-size 128 \
  --timeout 60 \
  --tags Project=dva-study

aws lambda wait function-active --function-name "$FUNCTION_NAME"

# 4. Event Source Mapping(Kinesis -> Lambda)
STREAM_ARN=$(aws kinesis describe-stream \
  --stream-name "$STREAM_NAME" \
  --query "StreamDescription.StreamARN" --output text)

aws lambda create-event-source-mapping \
  --function-name "$FUNCTION_NAME" \
  --event-source-arn "$STREAM_ARN" \
  --batch-size 100 \
  --starting-position LATEST

echo "作成完了: Stream=$STREAM_NAME (shard=1), Function=$FUNCTION_NAME (memory=128MB)"
