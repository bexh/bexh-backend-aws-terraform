resource "aws_s3_bucket" "this" {
  bucket = "bexh-${var.name}-${var.env_name}-${var.account_id}"
}

resource "aws_kinesis_firehose_delivery_stream" "this" {
  name        = "bexh-${var.name}-fhose-${var.env_name}-${var.account_id}"
  destination = "s3"

  s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.this.arn
  }

  kinesis_source_configuration {
    kinesis_stream_arn = var.kinesis_stream_arn
    role_arn           = aws_iam_role.firehose_role.arn
  }
}

resource "aws_iam_role" "firehose_role" {
  name = "bexh-${var.name}-fhose-role-${var.env_name}-${var.account_id}"

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
  name        = "bexh-${var.name}-fhose-${var.env_name}-${var.account_id}"
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
                "${aws_s3_bucket.this.arn}",	    
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
                "${var.kinesis_stream_arn}"
            ]
        }
    ]
    }
    EOF
}