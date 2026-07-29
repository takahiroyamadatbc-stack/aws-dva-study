#!/bin/bash
set -e

NAME="dva-010-imagebuilder-codedeploy"
ROLE_BUILD="${NAME}-build-role"
ROLE_APP="${NAME}-app-role"
ROLE_CODEDEPLOY="${NAME}-codedeploy-service-role"

EC2_TRUST_POLICY=$(cat <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF
)

CODEDEPLOY_TRUST_POLICY=$(cat <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "codedeploy.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF
)

# 1. Image Builderのビルド/テスト用インスタンスが引き受けるロール
aws iam create-role \
  --role-name "$ROLE_BUILD" \
  --assume-role-policy-document "$EC2_TRUST_POLICY" \
  --tags Key=Project,Value=dva-study > /dev/null

aws iam attach-role-policy \
  --role-name "$ROLE_BUILD" \
  --policy-arn arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder
aws iam attach-role-policy \
  --role-name "$ROLE_BUILD" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam create-instance-profile --instance-profile-name "$ROLE_BUILD" > /dev/null
aws iam add-role-to-instance-profile \
  --instance-profile-name "$ROLE_BUILD" --role-name "$ROLE_BUILD"

# 2. Auto Scalingで起動するアプリ用インスタンスが引き受けるロール
#    (CodeDeployエージェントがリビジョン取得のためS3を読む + SSM管理用)
aws iam create-role \
  --role-name "$ROLE_APP" \
  --assume-role-policy-document "$EC2_TRUST_POLICY" \
  --tags Key=Project,Value=dva-study > /dev/null

aws iam attach-role-policy \
  --role-name "$ROLE_APP" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
# 本来はリビジョン用S3バケットに絞ったポリシーにすべきだが、使い捨てLabなので簡略化
aws iam attach-role-policy \
  --role-name "$ROLE_APP" \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess

aws iam create-instance-profile --instance-profile-name "$ROLE_APP" > /dev/null
aws iam add-role-to-instance-profile \
  --instance-profile-name "$ROLE_APP" --role-name "$ROLE_APP"

# 3. CodeDeployサービス自体が引き受けるロール(ASG連携・EC2操作用)
aws iam create-role \
  --role-name "$ROLE_CODEDEPLOY" \
  --assume-role-policy-document "$CODEDEPLOY_TRUST_POLICY" \
  --tags Key=Project,Value=dva-study > /dev/null

aws iam attach-role-policy \
  --role-name "$ROLE_CODEDEPLOY" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole

echo "IAMロール伝播待ち..."
sleep 10

echo "作成完了: $ROLE_BUILD / $ROLE_APP / $ROLE_CODEDEPLOY"
