#!/bin/bash
set -e

REGION="${AWS_REGION:-ap-northeast-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="dva-014-cloudfront-s3-origin-${ACCOUNT_ID}"

if [ "$REGION" == "us-east-1" ]; then
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION"
else
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
fi

aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-tagging \
  --bucket "$BUCKET" \
  --tagging 'TagSet=[{Key=Project,Value=dva-study}]'

aws s3 cp src/index.html "s3://${BUCKET}/index.html"

echo "バケット作成完了: $BUCKET (region=$REGION)"
