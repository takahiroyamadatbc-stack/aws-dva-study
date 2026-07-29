#!/bin/bash
set -e

NAME="dva-010-imagebuilder-codedeploy"
ROLE_CODEDEPLOY="${NAME}-codedeploy-service-role"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)
BUCKET="${NAME}-revisions-${ACCOUNT_ID}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. デプロイリビジョン格納用S3バケット
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --create-bucket-configuration LocationConstraint="$REGION" > /dev/null
aws s3api put-bucket-tagging \
  --bucket "$BUCKET" \
  --tagging 'TagSet=[{Key=Project,Value=dva-study}]'

# 2. CodeDeployアプリケーション + デプロイグループ(Auto Scalingグループに紐付け)
#    デプロイグループにASG名を渡すだけで、CodeDeployがASGのライフサイクルフックを自動設定し、
#    スケールアウトで新規起動したインスタンスにも自動的に最新リビジョンをデプロイする
aws deploy create-application \
  --application-name "$NAME" \
  --compute-platform Server \
  --tags Key=Project,Value=dva-study

ROLE_ARN=$(aws iam get-role --role-name "$ROLE_CODEDEPLOY" --query "Role.Arn" --output text)

aws deploy create-deployment-group \
  --application-name "$NAME" \
  --deployment-group-name "${NAME}-dg" \
  --service-role-arn "$ROLE_ARN" \
  --auto-scaling-groups "${NAME}-asg" \
  --deployment-config-name CodeDeployDefault.OneAtATime

# 3. アプリの最新バージョンをリビジョンとしてpush(appspec.yml + デプロイスクリプトをzip化してS3へ)
aws deploy push \
  --application-name "$NAME" \
  --s3-location "s3://${BUCKET}/releases/app.zip" \
  --source "${SCRIPT_DIR}/src"

# 4. デプロイ実行(既存インスタンス + 以後スケールアウトする新規インスタンスにも自動適用される)
aws deploy create-deployment \
  --application-name "$NAME" \
  --deployment-group-name "${NAME}-dg" \
  --s3-location "bucket=${BUCKET},key=releases/app.zip,bundleType=zip" \
  --description "dva-010 initial deployment"

echo "作成完了: Application=$NAME, DeploymentGroup=${NAME}-dg, Bucket=$BUCKET"
