#!/bin/bash
set -e

DB_INSTANCE_ID="dva-006-cloudtrail-rds-delete"

aws rds delete-db-instance \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --skip-final-snapshot \
  --delete-automated-backups

echo "削除中... 削除完了まで待機します(数分かかります)"
aws rds wait db-instance-deleted --db-instance-identifier "$DB_INSTANCE_ID"
echo "削除完了: $DB_INSTANCE_ID"
