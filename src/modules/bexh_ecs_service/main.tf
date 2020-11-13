resource "aws_ecs_task_definition" "this" {
  family                   = "bexh-exchange-event-connector-${var.env_name}-${var.account_id}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  task_role_arn            = aws_iam_role.ecs_task_definition_role.arn
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = <<DEFINITION
[
  {
    "cpu": 128,
    "environment": [${var.env_vars}],
    "image": "${var.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_repository}:${var.event_connector_image_tag}",
    "memory": 128,
    "name": "app",
    "networkMode": "awsvpc",
    "portMappings": [],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${aws_cloudwatch_log_group.this.name}",
        "awslogs-region": "${var.region}",
        "awslogs-stream-prefix": "ecs" 
      }
    }
  }
]
DEFINITION

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_cloudwatch_log_group" "this" {
  name = "/ecs/bexh-${var.name}-${var.env_name}-${var.account_id}"
}

resource "aws_ecs_service" "main" {
  name            = "bexh-${var.name}-${var.env_name}-${var.account_id}"
  cluster         = env.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  # task_definition      = "${aws_ecs_task_definition.this.family}:${aws_ecs_task_definition.this.revision}"
  desired_count        = 0
  launch_type          = "FARGATE"
  force_new_deployment = true

  network_configuration {
    security_groups = var.security_groups
    subnets         = var.subnets
    # TODO: remove this after setting up privatelink
    assign_public_ip = true
  }

  depends_on = [aws_iam_policy.ecs_task_definition_policy]
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecs-${var.name}-task-execution-role-${var.env_name}-${var.account_id}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_assume_role_policy_doc" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_definition_role" {
  name               = "ecs-${var.name}-task-definition-role-${var.env_name}-${var.account_id}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "ecs_service_role_attachment" {
  role       = aws_iam_role.ecs_task_definition_role.name
  policy_arn = aws_iam_policy.ecs_task_definition_policy.arn
}

resource "aws_iam_policy" "ecs_task_definition_policy" {
  name = "bexh-${var.name}-service-policy-${var.env_name}-${var.account_id}"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
    {
        "Effect": "Allow",
        "Action": [
          "dynamodb:*"
        ],
        "Resource": "*"
        }
    ]
}
EOF
}
