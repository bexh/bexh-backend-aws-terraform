terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "bexh"

    workspaces {
      name = "bexh-backend-aws-terraform"
    }
  }
}

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

resource "aws_db_instance" "this" {
  allocated_storage      = 5
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0.17"
  instance_class         = "db.t2.micro"
  name                   = "BexhBackendDbMain"
  username               = local.db_creds.username
  password               = local.db_creds.password
  parameter_group_name   = "default.mysql8.0"
  publicly_accessible    = true
  skip_final_snapshot    = true
  vpc_security_group_ids = ["${aws_security_group.rds_sg.id}"]
}

resource "null_resource" "setup_db" {
  depends_on = [aws_db_instance.this] #wait for the db to be ready
  triggers = {
    file_sha = "${sha1(file("file.sql"))}"
  }
  provisioner "local-exec" {
    command = "echo test"
  }
}

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
      MYSQL_HOST_URL                    = aws_db_instance.this.address
      MYSQL_DATABASE_NAME               = aws_db_instance.this.name
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
#     resources = ["arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.es_domain}/*"]
#   }
# }

module "bexh_verification_email_sns_lambda" {
  source = "./modules/bexh_sns_lambda_integration"

  function_name     = "verification-email"
  s3_key            = "bexh-email-aws-lambda.zip"
  s3_object_version = var.bexh_email_lambda_s3_version
  env_name          = var.env_name
  account_id        = data.aws_caller_identity.current.account_id
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
  source = "./modules/bexh_sns_lambda_integration"

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
  name        = "bexh-exchange-bet-${var.env_name}-${data.aws_caller_identity.current.account_id}"
  shard_count = 1
}

module "bexh_bet_submit_lambda" {
  source = "./modules/bexh_lambda"

  function_name     = "bet-submit"
  s3_key            = "bexh-bet-submit-aws-lambda.zip"
  s3_object_version = var.bexh_bet_submit_lambda_s3_version
  env_name          = var.env_name
  account_id        = data.aws_caller_identity.current.account_id
  handler           = "main.src.service.handler"
  env_vars = {
    ENV_NAME  = var.env_name
    LOG_LEVEL = var.log_level
  }
}

resource "aws_iam_policy" "bet_submit_kinesis_policy" {
  name        = "bexh-bet-submit-kinesis-${var.env_name}-${data.aws_caller_identity.current.account_id}"
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

// subsection: ecs service role


# resource "aws_iam_role_policy_attachment" "ecs-service-role-attachment" {
#     role       = "${aws_iam_role.ecs-service-role.name}"
#     policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
# }

# data "aws_iam_policy_document" "ecs-service-policy" {
#     statement {
#         actions = ["sts:AssumeRole"]

#         principals {
#             type        = "Service"
#             identifiers = ["ecs.amazonaws.com"]
#         }
#     }
# }

// Section: ECS

resource "aws_security_group" "ecs_sg" {
  name        = "bexh-connector-sg-${var.env_name}-${data.aws_caller_identity.current.account_id}"
  description = "Connector ecs sg"

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

resource "aws_ecs_cluster" "main" {
  name = "bexh-connector-cluster-${var.env_name}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "0.25 vCPU"
  memory                   = "0.5GB"
  # task_role_arn            = aws_iam_role.ecs-task-definition-role.arn
  # execution_role_arn = aws_iam_role.ecs-task-execution-role.arn

  container_definitions = <<DEFINITION
[
  {
    "cpu": 128,
    "environment": [{
        "name": "FOO",
        "value": "bar"
      }],
    "image": "${data.aws_caller_identity.current.account_id}.dkr.ecr.us-east-1.amazonaws.com/bexh-connector-aws-ecs:${var.connector_image_tag}",
    "memory": 128,
    "name": "app",
    "networkMode": "awsvpc",
    "portMappings": []
  }
]
DEFINITION
}

resource "aws_ecs_service" "main" {
  name            = "bexh-ecs-service-${var.env_name}-${data.aws_caller_identity.current.account_id}"
  cluster         = aws_ecs_cluster.main.id
  # task_definition = aws_ecs_task_definition.app.arn
  task_definition = "${aws_ecs_task_definition.app.family}:${aws_ecs_task_definition.app.revision}"
  desired_count   = 1
  launch_type     = "FARGATE"
  force_new_deployment = true

  network_configuration {
    security_groups = ["${aws_security_group.ecs_sg.id}"]
    subnets         = var.es_subnets
  }
}

# resource "aws_iam_role" "ecs-task-execution-role" {
#     name                = "ecs-task-execution-role-${var.env_name}-${data.aws_caller_identity.current.account_id}"
#     assume_role_policy  = data.aws_iam_policy_document.ecs-assume-role-policy-doc.json
# }

# resource "aws_iam_role_policy_attachment" "ecs-execution-role-attachment" {
#     role       = aws_iam_role.ecs-task-execution-role.name
#     policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
# }

# data "aws_iam_policy_document" "ecs-assume-role-policy-doc" {
#     statement {
#         actions = ["sts:AssumeRole"]

#         principals {
#             type        = "Service"
#             identifiers = ["ecs.amazonaws.com"]
#         }
#     }
# }

# resource "aws_iam_role" "ecs-task-definition-role" {
#     name                = "ecs-task-definition-role-${var.env_name}-${data.aws_caller_identity.current.account_id}"
#     assume_role_policy  = data.aws_iam_policy_document.ecs-assume-role-policy-doc.json
# }

# resource "aws_iam_role_policy_attachment" "ecs-service-role-attachment" {
#     role       = aws_iam_role.ecs-task-definition-role.name
#     policy_arn = aws_iam_policy.ecs-task-definition-policy.arn
# }

# resource "aws_iam_policy" "ecs-task-definition-policy" {
#   name = "bexh-service-policy-${var.env_name}-${data.aws_caller_identity.current.account_id}"

#   policy = <<EOF
# {
#     "Version": "2012-10-17",
#     "Statement": [
#     {
#         "Effect": "Allow",
#         "Action": [
#           "dynamodb:*"
#         ],
#         "Resource": "*"
#         }
#     ]
# }
# EOF
# }
