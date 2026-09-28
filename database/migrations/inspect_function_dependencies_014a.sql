SELECT
    table_name,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
AND table_name IN (
    'course_result_policies',
    'examination_marks',
    'students',
    'application_choices',
    'admission_offers'
)
ORDER BY
    table_name,
    ordinal_position;
