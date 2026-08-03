"""決済処理ステップ。

payment_behavior によって挙動を切り替える。
- success: 常に成功
- fail_then_success: retryCount(Step Functionsのコンテキストオブジェクト
  $$.State.RetryCount から渡された値)が2未満なら例外を投げ、Retryで
  リトライされた3回目以降に成功する
- always_fail: 常に例外を投げ、Retryを使い切った後にCatchへ落ちる

retryCount はLambda自身が持つ状態ではなく、Step Functions側が
「このタスクを何回リトライしたか」を管理して渡してくる値。
Lambda単体ではこの挙動は作れない。
"""


class PaymentError(Exception):
    pass


def lambda_handler(event, context):
    behavior = event.get("payment_behavior", "success")
    retry_count = event.get("retryCount", 0)

    if behavior == "always_fail":
        raise PaymentError(f"payment gateway unavailable (retryCount={retry_count})")

    if behavior == "fail_then_success" and retry_count < 2:
        raise PaymentError(f"transient error, retryCount={retry_count}")

    return {
        "item_id": event.get("item_id", "item-001"),
        "payment_status": "APPROVED",
        "retryCount": retry_count,
    }
