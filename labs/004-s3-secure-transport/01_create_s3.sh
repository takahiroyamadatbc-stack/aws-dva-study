BUCKET=dva-004-secure-transport-$RANDOM
aws s3 mb s3://$BUCKET
echo "test data" > test.txt
aws s3 cp test.txt s3://$BUCKET/

cat > policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyInsecureTransport",
    "Effect": "Deny",
    "Principal": "*",
    "Action": "s3:*",
    "Resource": ["arn:aws:s3:::__BUCKET__", "arn:aws:s3:::__BUCKET__/*"],
    "Condition": { "Bool": { "aws:SecureTransport": "false" } }
  }]
}
EOF
sed -i "s/__BUCKET__/$BUCKET/g" policy.json
aws s3api put-bucket-policy --bucket $BUCKET --policy file://policy.json