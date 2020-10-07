variable "to_addresses" {
  type        = list(string)
  description = "[Required] The email addresses that will receive the bounce and complaint report."
}

variable "unique_bucket_name" {
  default     = ""
  description = "[Optional] Name of an S3 bucket to create, which will hold the dashboard files. If not specified, generated with random identifier."
}

variable "tags" {
  default     = {}
  description = "[Optional] Tags to be added to resources that support tagging."
}

variable "email_from_display_name" {
  default     = "Email Delivery Dashboard"
  description = "[Optional] The email sender displayed in report recipients inbox.  Useful if you have many accounts being monitored."
}

variable "email_introduction_message" {
  default     = ""
  description = "[Optional] Introduction sent with an email when we need to notify that emails have bounced."
}

variable "bucket_prefix" {
  default     = ""
  description = "[Optional] Prefix (folder) in which to place reports."
}

variable "report_retention_days" {
  default     = 30
  description = "[Optional] Number of days to retain the reports."
}

variable "queue_name" {
  default     = "email-delivery-queue"
  description = "[Optional] Name of the SQS queue created by this module."
}

variable "email_delivery_topic_name" {
  default     = "email-delivery-topic"
  description = "[Optional] Name of the SNS Topic created by this module."
}

variable "email_dashboard_name" {
  default     = "email-delivery-dashboard-email-recipient"
  description = "[Optional] Name of CloudFormation stack."
}

