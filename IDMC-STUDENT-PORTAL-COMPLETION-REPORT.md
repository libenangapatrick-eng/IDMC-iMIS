# IDMC iMIS Student Portal Completion

Completed on 26 September 2026.

Migration version collision repair: the new result and portal migrations use
unique versions `20260926151502` and `20260926151503`. The included
`Repair-IDMC-Migration-Version-Collision.ps1` also relocates a local
`202609260001_student_engagement_services.sql` migration to `20260926151501`
and preserves the already-recorded remote version with a history marker.

## Delivered phases

1. Results calculation/import integrity remains protected by the P0 migration and staged import workflow.
2. Focused ownership-scoped student endpoints were added for dashboard, registration, results, attendance, timetable, finance, documents, notifications and transcript.
3. Registration now supports course selection, credit/prerequisite/capacity checks, submission and ADD/DROP requests.
4. Finance now shows account, invoices, payment requests, payments and statement transactions. A control-number request never records a payment. Only an authenticated provider callback can confirm a payment through one atomic database function.
5. Notifications support individual and bulk read state. Student documents use ownership checks and five-minute signed downloads.
6. Transcript view follows the existing DRAFT → GENERATED → REVIEW → APPROVED → ISSUED workflow and displays its protected semester/course snapshot.
7. Dashboard now displays current semester registration identity, GPA/CGPA, attendance, balance, academic risk, alerts and upcoming classes/examinations.
8. PowerShell apply, restart and E2E audit scripts are included.

## Run

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& ".\Apply-IDMC-Student-Portal-Completion.ps1" `
  -ProjectPath "C:\Users\liben\Documents\IDMC_iMIS"
```

To validate authenticated student endpoints after login, obtain the current bearer token from the browser session and run:

```powershell
& ".\Test-IDMC-Student-Portal-E2E.ps1" `
  -ProjectPath "C:\Users\liben\Documents\IDMC_iMIS" `
  -AccessToken "STUDENT-ACCESS-TOKEN"
```

## Payment provider configuration

Set a random value of at least 24 characters in `apps/backend/.env`:

```text
PAYMENT_PROVIDER_CALLBACK_SECRET=replace-with-a-long-random-secret
```

The provider sends `POST /api/v1/payment-provider/callback` with that value in `X-IDMC-Provider-Secret`. Until a provider is configured, requests safely remain `PENDING_PROVIDER`; no payment, allocation, invoice credit or statement transaction is fabricated.
