SELECT
    table_name,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
AND table_name IN (
    'applications',
    'assessments',
    'assessment_marks'
)
ORDER BY
    table_name,
    ordinal_position;
