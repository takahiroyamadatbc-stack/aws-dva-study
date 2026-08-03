"""在庫確認ステップ。

実行入力の in_stock をそのまま次のステートに渡すだけ。
実際の在庫DBを持たず、検証時に in_stock を true/false で切り替えて
Choice state の分岐を確認できるようにしている。
"""


def lambda_handler(event, context):
    return {
        "item_id": event.get("item_id", "item-001"),
        "in_stock": event.get("in_stock", True),
        "payment_behavior": event.get("payment_behavior", "success"),
    }
