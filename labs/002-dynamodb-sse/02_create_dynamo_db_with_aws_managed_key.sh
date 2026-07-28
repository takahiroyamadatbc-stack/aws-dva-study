aws dynamodb create-table \
  --table-name dva-002-managed \
  --attribute-definitions AttributeName=pk,AttributeType=S \
  --key-schema AttributeName=pk,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --sse-specification Enabled=true,SSEType=KMS \
  --tags Key=Project,Value=dva-study