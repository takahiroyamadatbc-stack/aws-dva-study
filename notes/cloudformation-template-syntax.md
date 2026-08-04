# CloudFormation テンプレートの書き方・構成要素 メモ

模擬テストで「テンプレートを実際に書いたことがない」ために解けなかった問題への対策ノート。**テンプレートファイル自体の構造・記法・リソース属性のオプション**に絞って整理する。値の参照方法（Ref/GetAtt/ImportValue/動的参照）は[cloudformation-references.md](cloudformation-references.md)、CFn自体の位置づけ・ヘルパースクリプト・チェンジセット・StackSets・ドリフト検出・カスタムリソースは[iac-services.md](iac-services.md)を参照（本ノートでは重複させない）。

## テンプレートの全体構造（トップレベルセクション）

| セクション | 必須 | 役割 |
|------------|------|------|
| `AWSTemplateFormatVersion` | 任意 | `"2010-09-09"`固定（現状これ以外の値は存在しない） |
| `Description` | 任意 | テンプレートの説明文（先頭付近に書くのが慣例） |
| `Metadata` | 任意 | `AWS::CloudFormation::Interface`（コンソールでのパラメータ表示グループ化）や`AWS::CloudFormation::Init`（cfn-init用、[iac-services.md](iac-services.md)参照）など |
| `Parameters` | 任意 | スタック作成/更新時に外部から値を注入する変数定義 |
| `Mappings` | 任意 | 静的なキー・バリューのルックアップテーブル |
| `Conditions` | 任意 | 条件式の定義（リソース作成有無やプロパティの出し分けに使う） |
| `Transform` | 任意 | テンプレート全体に適用するマクロ（SAM/Includeなど） |
| `Resources` | **必須** | 実際に作成するAWSリソースの定義（テンプレートの本体） |
| `Outputs` | 任意 | スタックの出力値（コンソール表示・クロススタック参照用） |

`Resources`だけが必須。他は書かなければ省略時のデフォルト挙動になる。

## Parameters（パラメータ定義のオプション）

| 属性 | 用途 |
|------|------|
| `Type` | `String` / `Number` / `List<Number>` / `CommaDelimitedList` / AWS固有型（`AWS::EC2::KeyPair::KeyName`, `AWS::EC2::VPC::Id`, `AWS::EC2::Subnet::Id`, `AWS::EC2::SecurityGroup::Id`など、コンソールでドロップダウン選択になる）/ `AWS::SSM::Parameter::Value<Type>`（詳細は[cloudformation-references.md](cloudformation-references.md)） |
| `Default` | 未指定時のデフォルト値 |
| `AllowedValues` | 選択肢を配列で限定 |
| `AllowedPattern` | 正規表現でバリデーション |
| `ConstraintDescription` | `AllowedPattern`等に違反した際のエラーメッセージ |
| `MinLength` / `MaxLength` | 文字列長の制約 |
| `MinValue` / `MaxValue` | 数値の範囲制約 |
| `NoEcho` | `true`にするとコンソール/CLIの出力でマスクされる |

**引っかけポイント**：`NoEcho: true`は「表示をマスクする」だけで、値自体を暗号化・秘匿するものではない（テンプレート内には平文で残り、CloudFormationサービスのAPIレスポンスやログ経由で見える経路が残る）。パスワード等の機密値を本当に秘匿したい場合は`NoEcho`ではなく、Secrets Manager/SSM SecureStringの動的参照を使うべき（[cloudformation-references.md](cloudformation-references.md)参照）。

## Mappings（静的ルックアップテーブル）

```yaml
Mappings:
  RegionMap:
    us-east-1:
      AMI: ami-0ff8a91507f77f867
    ap-northeast-1:
      AMI: ami-0c3fd0f5d33134a76
```

`Fn::FindInMap: [MapName, TopLevelKey, SecondLevelKey]`（短縮形 `!FindInMap [RegionMap, !Ref "AWS::Region", AMI]`）で参照する。

