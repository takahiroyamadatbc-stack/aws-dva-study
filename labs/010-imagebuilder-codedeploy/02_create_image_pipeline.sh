#!/bin/bash
set -e

NAME="dva-010-imagebuilder-codedeploy"
ROLE_BUILD="${NAME}-build-role"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SSM_PARAM_NAME="/dva-010/imagebuilder-codedeploy/latest-ami"

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text)
SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=default-for-az,Values=true" \
  --query "Subnets[0].SubnetId" --output text)
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=default" \
  --query "SecurityGroups[0].GroupId" --output text)

# 1. コンポーネント(OSセキュリティパッチ + CodeDeployエージェントのみ。アプリ本体は含めない)
COMPONENT_ARN=$(aws imagebuilder create-component \
  --name "${NAME}-component" \
  --semantic-version 1.0.0 \
  --platform Linux \
  --data "file://${SCRIPT_DIR}/src/component-document.yml" \
  --tags Project=dva-study \
  --query "componentBuildVersionArn" --output text)

# 2. インフラ設定(ビルド/テストに使う一時インスタンスの条件)
INFRA_ARN=$(aws imagebuilder create-infrastructure-configuration \
  --name "${NAME}-infra" \
  --instance-profile-name "$ROLE_BUILD" \
  --instance-types t3.micro \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$SG_ID" \
  --terminate-instance-on-failure \
  --tags Project=dva-study \
  --query "infrastructureConfigurationArn" --output text)

# 3. イメージレシピ(ベースAMI + コンポーネントの組み合わせ)
PARENT_IMAGE="arn:aws:imagebuilder:${REGION}:aws:image/amazon-linux-2023-x86/x.x.x"

RECIPE_ARN=$(aws imagebuilder create-image-recipe \
  --name "${NAME}-recipe" \
  --semantic-version 1.0.0 \
  --parent-image "$PARENT_IMAGE" \
  --components "componentArn=${COMPONENT_ARN}" \
  --tags Project=dva-study \
  --query "imageRecipeArn" --output text)

# 4. 配布設定(生成したAMI IDを自動でSSMパラメータに公開し、起動テンプレートから動的参照する)
DIST_ARN=$(aws imagebuilder create-distribution-configuration \
  --name "${NAME}-dist" \
  --distributions "region=${REGION},amiDistributionConfiguration={name=${NAME}-{{ imagebuilder:buildDate }}},ssmParameterConfigurations=[{parameterName=${SSM_PARAM_NAME},amiAccountId=${ACCOUNT_ID}}]" \
  --tags Project=dva-study \
  --query "distributionConfigurationArn" --output text)

# 5. イメージパイプライン(毎週日曜3時UTCに再ビルドし、常に最新のセキュリティパッチを反映)
PIPELINE_ARN=$(aws imagebuilder create-image-pipeline \
  --name "${NAME}-pipeline" \
  --image-recipe-arn "$RECIPE_ARN" \
  --infrastructure-configuration-arn "$INFRA_ARN" \
  --distribution-configuration-arn "$DIST_ARN" \
  --schedule "scheduleExpression=cron(0 3 ? * SUN *),pipelineExecutionStartCondition=EXPRESSION_MATCH_ONLY" \
  --status ENABLED \
  --tags Project=dva-study \
  --query "imagePipelineArn" --output text)

# スケジュールを待たず初回ビルドを即時起動
aws imagebuilder start-image-pipeline-execution --image-pipeline-arn "$PIPELINE_ARN" > /dev/null

echo "作成完了: Component=$COMPONENT_ARN"
echo "Pipeline=$PIPELINE_ARN"
echo "AMI ID公開先SSMパラメータ: $SSM_PARAM_NAME (初回ビルド完了まで数十分かかる)"
