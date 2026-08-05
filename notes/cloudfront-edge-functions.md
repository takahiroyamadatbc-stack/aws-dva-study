# CloudFront エッジ関数: CloudFront Functions vs Lambda@Edge

CloudFrontはユーザーの近く（エッジロケーション）でリクエスト/レスポンスを加工できる。この「エッジ関数」には**CloudFront Functions**と**Lambda@Edge**の2種類があり、DVAでは実行タイミングと得意領域の違いが頻出。

## 一行結論

> 「URLリライト」「HTTP→HTTPSリダイレクト」「ヘッダー追加」「Basic認証」など軽量・高速な処理 → **CloudFront Functions**（Viewer Request/Responseのみ、JSのみ、数ミリ秒）。
> 「Origin切り替え」「外部API呼び出し」「JWT/OAuth認証」「画像変換」など重い処理 → **Lambda@Edge**（4イベント全てで実行可、何でもできるが遅い・高い）。

## 1. 通信フローのどこに割り込むか

通常のCloudFrontはユーザー→CloudFront→Origin(S3/ALB等)という単純な流れだが、エッジ関数を挟むとリクエスト/レスポンスの途中で処理を実行できる。

## 2. CloudFront Functions

| 項目 | 内容 |
|---|---|
| 実行速度 | 非常に速い（ミリ秒オーダー） |
| 言語 | JavaScriptのみ |
| メモリ | 小さい |
| 実行タイミング | **Viewer Request** と **Viewer Response** の2箇所のみ（Originには一切触れない） |
| 得意な処理 | HTTPヘッダーの変更・追加、URL/リクエストの書き換え |
| コスト | 安い |

### 典型的なユースケース

- HTTP→HTTPSリダイレクト（`http://example.com` → `https://example.com`）
- URL書き換え（`/abc` → `/abc/index.html`）
- 国別アクセス制御（リクエストヘッダー `CloudFront-Viewer-Country` を見てJPは許可・USは拒否等）
- Basic認証（リクエストヘッダー `Authorization` を確認し、認証失敗なら `401 Unauthorized` を返す）

## 3. Lambda@Edge

通常のLambda関数をCloudFront上で実行するイメージ。CloudFront Functionsより高機能で、外部API呼び出し・JWT認証・Cookie解析・HTML生成・画像加工など何でもできる。

### 実行できる4イベント

| イベント | タイミング |
|---|---|
| Viewer Request | ユーザー → CloudFront に届いた直後 |
| Origin Request | CloudFront → Origin へ行く直前（**Originアクセス前**） |
| Origin Response | Origin → CloudFront に返ってきた直後（**Originアクセス後**） |
| Viewer Response | CloudFront → ユーザーへ返す直前 |

Origin Request/Responseに触れられるのがCloudFront Functionsとの決定的な違い。例えば「USユーザーはUS用Origin、JPユーザーは東京Originへ振り分ける」といったOrigin動的切り替えはLambda@Edgeでしか実現できない。

## 4. 比較表

| 項目 | CloudFront Functions | Lambda@Edge |
|---|---|---|
| 実行速度 | 非常に速い（ミリ秒） | 少し遅い |
| コスト | 安い | 高い |
| 実行タイミング | Viewer Request / Viewer Response | Viewer Request / Origin Request / Origin Response / Viewer Response（4種類すべて） |
| Originアクセス前後への介入 | ✕ | ○ |
| 外部サービス呼び出し | ✕ | ○ |
| HTTPヘッダー変更 | ◎ | ◎ |
| 複雑な処理（JWT認証、HTML生成、画像加工等） | ✕ | ◎ |
| 言語 | JavaScriptのみ | Node.js / Python等（通常のLambdaランタイム） |

## 5. 使い分けの覚え方

- **CloudFront Functions = 「軽く・速く・安く」** — URLリライト、HTTP→HTTPS、Basic認証、ヘッダー追加、Cookieの確認など軽量なアクセス制御
- **Lambda@Edge = 「何でもできるが重い」** — JWT/OAuth認証、外部API呼び出し、画像変換、HTML生成、Origin切り替えなど複雑なリクエスト加工

## 6. 試験でのキーワード対応

| 設問の記述 | 対応する答え |
|---|---|
| 「URLを書き換えたい」「HTTPヘッダーを追加したい」 | CloudFront Functions |
| 「数ミリ秒で完結する軽量な処理」「低コストで大量リクエストを捌きたい」 | CloudFront Functions |
| 「Originを動的に切り替えたい」 | Lambda@Edge（Origin Request） |
| 「認証サーバー（外部API）と連携したい」「JWT/OAuth検証」 | Lambda@Edge |
| 「Originからのレスポンスに手を加えたい（画像加工・ヘッダー追加）」 | Lambda@Edge（Origin Response） |
| 「CloudFront FunctionsでOriginにアクセスできるか」 | できない（Viewer Request/Responseのみ、Originには一切触れない） |
