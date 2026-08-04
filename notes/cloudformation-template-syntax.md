# CloudFormation テンプレートの書き方・構成要素 メモ

模擬テストで「テンプレートを実際に書いたことがない」ために解けなかった問題への対策ノート。**テンプレートファイル自体の構造・記法・リソース属性のオプション**に絞って整理する。`Ref`/`Fn::GetAtt`/`Fn::ImportValue`/動的参照の詳しい比較は[cloudformation-references.md](cloudformation-references.md)、CFn自体の位置づけ・ヘルパースクリプト・チェンジセット・StackSets・ドリフト検出・カスタムリソースは[iac-services.md](iac-services.md)を参照（本ノートでは重複させない）。

## 1. 全体構造（最小サンプル）

```yaml
AWSTemplateFormatVersion: '2010-09-09'

Description: サンプルテンプレート

Parameters:
  InstanceType:
    Type: String
    Default: t3.micro

Resources:
  MyEC2Instance:
    Type: AWS::EC2::Instance
    Properties:
      InstanceType: !Ref InstanceType
      ImageId: ami-xxxxxxxx

Outputs:
  InstanceId:
    Value: !Ref MyEC2Instance
```

| セクション | 必須 | 役割 |
| --- | --- | --- |
| `AWSTemplateFormatVersion` | 任意 | `"2010-09-09"`固定（現状これ以外の値は存在しない） |
| `Description` | 任意 | テンプレートの説明文 |
| `Metadata` | 任意 | `AWS::CloudFormation::Interface`（コンソールでのパラメータ表示グループ化）や`AWS::CloudFormation::Init`（cfn-init用、[iac-services.md](iac-services.md)参照）など |
| `Parameters` | 任意 | 外部から渡す値 |
| `Mappings` | 任意 | 固定値の辞書（静的ルックアップテーブル） |
| `Conditions` | 任意 | 条件分岐 |
| `Transform` | 任意 | テンプレート全体に適用するマクロ（SAM/Includeなど） |
| `Resources` | **必須** | 作成するAWSリソース本体 |
| `Outputs` | 任意 | 作成結果の出力 |

`Resources`だけが必須。他は書かなければ省略時のデフォルト挙動になる。

## 2. Resourcesの文法（最重要）

基本形：

```yaml
Resources:
  論理ID:
    Type: AWS::サービス::リソース種類
    Properties:
      プロパティ名: 値
```

例：

```yaml
Resources:
  MyBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: my-test-bucket
```

- **論理ID**（`MyBucket`）：テンプレート内だけで使う識別名
- **AWSリソース種類**（`Type`）：作成するリソースの型
- **設定**（`Properties`）：そのリソースの設定値

実際にAWS上にできる名前（**Physical ID**、例: S3バケット名やEC2インスタンスIDそのもの）はCloudFormationが決める。`BucketName`のように明示的に物理名を指定できるプロパティもあるが、指定しなければCloudFormationがスタック名等を元に自動生成する。**論理ID ≠ 物理ID**という区別は試験でも問われるポイント。

## 3. Logical ID（論理ID）と他リソースからの参照

```yaml
Resources:
  SecurityGroup:
    Type: AWS::EC2::SecurityGroup

  Server:
    Type: AWS::EC2::Instance
    Properties:
      SecurityGroups:
        - !Ref SecurityGroup
```

`!Ref SecurityGroup`は「`SecurityGroup`という論理IDのリソースの値を取得して」という意味。`Ref`はCloudFormationで最も使う組み込み関数。

## 4. 組み込み関数（Intrinsic Function）— 頻出のもの

CloudFormation独自の関数群。YAMLでは`!関数名`の短縮形で書ける。

### `!Ref` — 値を取得

```yaml
VpcId: !Ref MyVpc
```

`MyVpc`が`AWS::EC2::VPC`なら、`!Ref MyVpc`は`vpc-0123456789`のような物理IDに解決される（リソースの種類によって「何が返るか」が変わる点は[cloudformation-references.md](cloudformation-references.md)参照）。

### `!GetAtt` — 属性を取得

```yaml
MyDistribution:
  Type: AWS::CloudFront::Distribution
  Properties:
    DomainName: !GetAtt MyBucket.DomainName
```

`MyBucket`の`DomainName`属性を取ってくる。`Ref`では取れない細かい属性（ARN、DNS名など）を取るときに使う。

### `!Sub` — 文字列置換

```yaml
Parameters:
  Environment:
    Default: dev

Resources:
  MyBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub "${Environment}-bucket"
```

結果：`dev-bucket`。`${}`の中にはパラメータ・擬似パラメータ・`論理ID.属性名`（`Fn::GetAtt`相当）を埋め込める。

