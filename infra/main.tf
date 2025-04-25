terraform {
  required_version = "~> 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.34.0"
    }
  }
  backend "s3" {
    bucket         = "terraform-states-serverless-test"
    key            = "serverless.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform_state_lock"
  }
}

provider "aws" {
  region = "us-east-1"
}
# lock
resource "aws_dynamodb_table" "terraform_state_lock" {
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "LockID"
  name                        = "terraform_state_lock"

  attribute {
    name = "LockID"
    type = "S"
  }
}
# Dynamo DB
resource "aws_dynamodb_table" "register_table" {
  name         = "registerTable"
  hash_key     = "id"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "id"
    type = "S"
  }
}

# Lambda

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Effect = "Allow",
      Sid    = ""
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:PutItem"
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.register_table.arn
      }
    ]
  })
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "register_user" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "register_user"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.register_table.name
    }
  }
}

# api gateway
resource "aws_api_gateway_rest_api" "register_api" {
  name        = "register-api"
  description = "API for registering user"
}

resource "aws_api_gateway_resource" "register_resource" {
  rest_api_id = aws_api_gateway_rest_api.register_api.id
  parent_id   = aws_api_gateway_rest_api.register_api.root_resource_id
  path_part   = "register"
}

resource "aws_api_gateway_method" "register_method" {
  rest_api_id   = aws_api_gateway_rest_api.register_api.id
  resource_id   = aws_api_gateway_resource.register_resource.id
  http_method   = "POST"
  authorization = "NONE"
}