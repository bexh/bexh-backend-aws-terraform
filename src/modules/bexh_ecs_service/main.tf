resource "aws_ecs_task_definition" "this" {
  family                   = "bexh-${var.name}-${var.env_name}-${var.account_id}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  task_role_arn            = aws_iam_role.ecs_task_definition_role.arn
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = module.container_definition.container_definitions

  depends_on = [
      aws_cloudwatch_log_group.this,
      aws_iam_role.ecs_task_execution_role
    ]
}

module "container_definition" {
  source = "../terraform_aws_ecs_task_definition"

  name         = var.name
  family       = "bexh-${var.name}-${var.env_name}-${var.account_id}"
  cpu          = 128
  environment  = var.env_vars
  image        = var.image
  memory       = 128
  network_mode = "awsvpc"
  portMappings = var.portMappings
  secrets      = var.secrets
  logConfiguration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = "${aws_cloudwatch_log_group.this.name}"
      awslogs-region        = "${var.region}"
      awslogs-stream-prefix = "ecs"
    }
  }
}

resource "aws_cloudwatch_log_group" "this" {
  name = "/ecs/bexh-${var.name}-${var.env_name}-${var.account_id}"
}

resource "aws_ecs_service" "main" {
  name            = "bexh-${var.name}-${var.env_name}-${var.account_id}"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  # task_definition      = "${aws_ecs_task_definition.this.family}:${aws_ecs_task_definition.this.revision}"
  desired_count = var.instance_count
  launch_type   = "FARGATE"

  network_configuration {
    security_groups = var.security_groups
    subnets         = var.subnets
    # TODO: remove this after setting up privatelink
    assign_public_ip = true
  }

  dynamic "load_balancer" {
    for_each = var.load_balancer ? [1] : []

    content {
      target_group_arn = aws_lb_target_group.ecs_target[0].arn
      container_name   = var.name
      container_port   = var.portMappings[0].containerPort
    }
  }

  depends_on = [
    aws_iam_policy.ecs_task_definition_policy,
    aws_lb_listener.this,
    aws_lb.this
  ]
}

resource "aws_lb_target_group" "ecs_target" {
  count = var.load_balancer ? 1 : 0

  name        = "bexh-${var.name}-tg-${var.env_name}"
  port        = var.portMappings[0].hostPort
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc
}

resource "aws_lb" "this" {
  count = var.load_balancer ? 1 : 0

  name               = "bexh-${var.name}-lb-${var.env_name}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = var.security_groups
  subnets            = var.subnets
}

resource "aws_lb_listener" "this" {
  count = var.load_balancer ? 1 : 0

  load_balancer_arn = aws_lb.this[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.ecs_target[0].arn
    type             = "forward"
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecs-${var.name}-task-exec-role-${var.env_name}-${var.account_id}"
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

resource "aws_iam_role_policy_attachment" "ecs_execution_role_attach_get_secret" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.secrets.arn
}

resource "aws_iam_policy" "secrets" {
  name        = "bexh-${var.name}-get-secrets-${var.env_name}-${var.account_id}"
  description = "Allows ecs to use secrets as env vars in container definition"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.region}:${var.account_id}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task_definition_role" {
  name               = "ecs-${var.name}-task-def-role-${var.env_name}-${var.account_id}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "ecs_service_role_attachment" {
  role       = aws_iam_role.ecs_task_definition_role.name
  policy_arn = aws_iam_policy.ecs_task_definition_policy.arn
}

resource "aws_iam_policy" "ecs_task_definition_policy" {
  name = "bexh-${var.name}-service-policy-${var.env_name}-${var.account_id}"

  policy = var.ecs_task_definition_policy
}
