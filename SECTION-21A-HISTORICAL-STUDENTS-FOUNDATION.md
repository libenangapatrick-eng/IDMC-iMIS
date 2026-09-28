# IDMC iMIS — Section 21A Historical Students Foundation

## Outcome

Section 21A adds the first mandatory Priority 1 layer to the existing IDMC iMIS. It does not replace Admissions and it does not delete institutional data.

## Implemented

- Separate Historical Student workspace for cohorts 2023–2026.
- CSV and real `.xlsx` parsing without adding an unverified spreadsheet dependency.
- Upload → Validate → Preview → Fix Errors → Confirm → Report workflow.
- Manual legacy student entry.
- Full-file duplicate detection, including databases with more than 1,000 students.
- Programme, programme-version, curriculum, cohort and academic-year resolution in the backend.
- Clean-batch rule: a batch with invalid or duplicate rows cannot be confirmed.
- Import batch and row audit history with file SHA-256 fingerprint.
- Reconciliation rollback that archives/deactivates imported students instead of deleting them.
- Student source classification: `NORMAL_ADMISSION`, `HISTORICAL_IMPORT`, or `MANUAL_ENTRY`.
- Cohort master separate from Academic Year.
- Student programme-version and status history linkage.
- Course-attempt foundation that preserves attempts, repeats, supplementary results and earlier failures.
- Historical Data Quality view and dashboard.
- Least-privilege permissions for Registrar, Academic Officer and administrators.
- Existing login isolation repair included to protect `/auth/me` after Supabase password authentication.

## Existing Modules Reused

The audit confirmed that the project already contains the main academic entities. Section 21A links to them instead of creating duplicates:

| Area | Existing source reused |
| --- | --- |
| Academic periods | `academic_years`, `semesters` |
| Programme control | `programmes`, `programme_versions` |
| Curriculum | `curricula`, `curriculum_courses`, prerequisites |
| Registration | student and course registration tables |
| Results | course results, semester results, cumulative results |
| Graduation | candidates, clearances, approvals, awards |
| Certification | certificates and verification records |
| Alumni | alumni records |
| Identity/RBAC | users, roles, permissions, role permissions |

## Safety Controls

- Corrective migration is additive and transactional.
- No `DROP TABLE`, `TRUNCATE`, or data deletion is used.
- Official student numbers remain unique.
- Existing modules and API URLs are retained.
- Rollback is a reconciled archive operation, not a destructive database rollback.
- Backend remains the source of truth for validation.
- Installer creates a timestamped source backup before copying files.
- Backend build and all automated tests must pass before restart.

## Verified

- TypeScript build: PASS
- Automated tests: 39/39 PASS
- Frontend JavaScript syntax: PASS
- Migration version collision scan: PASS

## Next Controlled Increment

Section 21B should build on this foundation to import historical course attempts/results, run centralized GPA/CGPA recalculation, and generate the per-student Academic Lifecycle Report. It must use `student_course_attempts` and the existing result tables rather than overwriting published results.

