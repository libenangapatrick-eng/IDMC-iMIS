# IDMC iMIS Section 14A — Deep Student Portal Audit

## Scope and source

This repair was prepared from `IDMC_iMIS(10).zip`. The functional organization in `gud(3).docx` was used only as a requirements reference. No names, registration numbers, programme names, campus names, photographs, credentials, or other sample data from that document were copied.

## Repository audit result

| Area | Source state | Repair result |
|---|---:|---:|
| Executable Supabase migrations | 45 | 46 |
| Migration-defined tables | 167 | 171 |
| Backend table references | 148 | 153 |
| Backend references without an executable table migration | 1 (`academic_records`) | 0 |
| Top-level frontend HTML pages | 52 | 56 |
| Broken local HTML/CSS/JS references | — | 0 |

The audit covered the executable migrations in `supabase/migrations`, the parallel SQL source in `database/migrations`, Express routes/controllers/services, RBAC permission checks, frontend module contracts, local asset links, and student identity resolution.

The repaired backend exposes 139 generic CRUD resources in addition to custom workflow and self-service routes.

## Student self-service completed

The new server-owned endpoint `/api/v1/students/me/portal` resolves the authenticated student and returns only that student's linked institutional records. It provides:

- home overview, current registration, class and announcements;
- student and admission profile, contacts, guardian/next-of-kin, qualifications, documents and profile photo;
- registered modules and credits;
- class and examination timetables;
- attendance, coursework, published results, GPA/CGPA and academic deficiencies;
- invoices, payments, ledger transactions and account balance;
- accommodation allocation and applicable hostel fees;
- result appeal, postponement, transcript, ID card, certificate and gown requests;
- notifications and helpdesk tickets;
- password change and security history.

The portal is institutional rather than a demonstration dashboard: maroon and white, Times New Roman, responsive layout, no invented values, and explicit empty states when the database has no record.

## Admission and registration corrections

- Added admission profile/passport photo support to the applicant record.
- Corrected authentication-token handling in the live admission form.
- Corrected the programme-choice mapping from `priority` to `choice_number`.
- Corrected qualification ownership from `application_id` to `applicant_id` and year mapping to `completion_year`.
- Corrected application-document mapping from `fileName` to `document_name`.
- Corrected application submission to use the installed workflow route.
- Added system generation of application numbers.
- Prevented applicant-number regeneration during profile edits.

## Database and RBAC corrections

Migration `202609210028_student_self_service_completion.sql` adds the missing compatibility table and the student-owned coursework responses, course evaluations and service requests. It adds `students.self.manage`, ensures the `STUDENT` role is active, and assigns the student portal permissions idempotently. Row-level security is enabled on the new student tables; backend access remains authenticated and permission-gated.

## Frontend/backend contract corrections

The visible module contracts for assessment, examinations, results, communications, library, hostel, graduation, alumni, operations, reports, system and finance were aligned with routes that actually exist in the backend. This removes false 404 errors caused by outdated frontend paths.

## Verification performed

- TypeScript backend build (`npm run build`).
- JavaScript syntax checks for the institutional portal, admission live form and corrected module-contract files.
- Static route/table audit against executable migrations.
- Local asset-reference audit.
- Search for copied reference-document identities and sample institution details.

## Deliberate next phase

Staff task ownership is a separate Section 14B so student self-service can be verified first. That phase should expose the already existing RBAC-backed resources through focused workspaces for Lecturer, Accountant/Finance Officer, Registry/Academic Officer, Helpdesk and Hostel staff, without granting student permissions to staff or staff permissions to students.
