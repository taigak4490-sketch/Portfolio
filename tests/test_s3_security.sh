#!/bin/bash
[ -f "../.env" ] && source ../.env || { echo "Error: .env not found"; exit 1; }

echo "=== Test 3-2: S3 Data Protection Check ==="

# 認証なしでS3のURLを直接叩く
# ※ S3の静的ウェブホスティングURLではなく、REST APIエンドポイント形式で試行
S3_URL="https://$S3_BUCKET.s3.$REGION.amazonaws.com/config.json"

echo -n "[Case 1] Public Access Attempt... "
# 期待値は 403 (Forbidden)
C_S3=$(curl -s -o /dev/null -w "%{http_code}" "$S3_URL")

if [ "$C_S3" == "403" ]; then
    echo "PASS (Secure: Access Denied)"
else
    echo "FAIL (Risky: Accessible with Code $C_S3)"
fi