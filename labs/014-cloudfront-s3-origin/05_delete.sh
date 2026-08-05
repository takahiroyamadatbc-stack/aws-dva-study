#!/bin/bash
set -e

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="dva-014-cloudfront-s3-origin-${ACCOUNT_ID}"
NAME="dva-014-cloudfront-s3-origin"

# 1. ディストリビューションを無効化→デプロイ待ち→削除(ETagが必要)
DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='${NAME}'].Id | [0]" --output text 2>/dev/null || echo "")

if [ -n "$DIST_ID" ] && [ "$DIST_ID" != "None" ]; then
  ETAG=$(aws cloudfront get-distribution-config --id "$DIST_ID" --query "ETag" --output text)
  CONFIG=$(aws cloudfront get-distribution-config --id "$DIST_ID" --query "DistributionConfig")
  echo "$CONFIG" | python -c "import sys,json; c=json.load(sys.stdin); c['Enabled']=False; print(json.dumps(c))" > /tmp/dva-014-dist-config-disable.json

  aws cloudfront update-distribution \
    --id "$DIST_ID" \
    --distribution-config file:///tmp/dva-014-dist-config-disable.json \
    --if-match "$ETAG" > /dev/null

  echo "ディストリビューション無効化待ち..."
  aws cloudfront wait distribution-deployed --id "$DIST_ID"

  ETAG=$(aws cloudfront get-distribution-config --id "$DIST_ID" --query "ETag" --output text)
  aws cloudfront delete-distribution --id "$DIST_ID" --if-match "$ETAG"
  echo "CloudFrontディストリビューション削除完了"
fi

# 2. OACを削除
OAC_ID=$(aws cloudfront list-origin-access-controls \
  --query "OriginAccessControlList.Items[?Name=='${NAME}'].Id | [0]" --output text 2>/dev/null || echo "")

if [ -n "$OAC_ID" ] && [ "$OAC_ID" != "None" ]; then
  OAC_ETAG=$(aws cloudfront get-origin-access-control --id "$OAC_ID" --query "ETag" --output text)
  aws cloudfront delete-origin-access-control --id "$OAC_ID" --if-match "$OAC_ETAG"
  echo "OAC削除完了: $OAC_ID"
fi

# 3. S3バケットのオブジェクト・ポリシーごと削除
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  aws s3 rm "s3://${BUCKET}" --recursive
  aws s3api delete-bucket --bucket "$BUCKET"
  echo "S3バケット削除完了: $BUCKET"
fi

echo "片付け完了"
