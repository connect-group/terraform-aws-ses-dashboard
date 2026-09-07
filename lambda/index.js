const {
    SQSClient,
    GetQueueAttributesCommand,
    ReceiveMessageCommand,
    DeleteMessageBatchCommand
} = require('@aws-sdk/client-sqs');
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const { SNSClient, PublishCommand } = require('@aws-sdk/client-sns');
const fs = require('fs');
const path = require('path');

// The Node.js 18+ managed runtimes bundle the AWS SDK for JavaScript v3 only
// (@aws-sdk/*); the v2 "aws-sdk" package they used to ship is gone. These three
// clients are all runtime-included, so the deployment package stays dependency-free.
const region = process.env.Region || process.env.AWS_REGION;
const sqs = new SQSClient({ region });
const s3 = new S3Client({ region });
const sns = new SNSClient({ region });

const queueURL = process.env.QueueURL;
const bucket = process.env.BucketName;
const prefix = process.env.BucketPrefix || "";
const emailToTopic = process.env.EmailReportToTopic;
const emailIntroductionMessage = process.env.EmailIntroductionMessage;

// ApproximateNumberOfMessages is only an estimate, so the drain loop cannot rely
// on receiving exactly that many messages. Stop after this many consecutive empty
// long polls, and always leave enough time to still upload and mail the report.
const RECEIVE_BATCH_SIZE = 10;
const RECEIVE_WAIT_SECONDS = 2;
const MAX_EMPTY_POLLS = 3;
const TIME_RESERVE_MS = 30000;

function row(type, btype, bsubtype, sender, destination, diagcode, time, id) {
    var otr = "<tr>";
    var ftr = "</tr>";
    var oline = "<td>";
    var cline = "</td>";

    return otr + oline + type + cline + oline + btype + cline + oline + bsubtype + cline + oline + sender + cline + oline + destination + cline + oline + diagcode + cline + oline + time + cline + oline + id + cline + ftr;
}

function objectUrl(key) {
    const encoded = key.split('/').map(encodeURIComponent).join('/');
    return `https://${bucket}.s3.${region}.amazonaws.com/${encoded}`;
}

function collect(message, rows) {
    const body = JSON.parse(message.Body);
    const msg = JSON.parse(body.Message);

    try {
        var destination = msg.mail.destination[0];
        var sender = msg.mail.source;
        var type = msg.notificationType;
        var time = msg.mail.timestamp;
        var id = msg.mail.messageId;
        var btype = null;
        var bsubtype = null;
        var diagcode = null;

        if (type == "Bounce") {
            btype = msg.bounce.bounceType; // Permanent || Transient
            bsubtype = msg.bounce.bounceSubType; // General || Supressed
            if (btype == "Permanent" && bsubtype == "Suppressed") {
                diagcode = "Suppressed by SES";
                msg.bounce.bouncedRecipients.forEach((recipient) => {
                    rows.suppressed.push(row(type, btype, bsubtype, sender, recipient.emailAddress, diagcode, time, id));
                });
            } else if (btype == "Permanent" && bsubtype == "General") {
                msg.bounce.bouncedRecipients.forEach((recipient) => {
                    diagcode = recipient.diagnosticCode;
                    rows.bouncePerm.push(row(type, btype, bsubtype, sender, recipient.emailAddress, diagcode, time, id));
                });
            } else if (btype == "Permanent" && bsubtype == "NoEmail") {
                diagcode = msg.bounce.bouncedRecipients[0].diagnosticCode;
                rows.bouncePerm.push(row(type, btype, bsubtype, sender, destination, diagcode, time, id));

            } else if (btype == "Undetermined") {
                diagcode = msg.bounce.bouncedRecipients[0].diagnosticCode;
                rows.bouncePerm.push(row(type, btype, bsubtype, sender, destination, diagcode, time, id));

            } else if (btype == "Transient") {
                diagcode = "soft-Bounce";
                msg.bounce.bouncedRecipients.forEach((recipient) => {
                    rows.bounceTrans.push(row(type, btype, bsubtype, sender, recipient.emailAddress, diagcode, time, id));
                });
            } else {
                console.log("it's an unknown bounce");
                diagcode = "unknown";
                rows.bouncePerm.push(row(type, btype, bsubtype, sender, destination, diagcode, time, id));
            }

        } else if (type == "Delivery") {
            console.log("Delivery notification not supported");

        } else if (type == "Complaint") {
            btype = "null";
            bsubtype = "null";
            diagcode = "null";
            rows.complaint.push(row(type, btype, bsubtype, sender, destination, diagcode, time, id));

        } else {
            console.log("not identified");
        }
    } catch (err) {
        console.log("Unexpected error, perhaps message type was not bounce/complaint. " + err.message + "\nMessage: " + msg);
    }
}

