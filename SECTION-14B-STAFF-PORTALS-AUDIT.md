# IDMC iMIS Section 14B — Staff Role Workspaces

## Outcome

Section 14B replaces the former staff portal link cards with three authenticated, database-driven institutional workspaces. All remain inside the same IDMC iMIS identity, API and PostgreSQL architecture established in Section 14A.

| Portal | Authorized roles | Main operational scope |
|---|---|---|
| Lecturer | `LECTURER` | Assigned courses/classes, timetable, attendance, draft assessment marks, mark submission and result submission |
| Finance | `FINANCE_OFFICER`, `ACCOUNTANT`, `FINANCE_MANAGER` | Student accounts, charges, invoices, receipts, payment allocation, ledger and fee structures |
| Registry | `REGISTRAR`, `ACADEMIC_OFFICER` | Student master, registration approval/register/lock, result verification/approval/publication/lock, student requests and academic structure |

## Security corrections

- Portal access is permission-gated (`portal.lecturer`, `portal.finance`, `portal.registry`).
- Lecturer data is selected only through active lecturer assignments.
- Attendance changes require an assigned course, open session and an actively registered student.
- Assessment-mark changes require an assigned course, editable assessment, registered student and a mark not exceeding the configured maximum.
- Submitted marks cannot be edited through the lecturer workspace.
- Lecturer mark/result submission uses scoped custom routes rather than unscoped generic workflow routes.
- Lecturer approval, publication, locking, admissions, registry and graduation permissions are explicitly removed.
- Finance payment recording is a single PostgreSQL transaction that verifies invoice ownership/balance and creates payment, receipt, allocation, ledger transaction and account refresh.
- Registry transitions reject skipped or backward states.

## Authoritative workflow states

Registration:

`SUBMITTED → APPROVED → REGISTERED → LOCKED`

Course result:

`CALCULATED → SUBMITTED → VERIFIED → APPROVED → PUBLISHED → LOCKED`

Assessment mark:

`DRAFT → SUBMITTED → APPROVED → LOCKED`

## Interface

All three portals use the institutional maroon/white palette, Times New Roman, responsive navigation, real empty states and no sample personal data. Login routing now directs Lecturer, Finance and Registry roles to the correct portal while preserving the Student Portal and administrative dashboard routes.

## Files and contracts verified

- TypeScript backend compilation.
- JavaScript syntax for staff workspace and authentication routing.
- Staff workspace route mount under `/api/v1/staff-workspace`.
- Required role and permission codes in migration `202609210029_staff_role_workspaces.sql`.
- Required portal HTML, shared CSS and JavaScript assets.
- No copied identity, campus, programme or photograph details from the structural reference document.

## Account assignment boundary

This installation creates and repairs roles and permissions but does not guess which real person should receive Lecturer, Accountant or Registrar authority. Existing IDMC users must be assigned the appropriate role through the administrator's Roles/User interface after the installer completes. This avoids silently granting financial or academic approval authority to the wrong account.
