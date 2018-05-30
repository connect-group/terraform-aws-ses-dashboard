{
  "AWSTemplateFormatVersion": "2010-09-09",

  "Resources" : {
    "EmailSNSTopic": {
      "Type" : "AWS::SNS::Topic",
      "Properties" : {
        "DisplayName" : "${display_name}",
        "Subscription": [
          ${email_addresses}
        ]
      }
    }
  },

  "Outputs" : {
    "ARN" : {
      "Description" : "Email SNS Topic ARN",
      "Value" : { "Ref" : "EmailSNSTopic" }
    }
  }
}

