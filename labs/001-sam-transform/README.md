# 001 SAM Transform

## 問題

Q22（出典: 模試）
サーバーレスなインフラをSAM（Serverless Application Model）で定義し、
それをCloudFormationでデプロイしたい。この要件を満たす方法はどれか。

1. `AWS::CloudFormation::Stack` リソースでネストスタックを組む
2. テンプレートに `Transform: AWS::Serverless-2016-10-31` を追加し、
   SAM構文（`AWS::Serverless::Function` など）でリソースを定義する
3. CodeDeployのAppSpecファイルにSAMリソースを直接記述する
4. CloudFormationのカスタムリソースとしてSAMリソースをラップする

正解: 2

## 選んだ答えと理由

SAMを「CloudFormationとは別の独立したデプロイの仕組み」だと思い込み、
選択肢1（ネストスタック）を選んでしまった。
SAMがCloudFormationの拡張構文であるという認識がなかった。

## 誤答の型

用語未知（SAM未経験）

## 仮説

`Transform` セクションはCloudFormationに対して「このテンプレートは
デプロイ前にマクロで前処理してから展開してほしい」と伝える宣言であり、
`AWS::Serverless-2016-10-31` を指定すると `AWS::Serverless::Function` のような
簡略構文がLambda・API Gateway・IAMロールなどの通常のCloudFormationリソースに
変換されてからスタックが作成される。つまりSAMは独立したデプロイ機構ではなく、
CloudFormationのマクロ機能の一種である。

## 検証

1. `sam init` でPythonランタイムのHello Worldテンプレートを作成し、
   本Labの `template.yaml` と構成を比較する
2. `sam build` でビルドし、`.aws-sam/build/` 配下に生成される
   `template.yaml` を確認する（この時点ではまだ `AWS::Serverless::Function` のまま）
3. `sam deploy --guided --stack-name dva-001-sam-transform --tags Project=dva-study`
   でデプロイする
4. CloudFormationコンソールでスタックを開き、「テンプレート」タブ →
   「表示: 処理済みテンプレート」を選択し、`AWS::Serverless::Function` が
   `AWS::Lambda::Function` + `AWS::IAM::Role` + `AWS::ApiGateway::*` 等に
   展開されていることを確認する
5. 元の `template.yaml`（`Transform` あり）と処理済みテンプレートを見比べ、
   Transformが「デプロイ時にサーバー側で展開されるマクロ」であることを確認する

<!-- 実際に検証した際の出力・スクリーンショットへのリンクなどをここに追記する -->

## 結論（1行）

TransformはCFnデプロイ時にサーバー側で展開されるマクロ

## 片付け

```bash
sam delete --stack-name dva-001-sam-transform
```
