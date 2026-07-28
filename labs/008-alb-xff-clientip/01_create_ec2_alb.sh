#!/bin/bash
set -e

NAME="dva-008-alb-xff-clientip"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. デフォルトVPCと、異なるAZの2つのデフォルトサブネットを取得(ALBは最低2AZ必要)
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=is-default,Values=true" \
  --query "Vpcs[0].VpcId" --output text)

SUBNET_IDS=($(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=default-for-az,Values=true" \
  --query "Subnets[0:2].SubnetId" --output text))

# 2. セキュリティグループ(ALB用: 0.0.0.0/0から80番、EC2用: ALBからのみ80番)
ALB_SG_ID=$(aws ec2 create-security-group \
  --group-name "${NAME}-alb-sg" \
  --description "dva-008 ALB SG" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=dva-study},{Key=Name,Value=${NAME}-alb-sg}]" \
  --query "GroupId" --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$ALB_SG_ID" \
  --protocol tcp --port 80 --cidr 0.0.0.0/0 > /dev/null

EC2_SG_ID=$(aws ec2 create-security-group \
  --group-name "${NAME}-ec2-sg" \
  --description "dva-008 EC2 SG" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=dva-study},{Key=Name,Value=${NAME}-ec2-sg}]" \
  --query "GroupId" --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$EC2_SG_ID" \
  --protocol tcp --port 80 --source-group "$ALB_SG_ID" > /dev/null

# 3. EC2へのSSM接続用IAMロール(SSH鍵を使わずログを確認するため)
ROLE_NAME="${NAME}-ssm-role"
TRUST_POLICY=$(cat <<'EOF'
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

aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document "$TRUST_POLICY" \
  --tags Key=Project,Value=dva-study > /dev/null

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam create-instance-profile --instance-profile-name "$ROLE_NAME" > /dev/null
aws iam add-role-to-instance-profile \
  --instance-profile-name "$ROLE_NAME" \
  --role-name "$ROLE_NAME"

echo "IAMロール伝播待ち..."
sleep 10

# 4. EC2起動(最新のAmazon Linux 2023 AMIをSSMパラメータから取得)
AMI_ID=$(aws ssm get-parameters \
  --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query "Parameters[0].Value" --output text)

INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type t3.micro \
  --subnet-id "${SUBNET_IDS[0]}" \
  --security-group-ids "$EC2_SG_ID" \
  --iam-instance-profile "Name=${ROLE_NAME}" \
  --user-data "file://${SCRIPT_DIR}/src/user_data.sh" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Project,Value=dva-study},{Key=Name,Value=${NAME}}]" \
  --query "Instances[0].InstanceId" --output text)

echo "EC2起動待ち: $INSTANCE_ID"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

# 5. ターゲットグループ
TG_ARN=$(aws elbv2 create-target-group \
  --name "${NAME}-tg" \
  --protocol HTTP --port 80 \
  --vpc-id "$VPC_ID" \
  --target-type instance \
  --health-check-path / \
  --tags Key=Project,Value=dva-study \
  --query "TargetGroups[0].TargetGroupArn" --output text)

aws elbv2 register-targets \
  --target-group-arn "$TG_ARN" \
  --targets "Id=${INSTANCE_ID}"

# 6. ALB(internet-facing) + リスナー
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "${NAME}" \
  --subnets "${SUBNET_IDS[@]}" \
  --security-groups "$ALB_SG_ID" \
  --tags Key=Project,Value=dva-study \
  --query "LoadBalancers[0].LoadBalancerArn" --output text)

aws elbv2 create-listener \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP --port 80 \
  --default-actions "Type=forward,TargetGroupArn=${TG_ARN}" > /dev/null

echo "ALB作成待ち(active)..."
aws elbv2 wait load-balancer-available --load-balancer-arns "$ALB_ARN"

echo "ターゲットのヘルスチェック待ち(healthy)..."
aws elbv2 wait target-in-service --target-group-arn "$TG_ARN" --targets "Id=${INSTANCE_ID}"

ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" \
  --query "LoadBalancers[0].DNSName" --output text)

echo "作成完了: Instance=$INSTANCE_ID"
echo "ALB DNS: http://${ALB_DNS}/"
