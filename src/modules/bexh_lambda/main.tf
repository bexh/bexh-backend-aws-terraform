resource "aws_lambda_function" "this" {
  s3_bucket         = "bexh-lambda-deploy-${var.env_name}-${var.account_id}"
  s3_key            = var.s3_key
  s3_object_version = var.s3_object_version
  function_name     = "bexh-${var.function_name}-${var.env_name}-${var.account_id}"
  role              = aws_iam_role.lambda_role.arn
  handler           = var.handler
  runtime           = "python3.8"
  timeout           = var.timeout
  environment {
    variables = var.env_vars
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "bexh-${var.function_name}-lambda-role-${var.env_name}-${var.account_id}"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "basic_lambda_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}