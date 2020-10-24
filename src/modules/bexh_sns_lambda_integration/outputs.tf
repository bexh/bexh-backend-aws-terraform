output "aws_lambda_function" {
    value = module.bexh_lambda.aws_lambda_function
}

output "aws_iam_role" {
    value = module.bexh_lambda.aws_iam_role
}

output "aws_iam_role_policy_attachment" {
    value = module.bexh_lambda.aws_iam_role_policy_attachment
}

output "aws_sns_topic" {
    value = aws_sns_topic.this
}

output "aws_sns_topic_subscription" {
    value = aws_sns_topic_subscription.invoke_with_sns
}

output "aws_sns_topic_policy" {
    value = aws_sns_topic_policy.default
}
