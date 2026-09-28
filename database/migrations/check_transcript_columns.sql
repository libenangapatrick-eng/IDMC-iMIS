SELECT
    table_name,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
AND table_name IN (
    'student_transcripts',
    'student_transcript_semesters',
    'student_transcript_courses',
    'student_academic_deficiencies',
    'course_results',
    'course_offerings'
)
ORDER BY table_name, ordinal_position;
