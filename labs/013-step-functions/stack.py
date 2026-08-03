"""Step Functions入門用のLabスタック。

注文処理を題材に、Step Functionsの主要な要素(Task/Choice/Wait/Retry/Catch)を
一通り体験できる最小構成のステートマシンを組む。

  CheckStock -> Choice(在庫あり?)
    Yes -> Wait -> ProcessPayment(Retry付き, 失敗時はCatch) -> SendConfirmation
    No  -> OutOfStockNotify

  ProcessPaymentがRetryを使い切って失敗した場合は Catch で
  PaymentFailedNotify に遷移する。
"""

from aws_cdk import Duration, Stack
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_stepfunctions as sfn
from aws_cdk import aws_stepfunctions_tasks as tasks
from constructs import Construct


class DvaLabStack(Stack):
    """DVA-C02検証用の最小Labスタック。"""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        def make_fn(id_: str, src_dir: str) -> lambda_.Function:
            return lambda_.Function(
                self,
                id_,
                runtime=lambda_.Runtime.PYTHON_3_12,
                handler="handler.lambda_handler",
                code=lambda_.Code.from_asset(f"src/{src_dir}"),
                timeout=Duration.seconds(10),
            )

        check_stock_fn = make_fn("CheckStockFn", "check_stock")
        process_payment_fn = make_fn("ProcessPaymentFn", "process_payment")
        send_confirmation_fn = make_fn("SendConfirmationFn", "send_confirmation")
        out_of_stock_notify_fn = make_fn("OutOfStockNotifyFn", "out_of_stock_notify")
        payment_failed_notify_fn = make_fn("PaymentFailedNotifyFn", "payment_failed_notify")

        check_stock = tasks.LambdaInvoke(
            self,
            "CheckStock",
            lambda_function=check_stock_fn,
            output_path="$.Payload",
        )

        # $$.State.RetryCount はStep Functionsが保持するコンテキスト値。
        # これをpayloadに混ぜて渡すことで、ステートレスなLambda側でも
        # 「これは何回目の試行か」を判定できるようにしている。
        process_payment = tasks.LambdaInvoke(
            self,
            "ProcessPayment",
            lambda_function=process_payment_fn,
            payload=sfn.TaskInput.from_object(
                {
                    "item_id.$": "$.item_id",
                    "payment_behavior.$": "$.payment_behavior",
                    "retryCount.$": "$$.State.RetryCount",
                }
            ),
            output_path="$.Payload",
        )
        process_payment.add_retry(
            errors=["States.ALL"],
            interval=Duration.seconds(1),
            max_attempts=3,
            backoff_rate=2.0,
        )

        send_confirmation = tasks.LambdaInvoke(
            self,
            "SendConfirmation",
            lambda_function=send_confirmation_fn,
            output_path="$.Payload",
        )
        out_of_stock_notify = tasks.LambdaInvoke(
            self,
            "OutOfStockNotify",
            lambda_function=out_of_stock_notify_fn,
            output_path="$.Payload",
        )
        payment_failed_notify = tasks.LambdaInvoke(
            self,
            "PaymentFailedNotify",
            lambda_function=payment_failed_notify_fn,
            output_path="$.Payload",
        )

        # Retryを使い切ってもなお失敗した場合にここへフォールバックする
        process_payment.add_catch(
            payment_failed_notify,
            errors=["States.ALL"],
            result_path="$.error",
        )

        wait_before_payment = sfn.Wait(
            self,
            "WaitBeforePayment",
            time=sfn.WaitTime.duration(Duration.seconds(3)),
        )

        definition = check_stock.next(
            sfn.Choice(self, "InStock?")
            .when(
                sfn.Condition.boolean_equals("$.in_stock", True),
                wait_before_payment.next(process_payment).next(send_confirmation),
            )
            .otherwise(out_of_stock_notify)
        )

        sfn.StateMachine(
            self,
            "OrderStateMachine",
            state_machine_name="dva-013-step-functions",
            definition_body=sfn.DefinitionBody.from_chainable(definition),
            state_machine_type=sfn.StateMachineType.STANDARD,
            timeout=Duration.minutes(5),
        )
