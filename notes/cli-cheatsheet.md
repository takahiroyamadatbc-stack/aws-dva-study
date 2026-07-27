# AWS CLI チートシート

検証でよく使うコマンドのメモ。

## CloudFormation

| 用途 | コマンド | メモ |
|------|----------|------|
| dva-* スタック一覧（消し忘れ検出） | `aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query "StackSummaries[?starts_with(StackName,'dva-')].StackName"` | 作業終了時に必ず実行する |
| スタック詳細 | `aws cloudformation describe-stacks --stack-name <name>` | |
| スタック削除 | `aws cloudformation delete-stack --stack-name <name>` | |

## IAM Identity Center (SSO)

| 用途 | コマンド | メモ |
|------|----------|------|
| SSOログイン | `aws sso login --profile <profile>` | start URLは `~/.aws/config` 側で管理 |
| 現在の認証情報確認 | `aws sts get-caller-identity --profile <profile>` | |

## CDK

| 用途 | コマンド | メモ |
|------|----------|------|
| 差分確認 | `cdk diff` | Labディレクトリで実行 |
| デプロイ | `cdk deploy --tags Project=dva-study` | |
| 削除 | `cdk destroy` | |

## SAM

| 用途 | コマンド | メモ |
|------|----------|------|
| ビルド | `sam build` | |
| デプロイ | `sam deploy --guided --tags Project=dva-study` | |
| 削除 | `sam delete` | |

## その他

- （ここに追記していく）
