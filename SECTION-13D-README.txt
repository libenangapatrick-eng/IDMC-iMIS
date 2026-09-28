IDMC iMIS - SECTION 13D LOGIN SEPARATION REPAIR
================================================

CONFIRMED DIAGNOSIS
- Owner Auth email: libenangapatrick@gmail.com
- Owner Auth UUID: e84d7422-b1cc-411a-b062-70c2e7496e4f
- Owner public.users mapping: correct and ACTIVE.
- Owner roles: ADMIN and SUPER_ADMIN; no STUDENT role in the latest audit.
- Student IDMC/2026/00001 has a separate Auth/public.users identity and STUDENT role.
- Therefore the current owner "Invalid login credentials" is an Auth password
  mismatch, not a missing public user, RBAC problem, or student linkage.
- The old backend also performed password sign-in on the shared service-role
  client. Section 13D separates the public login client from the admin DB client.

WHAT THE REPAIR DOES
1. Backs up every replaced source file and writes before/after JSON evidence.
2. Installs a two-mode login form: Staff/Admin and Student.
3. Adds SUPABASE_PUBLISHABLE_KEY to backend .env from the existing public
   frontend configuration; no secret key is exposed to the browser.
4. Prompts securely for a new owner password, resets it, and verifies login.
5. Ensures the owner has ADMIN + SUPER_ADMIN and removes STUDENT if present.
6. Ensures the student has STUDENT and removes ADMIN/SUPER_ADMIN if present.
7. Verifies that the owner is not linked to any students row.
8. Resets/verifies the student's initial password as the Registration Number.
9. Rebuilds the backend.

RUN FROM PROJECT ROOT
Set-ExecutionPolicy -Scope Process Bypass -Force
.\IDMC-Section-13D-Login-Separation-Repair.ps1

When prompted for the owner password, input is hidden. To use Patrick@0269,
type exactly Patrick@0269. Do NOT type a backslash before @.

RESTART
$Project = "C:\Users\liben\Documents\IDMC_iMIS"
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
  Where-Object LocalPort -in 4000,5500 |
  Select-Object -ExpandProperty OwningProcess -Unique |
  ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
Start-Process powershell.exe -ArgumentList "-NoExit","-Command","cd '$Project\apps\backend'; npm.cmd run dev"
Start-Sleep 8
Start-Process powershell.exe -ArgumentList "-NoExit","-Command","cd '$Project'; npx.cmd live-server apps/frontend --port=5500"

TEST URL
http://127.0.0.1:5500/login.html

STAFF / ADMIN MODE
Email: libenangapatrick@gmail.com
Password: the new password entered during repair

STUDENT MODE
Registration No.: IDMC/2026/00001
Password: IDMC/2026/00001
