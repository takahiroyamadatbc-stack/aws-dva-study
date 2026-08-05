#!/bin/bash
set -e

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="dva-014-cloudfront-s3-origin-${ACCOUNT_ID}"
NAME="dva-014-cloudfront-s3-origin"

DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='${NAME}'].Id | [0]" --output text)

if [ -z "$DIST_ID" ] || [ "$DIST_ID" == "None" ]; then
  echo "ディストリビューションが見つかりません。02_create_distribution.shを先に実行してください" >&2
  exit 1
fi

DIST_ARN="arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DIST_ID}"

# Principal(cloudfront.amazonaws.com)だけだと「同じAWSアカウント内の任意のCloudFrontディストリビューション」から
# 読めてしまう(confused deputy)。Condition(AWS:SourceArn)でこのディストリビューションだけに絞る。
POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowCloudFrontServicePrincipal",
    "Effect": "Allow",
    "Principal": { "Service": "cloudfront.amazonaws.com" },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::${BUCKET}/*",
    "Condition": {
      "StringEquals": { "AWS:SourceArn": "${DIST_ARN}" }
    }
  }]
}
EOF
)

echo "$POLICY" > /tmp/dva-014-bucket-policy.json

aws s3api put-bucket-policy \
  --bucket "$BUCKET" \
  --policy file:///tmp/dva-014-bucket-policy.json

echo "バケットポリシー適用完了: $BUCKET (Condition対象ディストリビューション: $DIST_ID)"
