#!/bin/bash
set -e

NAME="dva-011-cloudfront-acm-alias"
API_REGION="us-east-2"

# 問題文の前提どおりus-east-2でREST APIを構築する(リージョナルエンドポイント)。
# エッジ最適化(EDGE)にするとAPI Gateway自体が内部でCloudFrontを持ってしまい、
# 前段に置く自前のCloudFrontと二重構成になるためREGIONALを選ぶ。
API_ID=$(aws apigateway create-rest-api \
  --region "$API_REGION" \
  --name "$NAME" \
  --endpoint-configuration types=REGIONAL \
  --tags Project=dva-study,Name="$NAME" \
  --query "id" --output text)

ROOT_RESOURCE_ID=$(aws apigateway get-resources \
  --region "$API_REGION" \
  --rest-api-id "$API_ID" \
  --query "items[?path=='/'].id | [0]" --output text)

# ルートパスにGET+モック統合(Lambda等を使わず最小構成でHTTP 200を返すだけ)
aws apigateway put-method \
  --region "$API_REGION" \
  --rest-api-id "$API_ID" \
  --resource-id "$ROOT_RESOURCE_ID" \
  --http-method GET \
  --authorization-type NONE > /dev/null

aws apigateway put-integration \
  --region "$API_REGION" \
  --rest-api-id "$API_ID" \
  --resource-id "$ROOT_RESOURCE_ID" \
  --http-method GET \
  --type MOCK \
  --request-templates '{"application/json": "{\"statusCode\": 200}"}' > /dev/null

aws apigateway put-method-response \
  --region "$API_REGION" \
  --rest-api-id "$API_ID" \
  --resource-id "$ROOT_RESOURCE_ID" \
  --http-method GET \
  --status-code 200 > /dev/null

aws apigateway put-integration-response \
  --region "$API_REGION" \
  --rest-api-id "$API_ID" \
  --resource-id "$ROOT_RESOURCE_ID" \
  --http-method GET \
  --status-code 200 \
  --response-templates '{"application/json": "{\"message\": \"hello from dva-011\"}"}' > /dev/null

aws apigateway create-deployment \
  --region "$API_REGION" \
  --rest-api-id "$API_ID" \
  --stage-name prod > /dev/null

API_DOMAIN="${API_ID}.execute-api.${API_REGION}.amazonaws.com"

echo "API作成完了: $API_ID"
echo "リージョナルドメイン(CloudFrontのオリジンに使う): $API_DOMAIN"
echo "直接確認: https://${API_DOMAIN}/prod"
