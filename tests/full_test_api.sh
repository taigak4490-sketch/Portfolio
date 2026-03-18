#!/bin/bash

# 親ディレクトリにある .env ファイルを読み込む
if [ -f "../.env" ]; then
    source ../.env
else
    echo "Error: .env file not found in parent directory."
    exit 1
fi

# 1. ClientID & トークン取得 (変数は .env から引き継がれる)
# 取得に失敗した場合に備えてエラー出力を抑制しつつ取得
CID=$(aws cognito-idp list-user-pool-clients --user-pool-id "$UPID" --query 'UserPoolClients[0].ClientId' --output text 2>/dev/null)
ID_TOKEN=$(aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH --client-id "$CID" --auth-parameters USERNAME="$UNAME",PASSWORD="$PW" --query 'AuthenticationResult.IdToken' --output text 2>/dev/null)


echo "DEBUG: API_URL is [$API_URL]"
echo "DEBUG: UPID is [$UPID]"
echo "DEBUG: Token length is [${#ID_TOKEN}]"
echo "Logging into Cognito..."
ID_TOKEN=$(aws cognito-idp initiate-auth \
    --region $REGION \
    --auth-flow USER_PASSWORD_AUTH \
    --client-id "$CID" \
    --auth-parameters USERNAME="$UNAME",PASSWORD="$PW" \
    --query 'AuthenticationResult.IdToken' \
    --output text)
echo "============================================"
echo " AWS Test Report: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"

# --- Test 1: API Authentication ---
echo -n "[Test 1] API Auth (401/200/403 Check)... "
C401=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API_URL")
C200=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: $ID_TOKEN" -X POST "$API_URL")

# ステータスコードの判定
if { [ "$C401" -eq "401" ] || [ "$C401" -eq "403" ]; } && [ "$C200" == "200" ]; then
    echo "PASS"
else
    echo "FAIL (Code: $C401 / $C200)"
fi

# --- Test 2: DynamoDB Write ---
echo -n "[Test 2] DynamoDB Data Consistency... "
COUNT=$(aws dynamodb scan --table-name "$TABLE_NAME" --select "COUNT" --query "Count" --output text 2>/dev/null)
if [ -n "$COUNT" ] && [ "$COUNT" -gt 0 ]; then
    echo "PASS (Items: $COUNT)"
else
    echo "FAIL (No data)"
fi

# --- Test 3: S3 Static File ---
echo -n "[Test 3] S3 Config Export... "
S3_EXIST=$(aws s3 ls "s3://$S3_BUCKET/configs/" --recursive 2>/dev/null | wc -l)
if [ "$S3_EXIST" -gt 0 ]; then
    echo "PASS (Files: $S3_EXIST)"
else
    echo "FAIL (No file)"
fi

# --- Test 4: Lambda Logging ---
echo -n "[Test 4] CloudWatch Log Health... "
HAS_ERR=$(aws logs filter-log-events --log-group-name "/aws/lambda/$LAMBDA_NAME" --filter-pattern "ERROR" --max-items 1 --query "events" --output text 2>/dev/null)
if [ -z "$HAS_ERR" ] || [ "$HAS_ERR" == "None" ] || [ "$HAS_ERR" == "[]" ]; then
    echo "PASS (No Errors)"
else
    echo "FAIL (Error Detected)"
fi

echo "============================================"