provider "aws" {
    region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_secretsmanager_secret_version" "creds" {
  secret_id = "db-creds"
}

locals {
  db_creds = jsondecode(
    data.aws_secretsmanager_secret_version.creds.secret_string
  )
}

resource "aws_security_group" "rds_sg" {
    name = "tcp-ip-whitelist"
    description = "RDS tcp ip whitelist"

    ingress {
        description = "TCP/IP for RDS with whitelisting"
        from_port = 3306
        to_port = 3306
        protocol  = "tcp"
        cidr_blocks = var.whitelisted_ips
    }

    ingress {
        description = "All inbound from sg"
        from_port = 0
        to_port = 0
        protocol = "-1"
        self = true
    }

    egress {
        description = "All outbound"
        from_port = 0
        to_port = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_db_instance" "this" {
    allocated_storage = 5
    storage_type = "gp2"
    engine = "mysql"
    engine_version = "8.0.17"
    instance_class = "db.t2.micro"
    name = "BexhBackendDbMain"
    username = local.db_creds.username
    password = local.db_creds.password
    parameter_group_name = "default.mysql8.0"
    publicly_accessible = true
    skip_final_snapshot = true
    vpc_security_group_ids = ["${aws_security_group.rds_sg.id}"]
}

resource "null_resource" "setup_db" {
  depends_on = [aws_db_instance.this] #wait for the db to be ready
  triggers = {
    file_sha = "${sha1(file("file.sql"))}"
  }
  provisioner "local-exec" {
    command = "mysql -u ${local.db_creds.username} -p${local.db_creds.password} -h ${aws_db_instance.this.address} < file.sql"
  }
}

resource "aws_api_gateway_rest_api" "this" {
  name        = "BexhApi"
  description = "API Gateway for all things bexh"
}

resource "aws_api_gateway_resource" "bexh" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "bexh"
}

resource "aws_api_gateway_method" "post" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.bexh.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.bexh.id
  http_method             = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.bexh_api_proxy_post.invoke_arn
}

resource "aws_lambda_function" "bexh_api_proxy_post" {
  s3_bucket = "lambda-deploy-develop-189266647936"
  s3_key = "lambda.py.zip"
  function_name = "bexh-api-proxy-post"
  role          = aws_iam_role.bexh_api_proxy_post_lambda_role.arn
  handler       = "lambda.lambda_handler"
  runtime       = "python3.6"

  # source_code_hash = filebase64sha256("lambda.zip")
}

resource "aws_api_gateway_deployment" "this" {
   depends_on = [
     aws_lambda_function.bexh_api_proxy_post
   ]

   rest_api_id = aws_api_gateway_rest_api.this.id
   stage_name  = "test"
}

resource "aws_iam_role" "bexh_api_proxy_post_lambda_role" {
  name = "bexh-api-proxy-post-lambda-role"

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

resource "aws_lambda_permission" "apigw" {
   statement_id  = "AllowAPIGatewayInvoke"
   action        = "lambda:InvokeFunction"
   function_name = aws_lambda_function.bexh_api_proxy_post.function_name
   principal     = "apigateway.amazonaws.com"

   # The "/*/*" portion grants access from any method on any resource
   # within the API Gateway REST API.
   source_arn = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

output "base_url" {
  value = aws_api_gateway_deployment.this.invoke_url
}
