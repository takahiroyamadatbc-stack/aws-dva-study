#!/bin/bash
set -e

: "${ROOT_DOMAIN:?ROOT_DOMAINを指定してください}"
: "${HOSTED_ZONE_ID:?HOSTED_ZONE_IDを指定してください}"
SUBDOMAIN="${SUBDOMAIN:-dva011}"
FQDN="${SUBDOMAIN}.${ROOT_DOMAIN}"
NAME="dva-011-cloudfront-acm-alias"

DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='${NAME}'].Id | [0]" --output text)

if [ -z "$DIST_ID" ] || [ "$DIST_ID" == "None" ]; then
  echo "ディストリビューションが見つかりません。04_create_distribution.shを先に実行してください" >&2
  exit 1
fi

DIST_DOMAIN=$(aws cloudfront get-distribution \
  --id "$DIST_ID" --query "Distribution.DomainName" --output text)

# CloudFrontのAliasTarget用HostedZoneIdは全ディストリビューション共通の固定値
CLOUDFRONT_HOSTED_ZONE_ID="Z2FDTNDATAQYW2"

CHANGE_BATCH=$(cat <<EOF
{
  "Changes": [{
    "Action": "UPSERT",
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
  --change-batch "$CHANGE_BATCH" > /dev/null

echo "Aレコード(エイリアス)作成: ${FQDN} -> ${DIST_DOMAIN}"
echo "IPを指定する通常のAレコードやCNAMEと違い、CloudFront側のIP変更にも自動追従する"
echo ""
echo "ディストリビューションのデプロイ完了を待機します(15〜20分程度)..."
aws cloudfront wait distribution-deployed --id "$DIST_ID"
echo "デプロイ完了。続けて 06_check_https.sh で疎通確認できます"
