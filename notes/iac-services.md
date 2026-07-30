# IaC（Infrastructure as Code）サービス比較メモ

「IaC = CloudFormation（YAML）」だけで覚えていると、選択肢にCodeBuild/Amplify/AppSyncなど紛らわしいサービスが混ざったときに誤答しやすい。ここでは「インフラ・アプリを宣言的/コードで定義してデプロイするサービス」を横断的に整理し、あわせて紛らわしい非IaC系サービスとの違いもまとめる。

## 比較表

| サービス | テンプレート形式 | 対象範囲 | ロールバック | 試験で問われやすいポイント |
|----------|------------------|----------|---------------|----------------------------|
| **AWS CloudFormation** | JSON **または** YAML | EC2/VPC/RDS/Lambdaなどほぼ全AWSリソース | スタック更新失敗時に自動ロールバック | JSON/YAMLどちらも使える（YAML限定ではない）。ヘルパースクリプト（cfn-init/cfn-signal/cfn-hup）でEC2内のソフトウェア導入・シグナル通知ができる |
| **AWS SAM** | YAML（CloudFormationの拡張＝`Transform: AWS::Serverless-2016-10-31`） | サーバーレス中心（Lambda/API Gateway/DynamoDB/Step Functions） | CloudFormationと同じ（スタック単位） | `sam local`でローカル実行・デバッグ可能。`AutoPublishAlias`＋`DeploymentPreference`でLambdaのCanary/Linearデプロイができる（[deployment.md](deployment.md)参照） |
| **AWS CDK** | TypeScript/Python/Java/C#/Go等の**汎用言語** | CloudFormationと同じ（内部でCFnテンプレートを合成） | 合成後はCloudFormationのロールバック機構に依存 | `cdk synth`でCFnテンプレートを生成、`cdk deploy`でデプロイ。L1(Cfn*)/L2/L3 Constructの抽象度の違いが問われる |
| **AWS Elastic Beanstalk** | アプリコード＋`.ebextensions`（YAML/JSON設定）or Saved Configuration | EC2/ELB/ASG/RDSなどのWebアプリ実行環境一式 | バージョンのロールバック（以前のアプリバージョンに切替） | PaaS的にプロビジョニングまで自動化。内部的にCloudFormationを利用している |
| **AWS OpsWorks** | Chef/Puppetのレシピ・マニフェスト | EC2上のミドルウェア構成管理（Stacks/Layers） | 特になし（構成管理ツール） | 試験では「レガシー・Chef/Puppetを使いたい場合」の選択肢として出る程度。優先度は低い |
| **AWS Systems Manager (State Manager/Automation)** | SSMドキュメント（YAML/JSON） | 既存インスタンスの構成維持・パッチ適用・自動化タスク | ドキュメント次第 | 新規プロビジョニングよりも「既存リソースの状態維持・運用自動化」向け。IaCというよりConfiguration as Code寄り |

## 各サービスの深掘りポイント

### AWS CloudFormation
- テンプレート形式は **JSON/YAMLどちらもOK**（今回の誤答選択肢の「JSON形式」も実は間違いではない＝正解の理由はJSON/YAMLの形式ではなく「CloudFormationを使うこと自体」）
- **ヘルパースクリプト**（EC2にプリインストール済み、`cfn-init`が呼ぶ）
  | スクリプト | 役割 |
  |------------|------|
  | `cfn-init` | メタデータ（`AWS::CloudFormation::Init`）を元にパッケージ導入・ファイル配置・サービス起動を実行 |
  | `cfn-signal` | 起動完了をCloudFormationに通知（`CreationPolicy`/`WaitCondition`と組み合わせる） |
  | `cfn-hup` | メタデータの変更を検知し、更新時に再設定を自動実行 |
  | `cfn-get-metadata` | メタデータを取得（デバッグ用） |
