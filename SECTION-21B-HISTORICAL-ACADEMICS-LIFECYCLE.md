# IDMC iMIS — Section 21B Historical Academics and Lifecycle

## Delivered

Section 21B extends Section 21A without replacing Admissions, Results, GPA, Transcript, Graduation or Alumni modules.

- CSV/XLSX historical academic records import.
- Validation of Student Number, Programme Version, Curriculum, Academic Year, Semester, Course, attempt number, credits, marks and institutional grade scale.
- Duplicate attempt detection against the whole database and within the uploaded file.
- One immutable row per attempt; failed first attempts are preserved when later attempts pass.
- Supported result types: normal, supplementary, special, resit, retake, repeat, carry-forward and makeup.
- Only `PUBLISHED` or `LOCKED` historical records can become official.
- Four-eyes confirmation: the validating officer cannot confirm the same batch.
- Centralized semester GPA and cumulative CGPA calculation in the backend.
- Semester academic standing and credits attempted/earned.
- Controlled rollback sets imported attempts to `CANCELLED`; it never deletes them.
- Rollback recalculates affected GPA/CGPA and withholds empty summaries.
- Student Academic Lifecycle report joining student, programme history, status history, attempts, GPA/CGPA, graduation and alumni.
- Student Results endpoint includes published/locked historical attempts only when no official `course_result` is linked, preventing duplicate display.
- Search, paginated lifecycle list and print-ready lifecycle detail.
- RBAC permissions for Registrar, Academic Officer and Examination Officer.

## Source-of-truth Reuse

| Requirement | Existing source reused |
| --- | --- |
| Grade calculation | `grade_scales`, `grade_scale_details` |
| Programme membership | `programme_versions`, `curricula`, `curriculum_courses` |
| Attempts | `student_course_attempts` from Section 21A |
| GPA summaries | `student_semester_results`, `student_gpa_records` |
| CGPA | `student_cgpa_records` |
| Student display | existing `/student-results/me` endpoint |
| Graduation and alumni | existing candidates and alumni tables |
| Audit | existing `audit_logs` service |

## Verification

- Backend TypeScript build: PASS
- Automated regression tests: 43/43 PASS
- Frontend syntax checks: PASS
- No destructive SQL in Section 21A or 21B migrations.
- Existing API routes remain compatible.

## Remaining Dependency-Ordered Releases

The remaining full specification must continue incrementally:

1. **21C:** graduation eligibility engine, multi-office clearance and automatic alumni creation.
2. **21D:** official transcript/certificate generation and public verification.
3. **21E:** student requests, notifications and document/photo security.
4. **21F:** finance clearance, lifecycle dashboards and institutional reports.
5. **21G:** API pagination consistency, integrity reconciliation and security hardening.
6. **21H:** full E2E/regression suite, backup/restore test and production-readiness gate.

This order follows data dependencies and prevents working modules from being destabilized by one unverified bulk change.