async function deleteBatch(messages) {
    const result = await sqs.send(new DeleteMessageBatchCommand({
        QueueUrl: queueURL,
        Entries: messages.map((message, i) => ({
            Id: String(i),
            ReceiptHandle: message.ReceiptHandle
        }))
    }));

    if (result.Failed && result.Failed.length > 0) {
        console.log("Failed to delete " + result.Failed.length + " message(s): " + JSON.stringify(result.Failed));
    }
}

async function sendMail(messageCount, url) {
    const emailMessage = `${emailIntroductionMessage}

There were ${messageCount} Bounced emails or complaints.

Please review the report at ${url}





Regards,


AWS SES Email Dashboard.







----------------------------------------------------------------
`;

    await sns.send(new PublishCommand({
        TargetArn: emailToTopic,
        Message: emailMessage
    }));
    console.log("sending email");
}

exports.handler = async (event, context) => {
    const date = (new Date()).toString().split(' ').splice(1, 4).join('-');

    console.log("Reading from: " + queueURL);
    const attributes = await sqs.send(new GetQueueAttributesCommand({
        QueueUrl: queueURL,
        AttributeNames: ["ApproximateNumberOfMessages"]
    }));
    const queueSize = parseInt(attributes.Attributes.ApproximateNumberOfMessages, 10) || 0;
    console.log("Reading queue, size = " + queueSize);

    if (queueSize == 0) {
        return 'Queue is empty.';
    }

    const rows = { bouncePerm: [], suppressed: [], bounceTrans: [], complaint: [] };
    let messageCount = 0;
    let emptyPolls = 0;

    while (messageCount < queueSize && emptyPolls < MAX_EMPTY_POLLS) {
        if (context.getRemainingTimeInMillis() < TIME_RESERVE_MS) {
            console.log("Out of time, publishing partial report after " + messageCount + " of " + queueSize + " message(s)");
            break;
        }

        const received = await sqs.send(new ReceiveMessageCommand({
            QueueUrl: queueURL,
            MaxNumberOfMessages: RECEIVE_BATCH_SIZE,
            WaitTimeSeconds: RECEIVE_WAIT_SECONDS
        }));
        const messages = received.Messages || [];

        if (messages.length == 0) {
            console.log("data without messages.");
            emptyPolls++;
            continue;
        }
        emptyPolls = 0;

        messages.forEach((message) => collect(message, rows));
        messageCount += messages.length;
        await deleteBatch(messages);
    }

    const middle = rows.bouncePerm.join('') + rows.suppressed.join('') + rows.bounceTrans.join('') + rows.complaint.join('');
    const begin = fs.readFileSync(path.join(__dirname, 'template', 'begin.html'), 'utf8');
    const end = fs.readFileSync(path.join(__dirname, 'template', 'end.html'), 'utf8');
    const content = begin + middle + end;
    const key = prefix + date + ".html";

    await s3.send(new PutObjectCommand({
        Bucket: bucket,
        Key: key,
        Body: content,
        ACL: 'public-read',
        ContentType: "text/html"
    }));
    console.log("uploading to s3");

    const url = objectUrl(key);

    if (emailToTopic) {
        await sendMail(messageCount, url);
    }

    return `Processed ${messageCount} message(s). Report: ${url}`;
};
