output "aws_s3_bucket" {
    value = aws_s3_bucket.this
}

output "aws_kinesis_firehose_delivery_stream" {
    value = aws_kinesis_firehose_delivery_stream.this
}

output "aws_iam_role" {
    value = aws_iam_role.firehose_role
}
