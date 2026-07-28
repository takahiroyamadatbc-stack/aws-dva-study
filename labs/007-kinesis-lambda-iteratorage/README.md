# 007 Kinesis Data Streams + Lambda の処理速度改善(IteratorAge)

## 問題

企業はAWS Lambda関数を使用して、Amazon Kinesis Data Streamsからレコードを処理している。最近、処理速度が遅くなり、IteratorAgeメトリクスが増加していること、Lambdaの実行時間が通常よりも長いことが確認された。処理速度を向上させるために実行すべき最適な方法を2つ選択する問題。

選択肢:
- Lambda関数に割り当てられるメモリを増やす
- Kinesis Data Streamsのシャード数を増やす
- Lambda関数のタイムアウトを短くする
- Kinesis Data Streamsのシャード数を減らす
- Lambda関数のタイムアウトを増やす

正解: 「メモリを増やす」「シャード数を増やす」の2つ。

## 選んだ答えと理由

選んだ: 「メモリを増やす」(正解) + 「タイムアウトを増やす」(不正解)

理由: IteratorAgeメトリクスの意味が分からず、「繰り返しが多い＝Lambdaが設定時間内に処理を終えられず、途中まで終わっているのに強制終了されている」と誤って解釈した。そのため、無駄な打ち切りを減らせばよいと考え、タイムアウト延長を選んでしまった。

## 誤答の型

サービスの守備範囲の誤解: IteratorAgeメトリクスが何を計測しているかを誤解していた。実行回数やタイムアウトによる再試行の指標だと思い込んでいたが、実際は「レコードがストリームに書き込まれてから、Lambdaがそのレコードを読み取るまでの滞留時間」を表す指標。

## 仮説

IteratorAgeは滞留時間の指標なので、増加している原因は「Lambdaの処理速度がKinesisへの書き込み速度に追いついていない」こと。この場合、有効な対策は次の2系統のはず。

- **1件あたりの処理を速くする**: Lambdaのメモリを増やすとCPU・ネットワーク帯域も比例して増えるため、1バッチの処理時間(Duration)が短縮し、ストリームの消化速度が上がる
- **同時に処理できる本数を増やす**: シャードは並列処理の単位。シャード数を増やすと同時に実行されるLambda数が増え、全体のスループットが上がる

逆に、タイムアウトの増減は1件あたりの処理速度そのものには影響しないため、IteratorAgeの改善には寄与しないはず(タイムアウト短縮はむしろ処理途中の強制終了・再試行を増やし悪化させるはず)。

## 検証

> 実機デプロイは行っていない(標準ではコード整備までを完了条件とする方針。CLAUDE.md「AWS実行について」参照)。以下はユーザーが実行を希望した場合の検証手順として設計したもの。

1. [`01_create_stream_and_lambda.sh`](01_create_stream_and_lambda.sh): シャード数1のKinesis Data Stream、メモリ128MBでレコード1件ごとに`time.sleep(0.2)`する[`src/handler.py`](src/handler.py)、Event Source Mapping(BatchSize=100)を作成し、意図的に「処理が書き込み速度に追いつかない」状態を用意する
2. [`02_generate_load.sh`](02_generate_load.sh): `put-record`を300回実行し、ストリームに負荷をかける
3. [`03_check_iteratorage.sh`](03_check_iteratorage.sh): CloudWatchの`IteratorAge`(Maximum)と`Duration`(Average)を取得し、対策前の状態を記録する
4. [`04_apply_fix.sh`](04_apply_fix.sh): Lambdaメモリを128MB→1024MBに、シャード数を1→2に変更する(2つの正解を同時に適用)
5. シャード分割が`ACTIVE`になった後、`02_generate_load.sh`→`03_check_iteratorage.sh`を再実行し、対策前後でIteratorAgeが減少することを比較する

期待する結果: 対策後は`Duration`(1バッチの処理時間)と`IteratorAge`(滞留時間)がともに減少する。

## 結論(1行)

> IteratorAgeは「レコードの滞留時間」を示す指標。改善にはLambdaメモリ増加(1件あたりの処理速度向上)とKinesisシャード数増加(並列処理数の向上)の組み合わせが正解で、タイムアウトの変更は処理速度自体に影響せず的外れ。

## 片付け

[`05_delete.sh`](05_delete.sh)でEvent Source Mapping → Lambda関数 → IAMロール → Kinesis Streamの順に削除する。
