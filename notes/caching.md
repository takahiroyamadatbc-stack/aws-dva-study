# ElastiCache: Memcached vs Redis

キャッシュ戦略の選定問題で毎回問われる2サービスの違い。「暗号化」と「データ構造」の観点で混同しやすいので整理する。

## 1. 暗号化サポートの違い

| 項目 | Memcached | Redis |
|---|---|---|
| 転送中暗号化（in-transit） | ❌ 非対応（TLS非対応） | ✅ `--transit-encryption-enabled` |
| 保管中暗号化（at-rest） | ❌ 非対応 | ✅ `--at-rest-encryption-enabled`（KMSで暗号化） |
| 認証 | SASLのみ（限定的） | Redis AUTH / RBAC対応 |

PHIやPIIなど「常に暗号化されている必要がある」という要件が出てきた時点で、Memcachedは選択肢から除外できる。Memcachedはそもそも暗号化データのキャッシュを想定したアーキテクチャではない。

## 2. データ構造の違い（ソート・ランキング機能）

| | Memcached | Redis |
|---|---|---|
| 構造 | 単純なkey-value（値は文字列/バイナリのみ） | String, List, Hash, Set, **Sorted Set (ZSET)**, Bitmap, HyperLogLog, Stream |
| ソート・ランキング | 非対応（アプリ側で実装が必要） | Sorted Setでネイティブ対応 |

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

| 項目 | Memcached | Redis |
|---|---|---|
| レプリケーション／自動フェイルオーバー | 非対応 | 対応（Multi-AZ） |
| 永続化 | なし（ノード障害でデータ消失） | RDBスナップショット／AOFで対応可 |
| スケール方向の強み | マルチスレッド、水平分割（シャーディング） | Cluster Modeで水平分割可（単一ノードはシングルスレッド） |
| トランザクション／Pub-Sub | なし | あり |

## 4. 試験でのキーワード対応

| 設問の語 | 対応する答え |
|---|---|
| PHI/PII等、常に暗号化 | Redis（Memcachedは保管中暗号化が非対応） |
| ソート・ランキング・リーダーボード | Redis Sorted Set |
| シンプルなkey-valueキャッシュ、マルチスレッドで水平分割したいだけ | Memcached |
| 自動フェイルオーバー／永続化が必要 | Redis |
| DynamoDBテーブル専用のキャッシュ | DAX（既存RDS等の前段には使えない） |

## 一行結論

> 「暗号化（転送中・保管中）」「高度なデータ構造（Sorted Setによるソート・ランキング）」「自動フェイルオーバー・永続化」のいずれかが問題文に出てきたら Redis 一択。Memcachedはこれらすべて非対応で、シンプルな水平分割型キャッシュ用途に限られる。
