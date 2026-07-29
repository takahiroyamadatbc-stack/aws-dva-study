# DynamoDB Streams: StreamViewType

テーブルへの書き込み（Put/Update/Delete）ごとに変更内容をキャプチャして最大24時間保持する仕組みが DynamoDB Streams。`StreamViewType` は「変更発生時にストリームレコードへ具体的に何を書き込むか」を決めるパラメータで、ストリーム有効化時にテーブル単位で設定する。

## 1. 4つの選択肢

| 値 | 内容 | レコードサイズ | 典型用途 |
|---|---|---|---|
| `KEYS_ONLY` | 変更された項目の**キー属性のみ**（PK/SK） | 最小 | 変更があったことだけ知りたい。詳細は自分でGetItemする |
| `NEW_IMAGE` | 変更後の項目全体 | 中 | 最新状態だけを別ストアに同期（検索インデックス更新など） |
| `OLD_IMAGE` | 変更前の項目全体 | 中 | 削除前のデータを監査ログに残す、削除検知など |
| `NEW_AND_OLD_IMAGES` | 変更前後の項目全体（両方） | 最大 | 差分計算が必要な処理（変更フィールド抽出、集計値の増減計算など） |

## 2. イベントタイプ（`eventName`）との組み合わせ

ストリームレコードには`eventName`（`INSERT` / `MODIFY` / `REMOVE`）もセットで入る。

- `INSERT`: `OldImage`は存在しない（新規作成なので「変更前」がない）
- `MODIFY`: `NEW_AND_OLD_IMAGES`なら両方入るので、どの属性が変わったかをアプリ側で比較できる
- `REMOVE`: `NewImage`は存在しない（削除後の状態はない）

**誤答の型**: 「削除前のデータを見たい／監査ログに残したい」という要件に対して`KEYS_ONLY`や`NEW_IMAGE`を選ぶと、REMOVEイベントで削除された内容の詳細が失われる（キーしか残らない）。この要件が出たら`OLD_IMAGE`系（`OLD_IMAGE`または`NEW_AND_OLD_IMAGES`）が必須。

## 3. 設定方法

### AWS CLI（テーブル作成時）

```bash
aws dynamodb create-table \
  --table-name dva-XXX-topic \
  --attribute-definitions AttributeName=PK,AttributeType=S \
  --key-schema AttributeName=PK,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
  --tags Key=Project,Value=dva-study
```

既存テーブルへの後付け:

```bash
aws dynamodb update-table \
  --table-name dva-XXX-topic \
  --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES
```

### CDK (TypeScript)

```typescript
new dynamodb.Table(this, 'Table', {
  partitionKey: { name: 'PK', type: dynamodb.AttributeType.STRING },
  stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
});
```

## 4. Lambdaトリガーでの見え方

Lambdaのイベントソースマッピングでストリームを紐づけると、`event.Records[].dynamodb`に以下のようなキーが入る（`StreamViewType`によって存在するキーが変わる）。

```json
{
  "eventName": "MODIFY",
  "dynamodb": {
    "Keys": { "PK": { "S": "user#1" } },
    "NewImage": { "PK": { "S": "user#1" }, "status": { "S": "active" } },
    "OldImage": { "PK": { "S": "user#1" }, "status": { "S": "pending" } },
    "SequenceNumber": "...",
    "StreamViewType": "NEW_AND_OLD_IMAGES"
  }
}
```

`Keys`は常に入る（`KEYS_ONLY`相当は常に含まれていると考えてよい）。

## 5. 周辺知識

- **DynamoDB Streams vs Kinesis Data Streams for DynamoDB**: 似た機能が2種類ある。Streamsは24時間保持・Lambda/KCLで消費が主用途、Kinesis連携は最大1年保持・複数コンシューマ・他のKinesisエコシステム（Firehose経由でS3/Redshiftなど）と繋げやすい。「保持期間」「同時コンシューマ数」の違いで問われがち
- **書き込みキャパシティへの影響**: ストリーム自体は追加のRCU/WCUを消費しない（読み取り側のGetRecordsは別課金・別スロットリング）
- **Global Tablesとの関係**: Global TablesはDynamoDB Streams（`NEW_AND_OLD_IMAGES`相当の内部レプリケーション）を使ってリージョン間複製している。ユーザーが明示的に選ぶ必要はないが、内部的に同じ仕組み
- **順序保証**: 同一パーティションキー内では順序が保証されるが、パーティションをまたいだ順序は保証されない

## 6. 試験でのキーワード対応

| 設問の語 | 対応する答え |
|---|---|
| 削除前の値を監査ログに残したい | `OLD_IMAGE` または `NEW_AND_OLD_IMAGES` |
| 変更前後の差分を比較したい | `NEW_AND_OLD_IMAGES` |
| 最新状態だけ他ストアに同期したい | `NEW_IMAGE` |
| 変更検知のトリガーだけしたい（詳細は別途取得） | `KEYS_ONLY` |
| 最大1年保持・複数コンシューマが必要 | Kinesis Data Streams for DynamoDB |

## 一行結論

> `StreamViewType`は「レコードに何を含めるか」を決めるだけで、`REMOVE`イベントの詳細を残したいなら`OLD_IMAGE`系が必須、差分比較が必要なら`NEW_AND_OLD_IMAGES`一択。
