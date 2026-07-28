API_ID=$(aws apigateway get-rest-apis \
  --query "items[?name=='dva-005-apigateway-usageplan'].id" --output text)
KEY_ID=$(aws apigateway get-api-keys \
  --name-query dva-005-apigateway-usageplan-key \
  --query 'items[0].id' --output text)
PLAN_ID=$(aws apigateway get-usage-plans \
  --query "items[?name=='dva-005-apigateway-usageplan-plan'].id" --output text)

aws apigateway delete-usage-plan-key --usage-plan-id $PLAN_ID --key-id $KEY_ID
aws apigateway delete-usage-plan --usage-plan-id $PLAN_ID
aws apigateway delete-api-key --api-key $KEY_ID
aws apigateway delete-rest-api --rest-api-id $API_ID

echo "削除完了"
