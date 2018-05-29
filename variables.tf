variable "unique_bucket_name" {
  description="Name of an S3 bucket which will hold the dashboard"
}

variable "tags" {
  default = {}
}

variable "to_addr" {
  default=""
	description="[Optional] The email address that will receive the bounce and complaint report."
}

variable "from_addr" {
  default=""
	description="[Optional] The email address that will send the bounce and complaint report."
}
