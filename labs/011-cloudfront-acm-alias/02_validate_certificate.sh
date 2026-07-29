#!/bin/bash
set -e

: "${ROOT_DOMAIN:?ROOT_DOMAINを指定してください}"
: "${HOSTED_ZONE_ID:?HOSTED_ZONE_IDを指定してください}"
SUBDOMAIN="${SUBDOMAIN:-dva011}"
FQDN="${SUBDOMAIN}.${ROOT_DOMAIN}"

CERT_ARN=$(aws acm list-certificates \
  --region us-east-1 \
  --query "CertificateSummaryList[?DomainName=='${FQDN}'].CertificateArn | [0]" \
  --output text)

if [ -z "$CERT_ARN" ] || [ "$CERT_ARN" == "None" ]; then
  echo "証明書が見つかりません。先に 01_request_certificate.sh を実行してください" >&2
  exit 1
fi

# DNS検証用のCNAMEレコード情報をACMから取得
VALIDATION_RECORD=$(aws acm describe-certificate \
  --region us-east-1 \
  --certificate-arn "$CERT_ARN" \
  --query "Certificate.DomainValidationOptions[0].ResourceRecord")

RECORD_NAME=$(echo "$VALIDATION_RECORD" | python -c "import sys,json;print(json.load(sys.stdin)['Name'])")
RECORD_VALUE=$(echo "$VALIDATION_RECORD" | python -c "import sys,json;print(json.load(sys.stdin)['Value'])")

echo "検証用CNAME: ${RECORD_NAME} -> ${RECORD_VALUE}"

CHANGE_BATCH=$(cat <<EOF
{
  "Changes": [{
    "Action": "UPSERT",
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
  --change-batch "$CHANGE_BATCH" > /dev/null

echo "検証用CNAMEを作成しました。ACMの検証完了を待機します(数分〜数十分かかる場合あり)..."
aws acm wait certificate-validated --region us-east-1 --certificate-arn "$CERT_ARN"
echo "証明書ISSUED: $CERT_ARN"
