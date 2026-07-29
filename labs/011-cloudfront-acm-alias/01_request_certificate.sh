#!/bin/bash
set -e

# 前提: ROOT_DOMAIN(例: example.com)がRoute 53のパブリックホストゾーンとして
# 自分のAWSアカウントに存在していること。HOSTED_ZONE_IDはそのゾーンID。
: "${ROOT_DOMAIN:?ROOT_DOMAIN(例: example.com)を指定してください}"
: "${HOSTED_ZONE_ID:?HOSTED_ZONE_ID(ROOT_DOMAINのRoute 53ホストゾーンID)を指定してください}"

SUBDOMAIN="${SUBDOMAIN:-dva011}"
FQDN="${SUBDOMAIN}.${ROOT_DOMAIN}"
NAME="dva-011-cloudfront-acm-alias"

# CloudFrontにアタッチする証明書は、API GatewayやCloudFrontの実体があるリージョンに関わらず
# 必ず us-east-1(バージニア北部) のACMにリクエストする
CERT_ARN=$(aws acm request-certificate \
  --region us-east-1 \
  --domain-name "$FQDN" \
  --validation-method DNS \
  --tags Key=Project,Value=dva-study Key=Name,Value="$NAME" \
  --query "CertificateArn" --output text)

echo "証明書リクエスト完了(us-east-1): $CERT_ARN"
echo "FQDN: $FQDN"
echo "続けて 02_validate_certificate.sh を実行してください"
