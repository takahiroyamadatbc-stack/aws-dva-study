#!/bin/bash
set -e

NAME="dva-008-alb-xff-clientip"

ALB_DNS=$(aws elbv2 describe-load-balancers --names "$NAME" \
  --query "LoadBalancers[0].DNSName" --output text)

echo "ALBへ3回リクエストを送信: http://${ALB_DNS}/"
for i in 1 2 3; do
  curl -s -o /dev/null -w "  [$i] HTTP %{http_code}\n" "http://${ALB_DNS}/?req=${i}"
done
