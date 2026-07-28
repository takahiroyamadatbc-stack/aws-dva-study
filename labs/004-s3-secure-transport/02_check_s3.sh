# HTTPSでの取得(成功するはず)
aws s3api get-object --bucket $BUCKET --key test.txt out.txt && echo "HTTPS: 成功"

# HTTPを強制した生のリクエスト(失敗するはず)
curl -v "http://$BUCKET.s3.amazonaws.com/test.txt" 2>&1 | grep -i "AccessDenied\|403"