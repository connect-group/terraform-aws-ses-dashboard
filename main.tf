data "aws_caller_identity" "current" {
}

data "aws_region" "current" {
}

resource "random_id" "bucket" {
  byte_length = 10
}

locals {
  bucket_name = length(var.unique_bucket_name) > 0 ? var.unique_bucket_name : format("email-delivery-dashboard-%s", random_id.bucket.hex)
}

resource "aws_sns_topic" "email_delivery_topic" {
  name = var.email_delivery_topic_name
}

resource "aws_sqs_queue" "email_delivery_queue" {
  name                       = var.queue_name
  visibility_timeout_seconds = 300

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Id": "arn:aws:sqs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${var.queue_name}/SQSDefaultPolicy",
  "Statement": [
    {
      "Sid": "${var.queue_name}",
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": "SQS:SendMessage",
      "Resource": "arn:aws:sqs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${var.queue_name}",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "arn:aws:sns:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${aws_sns_topic.email_delivery_topic.name}"
        }
      }
    }
  ]
}
EOF


  tags = var.tags
}

resource "aws_sns_topic_subscription" "email_delivery_queue_topic_subscription" {
  topic_arn = aws_sns_topic.email_delivery_topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.email_delivery_queue.arn
}

resource "aws_s3_bucket" "dashboard_bucket" {
  bucket = local.bucket_name
  acl    = "private"

  lifecycle_rule {
    id      = "retention"
    enabled = true

    expiration {
      days = var.report_retention_days
    }
  }

  tags = merge(
    var.tags,
    {
      "Name" = "Email Delivery Dashboard"
    },
  )
}

resource "aws_iam_policy" "email_delivery_dashboard_policy" {
  name        = "email-delivery-dashboard-policy"
  description = "Permissions for Email Delivery Dashboard"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
      {
          "Effect": "Allow",
          "Action": ["sns:Publish"],
          "Resource": "${aws_cloudformation_stack.email-dashboard-to-sns-topic.outputs["ARN"]}"
      },
      {
          "Sid": "s3allow",
          "Effect": "Allow",
          "Action": [
              "s3:PutObject",
              "s3:PutObjectAcl"
          ],
          "Resource": [
              "arn:aws:s3:::${aws_s3_bucket.dashboard_bucket.id}/*"
          ]
      },
      {
          "Sid": "AllowQueuePermissions",
          "Effect": "Allow",
          "Action": [
              "sqs:ChangeMessageVisibility",
              "sqs:ChangeMessageVisibilityBatch",
              "sqs:DeleteMessage",
              "sqs:DeleteMessageBatch",
              "sqs:GetQueueAttributes",
              "sqs:GetQueueUrl",
              "sqs:ReceiveMessage"
          ],
          "Resource": [
              "${aws_sqs_queue.email_delivery_queue.arn}"
          ]
      },
      {
          "Effect": "Allow",
          "Action": [
              "logs:CreateLogGroup",
              "logs:CreateLogStream",
              "logs:PutLogEvents",
              "logs:DescribeLogStreams"
          ],
          "Resource": [
              "arn:aws:logs:*:*:*"
          ]
      }
    ]
}
EOF

}

resource "aws_iam_role" "dashboard_role" {
  name = "email-delivery-dashboard-role"

  assume_role_policy = <<EOF
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
EOF

}

resource "aws_iam_role_policy_attachment" "attach_dashboard_policy_to_role" {
  role       = aws_iam_role.dashboard_role.name
  policy_arn = aws_iam_policy.email_delivery_dashboard_policy.arn
}

data "archive_file" "source" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/sesreport.zip"
}

resource "aws_lambda_function" "dashboard_lambda" {
  filename = substr(data.archive_file.source.output_path, 0, length(path.cwd)) == path.cwd ? substr(
    data.archive_file.source.output_path,
    length(path.cwd) + 1,
    -1,
  ) : data.archive_file.source.output_path
  function_name    = "publish_ses_dashboard"
  role             = aws_iam_role.dashboard_role.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.source.output_base64sha256
  runtime          = "nodejs12.x"
  description      = "MANAGED BY TERRAFORM"

  memory_size = "512"
  timeout     = "300"

  environment {
    variables = {
      QueueURL                 = aws_sqs_queue.email_delivery_queue.id
      Region                   = data.aws_region.current.name
      EmailReportToTopic       = aws_cloudformation_stack.email-dashboard-to-sns-topic.outputs["ARN"]
      EmailIntroductionMessage = var.email_introduction_message
      BucketName               = aws_s3_bucket.dashboard_bucket.id
      BucketPrefix             = var.bucket_prefix
    }
  }
}

resource "aws_cloudwatch_event_rule" "generate_dashboard" {
  name                = "generate_email_dashboard"
  description         = "MANAGED BY TERRAFORM"
  schedule_expression = "cron(0 4 * * ? *)"
}

resource "aws_lambda_permission" "allow-cloudwatch-to-run-generate-dashboard-lambda" {
  statement_id  = "AllowExecutionFromCloudWatchGenerateDashboard"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dashboard_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.generate_dashboard.arn
}

resource "aws_cloudwatch_event_target" "generate-dashboard-scheduled-event-target" {
  rule      = aws_cloudwatch_event_rule.generate_dashboard.name
  target_id = "generate-email-dashboard-target"
  arn       = aws_lambda_function.dashboard_lambda.arn
}

