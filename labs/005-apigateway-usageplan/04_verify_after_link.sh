API_ID=$(aws apigateway get-rest-apis \
  --query "items[?name=='dva-005-apigateway-usageplan'].id" --output text)
REGION=$(aws configure get region)
KEY_ID=$(aws apigateway get-api-keys \
  --name-query dva-005-apigateway-usageplan-key \
  --query 'items[0].id' --output text)
KEY_VALUE=$(aws apigateway get-api-key \
  --api-key $KEY_ID \
  --include-value \
  --query 'value' --output text)
PLAN_ID=$(aws apigateway get-usage-plans \
  --query "items[?name=='dva-005-apigateway-usageplan-plan'].id" --output text)

echo "Usage Plan紐付け後に呼び出す(200が期待値)"
curl -s -o /dev/null -w "HTTPステータス: %{http_code}\n" \
  -H "x-api-key: $KEY_VALUE" \
  "https://$API_ID.execute-api.$REGION.amazonaws.com/prod/"

TODAY=$(date +%Y-%m-%d)
echo "クォータ消費状況:"
aws apigateway get-usage \
  --usage-plan-id $PLAN_ID \
  --key-id $KEY_ID \
  --start-date $TODAY \
  --end-date $TODAY
