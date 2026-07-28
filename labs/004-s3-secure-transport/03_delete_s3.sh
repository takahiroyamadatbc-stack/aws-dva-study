aws s3 rm s3://$BUCKET/test.txt
aws s3 rb s3://$BUCKET
rm -f test.txt out.txt policy.json