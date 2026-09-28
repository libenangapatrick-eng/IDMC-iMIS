SELECT
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name IN (
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
