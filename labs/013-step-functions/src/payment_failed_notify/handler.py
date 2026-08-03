"""決済失敗(Catch経由)時の通知ステップ(検証用にログ出力のみ)。"""


def lambda_handler(event, context):
    print(f"send payment-failed notice: {event}")
    return {"notified": "payment_failed", "detail": event}
