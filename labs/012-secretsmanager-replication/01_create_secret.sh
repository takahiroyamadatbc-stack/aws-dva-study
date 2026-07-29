#!/bin/bash
set -e

PRIMARY_REGION="us-west-1"
SECRET_NAME="dva-012-secretsmanager-replication"

SECRET_ARN=$(aws secretsmanager create-secret \
  --region "$PRIMARY_REGION" \
  --name "$SECRET_NAME" \
  --description "dva-study Lab012: クロスリージョンレプリケーション検証用シークレット" \
  --secret-string '{"username":"app_user","password":"ChangeMe123!"}' \
  --tags Key=Project,Value=dva-study Key=Name,Value="$SECRET_NAME" \
  --query "ARN" --output text)

echo "シークレット作成完了(${PRIMARY_REGION}): $SECRET_ARN"
echo "続けて 02_create_kms_key.sh を実行してください"
