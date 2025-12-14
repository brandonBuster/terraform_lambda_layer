variable "aws_region" {
    type = string
    default = "us-west-2"
}

variable "project_name" {
    type = string
    default = "lambda-layer"
}

variable "lambda_runtime" {
    type = string
    default = "python3.12"
}