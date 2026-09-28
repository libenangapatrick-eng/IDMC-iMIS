-- IDMC iMIS Workflow Permissions
-- Adds granular action permissions used by workflow APIs.

INSERT INTO public.permissions
    (permission_code, permission_name, module_code, action_code, description, status)
VALUES
    ('admissions.submit','Submit application','ADMISSIONS','SUBMIT','Submit or resubmit an admission application', 'ACTIVE'),
    ('admissions.review','Review application','ADMISSIONS','REVIEW','Move an application into review', 'ACTIVE'),
    ('admissions.verify','Verify application','ADMISSIONS','VERIFY','Verify application documentation/status', 'ACTIVE'),
    ('admissions.eligibility','Decide application eligibility','ADMISSIONS','ELIGIBILITY','Set applicant eligibility outcome', 'ACTIVE'),
    ('admissions.decide','Approve or reject admission decision','ADMISSIONS','DECIDE','Approve or reject an admission decision', 'ACTIVE'),
    ('admissions.offer','Issue admission offer','ADMISSIONS','OFFER','Issue an admission offer after approval', 'ACTIVE'),
    ('admissions.accept','Record admission acceptance','ADMISSIONS','ACCEPT','Accept or decline an admission offer', 'ACTIVE'),
    ('students.activate','Activate student','STUDENTS','ACTIVATE','Activate an admitted student', 'ACTIVE'),
    ('registration.submit','Submit registration','ACADEMICS','SUBMIT_REGISTRATION','Submit a student registration for approval', 'ACTIVE'),
    ('registration.approve','Approve registration','ACADEMICS','APPROVE_REGISTRATION','Approve a student registration', 'ACTIVE'),
    ('registration.register','Register student courses','ACADEMICS','REGISTER','Move approved registration to REGISTERED', 'ACTIVE'),
    ('registration.lock','Lock registration','ACADEMICS','LOCK_REGISTRATION','Lock a registered semester record', 'ACTIVE'),
    ('registration.add_drop.decide','Decide add/drop request','ACADEMICS','DECIDE_ADD_DROP','Approve or reject add/drop requests', 'ACTIVE'),
    ('timetable.review','Review timetable','ACADEMICS','REVIEW_TIMETABLE','Move timetable into review', 'ACTIVE'),
    ('timetable.approve','Approve timetable','ACADEMICS','APPROVE_TIMETABLE','Approve timetable for publication', 'ACTIVE'),
    ('timetable.publish','Publish timetable','ACADEMICS','PUBLISH_TIMETABLE','Publish timetable', 'ACTIVE'),
    ('timetable.lock','Lock timetable','ACADEMICS','LOCK_TIMETABLE','Lock published timetable', 'ACTIVE'),
    ('assessment.open','Open assessment','ASSESSMENT','OPEN','Open assessment for operation', 'ACTIVE'),
    ('assessment.submit','Submit assessment','ASSESSMENT','SUBMIT','Submit assessment for review', 'ACTIVE'),
    ('assessment.approve','Approve assessment','ASSESSMENT','APPROVE','Approve assessment', 'ACTIVE'),
    ('assessment.lock','Lock assessment','ASSESSMENT','LOCK','Lock assessment', 'ACTIVE'),
    ('assessment.marks.submit','Submit assessment marks','ASSESSMENT','SUBMIT_MARKS','Submit marks for review', 'ACTIVE'),
    ('assessment.marks.approve','Approve assessment marks','ASSESSMENT','APPROVE_MARKS','Approve assessment marks', 'ACTIVE'),
    ('assessment.marks.lock','Lock assessment marks','ASSESSMENT','LOCK_MARKS','Lock assessment marks', 'ACTIVE'),
    ('assessment.correction.decide','Decide assessment correction','ASSESSMENT','DECIDE_CORRECTION','Approve or reject assessment mark corrections', 'ACTIVE'),
    ('examination.eligibility','Set examination eligibility','EXAMINATIONS','ELIGIBILITY','Set examination candidate eligibility', 'ACTIVE'),
    ('examination.marks.submit','Submit examination marks','EXAMINATIONS','SUBMIT_MARKS','Submit examination marks', 'ACTIVE'),
    ('examination.marks.approve','Approve examination marks','EXAMINATIONS','APPROVE_MARKS','Approve examination marks', 'ACTIVE'),
    ('examination.marks.lock','Lock examination marks','EXAMINATIONS','LOCK_MARKS','Lock examination marks', 'ACTIVE'),
    ('results.calculate','Calculate course result','RESULTS','CALCULATE','Calculate authoritative course result', 'ACTIVE'),
    ('results.submit','Submit result','RESULTS','SUBMIT','Submit result for review', 'ACTIVE'),
    ('results.review','Review result','RESULTS','REVIEW','Move submitted result into review', 'ACTIVE'),
    ('results.approve','Approve result','RESULTS','APPROVE','Approve result', 'ACTIVE'),
    ('results.publish','Publish result','RESULTS','PUBLISH','Publish approved result', 'ACTIVE'),
    ('results.lock','Lock result','RESULTS','LOCK','Lock published result', 'ACTIVE'),
    ('transcript.generate','Generate transcript','TRANSCRIPT','GENERATE','Generate a student transcript', 'ACTIVE'),
    ('transcript.review','Review transcript','TRANSCRIPT','REVIEW','Submit transcript for review', 'ACTIVE'),
    ('transcript.approve','Approve transcript','TRANSCRIPT','APPROVE','Approve transcript', 'ACTIVE'),
    ('transcript.issue','Issue transcript','TRANSCRIPT','ISSUE','Issue an approved transcript', 'ACTIVE'),
    ('transcript.revoke','Revoke transcript','TRANSCRIPT','REVOKE','Revoke an issued transcript', 'ACTIVE'),
    ('graduation.clearance','Manage graduation clearance','GRADUATION','CLEARANCE','Clear graduation requirements', 'ACTIVE'),
    ('graduation.eligibility','Decide graduation eligibility','GRADUATION','ELIGIBILITY','Set graduation eligibility', 'ACTIVE'),
    ('graduation.approve','Approve graduation candidate','GRADUATION','APPROVE','Approve a graduation candidate', 'ACTIVE'),
    ('graduation.graduate','Mark candidate graduated','GRADUATION','GRADUATE','Complete graduation of an approved candidate', 'ACTIVE'),
    ('certificate.issue','Issue certificate','GRADUATION','ISSUE_CERTIFICATE','Issue an academic certificate', 'ACTIVE'),
    ('certificate.revoke','Revoke certificate','GRADUATION','REVOKE_CERTIFICATE','Revoke an academic certificate', 'ACTIVE'),
    ('alumni.activate','Activate alumni record','ALUMNI','ACTIVATE','Activate an alumni record', 'ACTIVE')
