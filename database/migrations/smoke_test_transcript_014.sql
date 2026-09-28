SELECT
    'student_transcripts' AS table_name,
    COUNT(*) AS records
FROM public.student_transcripts

UNION ALL

SELECT
    'student_transcript_semesters',
    COUNT(*)
FROM public.student_transcript_semesters

UNION ALL

SELECT
    'student_transcript_courses',
    COUNT(*)
FROM public.student_transcript_courses

UNION ALL

SELECT
    'student_academic_deficiencies',
    COUNT(*)
FROM public.student_academic_deficiencies;


SELECT
    indexname
FROM pg_indexes
WHERE schemaname = 'public'
AND indexname IN (
    'uq_student_active_transcript_workflow',
    'uq_transcript_course_result',
    'uq_transcript_semester_context',
    'uq_student_course_open_deficiency'
)
ORDER BY indexname;


SELECT
    trigger_name,
    event_object_table
FROM information_schema.triggers
WHERE trigger_schema = 'public'
AND event_object_table = 'student_transcripts'
ORDER BY trigger_name;
