provider "aws" {
  region = "ap-northeast-1"
}

# --- VPC Module ---
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

# --- 1. DynamoDB Table ---
resource "aws_dynamodb_table" "config_db" {
  name           = "hotel-configuration"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "ConfigId"

  server_side_encryption {
    enabled = true
  }
  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "ConfigId"
    type = "S"
  }

  tags = { Name = "hotel-config-db" }
}

# --- 2. S3 Bucket ---
resource "aws_s3_bucket" "published_config" {
  bucket = "hotel-config-published-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_versioning" "config_versioning" {
  bucket = aws_s3_bucket.published_config.id
  versioning_configuration {
    status = "Enabled"
  }
}

# tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket_server_side_encryption_configuration" "config_enc" {
  bucket = aws_s3_bucket.published_config.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "config_block" {
  bucket = aws_s3_bucket.published_config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "random_id" "suffix" {
  byte_length = 4
}

# --- 3. IAM Role & Policy ---
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

# tfsec:ignore:aws-iam-no-policy-wildcards
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
        Resource = "${aws_s3_bucket.published_config.arn}/configs/*"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:ap-northeast-1:869742660516:log-group:/aws/lambda/hotel-config-manager:*"
      }
    ]
  })
}

# --- 4. Lambda Function ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "config_manager" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "hotel-config-manager"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.9"

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME  = aws_dynamodb_table.config_db.name
      BUCKET_NAME = aws_s3_bucket.published_config.id
    }
  }
}

# --- 5. API Gateway ---
resource "aws_api_gateway_rest_api" "hotel_api" {
  name        = "HotelConfigAPI"
  description = "API for Hotel Configuration Management"
}

resource "aws_api_gateway_resource" "config_res" {
  rest_api_id = aws_api_gateway_rest_api.hotel_api.id
  parent_id   = aws_api_gateway_rest_api.hotel_api.root_resource_id
  path_part   = "config"
}

resource "aws_api_gateway_method" "config_post" {
  rest_api_id   = aws_api_gateway_rest_api.hotel_api.id
  resource_id   = aws_api_gateway_resource.config_res.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_auth.id
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.hotel_api.id
  resource_id             = aws_api_gateway_resource.config_res.id
  http_method             = aws_api_gateway_method.config_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.config_manager.invoke_arn
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.config_manager.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.hotel_api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "hotel_api_deployment" {
  depends_on = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.hotel_api.id

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

resource "aws_api_gateway_stage" "hotel_api_stage" {
  deployment_id = aws_api_gateway_deployment.hotel_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.hotel_api.id
  stage_name    = "prod"
  xray_tracing_enabled = true
}

# --- 6. Cognito ---
resource "aws_cognito_user_pool" "pool" {
  name = "hotel-admin-pool"

  admin_create_user_config {
    allow_admin_create_user_only = true
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "hotel-app-client"
  user_pool_id = aws_cognito_user_pool.pool.id
  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  id_token_validity      = 60
  access_token_validity  = 60
  refresh_token_validity = 30

  token_validity_units {
    id_token      = "minutes"
    access_token  = "minutes"
    refresh_token = "days"
  }
}

resource "aws_api_gateway_authorizer" "cognito_auth" {
  name          = "CognitoAuthorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id   = aws_api_gateway_rest_api.hotel_api.id
  provider_arns = [aws_cognito_user_pool.pool.arn]
}

# --- Outputs ---
output "base_url" {
  value = "${aws_api_gateway_stage.hotel_api_stage.invoke_url}/config"
}

output "client_id" {
  value = aws_cognito_user_pool_client.client.id
}