### `!Join` — 文字列結合

```yaml
!Join
  - "-"
  - - dev
    - app
    - server
```

結果：`dev-app-server`。単純な配列連結なら`Join`、変数を埋め込んだ文章を作るなら`Sub`、という使い分けが試験でも問われる。

> `Ref`/`GetAtt`/`ImportValue`/動的参照（SSM・Secrets Manager）の使い分けを詳しく比較した表は[cloudformation-references.md](cloudformation-references.md)にまとめてあるので、そちらを参照。

### その他の組み込み関数

| 関数 | YAML短縮形 | 用途 |
| --- | --- | --- |
| `Fn::Select` | `!Select` | 配列からインデックス指定で1要素取得（AZ一覧から1つ選ぶ等） |
| `Fn::Split` | `!Split` | 文字列を区切り文字で配列に分割 |
| `Fn::Base64` | `!Base64` | 文字列をBase64エンコード（EC2の`UserData`で必須） |
| `Fn::Cidr` | `!Cidr` | 親CIDRブロックからサブネット用CIDRを自動計算・分割生成 |
| `Fn::GetAZs` | `!GetAZs` | 指定リージョンのAZ一覧を取得 |
| `Fn::FindInMap` | `!FindInMap` | `Mappings`の値を参照（後述） |
| `Fn::If` / `Fn::And` / `Fn::Or` / `Fn::Not` / `Fn::Equals` | `!If`等 | `Conditions`の定義・プロパティ内での条件分岐 |
| `Fn::Length`（LanguageExtensions） | `!Length` | 配列の要素数を取得 |
| `Fn::ForEach`（LanguageExtensions） | - | リストの要素分だけリソース定義を繰り返し生成 |

## 5. Parameters

外から値を渡す場所。

```yaml
Parameters:
  Environment:
    Type: String
    Default: dev
```

利用：

```yaml
BucketName: !Sub "${Environment}-bucket"
```

イメージ：デプロイ時に`Environment=prod`を渡す → `prod-bucket`が作成される。

| 属性 | 用途 |
| --- | --- |
| `Type` | `String` / `Number` / `List<Number>` / `CommaDelimitedList` / AWS固有型（`AWS::EC2::KeyPair::KeyName`, `AWS::EC2::VPC::Id`, `AWS::EC2::Subnet::Id`, `AWS::EC2::SecurityGroup::Id`など、コンソールでドロップダウン選択になる）/ `AWS::SSM::Parameter::Value<Type>`（詳細は[cloudformation-references.md](cloudformation-references.md)） |
| `Default` | 未指定時のデフォルト値 |
| `AllowedValues` | 選択肢を配列で限定 |
| `AllowedPattern` | 正規表現でバリデーション |
| `ConstraintDescription` | `AllowedPattern`等に違反した際のエラーメッセージ |
| `MinLength` / `MaxLength` | 文字列長の制約 |
| `MinValue` / `MaxValue` | 数値の範囲制約 |
| `NoEcho` | `true`にするとコンソール/CLIの出力でマスクされる |

**引っかけポイント**：`NoEcho: true`は「表示をマスクする」だけで、値自体を暗号化・秘匿するものではない。パスワード等の機密値を本当に秘匿したい場合は`NoEcho`ではなく、Secrets Manager/SSM SecureStringの動的参照を使うべき（[cloudformation-references.md](cloudformation-references.md)参照）。

## 6. Mappings（固定値の辞書）

```yaml
Mappings:
  RegionMap:
    us-east-1:
      AMI: ami-0ff8a91507f77f867
    ap-northeast-1:
      AMI: ami-0c3fd0f5d33134a76
```

`!FindInMap [RegionMap, !Ref "AWS::Region", AMI]`で参照する。

**引っかけポイント**：`Mappings`の値は**静的なリテラルのみ**。`Parameters`や擬似パラメータの値をキー・バリューとして動的に生成することはできない（キーの決定に`!Ref`は使えるが、マップの中身自体は事前に書き切る必要がある）。

## 7. Conditions（条件分岐）

例えば本番だけリソースを作る。

```yaml
Conditions:
  IsProduction: !Equals [!Ref Environment, prod]

Resources:
  BackupBucket:
    Type: AWS::S3::Bucket
    Condition: IsProduction
```

意味：`Environment`が`prod`なら作成、それ以外は作らない。

