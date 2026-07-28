#!/bin/bash
set -e

STREAM_NAME="dva-007-kinesis-lambda-iteratorage"

echo "ストリームにレコードを投入し、Lambdaの処理がストリームへの書き込み速度に追いつかない状態を作る"

for i in $(seq 1 300); do
  aws kinesis put-record \
    --stream-name "$STREAM_NAME" \
    --partition-key "pk-$((i % 4))" \
    --data "record-$i" \
    > /dev/null
done

echo "300件投入完了。数分待ってから 03_check_iteratorage.sh でIteratorAgeを確認する"
