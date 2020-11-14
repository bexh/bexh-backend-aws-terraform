provider "aws" {
  region = "us-east-1"
}

// section: ECS Fargate Configuration

resource "aws_security_group" "ecs_sg" {
  name        = "bexh-event-connector-sg-${var.env_name}-${var.account_id}"
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

resource "aws_ecs_cluster" "main" {
  name = "bexh-exchange-cluster-${var.env_name}-${var.account_id}"
}

# module "bexh_event_connector_service" {
#     source "../bexh_ecs_service"

#     name = "exchange-event-connector"
#     cluster_id = aws_ecs_cluster.main.id
#     env_name = var.env_name
#     account_id = var.account_id
#     ecr_repository = "bexh-event-connector-aws-ecs"
#     image_tag = var.event_connector_image_tag
#     security_groups = ["${aws_security_group.ecs_sg.id}"]
#     log_level = var.log_level
#     subnets = var.es_subnets
#     env_vars = {
#         "LOG_LEVEL": "${var.log_level}",
#         "ENV_NAME": "${var.env_name}",
#         "REDIS_HOST": "${aws_elasticache_cluster.this.configuration_endpoint}",
#         "REDIS_PORT": "${aws_elasticache_cluster.this.port}",
#         "INCOMING_KINESIS_STREAM_NAME": "${aws_kinesis_stream.incoming.name}",
#         "OUTGOING_KINESIS_STREAM_NAME": "${aws_kinesis_stream.outgoing.name}",
#         "TEST": "${aws_elasticache_cluster.this.cache_nodes.0.address}"
#       }
# }

# resource "aws_ecs_task_definition" "event_connector" {
#   family                   = "bexh-exchange-event-connector-${var.env_name}-${var.account_id}"
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   cpu                      = "512"
#   memory                   = "1024"
#   task_role_arn            = aws_iam_role.ecs_task_definition_role.arn
#   execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

#   container_definitions = <<DEFINITION
# [
#   {
#     "cpu": 128,
#     "environment": [{
#         "LOG_LEVEL": "${var.log_level}",
#         "ENV_NAME": "${var.env_name}",
#         "REDIS_HOST": "${aws_elasticache_cluster.this.configuration_endpoint}",
#         "REDIS_PORT": "${aws_elasticache_cluster.this.port}",
#         "INCOMING_KINESIS_STREAM_NAME": "${aws_kinesis_stream.incoming.name}",
#         "OUTGOING_KINESIS_STREAM_NAME": "${aws_kinesis_stream.outgoing.name}",
#         "TEST": "${aws_elasticache_cluster.this.cache_nodes.0.address}"
#       }],
#     "image": "${var.account_id}.dkr.ecr.us-east-1.amazonaws.com/bexh-event-connector-aws-ecs:${var.event_connector_image_tag}",
#     "memory": 128,
#     "name": "app",
#     "networkMode": "awsvpc",
#     "portMappings": [],
#     "logConfiguration": {
#       "logDriver": "awslogs",
#       "options": {
#         "awslogs-group": "${aws_cloudwatch_log_group.ecs_connector.name}",
#         "awslogs-region": "us-east-1",
#         "awslogs-stream-prefix": "ecs" 
#       }
#     }
#   }
# ]
# DEFINITION

#   depends_on = [aws_cloudwatch_log_group.ecs_connector]
# }

# resource "aws_cloudwatch_log_group" "ecs_connector" {
#   name = "/ecs/bexh-exchange-connector-${var.env_name}-${var.account_id}"
# }

# resource "aws_ecs_service" "main" {
#   name            = "exchange-event-connector"
#   env_name = var.env_name
#   account_id = var.account_id
#   cluster         = aws_ecs_cluster.main.id
#   task_definition = aws_ecs_task_definition.event_connector.arn
#   # task_definition      = "${aws_ecs_task_definition.event_connector.family}:${aws_ecs_task_definition.event_connector.revision}"
#   desired_count        = 0
#   launch_type          = "FARGATE"
#   force_new_deployment = true

#   network_configuration {
#     security_groups = ["${aws_security_group.ecs_sg.id}"]
#     subnets         = var.es_subnets
#     # TODO: remove this after setting up privatelink
#     assign_public_ip = true
#   }

#   depends_on = [aws_iam_policy.ecs_task_definition_policy]
# }

# resource "aws_iam_role" "ecs_task_execution_role" {
#   name               = "ecs-exchange-task-execution-role-${var.env_name}-${var.account_id}"
#   assume_role_policy = data.aws_iam_policy_document.ecs_assume_role_policy_doc.json
# }

# resource "aws_iam_role_policy_attachment" "ecs_execution_role_attachment" {
#   role       = aws_iam_role.ecs_task_execution_role.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
# }

# data "aws_iam_policy_document" "ecs_assume_role_policy_doc" {
#   statement {
#     actions = ["sts:AssumeRole"]

#     principals {
#       type        = "Service"
#       identifiers = ["ecs-tasks.amazonaws.com"]
#     }
#   }
# }

# resource "aws_iam_role" "ecs_task_definition_role" {
#   name               = "ecs-exchange-task-definition-role-${var.env_name}-${var.account_id}"
#   assume_role_policy = data.aws_iam_policy_document.ecs_assume_role_policy_doc.json
# }

# resource "aws_iam_role_policy_attachment" "ecs_service_role_attachment" {
#   role       = aws_iam_role.ecs_task_definition_role.name
#   policy_arn = aws_iam_policy.ecs_task_definition_policy.arn
# }

# resource "aws_iam_policy" "ecs_task_definition_policy" {
#   name = "bexh-exchange-service-policy-${var.env_name}-${var.account_id}"

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

// region: s3 bucket

resource "aws_s3_bucket" "incoming_data" {
  bucket = "bexh-exchange-incoming-${var.env_name}-${var.account_id}"
}

resource "aws_s3_bucket" "outgoing_data" {
  bucket = "bexh-exchange-outgoing-${var.env_name}-${var.account_id}"
}

// region: kinesis

resource "aws_kinesis_stream" "incoming" {
  name        = "bexh-exchange-incoming-${var.env_name}-${var.account_id}"
  shard_count = 1
}

resource "aws_kinesis_stream" "outgoing" {
  name        = "bexh-exchange-outgoing-${var.env_name}-${var.account_id}"
  shard_count = 1
}

// region: kinesis firehose

resource "aws_kinesis_firehose_delivery_stream" "incoming" {
  name        = "bexh-exchange-incoming-firehose-${var.env_name}-${var.account_id}"
  destination = "s3"

  s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.incoming_data.arn
  }

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.incoming.arn
    role_arn           = aws_iam_role.firehose_role.arn
  }
}

