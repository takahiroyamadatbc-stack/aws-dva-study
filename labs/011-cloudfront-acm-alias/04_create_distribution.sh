#!/bin/bash
set -e

: "${ROOT_DOMAIN:?ROOT_DOMAINを指定してください}"
SUBDOMAIN="${SUBDOMAIN:-dva011}"
FQDN="${SUBDOMAIN}.${ROOT_DOMAIN}"
NAME="dva-011-cloudfront-acm-alias"
API_REGION="us-east-2"

CERT_ARN=$(aws acm list-certificates \
  --region us-east-1 \
  --query "CertificateSummaryList[?DomainName=='${FQDN}'].CertificateArn | [0]" \
  --output text)

API_ID=$(aws apigateway get-rest-apis \
  --region "$API_REGION" \
  --query "items[?name=='${NAME}'].id | [0]" --output text)

if [ -z "$CERT_ARN" ] || [ "$CERT_ARN" == "None" ]; then
  echo "ISSUED状態の証明書が見つかりません。02_validate_certificate.shを先に完了させてください" >&2
  exit 1
fi
if [ -z "$API_ID" ] || [ "$API_ID" == "None" ]; then
  echo "API Gatewayが見つかりません。03_create_api.shを先に実行してください" >&2
  exit 1
fi

API_DOMAIN="${API_ID}.execute-api.${API_REGION}.amazonaws.com"

# マネージドポリシー: CachingDisabled(検証用にキャッシュさせない) / AllViewerExceptHostHeader
CACHE_POLICY_ID="4135ea2d-6df8-6558-b2c3-e2c8f7444e07"
ORIGIN_REQUEST_POLICY_ID="b689b0a8-53d0-40ab-baf2-68738e2966ac"

DIST_CONFIG=$(cat <<EOF
{
  "CallerReference": "${NAME}-$(date +%s)",
  "Comment": "${NAME}",
  "Enabled": true,
  "Aliases": { "Quantity": 1, "Items": ["${FQDN}"] },
  "Origins": {
    "Quantity": 1,
    "Items": [{
      "Id": "apigw-origin",
      "DomainName": "${API_DOMAIN}",
      "OriginPath": "/prod",
      "CustomOriginConfig": {
        "HTTPPort": 80,
        "HTTPSPort": 443,
        "OriginProtocolPolicy": "https-only",
        "OriginSslProtocols": { "Quantity": 1, "Items": ["TLSv1.2"] }
      }
    }]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "apigw-origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "CachePolicyId": "${CACHE_POLICY_ID}",
    "OriginRequestPolicyId": "${ORIGIN_REQUEST_POLICY_ID}",
    "AllowedMethods": {
      "Quantity": 7,
      "Items": ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"],
      "CachedMethods": { "Quantity": 2, "Items": ["GET", "HEAD"] }
    }
  },
  "ViewerCertificate": {
    "ACMCertificateArn": "${CERT_ARN}",
    "SSLSupportMethod": "sni-only",
    "MinimumProtocolVersion": "TLSv1.2_2021"
  },
  "PriceClass": "PriceClass_100"
}
EOF
)

echo "$DIST_CONFIG" > /tmp/dva-011-dist-config.json

RESULT=$(aws cloudfront create-distribution \
  --distribution-config file:///tmp/dva-011-dist-config.json)

DIST_ID=$(echo "$RESULT" | python -c "import sys,json;print(json.load(sys.stdin)['Distribution']['Id'])")
DIST_DOMAIN=$(echo "$RESULT" | python -c "import sys,json;print(json.load(sys.stdin)['Distribution']['DomainName'])")
DIST_ARN=$(echo "$RESULT" | python -c "import sys,json;print(json.load(sys.stdin)['Distribution']['ARN'])")

aws cloudfront tag-resource \
  --resource "$DIST_ARN" \
  --tags "Items=[{Key=Project,Value=dva-study},{Key=Name,Value=${NAME}}]"

echo "CloudFrontディストリビューション作成開始: $DIST_ID"
echo "ディストリビューションドメイン(Route 53エイリアスの向き先): $DIST_DOMAIN"
echo "デプロイ完了まで15〜20分程度かかります。続けて 05_create_alias_record.sh を実行してください"
