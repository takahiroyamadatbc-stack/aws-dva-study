#!/bin/bash
set -e

REGION="${AWS_REGION:-ap-northeast-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="dva-014-cloudfront-s3-origin-${ACCOUNT_ID}"
NAME="dva-014-cloudfront-s3-origin"
# S3のRESTエンドポイント(OAC/OAIが使えるのはこちら。静的website hostingエンドポイントでは使えない)
ORIGIN_DOMAIN="${BUCKET}.s3.${REGION}.amazonaws.com"

# 1. Origin Access Control(OAC)を作成
OAC_ID=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config \
    Name="${NAME}",SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=s3 \
  --query "OriginAccessControl.Id" --output text)

echo "OAC作成完了: $OAC_ID"

# 2. マネージドキャッシュポリシー: CachingOptimized
CACHE_POLICY_ID="658327ea-f89d-4fab-a63d-7e88639e58f6"

DIST_CONFIG=$(cat <<EOF
{
  "CallerReference": "${NAME}-$(date +%s)",
  "Comment": "${NAME}",
  "Enabled": true,
  "DefaultRootObject": "index.html",
  "Origins": {
    "Quantity": 1,
    "Items": [{
      "Id": "s3-origin",
      "DomainName": "${ORIGIN_DOMAIN}",
      "OriginAccessControlId": "${OAC_ID}",
      "S3OriginConfig": { "OriginAccessIdentity": "" }
    }]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "s3-origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "CachePolicyId": "${CACHE_POLICY_ID}",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"],
      "CachedMethods": { "Quantity": 2, "Items": ["GET", "HEAD"] }
    }
  },
  "PriceClass": "PriceClass_100"
}
EOF
)

echo "$DIST_CONFIG" > /tmp/dva-014-dist-config.json

RESULT=$(aws cloudfront create-distribution \
  --distribution-config file:///tmp/dva-014-dist-config.json)

DIST_ID=$(echo "$RESULT" | python -c "import sys,json;print(json.load(sys.stdin)['Distribution']['Id'])")
DIST_DOMAIN=$(echo "$RESULT" | python -c "import sys,json;print(json.load(sys.stdin)['Distribution']['DomainName'])")
DIST_ARN=$(echo "$RESULT" | python -c "import sys,json;print(json.load(sys.stdin)['Distribution']['ARN'])")

aws cloudfront tag-resource \
  --resource "$DIST_ARN" \
  --tags "Items=[{Key=Project,Value=dva-study},{Key=Name,Value=${NAME}}]"

echo "CloudFrontディストリビューション作成開始: $DIST_ID"
echo "ディストリビューションドメイン: https://${DIST_DOMAIN}"
echo "デプロイ完了まで10〜15分程度かかります。続けて 03_apply_bucket_policy.sh を実行してください"
echo "(この時点ではまだバケットポリシー未適用のため、S3への直アクセスもCloudFront経由アクセスもどちらも403/AccessDeniedになる)"
