terraform {
    required_version = ">= 1.5"
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = ">= 5.0"
        }
    }
}

provider "aws" {
    region = var.aws_region
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
    name = "${var.project_name}-lambda-role"

    assume_role_policy = json_encode({
        Version = "2012-10-17"
        Statement = [{
            Effect = "Allow"
            Principal = {Service = "lambda.amazonaws.com"}
            Action = "sts:AsumeRole"
        }]
    })
}

# Logging permissions
resource "aws_iam_role_policy_attachment" "basic_exec" {
    role = aws_iam_role.lambda_role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Layer
resource "aws_lambda_layer_version" "data_layer" {
    layer_name          = "${var.project_name}-data-layer"
    filename            = "${path.module}/../build/layer.zip"
    source_code_hash    = filebase64sha256("${path.module}/../build/layer.zip")
    compatible_runtimes = [var.lambda_runtime]
    description         = "Data layer with Numpy and Pandas"
}

#Lambda function
resource "aws_lambda_function" "fn" {
    function_name       = "${var.project_name}-fn"
    role                = aws_iam_role.lambda_role.arn
    filename            = "${path.module}/../build/function.zip"
    source_code_hash    = filebase64sha256("${path.module}/../build/function.zip")
    runtime             = var.lambda_runtime
    handler             = "app.handler"
    timeout             = 30
    memory_size         = 512

    layers = [aws_lambda_layer_version.data_layer.arn]
    
    environment {
        variables = {
            LOG_LEVEL = "INFO"
        }
    }
}

