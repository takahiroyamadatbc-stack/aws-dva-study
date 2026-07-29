#!/bin/bash
set -e

NAME="dva-010-imagebuilder-codedeploy"
ROLE_APP="${NAME}-app-role"
SSM_PARAM_NAME="/dva-010/imagebuilder-codedeploy/latest-ami"

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text)
SUBNET_IDS=($(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=default-for-az,Values=true" \
  --query "Subnets[*].SubnetId" --output text))
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=default" \
  --query "SecurityGroups[0].GroupId" --output text)

# 1. 起動テンプレート: ImageIdに"resolve:ssm:<パラメータ名>"を指定すると、
#    インスタンス起動のたびにEC2がそのSSMパラメータの最新値(=Image Builderが公開した最新AMI)を動的解決する。
#    これによりASGは常に最新パッチ済みAMIから起動でき、起動テンプレートの手動更新が不要になる。
aws ec2 create-launch-template \
  --launch-template-name "${NAME}-lt" \
  --launch-template-data "{
    \"ImageId\": \"resolve:ssm:${SSM_PARAM_NAME}\",
    \"InstanceType\": \"t3.micro\",
    \"IamInstanceProfile\": {\"Name\": \"${ROLE_APP}\"},
    \"SecurityGroupIds\": [\"${SG_ID}\"],
    \"TagSpecifications\": [{\"ResourceType\": \"instance\", \"Tags\": [{\"Key\": \"Project\", \"Value\": \"dva-study\"}, {\"Key\": \"Name\", \"Value\": \"${NAME}\"}]}]
  }" \
  --tag-specifications "ResourceType=launch-template,Tags=[{Key=Project,Value=dva-study}]" > /dev/null

# 2. Auto Scalingグループ(デフォルトVPCの全AZに分散)
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "${NAME}-asg" \
  --launch-template "LaunchTemplateName=${NAME}-lt,Version=\$Latest" \
  --min-size 1 --max-size 3 --desired-capacity 1 \
  --vpc-zone-identifier "$(IFS=,; echo "${SUBNET_IDS[*]}")" \
  --tags "Key=Project,Value=dva-study,PropagateAtLaunch=true"

echo "作成完了: LaunchTemplate=${NAME}-lt, ASG=${NAME}-asg"
