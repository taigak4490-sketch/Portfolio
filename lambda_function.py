import json
import boto3
import os

# AWSリソースの準備
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

# Terraformから渡される環境変数
TABLE_NAME = os.environ['TABLE_NAME']
BUCKET_NAME = os.environ['BUCKET_NAME']

def lambda_handler(event, context):
    # --- 修正ポイント：API Gatewayからのbodyをパースする ---
    body = {}
    if 'body' in event and event['body']:
        body = json.loads(event['body'])
    
    # bodyの中から値を取り出す。見つからない場合はデフォルト値
    config_id = body.get('ConfigId', 'default_001')
    setting_value = body.get('SettingValue', 'Standard_Mode')
    # --------------------------------------------------

    # 2. DynamoDBへの保存
    table = dynamodb.Table(TABLE_NAME)
    table.put_item(
        Item={
            'ConfigId': config_id,
            'Status': 'Published',
            'Value': setting_value
        }
    )

    # 3. S3へJSONファイルとして公開
    publish_data = {
        'id': config_id,
        'setting': setting_value,
        'updated_at': '2026-03-12'
    }
    
    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=f"configs/{config_id}.json",
        Body=json.dumps(publish_data),
        ContentType='application/json'
    )

    return {
        'statusCode': 200,
        'body': json.dumps(f"Successfully updated {config_id} and published to S3!")
    }