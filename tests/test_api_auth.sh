#!/bin/bash
# --- Setup ---
[ -f "../.env" ] && source ../.env || { echo "Error: .env not found"; exit 1; }
CID=$(aws cognito-idp list-user-pool-clients --user-pool-id "$UPID" --query 'UserPoolClients[0].ClientId' --output text 2>/dev/null)
ID_TOKEN=$(aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH --client-id "$CID" --auth-parameters USERNAME="$UNAME",PASSWORD="$PW" --query 'AuthenticationResult.IdToken' --output text 2>/dev/null)

# --- Test 1: API Authentication ---
echo -n "[Test 1] API Auth (401/200/403 Check)... "
C401=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API_URL")
C200=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: $ID_TOKEN" -X POST "$API_URL")

if { [ "$C401" -eq "401" ] || [ "$C401" -eq "403" ]; } && [ "$C200" == "200" ]; then
    echo "PASS"
else
    echo "FAIL (Code: $C401 / $C200)"
fi