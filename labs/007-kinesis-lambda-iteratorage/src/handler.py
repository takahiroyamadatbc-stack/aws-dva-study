import base64
import time


def handler(event, context):
    records = event.get("Records", [])
    for record in records:
        base64.b64decode(record["kinesis"]["data"])
        # 実際のワークロード(変換処理・外部API呼び出し等)を模擬して意図的に遅くする
        time.sleep(0.2)
    return {"processed": len(records)}
