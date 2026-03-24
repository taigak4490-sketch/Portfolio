#!/bin/bash
echo "=== AWS Full Test Start ==="
bash test_api_auth.sh
bash test_dynamo_db.sh
bash test_s3_files.sh
bash test_lambda_logs.sh
echo "=== Tests Completed ==="