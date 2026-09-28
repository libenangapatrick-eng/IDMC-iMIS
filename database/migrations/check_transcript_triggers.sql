SELECT
    event_object_table,
    trigger_name,
    event_manipulation,
    action_timing
FROM information_schema.triggers
WHERE trigger_schema = 'public'
AND event_object_table IN (
    'student_transcripts',
    'student_transcript_semesters',
    'student_transcript_courses',
    'student_academic_deficiencies'
)
ORDER BY event_object_table, trigger_name;
