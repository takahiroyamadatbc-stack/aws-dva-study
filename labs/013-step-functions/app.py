"""CDKアプリのエントリポイント。

スタック名は dva-013-step-functions。
デプロイ時はタグ Project=dva-study を必ず付ける
(例: cdk deploy --tags Project=dva-study)。
"""

import aws_cdk as cdk

from stack import DvaLabStack

app = cdk.App()

DvaLabStack(app, "dva-013-step-functions")

app.synth()
