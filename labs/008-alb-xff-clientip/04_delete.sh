#!/bin/bash
set -e

NAME="dva-008-alb-xff-clientip"
ROLE_NAME="${NAME}-ssm-role"

VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=is-default,Values=true" \
  --query "Vpcs[0].VpcId" --output text)

# 1. ALBとリスナーを削除
ALB_ARN=$(aws elbv2 describe-load-balancers --names "$NAME" \
  --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null || echo "")

if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
  echo "ALB削除待ち..."
  aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN"
fi

# 2. ターゲットグループを削除
TG_ARN=$(aws elbv2 describe-target-groups --names "${NAME}-tg" \
  --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null || echo "")

if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
  aws elbv2 delete-target-group --target-group-arn "$TG_ARN"
fi

# 3. EC2インスタンスを削除
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${NAME}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query "Reservations[0].Instances[0].InstanceId" --output text 2>/dev/null || echo "")

if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" > /dev/null
  echo "EC2削除待ち: $INSTANCE_ID"
  aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
fi

# 4. IAMロール/インスタンスプロファイルを削除
aws iam remove-role-from-instance-profile \
  --instance-profile-name "$ROLE_NAME" --role-name "$ROLE_NAME" 2>/dev/null || true
aws iam delete-instance-profile --instance-profile-name "$ROLE_NAME" 2>/dev/null || true
aws iam detach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null || true

# 5. セキュリティグループを削除(EC2用 -> ALB用の順。ALB用を先に消すと参照エラーになる)
EC2_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${NAME}-ec2-sg" "Name=vpc-id,Values=${VPC_ID}" \
  --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "")
ALB_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${NAME}-alb-sg" "Name=vpc-id,Values=${VPC_ID}" \
  --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "")

[ -n "$EC2_SG_ID" ] && [ "$EC2_SG_ID" != "None" ] && aws ec2 delete-security-group --group-id "$EC2_SG_ID"
[ -n "$ALB_SG_ID" ] && [ "$ALB_SG_ID" != "None" ] && aws ec2 delete-security-group --group-id "$ALB_SG_ID"

echo "片付け完了"
