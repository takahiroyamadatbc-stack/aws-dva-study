#!/bin/bash
set -e

: "${ROOT_DOMAIN:?ROOT_DOMAINを指定してください}"
: "${HOSTED_ZONE_ID:?HOSTED_ZONE_IDを指定してください}"
SUBDOMAIN="${SUBDOMAIN:-dva011}"
FQDN="${SUBDOMAIN}.${ROOT_DOMAIN}"
NAME="dva-011-cloudfront-acm-alias"
API_REGION="us-east-2"
CLOUDFRONT_HOSTED_ZONE_ID="Z2FDTNDATAQYW2"

# 1. Route 53のAレコード(エイリアス)を削除
DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='${NAME}'].Id | [0]" --output text 2>/dev/null || echo "")

if [ -n "$DIST_ID" ] && [ "$DIST_ID" != "None" ]; then
  DIST_DOMAIN=$(aws cloudfront get-distribution --id "$DIST_ID" --query "Distribution.DomainName" --output text)

  CHANGE_BATCH=$(cat <<EOF
{
  "Changes": [{
    "Action": "DELETE",
    "ResourceRecordSet": {
      "Name": "${FQDN}",
      "Type": "A",
      "AliasTarget": {
        "HostedZoneId": "${CLOUDFRONT_HOSTED_ZONE_ID}",
        "DNSName": "${DIST_DOMAIN}",
        "EvaluateTargetHealth": false
      }
    }
  }]
}
EOF
  )
  aws route53 change-resource-record-sets \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --change-batch "$CHANGE_BATCH" > /dev/null 2>&1 || true
  echo "Aレコード(エイリアス)削除"

  # 2. CloudFrontディストリビューションを無効化してから削除(ETagが必要)
  ETAG=$(aws cloudfront get-distribution-config --id "$DIST_ID" --query "ETag" --output text)
  CONFIG=$(aws cloudfront get-distribution-config --id "$DIST_ID" --query "DistributionConfig")
  echo "$CONFIG" | python -c "import sys,json; c=json.load(sys.stdin); c['Enabled']=False; print(json.dumps(c))" > /tmp/dva-011-dist-config-disable.json

  aws cloudfront update-distribution \
    --id "$DIST_ID" \
    --distribution-config file:///tmp/dva-011-dist-config-disable.json \
    --if-match "$ETAG" > /dev/null

  echo "ディストリビューション無効化待ち..."
  aws cloudfront wait distribution-deployed --id "$DIST_ID"

  ETAG=$(aws cloudfront get-distribution-config --id "$DIST_ID" --query "ETag" --output text)
  aws cloudfront delete-distribution --id "$DIST_ID" --if-match "$ETAG"
  echo "CloudFrontディストリビューション削除完了"
fi

# 3. API Gatewayを削除
API_ID=$(aws apigateway get-rest-apis \
  --region "$API_REGION" \
  --query "items[?name=='${NAME}'].id | [0]" --output text 2>/dev/null || echo "")

if [ -n "$API_ID" ] && [ "$API_ID" != "None" ]; then
  aws apigateway delete-rest-api --region "$API_REGION" --rest-api-id "$API_ID"
  echo "API Gateway削除完了: $API_ID"
fi

# 4. ACM証明書とDNS検証用CNAMEを削除(us-east-1)
CERT_ARN=$(aws acm list-certificates \
  --region us-east-1 \
  --query "CertificateSummaryList[?DomainName=='${FQDN}'].CertificateArn | [0]" \
  --output text 2>/dev/null || echo "")

if [ -n "$CERT_ARN" ] && [ "$CERT_ARN" != "None" ]; then
  VALIDATION_RECORD=$(aws acm describe-certificate \
    --region us-east-1 \
    --certificate-arn "$CERT_ARN" \
    --query "Certificate.DomainValidationOptions[0].ResourceRecord" 2>/dev/null || echo "")

  if [ -n "$VALIDATION_RECORD" ] && [ "$VALIDATION_RECORD" != "None" ]; then
    RECORD_NAME=$(echo "$VALIDATION_RECORD" | python -c "import sys,json;print(json.load(sys.stdin)['Name'])")
    RECORD_VALUE=$(echo "$VALIDATION_RECORD" | python -c "import sys,json;print(json.load(sys.stdin)['Value'])")

    CHANGE_BATCH=$(cat <<EOF
{
  "Changes": [{
    "Action": "DELETE",
    "ResourceRecordSet": {
      "Name": "${RECORD_NAME}",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{"Value": "${RECORD_VALUE}"}]
    }
  }]
}
EOF
    )
    aws route53 change-resource-record-sets \
      --hosted-zone-id "$HOSTED_ZONE_ID" \
      --change-batch "$CHANGE_BATCH" > /dev/null 2>&1 || true
    echo "検証用CNAME削除"
  fi

  aws acm delete-certificate --region us-east-1 --certificate-arn "$CERT_ARN"
  echo "ACM証明書削除完了"
fi

echo "片付け完了"
