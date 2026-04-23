resource "aws_codecommit_repository" "test_repo" {
  repository_name = "test-pipeline-repo"
}
# 静的ウェブサイトを公開するためのS3バケット
resource "aws_s3_bucket" "static_site" {
  bucket = "my-test-pipeline-bucket-${random_id.id.hex}" # バケット名は世界で唯一である必要があります
}

# バケット名の重複を避けるためのランダムな文字列生成
resource "random_id" "id" {
  byte_length = 4
}

# 公開設定（ウェブサイトホスティング）
resource "aws_s3_bucket_website_configuration" "static_site_config" {
  bucket = aws_s3_bucket.static_site.id

  index_document {
    suffix = "index.html"
  }
}
# CodeBuild用のIAMロール
resource "aws_iam_role" "codebuild_role" {
  name = "test-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

# CodeBuild用のポリシー（S3への書き込みとログ出力の許可）
resource "aws_iam_role_policy" "codebuild_policy" {
  role = aws_iam_role.codebuild_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "codecommit:GitPull"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# CodePipeline用のIAMロール（簡略化のため広めに設定）
resource "aws_iam_role" "pipeline_role" {
  name = "test-pipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "pipeline_policy" {
  role = aws_iam_role.pipeline_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "codecommit:GetBranch",
          "codecommit:GetCommit",
          "codecommit:UploadArchive",
          "codecommit:GetUploadArchiveStatus",
          "codebuild:BatchGetBuild",
          "codebuild:StartBuild"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# CodeBuild プロジェクト
resource "aws_codebuild_project" "test_build" {
  name          = "test-web-build"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type                        = "LINUX_CONTAINER"
  }

  source {
    type = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
}

# 成果物保存用のS3（Pipelineが内部で使うもの）
resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket = "pipeline-artifacts-${random_id.id.hex}"
}

# CodePipeline 本体
resource "aws_codepipeline" "test_pipeline" {
  name     = "test-web-pipeline"
  role_arn = aws_iam_role.pipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        RepositoryName = aws_codecommit_repository.test_repo.repository_name
        BranchName     = "main"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"
      configuration = {
        ProjectName = aws_codebuild_project.test_build.name
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "S3"
      input_artifacts = ["build_output"]
      version         = "1"
      configuration = {
        BucketName = aws_s3_bucket.static_site.bucket
        Extract    = "true"
      }
    }
  }
}