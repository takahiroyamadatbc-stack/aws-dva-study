"""在庫切れ時の通知ステップ(検証用にログ出力のみ)。"""


def lambda_handler(event, context):
    print(f"send out-of-stock notice: {event}")
    return {"notified": "out_of_stock", "detail": event}
