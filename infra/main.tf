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
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.register_user.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.register_api.execution_arn}/*/*"
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

# integration
resource "aws_api_gateway_integration" "register_integration" {
  rest_api_id             = aws_api_gateway_rest_api.register_api.id
  resource_id             = aws_api_gateway_resource.register_resource.id
  http_method             = aws_api_gateway_method.register_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/${aws_lambda_function.register_user.arn}/invocations"
}

resource "aws_lambda_permission" "allow_api_gateway_invocation" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.register_user.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.register_api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "register_deployment" {
  depends_on = [
    aws_api_gateway_integration.register_integration,
    aws_api_gateway_method.register_method
  ]
  rest_api_id = aws_api_gateway_rest_api.register_api.id
}

resource "aws_api_gateway_stage" "stage" {
  deployment_id = aws_api_gateway_deployment.register_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.register_api.id
  stage_name    = "stage"
  access_log_settings {
    destination_arn = "arn:aws:logs:us-east-1:784865752476:log-group:/aws/api-gateway/register-api-logs"
    format          = "$context.identity.sourceIp - $context.identity.user - $context.requestTime - $context.requestId"
  }
  variables = {
    "logLevel" = "INFO"
  }
}

# logging

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name = "/aws/api-gateway/register-api-logs"
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_4xx_alarm" {
  alarm_name                = "APIGateway4xxErrors"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "1"
  metric_name               = "4XXError"
  namespace                 = "AWS/ApiGateway"
  period                    = "60"
  statistic                 = "Sum"
  threshold                 = "1"
  alarm_description         = "Alarm for 4XX errors in API Gateway"
  dimensions = {
    ApiName = aws_api_gateway_rest_api.register_api.name
    Stage   = aws_api_gateway_stage.stage.stage_name
  }

  actions_enabled           = true
  alarm_actions = [
    "arn:aws:sns:us-east-1:784865752476:ErrorNotifications"
  ]
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx_alarm" {
  alarm_name                = "APIGateway5xxErrors"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "1"
  metric_name               = "5XXError"
  namespace                 = "AWS/ApiGateway"
  period                    = "60"
  statistic                 = "Sum"
  threshold                 = "1"
  alarm_description         = "Alarm for 5XX errors in API Gateway"
  dimensions = {
    ApiName = aws_api_gateway_rest_api.register_api.name
    Stage   = aws_api_gateway_stage.stage.stage_name
  }

  actions_enabled           = true
  alarm_actions = [
    "arn:aws:sns:us-east-1:784865752476:ErrorNotifications"
  ]
}

resource "aws_sns_topic" "error_notifications" {
  name = "ErrorNotifications"
}

resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.error_notifications.arn
  protocol  = "email"
  endpoint  = "mandresuri@gmail.om"
}