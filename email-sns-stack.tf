resource "aws_cloudformation_stack" "email-dashboard-to-sns-topic" {
  name = var.email_dashboard_name
  template_body = templatefile("${path.module}/cloudformation/email-sns-stack.json.tpl", {
    display_name = var.email_from_display_name
    email_addresses = join(
      ",",
      formatlist(
        "{\"Endpoint\": \"%s\", \"Protocol\": \"email\"}",
        var.to_addresses,
      ),
    )
  })

  tags = var.tags
}

