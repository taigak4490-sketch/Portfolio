#!/bin/bash
# --- Setup ---
[ -f "../.env" ] && source ../.env || { echo "Error: .env not found"; exit 1; }

# --- Test 4: CloudWatch Log Health ---
echo -n "[Test 4] CloudWatch Log Health... "
HAS_ERR=$(aws logs filter-log-events --log-group-name "/aws/lambda/$LAMBDA_NAME" --filter-pattern "ERROR" --max-items 1 --query "events" --output text 2>/dev/null)

if [ -z "$HAS_ERR" ] || [ "$HAS_ERR" == "None" ] || [ "$HAS_ERR" == "[]" ]; then
    echo "PASS (No Errors)"
else
    echo "FAIL (Error Detected)"
fi