**引っかけポイント**：`Mappings`の値は**静的なリテラルのみ**。`Parameters`や擬似パラメータの値をキー・バリューとして動的に生成することはできない（キーの決定に`!Ref`は使えるが、マップの中身自体は事前に書き切る必要がある）。

## Conditions（条件分岐）

```yaml
Conditions:
  IsProd: !Equals [!Ref EnvType, "prod"]

Resources:
  ProdOnlyBucket:
    Type: AWS::S3::Bucket
    Condition: IsProd
```

- `Fn::Equals` / `Fn::And` / `Fn::Or` / `Fn::Not` を組み合わせて条件式を作る
- `Conditions`セクションは`Parameters`・`Mappings`・擬似パラメータを参照できる（`Resources`のプロパティは参照不可）
- リソース/Outputsに`Condition: 条件名`を付けると、条件がfalseの場合そのリソース自体が作成されない
- プロパティ内で値を出し分けたい場合は`Fn::If`（短縮形`!If`）を使う（後述）

## Transform（マクロ）

| 値 | 用途 |
|----|------|
| `AWS::Serverless-2016-10-31` | AWS SAM（`AWS::Serverless::Function`等の短縮記法を有効化） |
| `AWS::Include` | 別ファイルのテンプレートスニペットを埋め込み（S3上のファイルを指定） |
| `AWS::LanguageExtensions` | `Fn::ForEach`（リソースの繰り返し生成）や`Fn::Length`などの言語拡張を有効化 |
| カスタムマクロ | 自前でLambdaベースのテンプレート変換処理を定義したもの |

## Resources共通のリソース属性

`Type`と`Properties`以外に、以下の属性をリソースごとに付与できる。

| 属性 | 役割 |
|------|------|
| `DependsOn` | 明示的な依存順序の指定。`Ref`/`Fn::GetAtt`で参照していれば暗黙的に推論されるため、通常は不要。参照関係のない依存（例: IAMロールのアタッチ完了を待ちたいだけ）がある場合に使う |
| `DeletionPolicy` | スタック削除・リソース削除時の挙動。`Delete`（デフォルト）/`Retain`（リソースを残す）/`Snapshot`（RDS/EBS/ElastiCache/Redshiftなどスナップショット対応リソースのみ、削除前にスナップショット取得） |
| `UpdateReplacePolicy` | 更新でリソースが**置換**される際、旧リソースをどうするか。値は`DeletionPolicy`と同じ（`Delete`/`Retain`/`Snapshot`） |
| `CreationPolicy` | リソース作成完了の判定を、`cfn-signal`からの成功シグナル数やWaitConditionで待つ設定（EC2 Auto Scalingグループ等。詳細は[iac-services.md](iac-services.md)のヘルパースクリプト参照） |
| `UpdatePolicy` | Auto Scalingグループのローリング更新（`AutoScalingRollingUpdate`）や、Lambdaの`AutoPublishAlias`と組み合わせたトラフィックシフト設定など |
| `Metadata` | リソース固有のメタデータ（`AWS::CloudFormation::Init`など） |
| `Condition` | このリソースを作成するかどうかの条件（前述の`Conditions`参照） |

**引っかけポイント**：`DeletionPolicy`は「スタック/リソースが削除されるとき」の話、`UpdateReplacePolicy`は「更新の結果リソースが**置換**されるとき」の話で、トリガーが違う。両方とも省略時のデフォルトは`Delete`なので、本番DBなど残したいリソースは明示的に`Retain`や`Snapshot`を指定しないと消える。

## Outputs

```yaml
Outputs:
  BucketArn:
    Description: "作成したバケットのARN"
    Value: !GetAtt MyBucket.Arn
    Condition: IsProd
    Export:
      Name: !Sub "${AWS::StackName}-BucketArn"
```