- **チェンジセット（Change Set）**: 適用前に変更内容をプレビュー
- **スタックセット（StackSets）**: 複数アカウント/リージョンへ同一テンプレートを一括適用
- **ドリフト検出（Drift Detection）**: 実際のリソースとテンプレート定義の差分を検出
- **DeletionPolicy/UpdateReplacePolicy**: リソース削除・置換時の挙動制御（`Retain`/`Snapshot`/`Delete`）
- 「同一環境の再現」「反復デプロイ」「ロールバック」という要件セットが出たら、まずCloudFormation（またはSAM/CDKなどその上位ツール）を疑う

### AWS SAM
- CloudFormationの拡張なので**素のCloudFormation構文もそのまま書ける**
- `AWS::Serverless::Function`などの短縮記法でLambda+API Gatewayなどをまとめて定義
- ローカルテスト（`sam local invoke`/`sam local start-api`）が可能な点がCDK/CFnとの差別化ポイント

### AWS CDK
- 「プログラミング言語でインフラを書く」＝ループ・条件分岐・関数化ができ、CloudFormationのテンプレートより柔軟
- 最終的に`cdk synth`でCloudFormationテンプレートに変換されるため、デプロイの実行主体はCloudFormation
- Construct Library（L1=Cfn*, L2=高レベルAPI, L3=パターン集）の階層が問われることがある

### AWS Elastic Beanstalk
- インフラ定義というより「アプリケーションのデプロイ環境を丸ごと自動構築するPaaS」
- `.ebextensions`でEC2の追加設定（yumパッケージ導入・環境変数など）が可能
- デプロイ方式（All at once/Rolling/Rolling with additional batch/Immutable/Blue-Green）はCodeDeployのデプロイタイプと混同しやすいので[deployment.md](deployment.md)と合わせて整理する

## 紛らわしい非IaC系サービスとの違い（今回の問題の整理）

今回のようにIaCサービスを問う設問では、**CI/CDサービス**や**アプリ実行基盤サービス**が誤答選択肢として混ぜられることが多い。役割の境界を混同しないこと。

| サービス | 本来の役割 | なぜIaCの正解になり得ないか |
|----------|------------|------------------------------|
| **AWS CodeBuild** | ソースのビルド・テスト・デプロイ用パッケージの作成（ビルドサービス） | インフラのプロビジョニングやEC2への継続的デプロイ・ロールバックの仕組みを持たない。AppSpec/デプロイグループは**CodeDeploy**の概念であり、CodeBuildの機能ではない |
| **AWS CodeDeploy** | 既にあるインスタンス/Lambda/ECSへの**デプロイ実行**（In-place/Blue-Green） | インフラそのものの定義（リソース作成）は行わない。EC2インスタンス自体はCloudFormation等で先に用意する必要がある |
| **AWS Amplify** | フロントエンド/モバイルアプリ向けのホスティング＋CI/CD（トラフィック分割デプロイあり） | EC2インスタンス上のバックエンドアプリ管理は対象外。IaC的な裏側はCDKだが、設問の「EC2への自動デプロイ」要件には合わない |
| **AWS AppSync** | GraphQL APIのマネージドサービス（リゾルバーでDynamoDB/Lambda/RDS等と連携） | EC2のプロビジョニングやデプロイとは無関係。「リゾルバーをバージョン管理として使う」という誤答パターンに注意 |

### 見分け方のコツ
- 設問に「**同一環境の再現**」「**反復デプロイ**」「**ロールバック**」「**テンプレート**」というキーワードが並ぶ → CloudFormation（またはSAM/CDK）を軸に考える
- 「ビルド」「テストの実行」というキーワード → CodeBuild
- 「既存環境への配布」「AppSpec」「デプロイグループ」「Canary/Linear」というキーワード → CodeDeploy
- 「フロントエンド」「モバイル」「Gitプッシュで自動ビルド」 → Amplify
- 「GraphQL」「リゾルバー」 → AppSync（デプロイ手段ではなくAPI基盤）

## その他

- （ここに追記していく）