resource "aws_kinesis_firehose_delivery_stream" "outgoing" {
  name        = "bexh-exchange-outgoing-firehose-${var.env_name}-${var.account_id}"
  destination = "s3"

  s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.outgoing_data.arn
  }

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.outgoing.arn
    role_arn           = aws_iam_role.firehose_role.arn
  }
}

resource "aws_iam_role" "firehose_role" {
  name = "bexh-exchange-firehose-role-${var.env_name}-${var.account_id}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "firehose.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "attach_s3_write" {
  role       = aws_iam_role.firehose_role.name
  policy_arn = aws_iam_policy.s3_write.arn
}

resource "aws_iam_policy" "s3_write" {
  name        = "bexh-exchange-firehose-${var.env_name}-${var.account_id}"
  description = "Allows firehose to write to s3"

  policy = <<EOF
{
    "Version": "2012-10-17",  
    "Statement":
    [    
        {      
            "Effect": "Allow",      
            "Action": [
                "s3:AbortMultipartUpload",
                "s3:GetBucketLocation",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:ListBucketMultipartUploads",
                "s3:PutObject"
            ],      
            "Resource": [        
                "${aws_s3_bucket.incoming_data.arn}",
                "${aws_s3_bucket.outgoing_data.arn}"		    
            ]    
        },        
        {
            "Effect": "Allow",
            "Action": [
                "kinesis:DescribeStream",
                "kinesis:GetShardIterator",
                "kinesis:GetRecords",
                "kinesis:ListShards"
            ],
            "Resource": [
                "${aws_kinesis_stream.incoming.arn}",
                "${aws_kinesis_stream.outgoing.arn}"
            ]
        }
    ]
    }
    EOF
}

// region: elasticache redis

resource "aws_elasticache_cluster" "this" {
  cluster_id           = "bexh-exchange-marketbook-${var.env_name}-${var.account_id}"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis6.0"
  port                 = 6379
}
