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

1. `labs/_template/` を `labs/NNN-topic/` としてコピーする（連番は最後に使った番号+1）
2. `README.md` の各セクション（問題／選んだ答えと理由／誤答の型／仮説／検証／結論／片付け）を埋める
3. IaCでの検証が必要ないLab（CLIだけで完結する場合）は `commands.md` だけでもよい。
   その場合 `app.py` / `cdk.json` / `stack.py` は削除してよい
4. 検証が終わったら本READMEの索引テーブルに1行追加する

**「一行結論」を埋めることがLabの完了条件です。** 試験直前の見直しは索引テーブルの
「一行結論」列だけを読めば足りるようにしてください。

## 命名・事故防止の規約

- スタック名は必ず `dva-NNN-topic` 形式にする（例: `dva-002-lambda-alias`）
- デプロイ時は必ず `--tags Project=dva-study` を付ける
- Labは使い捨て前提。検証が終わったら**必ず片付ける**（`cdk destroy` / `sam delete` など）

### 消し忘れ検出コマンド

作業終了時・久しぶりに作業を再開した時は、まずこれで残骸がないか確認する。

```bash
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?starts_with(StackName,'dva-')].StackName"
```

## 索引

| Lab | 問題 | テーマ | ツール | 状態 | 一行結論 |
|-----|------|--------|--------|------|----------|
| [001](labs/001-sam-transform/) | Q22 | SAM Transform | SAM | 完 | TransformはCFnデプロイ時にサーバー側で展開されるマクロ |

状態は `未着手` / `検証中` / `完` のいずれかを記載する。
