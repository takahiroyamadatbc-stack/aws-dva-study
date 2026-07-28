# 削除されたリソースの実行者を特定する 試験の判断基準

## 問題

過去90日以内に削除されたRDS for MySQLインスタンス(`mysql-db`)について、削除を行ったIAMユーザー/ロールを特定する最適な方法を選ぶ問題。

正解は「イベント名が`DeleteDBInstance`であるリソース`mysql-db`のAWS CloudTrailイベントを取得し、各イベントを調べる」。

## 監査ログの判断基準

「誰が・いつ・何をしたか」を調べたいのか、「何が起きたか(アプリ/インフラの内部状態)」を調べたいのかで使うサービスが変わる。この問題は前者(管理操作の実行者特定)。

| サービス | 記録対象 | RDS削除操作の実行者特定に使えるか |
| --- | --- | --- |
| AWS CloudTrail | 管理プレーンのAPI呼び出し全般(`userIdentity`, 送信元IP, アクセスキー等を含む) | ○ 適切。`DeleteDBInstance`イベントの`userIdentity`を見る |
| CloudWatch Logs(RDSロググループ) | DBエンジンレベルのログ(エラーログ/スロークエリログ/一般ログ) | × 管理操作(削除等)は記録されない。インスタンス削除時にロググループ自体も消える可能性がある |
| AWS X-Ray | アプリケーションのリクエストトレース、サービス間依存関係 | × 管理コンソール/CLIからの管理操作はトレース対象外。`ErrorRootCauses`はアプリ実行時エラー用 |
| Systems Manager インベントリ | 現存するリソース(主にEC2/オンプレミス)のソフトウェア・設定の現在の状態 | × 削除履歴を保持しない。RDSは標準の収集対象でもない |

## 誤答の判断基準

| 設問のキーワード | 判断 |
| --- | --- |
| 「誰が削除したか」を調べたい | CloudTrailの`userIdentity`を見る。`EventName=DeleteDBInstance`でフィルタするのが最短経路 |
| CloudWatch LogsのRDSロググループを見る選択肢 | 誤り。DBエンジンのログは管理プレーン操作(作成/削除等)を記録しない |
| X-Rayのトレース概要/`ErrorRootCauses`を見る選択肢 | 誤り。X-Rayはアプリ層のリクエストトレース専用で、インフラ変更操作とは無関係 |
| Systems Managerの削除インベントリという選択肢 | 誤り。インベントリに「削除」という概念はなく、現存リソースの状態収集機能。マネージドサービス(RDS等)は対象外 |
| 保持期間の考慮 | CloudTrailのイベント履歴(コンソール/`lookup-events`)は追加設定なしで過去90日を保持。今回の要件はこれで足りる |

## CloudTrailの2つの見え方

- **イベント履歴(Event history)**: `lookup-events` APIやコンソールの「イベント履歴」。追加設定不要・過去90日分を自動保持。今回の要件はこれで十分
- **証跡(Trail)**: S3への継続保存を設定するもの。90日を超える保持や複数リージョン/複数アカウントの集約が必要な場合に作る(証跡がなくても直近90日はCloudTrail自体が保持している点に注意)

## 検証の流れ(このLabのスクリプト)

1. `01_create_rds.sh`: `db.t3.micro`のRDS for MySQLインスタンス(識別子は命名規約により`dva-006-cloudtrail-rds-delete`)を作成し、利用可能になるまで待機
2. `02_delete_rds.sh`: 最終スナップショットなし・自動バックアップも削除する設定で削除
3. `03_check_cloudtrail.sh`: `aws cloudtrail lookup-events`で`ResourceName`を絞り込み、`EventName=DeleteDBInstance`のイベントを検索。`Username`と`CloudTrailEvent`(userIdentity等の詳細)を確認

> 命名規約(`dva-NNN-topic`)により、問題文の`mysql-db`ではなく`dva-006-cloudtrail-rds-delete`という識別子で作成した。本質(CloudTrailで`DeleteDBInstance`イベントを検索する)には影響しない。

## 結論

削除操作の実行者(IAMユーザー/ロール)を特定するには、CloudTrailで`EventName=DeleteDBInstance`のイベントを検索し`userIdentity`を確認するのが正解。CloudWatch Logs/X-Ray/Systems Managerインベントリはいずれも「AWS管理プレーンでのAPI呼び出し履歴」を記録する機能ではないため、削除操作の追跡には使えない。

> 実行環境にAWS認証情報が未設定のため、上記スクリプトは未実行(2026-07-28時点)。認証情報設定後に01→03の順で実行し、`DeleteDBInstance`イベントに実行者(`userIdentity`)が記録されていることを確認すること。CloudTrailへの反映には数分のラグがあるため、`03_check_cloudtrail.sh`はリトライ処理を入れてある。
