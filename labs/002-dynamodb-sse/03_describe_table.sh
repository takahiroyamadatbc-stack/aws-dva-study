aws dynamodb describe-table --table-name dva-002-owned   --query 'Table.SSEDescription'
aws dynamodb describe-table --table-name dva-002-managed --query 'Table.SSEDescription'