- `Export.Name`を付けると他スタックから`Fn::ImportValue`で参照できる（クロススタック参照。[cloudformation-references.md](cloudformation-references.md)参照）
- `Export.Name`は**同一アカウント・同一リージョン内で一意**でなければならない
- `Condition`属性で出力自体を条件分岐できる（対象リソースが作られない条件のとき、その出力も出さないようにする用途）

## 組み込み関数（Ref/GetAtt/ImportValue/動的参照 以外）

| 関数 | YAML短縮形 | 用途 |
|------|------------|------|
| `Fn::Sub` | `!Sub` | 文字列内で`${変数}`を展開。パラメータ・擬似パラメータ・リテラルマップの値を埋め込める |
| `Fn::Join` | `!Join` | 配列を区切り文字で連結して1つの文字列にする |
| `Fn::Select` | `!Select` | 配列からインデックス指定で1要素取得（AZ一覧から1つ選ぶ等） |
| `Fn::Split` | `!Split` | 文字列を区切り文字で配列に分割 |
| `Fn::Base64` | `!Base64` | 文字列をBase64エンコード（EC2の`UserData`で必須） |
| `Fn::Cidr` | `!Cidr` | 親CIDRブロックからサブネット用CIDRを自動計算・分割生成 |
| `Fn::GetAZs` | `!GetAZs` | 指定リージョンのAZ一覧を取得 |
| `Fn::FindInMap` | `!FindInMap` | `Mappings`の値を参照（前述） |
| `Fn::If` / `Fn::And` / `Fn::Or` / `Fn::Not` / `Fn::Equals` | `!If`等 | `Conditions`の定義・プロパティ内での条件分岐 |
| `Fn::Length`（LanguageExtensions） | `!Length` | 配列の要素数を取得 |
| `Fn::ForEach`（LanguageExtensions） | - | リストの要素分だけリソース定義を繰り返し生成 |

`Fn::Sub`の例（ARN組み立てなど頻出）：

```yaml
BucketPolicyResource: !Sub "arn:${AWS::Partition}:s3:::${MyBucket}/*"
LogGroupName: !Sub "/aws/lambda/${AWS::StackName}-handler"
```

**引っかけポイント**：`Fn::Join`と`Fn::Sub`はどちらも文字列連結に使えるが、可読性・保守性の観点では`${}`で変数展開できる`Fn::Sub`が推奨される。試験では「配列を単純に連結したいだけ」なら`Fn::Join`、「テンプレート中に変数を埋め込んだ文章を作りたい」なら`Fn::Sub`という使い分けが問われる。

## 擬似パラメータ（Pseudo Parameters）

| 擬似パラメータ | 内容 |
|----------------|------|
| `AWS::AccountId` | スタックを作成したアカウントID |
| `AWS::Region` | スタックを作成したリージョン |
| `AWS::StackName` | スタック名 |
| `AWS::StackId` | スタックの一意なARN |
| `AWS::Partition` | パーティション（`aws`/`aws-cn`/`aws-us-gov`） |
| `AWS::URLSuffix` | パーティションに応じたドメインサフィックス（通常`amazonaws.com`） |
| `AWS::NoValue` | `Fn::If`の分岐結果として使うと、そのプロパティ自体を「未指定」にできる |

**引っかけポイント**：`AWS::NoValue`は「空文字列」や「デフォルト値」とは別物で、プロパティを**指定しなかったこと**そのものを表現する。`Fn::If`と組み合わせて「条件によってプロパティごと省略したい」場合に使う（例: 条件がfalseのときだけ`KeyName`プロパティを外したい、など）。

## YAML特有の書き方（短縮形とフル形の対応）

| フル形（JSON互換） | YAML短縮形 | 補足 |
|---------------------|------------|------|
| `{"Ref": "Foo"}` | `!Ref Foo` | |
| `{"Fn::GetAtt": ["A", "B"]}` | `!GetAtt A.B` | 属性名にドットを含む場合など短縮形が使えず配列形式が必要になるケースがある |
| `{"Fn::Sub": "..."}` | `!Sub "..."` | |
| `{"Fn::Join": [...]}` | `!Join [...]` | |
| `{"Fn::If": [...]}` | `!If [...]` | |

