#!/bin/bash
set -e

STREAM_NAME="dva-007-kinesis-lambda-iteratorage"
FUNCTION_NAME="dva-007-kinesis-lambda-iteratorage"
ROLE_NAME="dva-007-kinesis-lambda-iteratorage-role"

MAPPING_UUID=$(aws lambda list-event-source-mappings \
  --function-name "$FUNCTION_NAME" \
  --query "EventSourceMappings[0].UUID" --output text)

if [ "$MAPPING_UUID" != "None" ] && [ -n "$MAPPING_UUID" ]; then
  aws lambda delete-event-source-mapping --uuid "$MAPPING_UUID"
fi

aws lambda delete-function --function-name "$FUNCTION_NAME"

aws iam detach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole
aws iam delete-role --role-name "$ROLE_NAME"

aws kinesis delete-stream --stream-name "$STREAM_NAME" --enforce-consumer-deletion

echo "削除完了: $STREAM_NAME / $FUNCTION_NAME / $ROLE_NAME"
