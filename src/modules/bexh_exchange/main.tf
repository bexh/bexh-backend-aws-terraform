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

resource "aws_ecs_cluster" "this" {
  name = "bexh-exch-cluster-${var.env_name}-${var.account_id}"
}

module "bexh_event_connector_service" {
  source = "../bexh_ecs_service"

  name            = "exch-event-connector"
  cluster_id      = aws_ecs_cluster.this.id
  env_name        = var.env_name
  account_id      = var.account_id
  ecr_repository  = "bexh-event-connector-aws-ecs"
  image_tag       = var.event_connector_image_tag
  security_groups = ["${aws_security_group.ecs_sg.id}"]
  log_level       = var.log_level
  subnets         = var.es_subnets
  env_vars        = <<EOF
[
    {
        "LOG_LEVEL" : "${var.log_level}",
        "ENV_NAME" : "${var.env_name}",
        "REDIS_HOST" : "${aws_elasticache_replication_group.this.configuration_endpoint_address}",
        "REDIS_PORT" : "${aws_elasticache_replication_group.this.port}",
        "INCOMING_BETS_KINESIS_STREAM_NAME" : "${aws_kinesis_stream.incoming_bets.name}",
        "OUTGOING_EVENTS_KINESIS_STREAM_NAME" : "${aws_kinesis_stream.outgoing_events.name}",
        "OUTGOING_BETS_KINESIS_STREAM_NAME": "${aws_kinesis_stream.outgoing_bets.name}"
    }
]
EOF
}

module "bexh_trade_executor_service" {
  source = "../bexh_ecs_service"

  name            = "exch-trade-executor"
  cluster_id      = aws_ecs_cluster.this.id
  env_name        = var.env_name
  account_id      = var.account_id
  ecr_repository  = "bexh-trade-executor-aws-ecs"
  image_tag       = var.trade_executor_image_tag
  security_groups = ["${aws_security_group.ecs_sg.id}"]
  log_level       = var.log_level
  subnets         = var.es_subnets
  env_vars        = <<EOF
[
    {
        "LOG_LEVEL" : "${var.log_level}",
        "ENV_NAME" : "${var.env_name}",
        "REDIS_HOST" : "${aws_elasticache_replication_group.this.configuration_endpoint_address}",
        "REDIS_PORT" : "${aws_elasticache_replication_group.this.port}",
        "INCOMING_KINESIS_STREAM_NAME" : "${aws_kinesis_stream.incoming_bets.name}",
        "OUTGOING_KINESIS_STREAM_NAME" : "${aws_kinesis_stream.outgoing_bets.name}",
        "KCL_STATE_MANAGER_TABLE_NAME": "${aws_dynamodb_table.trade_executor_kcl_state_manager.name}"
    }
]
EOF
}


// region: kcl state manager

resource "aws_dynamodb_table" "trade_executor_kcl_state_manager" {
  name         = "bexh-exch-kcl-st-mgmt-${var.env_name}-${var.account_id}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "shard"

  attribute {
    name = "shard"
    type = "S"
  }
}

// region: kinesis

resource "aws_kinesis_stream" "incoming_bets" {
  name        = "bexh-exch-bets-in-${var.env_name}-${var.account_id}"
  shard_count = 1
}

resource "aws_kinesis_stream" "outgoing_events" {
  name        = "bexh-exch-events-out-${var.env_name}-${var.account_id}"
  shard_count = 1
}

resource "aws_kinesis_stream" "outgoing_bets" {
  name        = "bexh-exch-bets-out-${var.env_name}-${var.account_id}"
  shard_count = 1
}

// region: kinesis firehose & s3

module "incoming_bets_kinesis_firehose_s3" {
  source = "../bexh_firehose_s3"

  name               = "bets-in"
  env_name           = var.env_name
  account_id         = var.account_id
  kinesis_stream_arn = aws_kinesis_stream.incoming_bets.arn
}

module "outgoing_bets_kinesis_firehose_s3" {
  source = "../bexh_firehose_s3"

  name               = "bets-out"
  env_name           = var.env_name
  account_id         = var.account_id
  kinesis_stream_arn = aws_kinesis_stream.outgoing_bets.arn
}

module "outgoing_events_kinesis_firehose_s3" {
  source = "../bexh_firehose_s3"

  name               = "events-out"
  env_name           = var.env_name
  account_id         = var.account_id
  kinesis_stream_arn = aws_kinesis_stream.outgoing_events.arn
}

// region: elasticache redis

# resource "aws_elasticache_cluster" "this" {
#   cluster_id           = "bexh-exch-mktbk-${var.env_name}-${var.account_id}"
#   replication_group_id = aws_elasticache_replication_group.this.id
# }

resource "aws_elasticache_replication_group" "this" {
  automatic_failover_enabled    = true
  replication_group_id          = "bexh-exch-mktbk-rep-${var.env_name}-${var.account_id}"
  replication_group_description = "bexh marketbook redis cluster"
  parameter_group_name          = aws_elasticache_parameter_group.this.name
  engine                        = "redis"
  node_type                     = "cache.t2.micro"
  port                          = 6379
  engine_version                = "6.x"

  cluster_mode {
    replicas_per_node_group = 1
    num_node_groups         = 2
  }
}

resource "aws_elasticache_parameter_group" "this" {
  name   = "bexh-exch-mktbk-params-${var.env_name}-${var.account_id}"
  family = "redis6.x"
  parameter {
    name  = "cluster-enabled"
    value = "yes"
  }
}

