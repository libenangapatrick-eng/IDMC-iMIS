# IDMC iMIS USERS AND ROLES

## 1. SUPER ADMIN

Purpose:
Full system governance.

Access:
- All modules
- All campuses
- All departments
- System configuration
- Roles
- Permissions
- Integrations
- Security
- Audit

Restrictions:
- Sensitive actions must be audited.
- Super Admin should not normally perform operational financial or academic transactions unless explicitly authorized.

## 2. SYSTEM ADMINISTRATOR

Purpose:
Technical administration.

Access:
- Users
- Roles
- Permissions
- Sessions
- Security
- System health
- Integrations
- Email configuration
- SMS configuration
- Backups
- Logs

No automatic access to confidential academic or financial data unless explicitly assigned.

## 3. PRINCIPAL / RECTOR

Purpose:
Institutional management.

Access:
- Executive dashboard
- Admissions reports
- Student reports
- Academic reports
- Finance reports
- HR reports
- Procurement reports
- Research reports
- QA reports
- Approvals
- Institutional analytics

Normally read/approve rather than perform daily data entry.

## 4. DEPUTY PRINCIPAL - ACADEMIC

Access:
- Academic management
- Departments
- Programmes
- Curriculum
- Courses
- Timetable
- Examination
- Results
- Academic approvals
- Academic reports

## 5. DEPUTY PRINCIPAL - FINANCE / ADMINISTRATION

Access:
- Finance
- Budget
- Procurement
- HR/Administration reports
- Assets
- Institutional financial reports
- Approvals

## 6. REGISTRAR

Access:
- Applicants
- Admissions
- Students
- Registration
- Academic records
- Student status
- Transcripts
- Certificates
- Graduation
- Academic documents
- Registry reports

## 7. ADMISSION OFFICER

Access:
- Applications
- Applicant verification
- Documents
- Eligibility
- Selection
- Admission offers
- Admission letters
- Joining instructions

Cannot publish examination results unless separately assigned.

## 8. ACADEMIC OFFICER

Access:
- Academic years
- Semesters
- Programmes
- Curriculum
- Courses
- Registration
- Timetable
- Academic records
- Academic reports

## 9. EXAMINATION OFFICER

Access:
- Examination setup
- Examination timetable
- Coursework
- Examination marks
- Result processing
- Result approval workflow
- Result publication
- Transcript data
- Examination reports

## 10. HEAD OF DEPARTMENT

Access:
- Department students
- Department lecturers
- Courses
- Curriculum
- Course allocation
- Timetable
- Marks review
- Result approval
- Department reports

Only within assigned department unless additional access is granted.

## 11. LECTURER

Access:
- Assigned courses
- Assigned classes
- Student lists
- Attendance
- Coursework
- Marks
- Timetable
- LMS

Cannot edit published results.

## 12. FINANCE MANAGER

Access:
- Fee structures
- Invoices
- Payments
- Student ledger
- Debtors
- Refunds
- Sponsors
- Financial reports
- Reconciliation

Sensitive financial actions must be audited.

## 13. ACCOUNTANT

Access:
- Payments
- Receipts
- Invoices
- Student ledger
- Financial transactions
- Reports

Cannot modify system security.

## 14. CASHIER

Access:
- Receive payments
- Issue receipts
- View relevant invoices
- Daily cashier reports

Cannot approve refunds independently.

## 15. HR MANAGER

Access:
- Employees
- Contracts
- Recruitment
- Leave
- Attendance
- Payroll
- Staff documents
- Appraisal
- HR reports

## 16. HR OFFICER

Access:
- Employee records
- Recruitment
- Leave
- Attendance
- Staff documents
- HR reports

## 17. PROCUREMENT OFFICER

Access:
- Suppliers
- Purchase requests
- RFQ
- Quotations
- Purchase orders
- Procurement reports

## 18. STORE KEEPER

Access:
- Stores
- Items
- Stock in
- Stock out
- Transfers
- Stock adjustments
- Inventory reports

## 19. LIBRARIAN

Access:
- Books
- Copies
- Borrowing
- Returns
- Reservations
- Fines
- Library reports

## 20. HOSTEL OFFICER

Access:
- Hostels
- Rooms
- Beds
- Applications
- Allocations
- Check-in
- Check-out
- Hostel reports

## 21. DEAN OF STUDENTS

Access:
- Student welfare
- Student requests
- Discipline
- Accommodation oversight
- Student support
- Relevant student reports

## 22. CLINICAL COORDINATOR

Access:
- Clinical sites
- Clinical placements
- Supervisors
- Rotations
- Clinical attendance
- Clinical assessments

## 23. FIELD PRACTICAL COORDINATOR

Access:
- Field organizations
- Student placements
- Supervisors
- Logbooks
- Assessments
- Field reports

## 24. RESEARCH COORDINATOR

Access:
- Research proposals
- Supervisors
- Research progress
- Ethics workflow
- Publications
- Research reports

## 25. QUALITY ASSURANCE OFFICER

Access:
- Course evaluation
- Lecturer evaluation
- Programme review
- Accreditation
- Audit findings
- Corrective actions
- Student feedback
- QA reports

## 26. AUDITOR

Access:
- Read-only financial records
- Read-only academic records
- Audit logs
- Approvals
- Transactions
- Reports

Cannot modify operational data.

## 27. STAFF

General institutional staff access.

Permissions depend on assigned department and responsibilities.

## 28. STUDENT

Access:
- Student profile
- Registration
- Courses
- Coursework
- Results
- Finance
- Timetable
- Examination timetable
- Hostel
- Library
- LMS
- Requests
- Documents
- Notifications

## 29. APPLICANT

Access:
- Application
- Application documents
- Application status
- Payments
- Admission offer
- Joining instructions
- Messages
- Profile

Applicant cannot access student modules until admitted and converted to student.

## IMPORTANT SECURITY RULE

Role alone is not enough.

Every user must be controlled by:

Role
+
Permission
+
Campus Scope
+
Department Scope
+
Data Scope

Example:

A lecturer assigned to Department A must not automatically see students belonging to Department B.

A Finance Officer should not automatically receive access to examination marks.

An Auditor should have read-only access.

A Student should only see their own records.

An Applicant should only see their own application.

All sensitive actions must be recorded in audit logs.
