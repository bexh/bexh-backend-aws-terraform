provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_secretsmanager_secret_version" "creds" {
  secret_id = "db-creds"
}

locals {
  db_creds = jsondecode(
    data.aws_secretsmanager_secret_version.creds.secret_string
  )
}

// region: rds

resource "aws_security_group" "rds_sg" {
  name        = "tcp-ip-whitelist"
  description = "RDS tcp ip whitelist"

  ingress {
    description = "TCP/IP for RDS with whitelisting"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = var.whitelisted_ips
  }

  ingress {
    description = "All inbound from sg"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_rds_cluster" "this" {
  engine_mode                     = "serverless"
  engine                          = "aurora-mysql"
  engine_version                  = "5.7.mysql_aurora.2.07.1"
  cluster_identifier              = "bexh-ods-cluster-${var.env_name}-${var.account_id}"
  database_name                   = "BexhOdsDb"
  master_username                 = local.db_creds.username
  master_password                 = local.db_creds.password
  db_cluster_parameter_group_name = "default.aurora-mysql5.7"
  vpc_security_group_ids          = ["${aws_security_group.rds_sg.id}"]
  enable_http_endpoint            = true
  final_snapshot_identifier       = "bexh-ods-cluster-snapshot-${var.env_name}-${var.account_id}"

  scaling_configuration {
    auto_pause               = true
    max_capacity             = 2
    seconds_until_auto_pause = 300
  }
}

# resource "null_resource" "setup_db" {
#   depends_on = [aws_rds_cluster.this] #wait for the db to be ready
#   triggers = {
#     file_sha = "${sha1(file("file.sql"))}"
#   }
#   provisioner "local-exec" {
#     command = "echo test"
#   }
# }

// region: api gateway + lambda

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
  s3_bucket         = "bexh-lambda-deploy-dev-189266647936"
  s3_key            = "bexh-api-aws-lambda.zip"
  s3_object_version = var.bexh_api_lambda_s3_version
  function_name     = "bexh-api-proxy-post"
  role              = aws_iam_role.bexh_api_proxy_post_lambda_role.arn
  handler           = "main.src.service.handler"
  runtime           = "python3.8"
  timeout           = 60
  environment {
    variables = {
      ENV_NAME                          = var.env_name
      LOG_LEVEL                         = var.log_level
      TOKEN_TABLE_NAME                  = aws_dynamodb_table.this.name
      MYSQL_HOST_URL                    = aws_rds_cluster.this.endpoint
      MYSQL_DATABASE_NAME               = aws_rds_cluster.this.database_name
      BET_STATUS_CHANGE_EMAIL_SNS_TOPIC = module.bexh_bet_status_change_sns_lambda.aws_sns_topic.arn
      VERIFICATION_EMAIL_SNS_TOPIC      = module.bexh_verification_email_sns_lambda.aws_sns_topic.arn
      EXCHANGE_BET_KINESIS_STREAM       = aws_kinesis_stream.this.name
    }
  }
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [
    aws_lambda_function.bexh_api_proxy_post,
    aws_api_gateway_integration.integration
  ]

  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "test"

  lifecycle {
    create_before_destroy = true
  }
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

resource "aws_iam_role_policy_attachment" "terraform_lambda_policy" {
  role       = aws_iam_role.bexh_api_proxy_post_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
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

// region: DynamoDb

resource "aws_dynamodb_table" "this" {
  name         = "Tokens"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "Uid"

  attribute {
    name = "Uid"
    type = "N"
  }

  ttl {
    attribute_name = "TimeToLive"
    enabled        = true
  }
}

// region: ES

# resource "aws_security_group" "es_sg" {
#   name        = "${var.es_domain}-sg"
#   description = "Allow inbound traffic to ElasticSearch from VPC CIDR"
#   vpc_id      = var.vpc

#   ingress {
#     from_port = 0
#     to_port   = 0
#     protocol  = "-1"
#     cidr_blocks = [
#       var.vpc_cidr
#     ]
#   }

#   ingress {
#     description = "whitelist IPs"
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = var.whitelisted_ips
#   }

#   ingress {
#     description = "All inbound from sg"
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     self        = true
#   }

#   egress {
#     description = "All outbound"
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

# resource "aws_iam_service_linked_role" "es" {
#   aws_service_name = "es.amazonaws.com"
#   description      = "Allows Amazon ES to manage AWS resources for a domain on your behalf."
# }

# resource "aws_elasticsearch_domain" "es" {
#   domain_name           = var.es_domain
#   elasticsearch_version = "6.8"

#   cluster_config {
#     instance_type = "t2.medium.elasticsearch"
#   }

#   vpc_options {
#     subnet_ids         = var.es_subnets
#     security_group_ids = [aws_security_group.es_sg.id]
#   }

#   ebs_options {
#     ebs_enabled = true
#     volume_size = 10
#   }

#   node_to_node_encryption {
#     enabled = true
#   }

#   domain_endpoint_options {
#     enforce_https       = true
#     tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
#   }

#   access_policies = data.aws_iam_policy_document.this.json

#   tags = {
#     Domain = var.es_domain
#   }
# }

# data "aws_iam_policy_document" "this" {
#   statement {
#     effect  = "Allow"
#     actions = ["es:*"]
#     principals {
#       type        = "AWS"
#       identifiers = ["*"]
#     }
#     resources = ["arn:aws:es:${data.aws_region.current.name}:${var.account_id}:domain/${var.es_domain}/*"]
#   }
# }

module "bexh_verification_email_sns_lambda" {
  source = "../bexh_sns_lambda_integration"

  function_name     = "verification-email"
  s3_key            = "bexh-email-aws-lambda.zip"
  s3_object_version = var.bexh_email_lambda_s3_version
  env_name          = var.env_name
  account_id        = var.account_id
  handler           = "main.src.app.verification_email.service.handler"
  timeout           = 900
  env_vars = {
    ENV_NAME       = var.env_name
    LOG_LEVEL      = var.log_level
    TWILIO_API_KEY = var.twilio_api_key
    BASE_URL       = var.base_url
    BEXH_EMAIL     = var.bexh_email
  }

  sns_topic_name = "verification-email"
}

module "bexh_bet_status_change_sns_lambda" {
  source = "../bexh_sns_lambda_integration"

  function_name     = "bet-status-change-email"
  s3_key            = "bexh-email-aws-lambda.zip"
  s3_object_version = var.bexh_email_lambda_s3_version
  env_name          = var.env_name
  account_id        = data.aws_caller_identity.current.account_id
  handler           = "main.src.app.bet_status_change_email.service.handler"
  timeout           = 900
  env_vars = {
    ENV_NAME       = var.env_name
    LOG_LEVEL      = var.log_level
    TWILIO_API_KEY = var.twilio_api_key
    BASE_URL       = var.base_url
    BEXH_EMAIL     = var.bexh_email
  }

  sns_topic_name = "bet-status-change-email"
}

// region: Kinesis Lambda Integration
resource "aws_kinesis_stream" "this" {
  name        = "bexh-exchange-bet-${var.env_name}-${var.account_id}"
  shard_count = 1
}

module "bexh_bet_submit_lambda" {
  source = "../bexh_lambda"

  function_name     = "bet-submit"
  s3_key            = "bexh-bet-submit-aws-lambda.zip"
  s3_object_version = var.bexh_bet_submit_lambda_s3_version
  env_name          = var.env_name
  account_id        = var.account_id
  handler           = "main.src.service.handler"
  env_vars = {
    ENV_NAME  = var.env_name
    LOG_LEVEL = var.log_level
  }
}

resource "aws_iam_policy" "bet_submit_kinesis_policy" {
  name        = "bexh-bet-submit-kinesis-${var.env_name}-${var.account_id}"
  description = "Allows kinesis to invoke lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "kinesis:*"
      ],
      "Effect": "Allow",
      "Resource": "${aws_kinesis_stream.this.arn}"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "kinesis_lambda" {
  role       = module.bexh_bet_submit_lambda.aws_iam_role.name
  policy_arn = aws_iam_policy.bet_submit_kinesis_policy.arn
}

resource "aws_lambda_event_source_mapping" "this" {
  event_source_arn  = aws_kinesis_stream.this.arn
  function_name     = module.bexh_bet_submit_lambda.aws_lambda_function.arn
  starting_position = "LATEST"
}

// section: ECS Fargate Configuration

resource "aws_security_group" "ecs_sg" {
  name        = "bexh-connector-sg-${var.env_name}-${var.account_id}"
  description = "Connector ecs sg"

  ingress {
    description = "All inbound from sg"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # TODO: replace this with privatelink https://aws.amazon.com/blogs/compute/setting-up-aws-privatelink-for-amazon-ecs-and-amazon-ecr/
  ingress {
    description = "Http inbound for ecr"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_cluster" "this" {
  name = "bexh-cluster-${var.env_name}-${var.account_id}"
}

module "bexh_connector_service" {
  source = "../bexh_ecs_service"

  name = "connector"
  cluster_id = aws_ecs_cluster.this.id
  env_name = var.env_name
  account_id = var.account_id
  ecr_repository = "bexh-connector-aws-ecs"
  image_tag = var.connector_image_tag
  security_groups = ["${aws_security_group.ecs_sg.id}"]
  log_level = var.log_level
  subnets = var.es_subnets
  env_vars = []
  instance_count = var.connector_instance_count
}
