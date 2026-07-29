#!/bin/bash
set -e

: "${ROOT_DOMAIN:?ROOT_DOMAINを指定してください}"
SUBDOMAIN="${SUBDOMAIN:-dva011}"
FQDN="${SUBDOMAIN}.${ROOT_DOMAIN}"

echo "=== dig: エイリアスレコードの解決結果(CNAMEチェーンを挟まずCloudFrontのIPが直接返る) ==="
dig +short "$FQDN"

echo ""
echo "=== curl: カスタムドメイン経由でのHTTPS疎通確認 ==="
curl -sv "https://${FQDN}/" -o /dev/null 2>&1 | grep -E "subject:|issuer:|HTTP/"

echo ""
echo "期待する結果: 証明書のsubject/issuerがus-east-1で発行したものと一致し、HTTP 200が返ること"
