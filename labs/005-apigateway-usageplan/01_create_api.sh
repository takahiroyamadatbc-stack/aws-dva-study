API_ID=$(aws apigateway create-rest-api \
  --name dva-005-apigateway-usageplan \
  --tags Project=dva-study \
  --query 'id' --output text)

ROOT_ID=$(aws apigateway get-resources \
  --rest-api-id $API_ID \
  --query 'items[0].id' --output text)

aws apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $ROOT_ID \
  --http-method GET \
  --authorization-type NONE \
  --api-key-required

aws apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $ROOT_ID \
  --http-method GET \
  --type MOCK \
  --request-templates '{"application/json":"{\"statusCode\": 200}"}'

aws apigateway put-method-response \
  --rest-api-id $API_ID \
  --resource-id $ROOT_ID \
  --http-method GET \
  --status-code 200

aws apigateway put-integration-response \
  --rest-api-id $API_ID \
  --resource-id $ROOT_ID \
  --http-method GET \
  --status-code 200 \
  --response-templates '{"application/json":"{\"message\": \"ok\"}"}'

aws apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name prod

echo "API_ID=$API_ID"
