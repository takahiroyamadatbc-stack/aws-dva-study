#!/bin/bash
set -e

REGION="${AWS_REGION:-ap-northeast-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="dva-014-cloudfront-s3-origin-${ACCOUNT_ID}"
NAME="dva-014-cloudfront-s3-origin"

DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='${NAME}'].Id | [0]" --output text)

if [ -z "$DIST_ID" ] || [ "$DIST_ID" == "None" ]; then
  echo "ディストリビューションが見つかりません。02_create_distribution.shを先に実行してください" >&2
  exit 1
fi

DIST_DOMAIN=$(aws cloudfront get-distribution --id "$DIST_ID" --query "Distribution.DomainName" --output text)

echo "ディストリビューションのデプロイ完了を待機中(最大15分程度)..."
aws cloudfront wait distribution-deployed --id "$DIST_ID"

echo "--- CloudFront経由アクセス(200が期待値) ---"
curl -sS -o /dev/null -w "HTTP %{http_code}\n" "https://${DIST_DOMAIN}/index.html"

echo "--- S3直URLへのアクセス(バケットポリシーによりCloudFront以外は拒否されるため403が期待値) ---"
curl -sS -o /dev/null -w "HTTP %{http_code}\n" "https://${BUCKET}.s3.${REGION}.amazonaws.com/index.html"