YAMLとJSONは相互変換可能で、CloudFormationはどちらの形式でも同等に扱う（[iac-services.md](iac-services.md)参照：「JSON形式だから不正解」という誤答トラップに注意）。

## リソース更新時の中断挙動（Update behavior）

| 挙動 | 内容 |
|------|------|
| **No interruption** | プロパティ変更のみ。リソースは維持されたまま更新される |
| **Some interruption** | リソースは維持されるが、更新中に一時的に利用不可になる（例: RDSの一部プロパティ変更でリブートが走る） |
| **Replacement** | 新しいリソースが作成され、参照が切り替わってから旧リソースが削除される（**物理ID・エンドポイントが変わる**点に注意） |

どのプロパティ変更がどの挙動になるかはリソースタイプごとに異なり、AWS公式のリソースリファレンス（各プロパティの説明に "Update requires: No interruption / Some interruption / Replacement" と明記）で確認する。**置換（Replacement）が起きるケースにおいて旧リソースをどう扱うか**を制御するのが`UpdateReplacePolicy`（前述）。

## スタックポリシー（Stack Policy）

- スタック更新時に、特定の**論理ID**のリソースが誤って更新・置換・削除されるのを防ぐJSONポリシー（IAMポリシーとは別物、`Principal`の概念はなく`Resource`に論理IDを指定する）
- デフォルトでは全リソースが更新可能。重要なリソース（本番DBなど）だけ`Deny`ルールを明示して保護するのが典型的な使い方
- スタック単位で1つ設定でき、更新のたびに一時的に上書き（override）することも可能

## ネストしたスタック vs クロススタック参照（要点）

| | ネストしたスタック（`AWS::CloudFormation::Stack`） | クロススタック参照 |
|---|---|---|
| 仕組み | 親テンプレートの`Resources`内に子テンプレートをリソースとして埋め込み、`Parameters`で値を渡す | 独立したスタック同士を`Outputs`の`Export`と`Fn::ImportValue`で連携（[cloudformation-references.md](cloudformation-references.md)） |
| ライフサイクル | 子は親と一体（親を消すと子も消える） | 各スタックが独立してライフサイクルを持つ |
| 向いている用途 | 強く結合した使い捨てのコンポーネント分割（同じテンプレートの再利用等） | VPCなど複数スタックから共有される基盤層を、他と独立して管理したい場合 |

## 引っかけポイントまとめ

- `Resources`以外の全セクションは省略可能。「`Parameters`が無いテンプレートは無効」という選択肢は誤り
- `Conditions`は`Resources`セクションの値を参照できない（`Parameters`/`Mappings`/擬似パラメータのみ参照可）
- `Mappings`の値は静的リテラルのみで、動的に計算した値は入れられない
- `NoEcho`はマスキングであって暗号化・秘匿ではない（[cloudformation-references.md](cloudformation-references.md)の`SecureString`/動的参照と混同しない）
- `DeletionPolicy`（削除時）と`UpdateReplacePolicy`（更新による置換時）はトリガーが異なる別属性。デフォルトはどちらも`Delete`
- `AWS::NoValue`はプロパティの「未指定化」であり、空文字列やデフォルト値とは異なる
- テンプレート形式はJSON/YAMLどちらも正解になり得る（形式そのものは正誤の分かれ目にならない）

## 関連

- [cloudformation-references.md](cloudformation-references.md)：`Ref`/`Fn::GetAtt`/`Fn::ImportValue`/動的参照など「値の参照方式」の詳細比較
- [iac-services.md](iac-services.md)：CloudFormation自体の位置づけ、ヘルパースクリプト（cfn-init等）、チェンジセット、StackSets、ドリフト検出、カスタムリソース、SAM/CDK/Beanstalkとの比較
