#!/bin/bash
echo "=== AWS Full Test Start ==="

# 0. 静的解析 (tfsec) - 結論の1行だけを表示
echo "[Test 0] tfsec Analysis"
../tfsec.exe .. | grep -E "passed|potential problem"

# 1. 既存のテスト
echo "[Test 1-4] Functional Tests"
bash test_api_auth.sh
bash test_dynamo_db.sh
bash test_s3_files.sh
bash test_lambda_logs.sh

# 2. 追加したセキュリティテスト
echo "[Test 5-6] Security Boundary Tests"
bash test_api_security.sh
bash test_s3_security.sh

echo "=== Tests Completed ==="
