IDMC iMIS - SECTION 13C IDENTITY / STUDENT LOGIN / RBAC REPAIR
================================================================

WHAT THIS FIXES
1. "Authenticated account is not registered in IDMC iMIS" for:
   alibenangapatrick@gmail.com
2. "Invalid login credentials" for student IDMC/2026/00001.
3. Student email collisions with an existing admin/staff Auth account.
4. Missing STUDENT portal permissions and late SUPER_ADMIN permission links.

SAFETY
- No account is deleted.
- The password of alibenangapatrick@gmail.com is NOT changed.
- The student gets a separate internal Auth identity.
- Only the student's initial password is reset to the exact registration no.
- Before/after JSON evidence and original source backups are written under
  repair-backups\identity-rbac-<timestamp>.
- The Supabase service-role key is never printed or saved in the reports.

HOW TO RUN
1. Extract the complete Section 13C ZIP into:
   C:\Users\liben\Documents\IDMC_iMIS

2. Stop the old backend process (Ctrl+C in its PowerShell window).

3. From the project root run:
   Set-ExecutionPolicy -Scope Process Bypass
   .\IDMC-Section-13C-Identity-RBAC-Repair.ps1

4. Start the rebuilt backend:
   cd .\apps\backend
   npm run dev

5. Keep the backend window open. In a second PowerShell window start frontend:
   cd C:\Users\liben\Documents\IDMC_iMIS
   npx live-server apps/frontend --port=5500

6. Open exactly:
   http://127.0.0.1:5500/login.html

LOGIN TESTS
- Admin/owner:
  Identifier: alibenangapatrick@gmail.com
  Password:   the existing password (unchanged)

- Student:
  Identifier: IDMC/2026/00001
  Password:   IDMC/2026/00001

Do not open http://127.0.0.1:5500/login because the static server has no
extensionless route; use /login.html.
