#!/bin/bash
set -e

LOG_GROUP="/dva-009/cloudwatch-metric-filter"
LOG_STREAM="app-log-stream"

# ERRORを含む行2件、含まない行3件を送信し、メトリクスフィルターが
# "ERROR"の出現回数だけを正しくカウントすることを確認できるようにする
NOW_MS=$(($(date +%s%N)/1000000))

EVENTS=$(cat <<EOF
[
  {"timestamp": $NOW_MS, "message": "INFO Application started"},
  {"timestamp": $((NOW_MS+100)), "message": "ERROR Failed to connect to database"},
  {"timestamp": $((NOW_MS+200)), "message": "INFO Request processed successfully"},
  {"timestamp": $((NOW_MS+300)), "message": "ERROR NullPointerException at handler.py:42"},
  {"timestamp": $((NOW_MS+400)), "message": "INFO Health check OK"}
]
EOF
)

aws logs put-log-events \
  --log-group-name "$LOG_GROUP" \
  --log-stream-name "$LOG_STREAM" \
  --log-events "$EVENTS"

echo "ログ5件を送信しました(ERROR行2件 / INFO行3件)。メトリクスフィルターは60秒集計なので、少し待ってから03を実行してください。"
