SES Deliverability Dashboard
============================
This module will create a [Bounce Complaint Dashboard](https://aws.amazon.com/blogs/messaging-and-targeting/creating-a-daily-dashboard-to-track-bounces-and-complaints/) report that shows information about SES Email bounces and complaints.

> Bounce and complaint rates can have a negative impact on your sender reputation. This makes it less likely that the emails you send through Amazon SES will reach your recipients' inboxes. Additionally, if your bounce or complaint rate is too high, we may have to suspend your Amazon SES account to protect other users.
> 
> For these reasons, it is essential that you have a process to remove email addresses that bounced or complained from your recipient list. This section describes a sample tracking dashboard that you can use to track bounces and complaints using other AWS services. You can customize this solution to meet your specific needs.
> 
> When you use this terraform module, you will receive an email every day that includes a link. When you click the link, you see a dashboard that displays information about the numbers of bounces and complaints that were received in the previous 24-hour period. The dashboard also provides details about the messages that resulted in bounces and complaints. The following image shows an example of this dashboard.

![](https://user-images.githubusercontent.com/1678311/67145683-265c6780-f27b-11e9-95f3-51d5889e19c9.png)

Note, the original article on which this is based was taken down in May 2019.  This terraform solution will still work.

It is a slight adaptation of the functionality described in the AWS Developer documentation because it uses an SNS Email topic to send the report, rather then sending it directly from a verified SES sender.  This elimates manual steps.

Usage
-----
```hcl
resource "aws_ses_domain_identity" "example" {
  domain = "example.com"
}

resource "aws_route53_record" "example_amazonses_verification_record" {
  zone_id = "ABCDEFGHIJ123"
  name    = "_amazonses.example.com"
  type    = "TXT"
  ttl     = "600"
  records = ["${aws_ses_domain_identity.example.verification_token}"]
}

module "dashboard" {
  source                     = "connect-group/ses-dashboard/aws"
  to_addresses               = ["someone@example.com", "someone.else@example.com"]
  email_from_display_name    = "Bounced Emails Dashboard"
  email_introduction_message = "Bounced emails, or complaint emails, have been received for this account."
}

resource "aws_ses_identity_notification_topic" "bounce_notifications" {
  topic_arn         = "${module.dashboard.topic_arn}"
  notification_type = "Bounce"
  identity          = "${aws_ses_domain_identity.example.domain}"
}

resource "aws_ses_identity_notification_topic" "complaint_notifications" {
  topic_arn         = "${module.dashboard.topic_arn}"
  notification_type = "Complaint"
  identity          = "${aws_ses_domain_identity.example.domain}"
}
```

Manual Steps
------------
AWS will send a subscription email to the email specified by `to_addr`.

In order to capture bounce and complaint notifications, the verified email sender (email identity, or domain identity) which sends emails must be configured to notify the application of bounces.  

Email Identities cannot be created by Terraform or CloudFormation, but domain identities can be created (as in the example above).

If your email identity is managed manually then you will need to  configure SES notifications as described in [Part 5](https://docs.aws.amazon.com/ses/latest/DeveloperGuide/dashboardconfigureSESnotifications.html) of the AWS tutorial.

1. Open the Amazon SES console at https://console.aws.amazon.com/ses/.

2. In the navigation bar, under Identity Management, choose Email Addresses.

3. Select the email address that you want to use to receive bounce and complaint notifications, 
   and then choose View Details.

4. Under Notifications, choose Edit Configuration.

5. For both Bounces and Complaints, choose the Amazon SNS topic 'email-delivery-topic'

6. Repeat steps 3–5 for each email address that should receive bounce or complaint notifications.


> **Note**
>
> Unlike the original articles AWS Dashboard - *there is no need to purge the SQS queue*.  
> This version of the lambda will ignore items in the queue that it cannot parse.

Restrictions
------------
This module expects the SQS and SNS topic to be in the same region.  

Testing
-------
To test the Lambda function,

1. Open the Amazon SES console at https://console.aws.amazon.com/ses/.

2. In the column on the left, choose either Email Addresses or Domains.

3. Select a verified email address or domain, and then choose Send a Test Email.

4. For To:, type bounce@simulator.amazonses.com. For Subject and Body, type some sample text. Choose Send Test Email.

5. Repeat steps 3 and 4 to create another test message, but this time, for To:, type complaint@simulator.amazonses.com.

6. Open the Amazon SQS console at https://console.aws.amazon.com/sqs/. The Messages Available column should indicate that 2 messages are available.

7. Open the Lambda console at https://console.aws.amazon.com/lambda/.

8. In the navigation bar, choose Functions.

9. In the list of functions, choose the new lambda, "publish_ses_dashboard"

10. Choose Test. When the function finishes running, expand the Details section. If the Lambda function was configured properly, you will receive one of the following messages:

> null: Indicates that the function ran without errors.
> Queue empty: Indicates that there were no new bounce or complaint notifications in the queue.

Compatibility
-------------
The 1.0.6 release is compatible with Terraform 0.10.4 - 0.12
The 2.0.0 release upgrades the syntax and is therefore compatible with Terraform 0.12-0.13.

The AWS Provider must be on v2.11+ as earlier versions do not recognise "node10.x" as a valid Lambda runtime environment.

References
----------
* [AWS Blog](https://aws.amazon.com/blogs/messaging-and-targeting/creating-a-daily-dashboard-to-track-bounces-and-complaints/)
* [Appendix: Create a Deliverability Dashboard](https://github.com/connect-group/terraform-aws-ses-dashboard/wiki)