- `Fn::Equals` / `Fn::And` / `Fn::Or` / `Fn::Not` を組み合わせて条件式を作る
- `Conditions`セクションは`Parameters`・`Mappings`・擬似パラメータを参照できる（`Resources`のプロパティは参照不可）
- リソース/Outputsに`Condition: 条件名`を付けると、条件がfalseの場合そのリソース自体が作成されない
- プロパティ内で値を出し分けたい場合は`Fn::If`（短縮形`!If`）を使う

## 8. DependsOn（依存関係）

CloudFormationは基本的に依存関係を自動判定する。

```yaml
Instance:
  Type: AWS::EC2::Instance
  Properties:
    SecurityGroupIds:
      - !Ref SecurityGroup
```

`!Ref`/`!GetAtt`で参照していれば、「SecurityGroup作成 → EC2作成」の順序は自動で推論される。

参照関係がないのに順序を強制したい場合は明示できる。

```yaml
Instance:
  Type: AWS::EC2::Instance
  DependsOn: SecurityGroup
```

（例: IAMロールのアタッチ完了を待ちたいだけ、など参照では表現できない依存関係がある場合）

## 9. Transform（マクロ）

| 値 | 用途 |
| --- | --- |
| `AWS::Serverless-2016-10-31` | AWS SAM（`AWS::Serverless::Function`等の短縮記法を有効化） |
| `AWS::Include` | 別ファイルのテンプレートスニペットを埋め込み（S3上のファイルを指定） |
| `AWS::LanguageExtensions` | `Fn::ForEach`や`Fn::Length`などの言語拡張を有効化 |
| カスタムマクロ | 自前でLambdaベースのテンプレート変換処理を定義したもの |

## 10. Resourcesのその他の属性（DeletionPolicy等）

`Type`/`Properties`/`DependsOn`/`Condition`以外にも、リソースごとに以下の属性を付与できる。

| 属性 | 役割 |
| --- | --- |
| `DeletionPolicy` | スタック削除・リソース削除時の挙動。`Delete`（デフォルト）/`Retain`（リソースを残す）/`Snapshot`（RDS/EBS/ElastiCache/Redshiftなどスナップショット対応リソースのみ、削除前にスナップショット取得） |
| `UpdateReplacePolicy` | 更新でリソースが**置換**される際、旧リソースをどうするか。値は`DeletionPolicy`と同じ（`Delete`/`Retain`/`Snapshot`） |
| `CreationPolicy` | リソース作成完了の判定を、`cfn-signal`からの成功シグナル数やWaitConditionで待つ設定（EC2 Auto Scalingグループ等。詳細は[iac-services.md](iac-services.md)のヘルパースクリプト参照） |
| `UpdatePolicy` | Auto Scalingグループのローリング更新（`AutoScalingRollingUpdate`）や、Lambdaの`AutoPublishAlias`と組み合わせたトラフィックシフト設定など |
| `Metadata` | リソース固有のメタデータ（`AWS::CloudFormation::Init`など） |

**引っかけポイント**：`DeletionPolicy`は「スタック/リソースが削除されるとき」の話、`UpdateReplacePolicy`は「更新の結果リソースが**置換**されるとき」の話で、トリガーが違う。両方とも省略時のデフォルトは`Delete`なので、本番DBなど残したいリソースは明示的に`Retain`や`Snapshot`を指定しないと消える。

## 11. Metadata / Outputs

作ったリソース情報を表示する。

```yaml
Outputs:
  BucketName:
    Value: !Ref MyBucket
```

デプロイ後、コンソールやCLIで`BucketName: my-test-bucket`のように確認できる。

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
- `Condition`属性で出力自体を条件分岐できる

## 12. CDKとの関係

CDKはこのCloudFormationテンプレートを最終的に生成するツール。

```text
CDK(Python等)
    ↓ cdk synth
CloudFormation Template(YAML)
    ↓ cdk deploy（内部はCloudFormationのスタック作成/更新）
AWS Resource
```

CDKの`bucket = s3.Bucket(self, "MyBucket")`のようなコードは、`cdk synth`で本ノートのようなCloudFormation YAMLに変換され、それをCloudFormationがデプロイする。つまりCDKを使っていても、最終的に動いているのは常にCloudFormationのスタック（ロールバック・チェンジセット・ドリフト検出などの挙動もCloudFormationのもの）。CDK自体の詳細比較は[iac-services.md](iac-services.md)参照。

## 13. DVA試験目線の優先順位

CloudFormation文法で覚える優先度が高いもの：

1. `Resources`（`Type` / `Properties`）
2. `!Ref`
3. `!GetAtt`
4. `!Sub`
5. `Parameters`
6. `Conditions`
7. `Outputs`
8. `DependsOn`

