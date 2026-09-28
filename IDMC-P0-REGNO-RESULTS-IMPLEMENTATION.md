# IDMC iMIS — P0 REGNO and Results Import

Implemented on 26 September 2026 using only the current source under `apps/frontend`, `apps/backend/src`, and `supabase/migrations`.

## Completed

- REGNO (`students.student_number`) is the import identity; UUID/student_id is not accepted in the template.
- Staged import tables: `result_import_batches` and `result_import_rows`.
- CSV template compatible with Microsoft Excel.
- Flow: parse → stage → validate → preview → confirm → import → calculate → audit.
- Validation for missing/unknown REGNO, inactive students, duplicate file rows, academic year, semester, course, offering, course registration, mark limits, result policy, and existing protected results.
- Database-controlled total, grade, grade point, and pass/fail calculation.
- Atomic database confirmation function for valid staged rows.
- Published/locked result marks are protected; changes must use Result Correction.
- Results review transition remains `SUBMITTED → UNDER_REVIEW` and now records reviewer/time.
- Results Import permission assigned to authorized academic/examination roles.
- Staff Results page includes import steps, summary, preview, error report, and confirmation.
- Student search explicitly supports REGNO, name, email, and phone.
- Student Profile Workspace replaces weak alert-style viewing and separates Student Number / REGNO from Semester Registration No.
- Student Portal document and unread notification counts use the self-service portal payload.

## Required deployment step

Run `Apply-IDMC-REGNO-Results-P0.ps1`. It applies the migration, runs backend typecheck/build, starts backend/frontend, and opens the login page.

## Next phases

1. Student dashboard summary, academic risk, alerts, and upcoming events.
2. Result correction UI and evidence upload workflow.
3. Registration/add-drop improvements.
4. Finance statement and payment-provider integration.
5. Notifications read/unread actions and document actions.
6. Transcript workflow and full end-to-end academic testing.
