import nodemailer, {
  Transporter,
  SendMailOptions,
} from "nodemailer";

import { env } from "../config/env.js";

let transporter: Transporter | null = null;

function getTransporter(): Transporter {
  if (!transporter) {
    transporter = nodemailer.createTransport({
      host: env.SMTP_HOST,
      port: env.SMTP_PORT,
      secure: env.SMTP_SECURE,

      auth: {
        user: env.SMTP_USER,
        pass: env.SMTP_PASSWORD,
      },

      connectionTimeout: 15000,
      greetingTimeout: 15000,
      socketTimeout: 20000,
    });
  }

  return transporter;
}

export interface WelcomeEmailInput {
  recipientEmail: string;
  recipientName: string;
  userNumber: string;
  username: string;
  setupPasswordUrl: string;
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

export async function verifyEmailConnection(): Promise<void> {
  await getTransporter().verify();
}

export async function sendWelcomeEmail(
  input: WelcomeEmailInput
): Promise<void> {
  const recipientName = escapeHtml(input.recipientName);
  const userNumber = escapeHtml(input.userNumber);
  const username = escapeHtml(input.username);
  const setupPasswordUrl = input.setupPasswordUrl;

  const mail: SendMailOptions = {
    from: {
      name: env.SMTP_FROM_NAME,
      address: env.SMTP_FROM_EMAIL,
    },

    to: input.recipientEmail,

    subject:
      "Welcome to IDMC Integrated Management Information System",

    text: `
Welcome to IDMC Integrated Management Information System.

Dear ${input.recipientName},

Your IDMC system account has been created successfully.

User Number:
${input.userNumber}

Username:
${input.username}

For security, no password is included in this email.

Please use the secure link below to set your password:

${input.setupPasswordUrl}

After setting your password, you can sign in to the IDMC system.

If you did not expect this account, please contact the IDMC system administrator.

Regards,
IDMC System Administration
`,

    html: `
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>IDMC Welcome</title>
</head>

<body style="margin:0;padding:0;background:#f4f4f4;font-family:Arial,Helvetica,sans-serif;">

<table width="100%" cellpadding="0" cellspacing="0" border="0">
<tr>
<td align="center" style="padding:30px 15px;">

<table
    width="600"
    cellpadding="0"
    cellspacing="0"
    border="0"
    style="max-width:600px;background:#ffffff;border-radius:8px;overflow:hidden;"
>

<tr>
<td style="background:#7a0019;color:#ffffff;padding:28px;text-align:center;">

<h1 style="margin:0;font-size:24px;">
IDMC iMIS
</h1>

<p style="margin:8px 0 0;font-size:14px;">
Integrated Management Information System
</p>

</td>
</tr>

<tr>
<td style="padding:35px;">

<h2 style="color:#222;margin-top:0;">
Welcome, ${recipientName}
</h2>

<p style="color:#444;line-height:1.6;">
Your IDMC system account has been created successfully.
</p>

<table
    width="100%"
    cellpadding="10"
    cellspacing="0"
    border="0"
    style="background:#f8f8f8;border:1px solid #e5e5e5;"
>

<tr>
<td>
<strong>User Number</strong>
</td>
<td>
${userNumber}
</td>
</tr>

<tr>
<td>
<strong>Username</strong>
</td>
<td>
${username}
</td>
</tr>

</table>

<p style="color:#444;line-height:1.6;margin-top:25px;">
For your security, your password is not included in this email.
Please use the button below to create your password.
</p>

<p style="text-align:center;margin:30px 0;">

<a
href="${setupPasswordUrl}"
style="
display:inline-block;
background:#7a0019;
color:#ffffff;
text-decoration:none;
padding:14px 25px;
border-radius:5px;
font-weight:bold;
"
>
Set My Password
</a>

</p>

<p style="font-size:13px;color:#777;line-height:1.6;">
If the button does not work, copy and paste the following address into
your browser:
</p>

<p style="font-size:12px;word-break:break-all;color:#555;">
${setupPasswordUrl}
</p>

<p style="font-size:13px;color:#777;line-height:1.6;">
If you did not expect this account, please contact the IDMC system
administrator immediately.
</p>

</td>
</tr>

<tr>
<td style="background:#f7f7f7;padding:20px;text-align:center;">

<p style="margin:0;font-size:12px;color:#777;">
IDMC System Administration
</p>

</td>
</tr>

</table>

</td>
</tr>
</table>

</body>
</html>
`,
  };

  await getTransporter().sendMail(mail);
}
