#!/bin/bash
set -e

DB_INSTANCE_ID="dva-006-cloudtrail-rds-delete"
DB_PASSWORD=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9' | head -c 16)

echo "生成したマスターパスワード(削除検証のみなら記録不要): $DB_PASSWORD"

aws rds create-db-instance \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --master-username admin \
  --master-user-password "$DB_PASSWORD" \
  --allocated-storage 20 \
  --no-multi-az \
  --no-publicly-accessible \
  --backup-retention-period 0 \
  --tags Key=Project,Value=dva-study

echo "作成中... 利用可能になるまで待機します(数分かかります)"
aws rds wait db-instance-available --db-instance-identifier "$DB_INSTANCE_ID"
echo "作成完了: $DB_INSTANCE_ID"
