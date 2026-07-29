#!/bin/bash
set -e

NAME="dva-010-imagebuilder-codedeploy"
ROLE_BUILD="${NAME}-build-role"
ROLE_APP="${NAME}-app-role"
ROLE_CODEDEPLOY="${NAME}-codedeploy-service-role"
SSM_PARAM_NAME="/dva-010/imagebuilder-codedeploy/latest-ami"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${NAME}-revisions-${ACCOUNT_ID}"

# 1. CodeDeploy(デプロイグループ -> アプリケーション)
aws deploy delete-deployment-group \
  --application-name "$NAME" --deployment-group-name "${NAME}-dg" 2>/dev/null || true
aws deploy delete-application --application-name "$NAME" 2>/dev/null || true

# 2. リビジョン格納用S3バケット
aws s3 rm "s3://${BUCKET}" --recursive 2>/dev/null || true
aws s3api delete-bucket --bucket "$BUCKET" 2>/dev/null || true

# 3. Auto Scalingグループ(強制削除でインスタンスも道連れに終了) -> 起動テンプレート
aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name "${NAME}-asg" --force-delete 2>/dev/null || true
echo "ASG削除待ち..."
sleep 20
aws ec2 delete-launch-template --launch-template-name "${NAME}-lt" 2>/dev/null || true

# 4. Image Builderパイプライン -> レシピ -> インフラ設定 -> 配布設定 -> コンポーネント
PIPELINE_ARN=$(aws imagebuilder list-image-pipelines \
  --query "imagePipelineList[?name=='${NAME}-pipeline'].arn | [0]" --output text 2>/dev/null || echo "None")
[ "$PIPELINE_ARN" != "None" ] && [ -n "$PIPELINE_ARN" ] && \
  aws imagebuilder delete-image-pipeline --image-pipeline-arn "$PIPELINE_ARN"

RECIPE_ARN=$(aws imagebuilder list-image-recipes \
  --query "imageRecipeSummaryList[?name=='${NAME}-recipe'].arn | [0]" --output text 2>/dev/null || echo "None")
[ "$RECIPE_ARN" != "None" ] && [ -n "$RECIPE_ARN" ] && \
  aws imagebuilder delete-image-recipe --image-recipe-arn "$RECIPE_ARN"

INFRA_ARN=$(aws imagebuilder list-infrastructure-configurations \
  --query "infrastructureConfigurationSummaryList[?name=='${NAME}-infra'].arn | [0]" --output text 2>/dev/null || echo "None")
[ "$INFRA_ARN" != "None" ] && [ -n "$INFRA_ARN" ] && \
  aws imagebuilder delete-infrastructure-configuration --infrastructure-configuration-arn "$INFRA_ARN"

DIST_ARN=$(aws imagebuilder list-distribution-configurations \
  --query "distributionConfigurationSummaryList[?name=='${NAME}-dist'].arn | [0]" --output text 2>/dev/null || echo "None")
[ "$DIST_ARN" != "None" ] && [ -n "$DIST_ARN" ] && \
  aws imagebuilder delete-distribution-configuration --distribution-configuration-arn "$DIST_ARN"

COMPONENT_ARN=$(aws imagebuilder list-components \
  --query "componentVersionList[?name=='${NAME}-component'].arn | [0]" --output text 2>/dev/null || echo "None")
if [ "$COMPONENT_ARN" != "None" ] && [ -n "$COMPONENT_ARN" ]; then
  for ARN in $(aws imagebuilder list-component-build-versions --component-version-arn "$COMPONENT_ARN" \
    --query "componentSummaryList[].arn" --output text); do
    aws imagebuilder delete-component --component-build-version-arn "$ARN"
  done
fi

# 5. パイプラインが生成したAMIとスナップショットを削除(登録解除だけではスナップショットが残る)
for IMAGE_ID in $(aws ec2 describe-images --owners self \
  --filters "Name=name,Values=${NAME}-*" --query "Images[].ImageId" --output text); do
  SNAPSHOT_IDS=$(aws ec2 describe-images --image-ids "$IMAGE_ID" \
    --query "Images[0].BlockDeviceMappings[].Ebs.SnapshotId" --output text)
  aws ec2 deregister-image --image-id "$IMAGE_ID"
  for SNAP_ID in $SNAPSHOT_IDS; do
    aws ec2 delete-snapshot --snapshot-id "$SNAP_ID" 2>/dev/null || true
  done
done

# 6. SSMパラメータ
aws ssm delete-parameter --name "$SSM_PARAM_NAME" 2>/dev/null || true

# 7. IAMロール/インスタンスプロファイル
for ROLE in "$ROLE_BUILD" "$ROLE_APP"; do
  aws iam remove-role-from-instance-profile \
    --instance-profile-name "$ROLE" --role-name "$ROLE" 2>/dev/null || true
  aws iam delete-instance-profile --instance-profile-name "$ROLE" 2>/dev/null || true
done

aws iam detach-role-policy --role-name "$ROLE_BUILD" \
  --policy-arn arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder 2>/dev/null || true
aws iam detach-role-policy --role-name "$ROLE_BUILD" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
aws iam delete-role --role-name "$ROLE_BUILD" 2>/dev/null || true

aws iam detach-role-policy --role-name "$ROLE_APP" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
aws iam detach-role-policy --role-name "$ROLE_APP" \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess 2>/dev/null || true
aws iam delete-role --role-name "$ROLE_APP" 2>/dev/null || true

aws iam detach-role-policy --role-name "$ROLE_CODEDEPLOY" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole 2>/dev/null || true
aws iam delete-role --role-name "$ROLE_CODEDEPLOY" 2>/dev/null || true

echo "片付け完了"
