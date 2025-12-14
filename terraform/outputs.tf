output "lambda_name" {
    value = aws_lambda_function.fn.function_name
}

output "layer_arn" {
    value = aws_lambda_layer_version.data_layer.arn
}