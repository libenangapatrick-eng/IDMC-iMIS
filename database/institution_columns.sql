SELECT
    table_name,
    ordinal_position,
    column_name,
    data_type,
    udt_name,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
      'institutions',
      'campuses',
      'schools',
      'departments'
  )
ORDER BY
    CASE table_name
        WHEN 'institutions' THEN 1
        WHEN 'campuses' THEN 2
        WHEN 'schools' THEN 3
        WHEN 'departments' THEN 4
        ELSE 5
    END,
    ordinal_position;
