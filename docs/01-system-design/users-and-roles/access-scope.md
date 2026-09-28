# IDMC iMIS ACCESS SCOPE

## Scope Levels

GLOBAL
All institutional data.

CAMPUS
Only data belonging to assigned campus.

SCHOOL
Only data belonging to assigned school/faculty.

DEPARTMENT
Only data belonging to assigned department.

PROGRAMME
Only data belonging to assigned programme.

CLASS
Only assigned class/course data.

SELF
Only user's own records.

## Examples

Principal:
GLOBAL

Registrar:
GLOBAL

Admission Officer:
CAMPUS or GLOBAL depending on assignment

HOD:
DEPARTMENT

Lecturer:
COURSE / CLASS

Student:
SELF

Applicant:
SELF

Auditor:
GLOBAL READ-ONLY

## Rule

Access must be checked on the backend.

Frontend hiding a menu is NOT security.

The backend API must enforce:

Authentication
Authorization
Permission
Scope
Ownership
Audit
