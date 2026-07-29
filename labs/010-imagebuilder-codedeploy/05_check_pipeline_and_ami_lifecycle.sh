#!/bin/bash
set -e

NAME="dva-010-imagebuilder-codedeploy"
SSM_PARAM_NAME="/dva-010/imagebuilder-codedeploy/latest-ami"

echo "=== イメージパイプラインのビルド履歴 ==="
PIPELINE_ARN=$(aws imagebuilder list-image-pipelines \
  --query "imagePipelineList[?name=='${NAME}-pipeline'].arn | [0]" --output text)
aws imagebuilder list-image-pipeline-images \
  --image-pipeline-arn "$PIPELINE_ARN" \
  --query "imageSummaryList[].{Version:version,Status:state.status,Ami:outputResources.amis[0].image}"

echo "=== 起動テンプレートが解決する最新AMI(SSMパラメータ) ==="
aws ssm get-parameter --name "$SSM_PARAM_NAME" --query "Parameter.Value" --output text

echo "=== Auto Scalingグループの状態 ==="
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "${NAME}-asg" \
  --query "AutoScalingGroups[0].{Desired:DesiredCapacity,Instances:Instances[].InstanceId}"

echo "=== CodeDeployデプロイ状況 ==="
DEPLOYMENT_ID=$(aws deploy list-deployments \
  --application-name "$NAME" --deployment-group-name "${NAME}-dg" \
  --query "deployments[0]" --output text)
aws deploy get-deployment --deployment-id "$DEPLOYMENT_ID" \
  --query "deploymentInfo.{Status:status,Overview:deploymentOverview}"

echo ""
echo "=== AMIライフサイクル操作の例(このLabで作られた自分のAMIのみ対象) ==="
echo "1. 保有AMI一覧:"
aws ec2 describe-images --owners self \
  --filters "Name=name,Values=${NAME}-*" \
  --query "Images[].{Id:ImageId,Name:Name,State:State,Deprecated:DeprecationTime}"

cat <<'EOF'

2. 古い世代を非推奨化(新規起動テンプレートの選択肢から外すが、既存参照は動作継続する):
   aws ec2 enable-image-deprecation --image-id <old-ami-id> --deprecate-at "$(date -u -d '+30 days' +%Y-%m-%dT%H:%M:%SZ)"

3. 完全に使わなくなったら登録解除(以後このAMIからは新規起動不可):
   aws ec2 deregister-image --image-id <old-ami-id>

4. 登録解除後も残るEBSスナップショットを削除(消し忘れやすいポイント):
   aws ec2 describe-images --image-ids <old-ami-id> --query "Images[0].BlockDeviceMappings[].Ebs.SnapshotId"
   aws ec2 delete-snapshot --snapshot-id <snapshot-id>
EOF
