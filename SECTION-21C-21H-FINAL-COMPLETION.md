# IDMC iMIS Section 21C–21H — Final Completion Bundle

This cumulative release extends Sections 21A and 21B without replacing Admissions, Students, Results, Finance, Graduation or Alumni.

## Delivered

- Graduation eligibility snapshots from curriculum, official attempts, CGPA, finance, library, hostel and document records.
- Eight-office clearance board: Academic, Finance, Library, Hostel, Department, Examination, Discipline and Documents.
- Six-stage approval: Department, HOD, Academic, Examination, Registrar and Management.
- Four-eyes replacement protection and append-only clearance/lifecycle histories.
- Finalize action creates/links the graduation award, issued certificate, notification and Alumni record, then marks the student Graduated.
- Public certificate verification exposes only limited academic identity data.
- Historical data quality view and the existing Student Academic Lifecycle report.
- Least-privilege permissions by institutional office.
- Backup, archive validation, isolated restore test and production-readiness scripts.
- Mobile-friendly maroon/white Lifecycle Completion workspace.

## Important controls

- No historical migration was changed.
- No student, result, payment, clearance, certificate or alumni record is hard-deleted.
- Finalization is blocked until eligibility, all eight clearances and all six approvals pass.
- Restore testing refuses to target the configured production database.
- Database credentials are read from environment variables and are never bundled.

## Deployment order

Run `Install-IDMC-Section-21C-Final.ps1`. It pushes migrations before installing dependent source, runs typecheck/tests and can restart the system with `-StartServers`.

## Backup operations

Run `scripts\Backup-IDMC-Database.ps1` daily. Retain daily backups for 35 days, archive one weekly copy for 12 weeks and one monthly copy according to institutional retention policy. Run `scripts\Test-IDMC-Database-Restore.ps1` against an isolated non-production database at least monthly and record the evidence.
