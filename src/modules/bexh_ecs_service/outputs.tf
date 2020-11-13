output "aws_ecs_task_definition" {
    value = aws_ecs_task_definition.this
}

output "aws_cloudwatch_log_group" {
    value = aws_ecs_task_definition.this
}

output "aws_ecs_service" {
    value = aws_ecs_service.main
}

output "task_execution_role" {
    value = aws_iam_role.ecs_task_execution_role
}

output "task_defintiion_role" {
    value = aws_iam_role.ecs_task_definition_role
}
