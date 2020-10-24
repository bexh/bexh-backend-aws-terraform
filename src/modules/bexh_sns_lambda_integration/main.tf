module "bexh_lambda" {
  source = "../bexh_lambda"

  function_name     = var.function_name
  s3_key            = var.s3_key
  s3_object_version = var.s3_object_version
  env_name          = var.env_name
  account_id        = var.account_id
  handler           = var.handler
  timeout           = var.timeout
  env_vars = var.env_vars
}

resource "aws_lambda_permission" "sns_invoke_function" {
  statement_id  = "AllowSnsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.bexh_lambda.aws_lambda_function.function_name
  principal     = "sns.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = aws_sns_topic.this.arn
}

resource "aws_sns_topic" "this" {
  name = "bexh-${var.sns_topic_name}-${var.env_name}-${var.account_id}"
}

resource "aws_sns_topic_subscription" "invoke_with_sns" {
  topic_arn = aws_sns_topic.this.arn
  protocol  = "lambda"
  endpoint  = module.bexh_lambda.aws_lambda_function.arn
}

resource "aws_sns_topic_policy" "default" {
  arn = aws_sns_topic.this.arn

  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  policy_id = "__default_policy_ID"

  statement {
    actions = [
      "SNS:Subscribe",
      # "SNS:SetTopicAttributes",
      # "SNS:RemovePermission",
      "SNS:Receive",
      "SNS:Publish",
      # "SNS:ListSubscriptionsByTopic",
      # "SNS:GetTopicAttributes",
      # "SNS:DeleteTopic",
      # "SNS:AddPermission",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"

      values = [
        var.account_id,
      ]
    }

    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    resources = [
      aws_sns_topic.this.arn,
    ]

    sid = "__default_statement_ID"
  }
}