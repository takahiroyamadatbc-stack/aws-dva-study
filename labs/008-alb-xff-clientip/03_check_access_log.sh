#!/bin/bash
set -e

NAME="dva-008-alb-xff-clientip"

INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${NAME}" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)

CMD_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["tail -n 10 /var/log/nginx/xff-access.log"]' \
  --query "Command.CommandId" --output text)

echo "コマンド実行待ち..."
sleep 5

aws ssm wait command-executed --command-id "$CMD_ID" --instance-id "$INSTANCE_ID"

echo "--- /var/log/nginx/xff-access.log ---"
aws ssm get-command-invocation \
  --command-id "$CMD_ID" \
  --instance-id "$INSTANCE_ID" \
  --query "StandardOutputContent" --output text

echo ""
echo "remote_addr = ALBノードのIP(常に同じ/内部IP)、x_forwarded_for = 実際のクライアントの送信元IPであることを確認する。"