ON CONFLICT (permission_code) DO UPDATE SET
    permission_name = EXCLUDED.permission_name,
    module_code = EXCLUDED.module_code,
    action_code = EXCLUDED.action_code,
    description = EXCLUDED.description,
    status = EXCLUDED.status,
    updated_at = now();

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE p.permission_code IN (
    'admissions.submit','admissions.review','admissions.verify','admissions.eligibility','admissions.decide','admissions.offer','admissions.accept',
    'students.activate','registration.submit','registration.approve','registration.register','registration.lock','registration.add_drop.decide',
    'timetable.review','timetable.approve','timetable.publish','timetable.lock',
    'assessment.open','assessment.submit','assessment.approve','assessment.lock','assessment.marks.submit','assessment.marks.approve','assessment.marks.lock','assessment.correction.decide',
    'examination.eligibility','examination.marks.submit','examination.marks.approve','examination.marks.lock',
    'results.calculate','results.submit','results.review','results.approve','results.publish','results.lock',
    'transcript.generate','transcript.review','transcript.approve','transcript.issue','transcript.revoke',
    'graduation.clearance','graduation.eligibility','graduation.approve','graduation.graduate','certificate.issue','certificate.revoke','alumni.activate'
)
AND r.role_code IN (
    'ADMIN','ADMISSIONS_OFFICER','ACADEMIC_OFFICER','REGISTRAR','EXAM_OFFICER','EXAMINATIONS_OFFICER','LECTURER','QUALITY_ASSURANCE','QA_OFFICER'
)
ON CONFLICT DO NOTHING;
