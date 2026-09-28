-- ============================================================
-- IDMC iMIS
-- Transcript / Results Status Validation
-- ============================================================

SELECT
    'TRANSCRIPT_STATUS' AS source,
    transcript_status AS value,
    COUNT(*) AS records
FROM public.student_transcripts
GROUP BY transcript_status
ORDER BY transcript_status;


SELECT
    'COURSE_RESULT_STATUS' AS source,
    result_status AS value,
    COUNT(*) AS records
FROM public.course_results
GROUP BY result_status
ORDER BY result_status;


SELECT
    'PASS_STATUS' AS source,
    pass_status AS value,
    COUNT(*) AS records
FROM public.course_results
GROUP BY pass_status
ORDER BY pass_status;


SELECT
    'DEFICIENCY_STATUS' AS source,
    deficiency_status AS value,
    COUNT(*) AS records
FROM public.student_academic_deficiencies
GROUP BY deficiency_status
ORDER BY deficiency_status;


-- Check constraints
SELECT
    tc.table_name,
    tc.constraint_name,
    tc.constraint_type,
    cc.check_clause
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.check_constraints cc
    ON tc.constraint_name = cc.constraint_name
   AND tc.constraint_schema = cc.constraint_schema
WHERE tc.table_schema = 'public'
AND tc.table_name IN (
    'student_transcripts',
    'student_transcript_semesters',
    'student_transcript_courses',
    'student_academic_deficiencies',
    'course_results'
)
AND tc.constraint_type = 'CHECK'
ORDER BY tc.table_name, tc.constraint_name;


-- Existing transcript-related function definitions
SELECT
    p.proname AS function_name,
    pg_get_functiondef(p.oid) AS function_definition
FROM pg_proc p
JOIN pg_namespace n
    ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
AND p.proname IN (
    'prepare_student_transcript',
    'validate_transcript_status_transition',
    'prevent_issued_transcript_change',
    'validate_transcript_issue',
    'create_result_deficiency'
)
ORDER BY p.proname;
