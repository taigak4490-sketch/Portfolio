provider "aws" {
  region = "ap-northeast-1"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "migration-portfolio-vpc"
  cidr = "10.0.0.0/16"

  azs              = ["ap-northeast-1a", "ap-northeast-1c"]
  public_subnets   = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets  = ["10.0.11.0/24", "10.0.12.0/24"]
  database_subnets = ["10.0.21.0/24", "10.0.22.0/24"]

  enable_nat_gateway = false 
  enable_dns_hostnames = true
  enable_dns_support   = true

vpc_tags = {
    Name = "migration-portfolio-vpc"
  }

  tags = {
    Project     = "Migration"
    Environment = "dev"
  }
}
# --- 1. DynamoDB Table (設定情報の保存用) ---
resource "aws_dynamodb_table" "config_db" {
  name           = "hotel-configuration"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "ConfigId"

  attribute {
    name = "ConfigId"
    type = "S" # String
  }

  tags = { Name = "hotel-config-db" }
}

# --- 2. S3 Bucket (公開済み設定ファイルの配置用) ---
resource "aws_s3_bucket" "published_config" {
  bucket = "hotel-config-published-${random_id.suffix.hex}" 
}
resource "random_id" "suffix" {
  byte_length = 4
}

# --- 3. Lambda用 IAM Role (権限設定) ---
resource "aws_iam_role" "lambda_role" {
  name = "hotel-config-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# DynamoDBとS3へのアクセス権限を付与
resource "aws_iam_role_policy" "lambda_policy" {
  name = "hotel-config-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.config_db.arn
      },
      {
        Action = ["s3:PutObject"]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.published_config.arn}/*"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}



# Pythonファイルをzipに固める設定
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "config_manager" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "hotel-config-manager"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler" # ファイル名.関数名
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.9"

  # プログラム内で使う変数を渡す
  environment {
    variables = {
      TABLE_NAME  = aws_dynamodb_table.config_db.name
      BUCKET_NAME = aws_s3_bucket.published_config.id
    }
  }
}

# APIの本体（名前を定義）
resource "aws_api_gateway_rest_api" "hotel_api" {
  name        = "HotelConfigAPI"
  description = "API for Hotel Configuration Management"
}

# リソース（URLのパス /config の作成）
resource "aws_api_gateway_resource" "config_res" {
  rest_api_id = aws_api_gateway_rest_api.hotel_api.id
  parent_id   = aws_api_gateway_rest_api.hotel_api.root_resource_id
  path_part   = "config"
}

resource "aws_api_gateway_method" "config_post" {
  rest_api_id   = aws_api_gateway_rest_api.hotel_api.id
  resource_id   = aws_api_gateway_resource.config_res.id
  http_method   = "POST"
  
  # ここを修正：認証を「NONE」から「COGNITO」に変更
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_auth.id
}

# Lambdaとの統合（APIが呼ばれたらLambdaを叩く設定）
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.hotel_api.id
  resource_id             = aws_api_gateway_resource.config_res.id
  http_method             = aws_api_gateway_method.config_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.config_manager.invoke_arn
}

# API GatewayがLambdaを呼び出すための「許可」設定
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.config_manager.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.hotel_api.execution_arn}/*/*"
}

# デプロイ（APIをインターネット上に公開する）
resource "aws_api_gateway_deployment" "hotel_api_deployment" {
  depends_on = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.hotel_api.id

  # 設定変更を検知して再デプロイされるようにする
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.config_res.id,
      aws_api_gateway_method.config_post.id,
      aws_api_gateway_integration.lambda_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ステージ（デプロイしたものを "prod" として公開）
resource "aws_api_gateway_stage" "hotel_api_stage" {
  deployment_id = aws_api_gateway_deployment.hotel_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.hotel_api.id
  stage_name    = "prod"
}

# 出力されるURLの定義も修正
output "base_url" {
  value = "${aws_api_gateway_stage.hotel_api_stage.invoke_url}/config"
}

# ユーザーの器（ユーザープール）
resource "aws_cognito_user_pool" "pool" {
  name = "hotel-admin-pool"

  # 自己署名（ユーザー登録）を許可するかなどの設定
  admin_create_user_config {
    allow_admin_create_user_only = true
  }
}

# 接続用クライアント（アプリから繋ぐためのIDを発行）
resource "aws_cognito_user_pool_client" "client" {
  name         = "hotel-app-client"
  user_pool_id = aws_cognito_user_pool.pool.id
explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
}

# API Gateway と Cognito を紐付ける「鍵穴」の設定
resource "aws_api_gateway_authorizer" "cognito_auth" {
  name          = "CognitoAuthorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id   = aws_api_gateway_rest_api.hotel_api.id
  provider_arns = [aws_cognito_user_pool.pool.arn]
}