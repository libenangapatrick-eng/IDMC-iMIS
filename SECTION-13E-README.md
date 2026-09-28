# IDMC Section 13E — Student Profile and Portal Repair

This repair connects `IDMC/2026/00001` to the authoritative applicant, programme, registration and self-service records. It also installs the maroon/white student portal and profile-picture flow.

## Install

Extract the ZIP into the root of `C:\Users\liben\Documents\IDMC_iMIS`, allowing the new repair files to be added. Then open PowerShell in that folder and run:

```powershell
cd C:\Users\liben\Documents\IDMC_iMIS
Set-ExecutionPolicy -Scope Process Bypass -Force
.\IDMC-Section-13E-Student-Profile-Portal-Repair.ps1
```

The installer backs up every replaced source file, reconciles the student master/profile from the applicant record, validates the semester registration and runs the backend build.

## Restart and test

Open PowerShell window 1:

```powershell
cd C:\Users\liben\Documents\IDMC_iMIS\apps\backend
npm install
npm run dev
```

Open PowerShell window 2:

```powershell
cd C:\Users\liben\Documents\IDMC_iMIS
npx live-server apps/frontend --port=5500
```

Open the login page:

```powershell
Start-Process "http://127.0.0.1:5500/login.html"
```

Sign in with:

- Registration number: `IDMC/2026/00001`
- Initial password: `IDMC/2026/00001` (unless it was changed after first login)

Expected portal values include the applicant's full name/email, the linked programme, `ACTIVE` student status, the registered semester, six registered courses and 60 credits.

The admin account remains a staff/admin identity and is not assigned the STUDENT role.
