# AWS Developer Associate (DVA-C02) 試験勉強リポジトリ

模擬試験・過去の演習で間違えた問題を、実際にAWSを触って検証し、
コードと結論をセットで残していくためのリポジトリです。

## 目的

- 誤答した問題を「なぜ間違えたか」まで分解し、仮説を実機検証で確認する
- 検証に使ったIaC/コマンドをLab単位で残し、後から再現できるようにする
- 試験直前は [索引テーブル](#索引) の「一行結論」列だけを読み返せば復習が完結する状態を保つ

## ディレクトリ構成

```
aws-dva-study/
├── labs/
│   ├── _template/        # 新しいLabのひな形（コピー元）
│   └── NNN-topic/        # 個々のLab（連番、フラット管理）
├── notes/                 # 試験ドメイン横断の暗記メモ
└── scratch/               # 使い捨ての検証置き場（gitignore対象）
```

## 依存環境について

依存はリポジトリ直下に **1つだけ** 置きます。Lab単位で venv や node_modules は作りません。

```bash
python -m venv .venv
.venv/Scripts/activate
pip install -r requirements.txt
```

CDKを使うLabは、Labディレクトリに `cd` してから `cdk` コマンドを実行してください
（上位ディレクトリで解決した依存を使う前提の構成です）。

```bash
cd labs/002-lambda-alias
cdk synth
```

## Labの作り方

Labには2つの型があり、内容に応じて選ぶ（CDKを組むほどの規模でなければCLIスクリプト型でよい）。
標準ではコード（IaC/CLIスクリプト）とREADMEの結論整理までを完了条件とし、実機へのデプロイ・実行はユーザーが明示的に指示した場合のみ行う（詳細はCLAUDE.md「AWS実行について」を参照）。

- **IaC型**: CDK/SAMでリソースを構築する場合。`template.yaml` / `app.py` / `cdk.json` / `stack.py` を使う
- **CLIスクリプト型**: CLIコマンドの実行だけで検証できる場合。`01_create_xxx.sh` → `02_check_xxx.sh` → `0N_delete_xxx.sh` のように、実行順に番号を振ったシェルスクリプトとして残す。最後の番号は必ず片付け（delete）用スクリプトにする

1. `labs/NNN-topic/` を作る（連番は最後に使った番号+1）。IaC型は `labs/_template/` をコピーする
2. `README.md` の各セクション（問題／選んだ答えと理由／誤答の型／仮説／検証／結論／片付け）を埋める
3. テンプレの型に収まらない、試験に出そうな周辺知識や整理したい内容は `memo.md` にMarkdownでまとめてよい。誤答の検証を伴わない知識整理オンリーのLabは、README.mdを作らず `memo.md` だけでもよい
4. 検証が終わったら本READMEの索引テーブルに1行追加する（memo.mdのみのLabは任意）

**「一行結論」を埋めることがLabの完了条件です。** 試験直前の見直しは索引テーブルの
「一行結論」列だけを読めば足りるようにしてください。

## 命名・事故防止の規約

- スタック名・S3バケット名・DynamoDBテーブル名など、AWS上に作るリソース名は必ず `dva-NNN-topic` 形式にし、Labのフォルダ番号（NNN）と一致させる（例: `dva-002-lambda-alias`）
- デプロイ・作成時は必ず `--tags Project=dva-study`（CLIコマンドごとの相当するタグ指定）を付ける
- Labは使い捨て前提。検証が終わったら**必ず片付ける**（`cdk destroy` / `sam delete` / CLIスクリプト型なら `0N_delete_xxx.sh` など）

### 消し忘れ検出コマンド

作業終了時・久しぶりに作業を再開した時は、まずこれで残骸がないか確認する。CFnスタックだけでなく、CLIスクリプト型Labで直接作ったリソースも `Project=dva-study` タグで横断的に検出する。

```bash
# CFnスタック（IaC型Lab）
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?starts_with(StackName,'dva-')].StackName"

# タグ付けされた全リソース（CLIスクリプト型Labも含む）
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=dva-study \
  --query "ResourceTagMappingList[].ResourceARN"
```

## 索引

| Lab | 問題 | テーマ | ツール | 状態 | 一行結論 |
|-----|------|--------|--------|------|----------|
| [001](labs/001-sam-transform/) | Q22 | SAM Transform | SAM | 完 | TransformはCFnデプロイ時にサーバー側で展開されるマクロ |
| [007](labs/007-kinesis-lambda-iteratorage/) | - | Kinesis+Lambda IteratorAge | CLI | 完 | IteratorAgeは滞留時間の指標。改善はLambdaメモリ増加とシャード数増加で、タイムアウト変更は的外れ |
| [008](labs/008-alb-xff-clientip/) | Q49 | ALB配下でのクライアントIP記録(X-Forwarded-For) | CLI | 完 | ALB配下ではremote_addrが常にALBのIPになるため、実クライアントIPはX-Forwarded-Forヘッダーをログ設定に追加して記録する |
| [009](labs/009-cloudwatch-metric-filter/) | Q52 | CloudWatch Logsメトリクスフィルターによるエラー検知通知 | CLI | 完 | CloudWatchアラームはメトリクスしか監視できないため、ログの文字列検知にはメトリクスフィルターでログをメトリクスに変換する必要がある |

状態は `未着手` / `検証中` / `完` のいずれかを記載する。
