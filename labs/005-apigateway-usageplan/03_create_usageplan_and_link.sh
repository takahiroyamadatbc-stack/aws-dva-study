API_ID=$(aws apigateway get-rest-apis \
  --query "items[?name=='dva-005-apigateway-usageplan'].id" --output text)
KEY_ID=$(aws apigateway get-api-keys \
  --name-query dva-005-apigateway-usageplan-key \
  --query 'items[0].id' --output text)

PLAN_ID=$(aws apigateway create-usage-plan \
  --name dva-005-apigateway-usageplan-plan \
  --api-stages apiId=$API_ID,stage=prod \
  --throttle burstLimit=5,rateLimit=2 \
  --quota limit=100,period=MONTH \
  --tags Project=dva-study \
  --query 'id' --output text)

aws apigateway create-usage-plan-key \
  --usage-plan-id $PLAN_ID \
  --key-id $KEY_ID \
  --key-type API_KEY

echo "PLAN_ID=$PLAN_ID"
