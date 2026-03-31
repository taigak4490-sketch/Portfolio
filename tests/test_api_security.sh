#!/bin/bash
[ -f "../.env" ] && source ../.env || { echo "Error: .env not found"; exit 1; }

echo "=== Test 1-2: API Security Boundary Check ==="

# 1. 無効なトークン（適当な文字列）でのアクセス
echo -n "[Case 1] Invalid Token Check... "
C401_INV=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: invalid-token-string" -X POST "$API_URL")

if [ "$C401_INV" == "401" ] || [ "$C401_INV" == "403" ]; then
    echo "PASS (Blocked with $C401_INV)"
else
    echo "FAIL (Allowed with $C401_INV)"
fi

# 2. トークンなしでのアクセス
echo -n "[Case 2] No Token Check... "
C401_NONE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API_URL")

if [ "$C401_NONE" == "401" ] || [ "$C401_NONE" == "403" ]; then
    echo "PASS (Blocked with $C401_NONE)"
else
    echo "FAIL (Allowed with $C401_NONE)"
fi