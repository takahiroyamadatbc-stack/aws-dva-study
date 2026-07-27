"""SAM Transformの展開確認用の最小Lambdaハンドラ。"""


def lambda_handler(event, context):
    """API Gateway経由で呼ばれたことが分かればよい、検証用の最小実装。"""
    return {"statusCode": 200, "body": "hello from SAM"}
