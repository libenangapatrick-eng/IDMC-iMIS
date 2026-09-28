SELECT
    p.proname AS function_name,
    pg_get_function_identity_arguments(p.oid) AS arguments,
    pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
JOIN pg_namespace n
    ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
AND p.proname IN (
    'convert_accepted_application_to_student',
    'calculate_course_result'
)
ORDER BY p.proname;
