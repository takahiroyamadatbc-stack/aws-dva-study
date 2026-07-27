"""CDKアプリのエントリポイント。

スタック名は必ず `dva-NNN-topic` 形式にすること(例: dva-002-lambda-alias)。
デプロイ時はタグ Project=dva-study を必ず付ける
(例: cdk deploy --tags Project=dva-study)。
"""

import aws_cdk as cdk

from stack import DvaLabStack

app = cdk.App()

# TODO: NNN-topic をこのLabの連番・テーマに書き換える
DvaLabStack(app, "dva-NNN-topic")

app.synth()
