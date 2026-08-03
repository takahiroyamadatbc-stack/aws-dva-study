"""決済成功時の通知ステップ(検証用にログ出力のみ)。"""


def lambda_handler(event, context):
    print(f"send confirmation: {event}")
    return {"notified": "confirmation", "detail": event}
