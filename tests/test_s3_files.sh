#!/bin/bash
# --- Setup ---
[ -f "../.env" ] && source ../.env || { echo "Error: .env not found"; exit 1; }

# --- Test 3: S3 Config Export ---
echo -n "[Test 3] S3 Config Export... "
S3_EXIST=$(aws s3 ls "s3://$S3_BUCKET/configs/" --recursive 2>/dev/null | wc -l)

if [ "$S3_EXIST" -gt 0 ]; then
    echo "PASS (Files: $S3_EXIST)"
else
    echo "FAIL (No file)"
fi