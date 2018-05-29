data "template_file" "cloudformation_sns_stack" {
  template = "${file("${path.module}/cloudformation/email-sns-stack.json.tpl")}"

  vars {
    display_name  = "${var.email_from_display_name}"
    email_address = "${var.to_addr}"
    protocol      = "email"
  }
}

resource "aws_cloudformation_stack" "email-dashboard-to-sns-topic" {
  name          = "email-delivery-dashboard-email-recipient"
  template_body = "${data.template_file.cloudformation_sns_stack.rendered}"

  tags = "${var.tags}"
}
