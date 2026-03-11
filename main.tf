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
