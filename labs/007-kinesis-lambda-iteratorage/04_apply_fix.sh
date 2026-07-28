#!/bin/bash
set -e

FUNCTION_NAME="dva-007-kinesis-lambda-iteratorage"
STREAM_NAME="dva-007-kinesis-lambda-iteratorage"

echo "対策1: Lambdaのメモリを128MB -> 1024MBに増やす(CPU/ネットワーク帯域も比例して向上し、1バッチの処理が速くなる)"
aws lambda update-function-configuration \
  --function-name "$FUNCTION_NAME" \
  --memory-size 1024

aws lambda wait function-updated --function-name "$FUNCTION_NAME"

echo "対策2: Kinesisのシャード数を1 -> 2に増やす(並列に処理できるLambda実行数が増える)"
aws kinesis update-shard-count \
  --stream-name "$STREAM_NAME" \
  --target-shard-count 2 \
  --scaling-type UNIFORM_SCALING

echo "シャード分割は反映まで数分かかる。aws kinesis describe-stream で StreamStatus=ACTIVE を確認してから"
echo "02_generate_load.sh -> 03_check_iteratorage.sh を再実行し、対策前後でIteratorAgeが下がることを比較する"
