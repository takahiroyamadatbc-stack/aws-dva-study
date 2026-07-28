API_ID=$(aws apigateway get-rest-apis \
  --query "items[?name=='dva-005-apigateway-usageplan'].id" --output text)
REGION=$(aws configure get region)

KEY_ID=$(aws apigateway create-api-key \
  --name dva-005-apigateway-usageplan-key \
  --enabled \
  --tags Project=dva-study \
  --query 'id' --output text)

KEY_VALUE=$(aws apigateway get-api-key \
  --api-key $KEY_ID \
  --include-value \
  --query 'value' --output text)

echo "KEY_ID=$KEY_ID"
echo "使用量プラン未紐付けの状態で呼び出す(403が期待値)"
curl -s -o /dev/null -w "HTTPステータス: %{http_code}\n" \
  -H "x-api-key: $KEY_VALUE" \
  "https://$API_ID.execute-api.$REGION.amazonaws.com/prod/"
