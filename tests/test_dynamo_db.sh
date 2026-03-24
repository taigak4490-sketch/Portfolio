#!/bin/bash
# --- Setup ---
[ -f "../.env" ] && source ../.env || { echo "Error: .env not found"; exit 1; }

# --- Test 2: DynamoDB Data Consistency ---
echo -n "[Test 2] DynamoDB Data Consistency... "
COUNT=$(aws dynamodb scan --table-name "$TABLE_NAME" --select "COUNT" --query "Count" --output text 2>/dev/null)

if [ -n "$COUNT" ] && [ "$COUNT" -gt 0 ]; then
    echo "PASS (Items: $COUNT)"
else
    echo "FAIL (No data)"
fi