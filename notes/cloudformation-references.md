# CloudFormation 値参照方式 比較メモ

CloudFormationテンプレートで「他の値を参照する」方法は`Ref`だけでなく複数あり、**参照先がテンプレート内か外か**、**外部ストアなら平文か暗号化か**によって使うべき方式が変わる。ここを混同すると「SSMのSecureStringなのに`ssm`動的参照を使う」「別スタックの値なのに`Ref`で参照しようとする」といった誤答をしやすい。

## 比較表

| 参照方式 | 構文例 | 参照先 | 使う場面 | 解決タイミング |
|----------|--------|--------|----------|----------------|
| **Ref**（組み込み関数） | `!Ref Logical ID` | 同一テンプレート内の`Parameters`/リソースの物理ID | テンプレート内で定義したパラメータ値やリソースの主要な識別子を使うとき | スタックのcreate/update実行時 |
| **Fn::GetAtt**（組み込み関数） | `!GetAtt LogicalID.AttributeName` | 同一テンプレート内のリソースの属性値（ARNなど、`Ref`では取れないもの） | 物理ID以外の属性（例: S3バケットのARN、ELBのDNS名）が欲しいとき | スタックのcreate/update実行時 |
| **Fn::ImportValue**（組み込み関数） | `!ImportValue ExportName` | **別のCloudFormationスタック**が`Outputs`で`Export`した値 | クロススタック参照（他スタックが作ったVPC IDやサブネットIDを使う） | スタックのcreate/update実行時（Export元は参照されている間、削除・変更不可） |
| **動的参照 `ssm`** | `{{resolve:ssm:/path/to/param:version}}` | SSM Parameter Storeの`String`/`StringList`（**平文**） | ホスト名・AMI IDなど、環境ごとに変わる非機密の設定値を外部化したいとき | スタックのcreate/update実行のたびに再取得（`version`省略時は常に最新値） |
| **動的参照 `ssm-secure`** | `{{resolve:ssm-secure:/path/to/param:version}}` | SSM Parameter Storeの`SecureString`（KMSで**復号済み平文**が展開される） | DBパスワードなど機密値を暗号化保存しつつテンプレートに埋め込みたいとき | 同上。CloudFormationの実行ロールに対象KMSキーの`kms:Decrypt`権限が必要 |
| **動的参照 `secretsmanager`** | `{{resolve:secretsmanager:secret-id:SecretString:json-key:version-stage:version-id}}` | Secrets Managerのシークレット | RDSなど自動ローテーション対象のシークレットをテンプレートで使うとき | 同上 |
| **パラメータ型 `AWS::SSM::Parameter::Value<Type>`** | `Parameters:`で型宣言 → `!Ref`で参照 | SSM Parameter Storeの`String`/`StringList`（**SecureStringは非対応**） | スタック実行コマンド発行時点の値をパラメータとして固定したい、CLIから`--parameter-overrides`で上書きもしたいとき | スタック実行コマンド発行時にバインド（動的参照と違い、テンプレート更新のたび自動で最新値を取り直すわけではない） |

## 使い分けの判断フロー

1. 値は**同一テンプレート内**で定義したもの？ → `Ref` / `Fn::GetAtt`
2. 値は**別のCloudFormationスタックのOutput**？ → `Fn::ImportValue`
3. 値は**外部ストア**（SSM Parameter Store / Secrets Manager）にある？
   - 平文の`String`/`StringList`で、更新のたび最新値を反映したい → 動的参照 `{{resolve:ssm:...}}`
   - `SecureString`（暗号化済み）を復号して使いたい → 動的参照 `{{resolve:ssm-secure:...}}`
   - Secrets Managerに保存済み（自動ローテーション対象など） → 動的参照 `{{resolve:secretsmanager:...}}`
   - 実行時点の値をパラメータとして固定・CLIから上書きもしたい（かつ平文） → パラメータ型 `AWS::SSM::Parameter::Value<String>` + `Ref`

## 引っかけポイント

- **`Ref`はテンプレート外を見に行けない**：外部のSSM/Secrets Managerの値を直接参照する経路を持たない。「Parameter Storeの値を`Ref`で取得する」という選択肢は原則誤り（パラメータ型を経由すれば間接的に可能だが、それでも`SecureString`は不可）
- **`SecureString`を`AWS::SSM::Parameter::Value<String>`型で`Ref`すると、復号されず暗号文（ciphertext）のまま渡ってしまう**。`SecureString`を扱う場合は必ず動的参照`ssm-secure`を使うこと。これは典型的な誤答トラップ
- **`Fn::ImportValue`とSSM動的参照の混同**：`Fn::ImportValue`はスタック間（CloudFormationのOutputs/Exportsの仕組み）、動的参照はCloudFormationの外にあるSSM/Secrets Managerというサービスへの参照。「別スタックの値」と「外部ストアの値」は別物
- **動的参照はすべてのリソースプロパティで使えるわけではない**：一部のプロパティ（特にカスタムリソースや一部のTransform経由のプロパティ）では非対応の場合がある。試験では「基本はどのリソースプロパティでも使える」という理解で問題ないが、実務では都度AWS公式ドキュメントの対応表を確認する
- **`Fn::ImportValue`で参照されているExport値は、参照が存在する限りExport元スタックで変更・削除できない**（依存関係ロック）。クロススタック設計の柔軟性を落とすトレードオフとして覚えておく

## 関連

- [iac-services.md](iac-services.md)：CloudFormation自体とSAM/CDK/Beanstalk等の比較
