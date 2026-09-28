-- ============================================================
-- IDMC iMIS
-- Migration Dependency Check
-- 013 Transcript + 014 Hardening
-- ============================================================

SELECT
    'TABLE' AS object_type,
    table_schema || '.' || table_name AS object_name
FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name IN
(
    'student_transcripts',
    'student_transcript_semesters',
    'student_transcript_courses',
    'student_academic_standings',
    'student_course_attempts',
    'student_academic_deficiencies',
    'student_gpa_records',
    'student_cgpa_records',
    'student_semester_results',
    'course_results',
    'course_registrations',
    'course_offerings',
    'courses',
    'students',
    'programme_versions',
    'academic_years',
    'semesters'
)
ORDER BY table_name;


SELECT
    'COLUMN' AS object_type,
    table_schema || '.' || table_name || '.' || column_name AS object_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'public'
AND
(
    (table_name = 'student_transcripts'
        AND column_name IN
        (
            'id',
            'student_id',
            'programme_version_id',
            'transcript_number',
            'transcript_type',
            'cumulative_credits',
            'quality_points',
            'cgpa',
            'academic_standing_code',
            'academic_standing_name',
            'status',
            'approved_at',
            'approved_by',
            'issued_at',
            'issued_by',
            'verification_code',
            'replacement_of',
            'document_file_id'
        ))
    OR
    (table_name = 'student_transcript_semesters'
        AND column_name IN
        (
            'id',
            'transcript_id',
            'academic_year_id',
            'semester_id',
            'semester_result_id',
            'gpa',
            'credits',
            'quality_points',
            'standing_code',
            'sequence_no'
        ))
    OR
    (table_name = 'student_transcript_courses'
        AND column_name IN
        (
            'id',
            'transcript_id',
            'transcript_semester_id',
            'course_result_id',
            'course_registration_id',
            'course_id',
            'course_code',
            'course_name',
            'credits',
            'marks',
            'grade',
            'point',
            'result_type',
            'attempt_number',
            'pass_status'
        ))
    OR
    (table_name = 'course_results'
        AND column_name IN
        (
            'id',
            'student_id',
            'course_id',
            'course_offering_id',
            'status',
            'pass_status'
        ))
    OR
    (table_name = 'student_academic_deficiencies'
        AND column_name IN
        (
            'id',
            'student_id',
            'course_id',
            'course_offering_id',
            'course_result_id',
            'deficiency_type',
            'status'
        ))
)
ORDER BY table_name, ordinal_position;


SELECT
    'FUNCTION' AS object_type,
    routine_schema || '.' || routine_name AS object_name
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name IN
(
    'set_updated_at',
    'generate_transcript_number',
    'generate_transcript_verification_code',
    'prepare_student_transcript',
    'validate_transcript_status_transition',
    'prevent_issued_transcript_change',
    'validate_transcript_issue',
    'calculate_student_academic_standing',
    'create_result_deficiency'
)
ORDER BY routine_name;


SELECT
    'FK' AS object_type,
    tc.table_name || '.' || kcu.column_name
        || ' -> '
        || ccu.table_name || '.' || ccu.column_name AS object_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
   AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage ccu
    ON ccu.constraint_name = tc.constraint_name
   AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
AND tc.table_schema = 'public'
AND
(
    tc.table_name IN
    (
        'student_transcripts',
        'student_transcript_semesters',
        'student_transcript_courses',
        'student_academic_deficiencies'
    )
    OR
    ccu.table_name IN
    (
        'student_transcripts',
        'student_transcript_semesters',
        'student_transcript_courses',
        'course_results',
        'students',
        'courses',
        'academic_years',
        'semesters'
    )
)
ORDER BY tc.table_name, kcu.column_name;


SELECT
    'TRIGGER' AS object_type,
    event_object_table || '.' || trigger_name AS object_name
FROM information_schema.triggers
WHERE trigger_schema = 'public'
AND event_object_table IN
(
    'student_transcripts',
    'student_transcript_semesters',
    'student_transcript_courses',
    'student_academic_deficiencies'
)
ORDER BY event_object_table, trigger_name;


SELECT
    'INDEX' AS object_type,
    schemaname || '.' || indexname AS object_name
FROM pg_indexes
WHERE schemaname = 'public'
AND tablename IN
(
    'student_transcripts',
    'student_transcript_semesters',
    'student_transcript_courses',
    'student_academic_deficiencies'
)
ORDER BY tablename, indexname;
