# Core Form-to-API Contracts

The generated structural inventory is in `generated-form-inventory.*`. These core
contracts identify the source handlers that must be included in authenticated E2E.

| Workflow | Frontend handler | API | Persistence | Authorization |
|---|---|---|---|---|
| Login | `auth.js` | `POST /auth/login` | Supabase Auth + `users` | Public, IP rate-limited; generic invalid-credential response |
| Student dashboard | `student-portal-home.js` | `GET /students/me/summary` | Ownership-scoped student/academic/finance reads | `students.self.view` |
| Registration select | `student-portal-pages.js` | `POST /self-service/student/registration/select` | `course_registrations` | `students.registration.manage_own`; programme, semester, prerequisite, capacity and credit checks |
| Registration submit | `student-portal-pages.js` | `POST /self-service/student/registration/submit` | `student_registrations`, `course_registrations` | Own editable registration only |
| ADD/DROP | `student-portal-pages.js` | `POST /self-service/student/registration/add-drop` | `course_add_drop_requests` | Own registered semester only |
| Result import | `results-import.js` | `/results/import/*` | staging tables + calculation RPC | `results.import`; published/locked records protected |
| Payment request | `student-portal-pages.js` | `POST /self-service/student/payments/control-number` | `student_payment_requests` | Own invoice; does not create payment |
| Provider payment | External provider | `POST /payment-provider/callback` | atomic RPC writes payment/allocation/ledger | provider secret + idempotent event reference |
| Notification read | `student-portal-pages.js` | `PATCH /students/me/notifications/:id/read` | `notifications` | own recipient only |
| Document download | `student-portal-pages.js` | `GET /students/me/documents/:id/download` | private storage signed URL | own document only; five-minute URL |
| Transcript request | `student-transcript.js` | `POST /students/me/requests` | `student_service_requests` | `students.self.manage` |

Generated inventories discover the remaining forms/routes; runtime E2E must record
success, validation, unauthenticated, unauthorized, not-found and duplicate cases.