特に「**この値を別リソースに渡すには？**」系の設問で`Ref` / `GetAtt` / `Sub`がよく出る。「物理IDが欲しいのか属性が欲しいのか」「テンプレート内かスタック外か」を見極める視点は[cloudformation-references.md](cloudformation-references.md)の判断フローと合わせて押さえておく。

## 14. その他の頻出トピック（要点のみ）

擬似パラメータ・YAML短縮形・更新時の中断挙動・スタックポリシー・ネスト vs クロススタックを簡潔にまとめる。

### 擬似パラメータ（Pseudo Parameters）

| 擬似パラメータ | 内容 |
| --- | --- |
| `AWS::AccountId` | スタックを作成したアカウントID |
| `AWS::Region` | スタックを作成したリージョン |
| `AWS::StackName` | スタック名 |
| `AWS::StackId` | スタックの一意なARN |
| `AWS::Partition` | パーティション（`aws`/`aws-cn`/`aws-us-gov`） |
| `AWS::URLSuffix` | パーティションに応じたドメインサフィックス（通常`amazonaws.com`） |
| `AWS::NoValue` | `Fn::If`の分岐結果として使うと、そのプロパティ自体を「未指定」にできる（空文字列やデフォルト値とは別物） |

### YAML短縮形とフル形（JSON互換）の対応

| フル形 | YAML短縮形 | 補足 |
| --- | --- | --- |
| `{"Ref": "Foo"}` | `!Ref Foo` | |
| `{"Fn::GetAtt": ["A", "B"]}` | `!GetAtt A.B` | 属性名にドットを含む場合など、短縮形が使えず配列形式が必要になるケースがある |
| `{"Fn::Sub": "..."}` | `!Sub "..."` | |

YAMLとJSONは相互変換可能で、CloudFormationはどちらの形式でも同等に扱う（「JSON形式だから不正解」という誤答トラップに注意）。

### リソース更新時の中断挙動（Update behavior）

| 挙動 | 内容 |
| --- | --- |
| **No interruption** | プロパティ変更のみ。リソースは維持されたまま更新される |
| **Some interruption** | リソースは維持されるが、更新中に一時的に利用不可になる |
| **Replacement** | 新しいリソースが作成され、参照が切り替わってから旧リソースが削除される（物理ID・エンドポイントが変わる点に注意） |

どのプロパティ変更がどの挙動になるかはリソースタイプごとに異なり、AWS公式のリソースリファレンスで確認する。

### スタックポリシー（Stack Policy）

スタック更新時に、特定の**論理ID**のリソースが誤って更新・置換・削除されるのを防ぐJSONポリシー（IAMポリシーとは別物、`Resource`に論理IDを指定する）。デフォルトでは全リソースが更新可能で、重要なリソース（本番DBなど）だけ`Deny`ルールを明示して保護する。

### ネストしたスタック vs クロススタック参照

| 項目 | ネストしたスタック（`AWS::CloudFormation::Stack`） | クロススタック参照 |
| --- | --- | --- |
| 仕組み | 親テンプレートの`Resources`内に子テンプレートをリソースとして埋め込み、`Parameters`で値を渡す | 独立したスタック同士を`Outputs`の`Export`と`Fn::ImportValue`で連携 |
| ライフサイクル | 子は親と一体（親を消すと子も消える） | 各スタックが独立してライフサイクルを持つ |
| 向いている用途 | 強く結合した使い捨てのコンポーネント分割 | VPCなど複数スタックから共有される基盤層を独立して管理したい場合 |

## 引っかけポイントまとめ

- `Resources`以外の全セクションは省略可能。「`Parameters`が無いテンプレートは無効」という選択肢は誤り
- **論理ID**（テンプレート内の識別名）と**物理ID**（AWS上の実名、CloudFormationが決める）は別物
- `Conditions`は`Resources`セクションの値を参照できない（`Parameters`/`Mappings`/擬似パラメータのみ参照可）
- `Mappings`の値は静的リテラルのみで、動的に計算した値は入れられない
- `NoEcho`はマスキングであって暗号化・秘匿ではない
- `DeletionPolicy`（削除時）と`UpdateReplacePolicy`（更新による置換時）はトリガーが異なる別属性。デフォルトはどちらも`Delete`
- テンプレート形式はJSON/YAMLどちらも正解になり得る

## 関連

- [cloudformation-references.md](cloudformation-references.md)：`Ref`/`Fn::GetAtt`/`Fn::ImportValue`/動的参照など「値の参照方式」の詳細比較
- [iac-services.md](iac-services.md)：CloudFormation自体の位置づけ、ヘルパースクリプト（cfn-init等）、チェンジセット、StackSets、ドリフト検出、カスタムリソース、SAM/CDK/Beanstalkとの比較
