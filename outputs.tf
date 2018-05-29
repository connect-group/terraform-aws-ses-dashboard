output "topic_arn" {
  value = "${aws_sns_topic.email_delivery_topic.arn}"
}
