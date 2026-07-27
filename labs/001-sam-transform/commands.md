# commands.md — 001 SAM Transform

実行したコマンドと出力の記録。出力欄は検証時に貼り付ける。

## 1. sam init（比較用に別ディレクトリで実行）

```bash
sam init --runtime python3.12 --name sam-transform-compare
```

出力:
```
（ここに貼り付け）
```

## 2. sam build

```bash
sam build
```

出力:
```
（ここに貼り付け）
```

## 3. sam deploy（初回はguidedで）

```bash
sam deploy --guided \
  --stack-name dva-001-sam-transform \
  --tags Project=dva-study
```

出力:
```
（ここに貼り付け）
```

## 4. 処理済みテンプレートの確認

CloudFormationコンソール → 対象スタック → 「テンプレート」タブ →
「表示」を「処理済みテンプレート」に切り替えて確認する（CLIでは未確認）。

差分メモ:
```
（ここに気づいた差分を書く）
```

## 5. 動作確認

```bash
curl "$(aws cloudformation describe-stacks \
  --stack-name dva-001-sam-transform \
  --query "Stacks[0].Outputs[?OutputKey=='HelloApiUrl'].OutputValue" \
  --output text)"
```

出力:
```
（ここに貼り付け）
```

## 6. 片付け

```bash
sam delete --stack-name dva-001-sam-transform
```

出力:
```
（ここに貼り付け）
```
