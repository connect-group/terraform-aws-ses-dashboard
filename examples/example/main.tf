#versioning has moved to terraform.tf

provider "aws" {
  region = "eu-west-1"
}

module "dashboard" {
  source                     = "../../"
  to_addresses               = [var.to_addr]
  email_from_display_name    = "Bounced Emails Dashboard"
  email_introduction_message = "Bounced emails, or complaint emails, have been received for this account. <b>Some bold text (maybe)</b>"
}

