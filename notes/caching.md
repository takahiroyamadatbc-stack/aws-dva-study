# ElastiCache: Memcached vs Redis vs Valkey

キャッシュ戦略の選定問題で毎回問われるサービスの違い。「暗号化」と「データ構造」の観点で混同しやすいので整理する。

## 0. Valkeyとは

Redis OSSが2024年にライセンスをBSD系（OSS）からSSPL/RSALVへ変更したことを受けて、Linux Foundation配下でフォークされたOSS版のインメモリDB。AWS（および他クラウドベンダ）が開発に参画しており、ElastiCache/MemoryDBの新規デプロイでは**Valkeyがデフォルトエンジン**として案内される。

- コマンド体系・データ構造（String, List, Hash, Set, Sorted Set等）はRedis OSSとほぼ互換 → 既存のRedisクライアント・`redis-cli`・`ZADD`/`ZRANGE`等のコマンドがそのまま使える
- ElastiCacheでは `--engine valkey` を指定して作成する（Redis OSSは `--engine redis`）
- ライセンスがOSSベース（BSD 3-Clause）に戻っているのが最大の差別化ポイント。試験文脈では「オープンソースライセンスを重視」「ベンダーロックインを避けたい」という要件があればValkeyが候補になる
- 料金面ではRedis OSSより安価な場合がある（AWS発表ベース）
- 既存のRedis OSSクラスタからValkeyへは**インプレース（無停止）でエンジンアップグレード可能**（逆方向の戻しは不可）

```bash
# ElastiCache for Valkey クラスタの作成例
aws elasticache create-replication-group \
  --replication-group-id dva-valkey-demo \
  --replication-group-description "Valkey demo cluster" \
  --engine valkey \
  --engine-version 7.2 \
  --cache-node-type cache.t4g.micro \
  --num-cache-clusters 2 \
  --transit-encryption-enabled \
  --at-rest-encryption-enabled \
  --tags Key=Project,Value=dva-study
```

## 1. 暗号化サポートの違い

| 項目 | Memcached | Redis | Valkey |
| --- | --- | --- | --- |
| 転送中暗号化（in-transit） | ❌ 非対応（TLS非対応） | ✅ `--transit-encryption-enabled` | ✅ `--transit-encryption-enabled` |
| 保管中暗号化（at-rest） | ❌ 非対応 | ✅ `--at-rest-encryption-enabled`（KMSで暗号化） | ✅ `--at-rest-encryption-enabled`（KMSで暗号化） |
| 認証 | SASLのみ（限定的） | Redis AUTH / RBAC対応 | Redis互換のAUTH / RBAC対応 |

PHIやPIIなど「常に暗号化されている必要がある」という要件が出てきた時点で、Memcachedは選択肢から除外できる。Memcachedはそもそも暗号化データのキャッシュを想定したアーキテクチャではない。RedisとValkeyは暗号化面では同等。

## 2. データ構造の違い（ソート・ランキング機能）

| | Memcached | Redis | Valkey |
| --- | --- | --- | --- |
| 構造 | 単純なkey-value（値は文字列/バイナリのみ） | String, List, Hash, Set, **Sorted Set (ZSET)**, Bitmap, HyperLogLog, Stream | Redis OSSとほぼ同一のデータ構造（Sorted Set含む） |
| ソート・ランキング | 非対応（アプリ側で実装が必要） | Sorted Setでネイティブ対応 | Sorted Setでネイティブ対応 |

「頻繁にアクセスされるデータをソート・ランク付けする」という要件は、ほぼそのままSorted Setの存在を問うている。スコア付きで要素を管理し、`ZADD` / `ZRANGE` / `ZRANK` / `ZREVRANGE` などO(log N)でランキング操作ができる。

```bash
# スコアを登録
redis-cli -h <endpoint> --tls ZADD leaderboard 1500 "user_A"
redis-cli -h <endpoint> --tls ZADD leaderboard 2300 "user_B"

# 上位からランキング取得（スコード付き）
redis-cli -h <endpoint> --tls ZREVRANGE leaderboard 0 2 WITHSCORES

# 特定要素の順位を取得
redis-cli -h <endpoint> --tls ZREVRANK leaderboard "user_A"
```

## 3. その他のアーキテクチャ上の違い

| 項目 | Memcached | Redis | Valkey |
| --- | --- | --- | --- |
| レプリケーション／自動フェイルオーバー | 非対応 | 対応（Multi-AZ） | 対応（Multi-AZ、Redisと同じ仕組み） |
| 永続化 | なし（ノード障害でデータ消失） | RDBスナップショット／AOFで対応可 | RDBスナップショット／AOFで対応可 |
| スケール方向の強み | マルチスレッド、水平分割（シャーディング） | Cluster Modeで水平分割可（単一ノードはシングルスレッド） | Cluster Modeで水平分割可。マルチスレッドI/O等パフォーマンス改善が継続的に入っている |
| トランザクション／Pub-Sub | なし | あり | あり |
| ライセンス | BSD（OSS） | SSPL/RSALv2（2024年以降、OSSではない） | BSD 3-Clause（OSS、Linux Foundation管理） |

## 4. 試験でのキーワード対応

| 設問の語 | 対応する答え |
| --- | --- |
| PHI/PII等、常に暗号化 | Redis or Valkey（Memcachedは保管中暗号化が非対応） |
| ソート・ランキング・リーダーボード | Redis or Valkey の Sorted Set |
| シンプルなkey-valueキャッシュ、マルチスレッドで水平分割したいだけ | Memcached |
| 自動フェイルオーバー／永続化が必要 | Redis or Valkey |
| DynamoDBテーブル専用のキャッシュ | DAX（既存RDS等の前段には使えない） |
| オープンソースライセンス／ベンダーロックイン回避を重視 | Valkey（Redis OSSはライセンス変更済み） |
| Redis互換で新規に構築したい（AWS推奨のデフォルト） | Valkey |

## 一行結論

> 「暗号化（転送中・保管中）」「高度なデータ構造（Sorted Setによるソート・ランキング）」「自動フェイルオーバー・永続化」のいずれかが問題文に出てきたら Redis系（Redis OSS or Valkey）一択。Memcachedはこれらすべて非対応で、シンプルな水平分割型キャッシュ用途に限られる。RedisとValkeyは機能的にはほぼ同等で、差はライセンス（ValkeyはOSS）とAWSの推奨度（新規はValkeyがデフォルト）。
